import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/dose_preset_panel.dart';
import 'package:true_grit_vital/features/recording/dose_presets.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;

import 'screen_record_dose_test.dart'
    show createItem, createContainer, enterAmount, selectSource;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder preset(String amount, String unit) =>
    find.byKey(ValueKey('dose-preset-$amount\u0000$unit'));
Finder editPreset(String amount, String unit) =>
    find.byKey(ValueKey('dose-preset-edit-$amount\u0000$unit'));
Finder dialogAmount() => find.byKey(const ValueKey('dose-preset-edit-amount'));
Finder dialogUnit() => find.byKey(const ValueKey('dose-preset-edit-unit'));
Finder dialogAction(String label) => find.descendant(
  of: find.byKey(const ValueKey('dose-preset-edit-dialog')),
  matching: find.text(label),
);
List<String> savedValues(ProviderContainer container, DosePresetOwner owner) =>
    [
      for (final value in container.read(dosePresetsProvider(owner)).values)
        '${value.text} ${value.unit}',
    ];
Finder amountField() => find.descendant(
  of: find.widgetWithText(LabelledInput, 'Amount'),
  matching: find.byType(TextField),
);
Future<void> choose(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

const captures = String.fromEnvironment('DOSE_PRESET_SNAPSHOTS');
Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (captures.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captures/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    if (captures.isEmpty) return;
    for (final (family, paths) in [
      (
        'StitchSans',
        [
          'assets/fonts/StitchNotoSans-Regular.ttf',
          'assets/fonts/StitchNotoSans-Medium.ttf',
          'assets/fonts/StitchNotoSans-SemiBold.ttf',
          'assets/fonts/StitchNotoSans-Bold.ttf',
        ],
      ),
      (
        'NotoSans',
        ['assets/fonts/NotoSans-Regular.ttf', 'assets/fonts/NotoSans-Bold.ttf'],
      ),
      (
        'packages/shadcn_flutter/LucideIcons',
        ['packages/shadcn_flutter/lib/icons/LucideIcons.ttf'],
      ),
    ]) {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });
  appTest(
    'saved amounts fill the durable form and never write an unreviewed dose',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => createItem(f.store)))!;
      f.container.read(routerProvider).go('/record/${item.id}');
      await settle(tester);
      await enterAmount(tester, '0.125000');
      await tap(tester, 'Configure');
      await choose(tester, find.byKey(const ValueKey('dose-preset-add')));
      final owner = (personId: meId, itemId: item.id);
      expect(
        f.container.read(dosePresetsProvider(owner)).values.single.text,
        '0.125',
      );
      expect((await runIo(tester, () => f.store.records()))!, isEmpty);
      f.container.invalidate(dosePresetsProvider(owner));
      await settle(tester);
      await enterAmount(tester, '2');
      await choose(tester, preset('0.125', 'ml'));
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        final semantic = find.bySemanticsLabel('Choose 0.125 ml');
        expect(semantic, findsOneWidget);
        expect(
          tester.getSemantics(semantic).flagsCollection.isSelected,
          ui.Tristate.isTrue,
        );
      } finally {
        semantics.dispose();
      }
      expect(tester.widget<TextField>(amountField()).controller!.text, '0.125');
      await tap(tester, 'Save');
      await waitForText(tester, 'Saved for Me: Synthetic dose, 0.125 ml.');
      final record = (await runIo(tester, () => f.store.records()))!.single;
      expect(record.actualAmount, ExactAmount.parseEntry('0.125'));
    },
  );

  appTest(
    'latest saved schedule amounts are exact choices beside manual entry',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => createItem(f.store)))!;
      await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: 'preset-plan',
          expectedPersonRevision: 2,
          expectedGeneration: f.store.generation,
          plan: DailyPlanVersion(
            personId: meId,
            planId: 'preset-plan',
            itemId: item.id,
            versionId: 'preset-version',
            start: CivilDate(2026, 10, 19),
            zoneBasis: FixedHome('Europe/London'),
            timing: DailySlots([
              for (final (id, quantity, hour) in [
                ('a', '0.700000', 8),
                ('b', '1.25', 20),
              ])
                DailySlot(
                  id: id,
                  time: WallTime(hour, 0),
                  amount: PlannedAmount(
                    quantity: ExactQuantity.parse(quantity),
                    enteredText: quantity,
                    unit: 'ml',
                  ),
                  reminderEnabled: false,
                ),
            ]),
          ),
        ),
      );
      f.container.read(routerProvider).go('/record/${item.id}');
      await settle(tester);
      await waitForText(tester, '0.7\u00a0ml');
      expect(preset('0.7', 'ml'), findsOneWidget);
      expect(preset('1.25', 'ml'), findsOneWidget);
      await choose(tester, preset('0.7', 'ml'));
      expect(tester.widget<TextField>(amountField()).controller!.text, '0.7');
      await enterAmount(tester, '0.123456');
      await tap(tester, 'Save');
      await waitForText(tester, 'Saved for Me: Synthetic dose, 0.123456 ml.');
    },
  );

  appTest(
    'a strength preset changes exact units and previews the actual stock deduction',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => createItem(f.store)))!;
      final source = (await runIo(
        tester,
        () => createContainer(f.store, item, opening: '2', strength: '10'),
      ))!;
      f.container.read(routerProvider).go('/record/${item.id}');
      await settle(tester);
      final owner = (personId: meId, itemId: item.id);
      await runIo(
        tester,
        () => f.container
            .read(dosePresetsProvider(owner).notifier)
            .add(DosePreset('5', 'mg')),
      );
      await settle(tester);
      expect(
        preset('5', 'mg'),
        findsNothing,
        reason: 'Cross-unit amounts require a real source or explicit labelled strength',
      );
      await selectSource(tester, source.id);
      await choose(tester, preset('5', 'mg'));
      expect(find.text('Deducts 0.5 ml, leaving 1.5 ml.'), findsOneWidget);
      expect((await runIo(tester, () => f.store.records()))!, isEmpty);
      await tap(tester, 'Save');
      await waitForText(tester, 'Saved for Me: Synthetic dose, 5 mg.');
      final record = (await runIo(tester, () => f.store.records()))!.single;
      expect(record.actualAmount, ExactAmount.parseEntry('5'));
      expect(record.actualUnit, 'mg');
    },
  );

  appTest(
    'editing a saved amount preserves the entered dose and supports cancellation',
    (tester) async {
      final f = await launch(tester);
      final screen = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: screen, child: const VitalApp()),
        ),
      );
      final item = (await runIo(tester, () => createItem(f.store)))!;
      f.container.read(routerProvider).go('/record/${item.id}');
      await settle(tester);
      final owner = (personId: meId, itemId: item.id);
      await runIo(tester, () async {
        final controller = f.container.read(
          dosePresetsProvider(owner).notifier,
        );
        await controller.add(DosePreset('1', 'ml'));
        await controller.add(DosePreset('2', 'ml'));
      });
      await enterAmount(tester, '9');
      await tap(tester, 'Configure');
      await choose(tester, editPreset('1', 'ml'));
      await tester.enterText(dialogAmount(), '0.25');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await settle(tester);
      expect(find.byType(DosePresetEditDialog), findsOneWidget);
      expect(savedValues(f.container, owner), ['1 ml', '2 ml']);
      if (captures.isNotEmpty) {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          f.container.read(appearanceProvider.notifier).setMode(mode);
          for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
            tester.view.physicalSize = Size(width, 844);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await settle(tester);
            expect(dialogAction('Save').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              screen,
              '${mode.name}-edit-${width.toInt()}x${scale.toInt()}',
            );
          }
        }
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.physicalSize = const Size(390, 844);
        await settle(tester);
      }
      await choose(tester, dialogAction('Save'));
      expect(savedValues(f.container, owner), ['0.25 ml', '2 ml']);
      expect(tester.widget<TextField>(amountField()).controller!.text, '9');
      expect(await runIo(tester, f.store.records), isEmpty);
      await choose(tester, editPreset('0.25', 'ml'));
      await tester.enterText(dialogAmount(), '2');
      await settle(tester);
      expect(
        find.text('That amount and unit are already saved.'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(DosePresetEditDialog), findsNothing);
      expect(savedValues(f.container, owner), ['0.25 ml', '2 ml']);
    },
  );

  appTest('a preset edit captured before lock cannot write after unlock', (
    tester,
  ) async {
    final f = await launch(tester, auth: FakeAuth());
    final item = (await runIo(tester, () => createItem(f.store)))!;
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container.read(routerProvider).go('/record/${item.id}');
    await settle(tester);
    final owner = (personId: meId, itemId: item.id);
    await runIo(
      tester,
      () => f.container
          .read(dosePresetsProvider(owner).notifier)
          .add(DosePreset('1', 'ml')),
    );
    await settle(tester);
    await tap(tester, 'Configure');
    await choose(tester, editPreset('1', 'ml'));
    final staleSave = tester
        .widget<DosePresetEditDialog>(find.byType(DosePresetEditDialog))
        .onSave;
    await tester.enterText(dialogAmount(), '0.5');
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    await tap(tester, 'Unlock');
    await settle(tester);
    expect(
      await runIo(tester, () => staleSave(DosePreset('0.5', 'ml'))),
      isFalse,
    );
    expect(savedValues(f.container, owner), ['1 ml']);
    expect(await runIo(tester, f.store.records), isEmpty);
  });

  appTest('a preset dialog keeps the old amount after failure and retries', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => createItem(f.store)))!;
    f.container.read(routerProvider).go('/record/${item.id}');
    await settle(tester);
    final owner = (personId: meId, itemId: item.id);
    final controller = f.container.read(dosePresetsProvider(owner).notifier);
    await runIo(tester, () => controller.add(DosePreset('1', 'ml')));
    await settle(tester);
    var attempts = 0;
    final dialog = showVitalDialog<void>(
      context: tester.element(find.byType(DosePresetPanel)),
      builder: (_) => DosePresetEditDialog(
        initial: DosePreset('1', 'ml'),
        allowedUnits: const {'ml'},
        otherIdentities: const {},
        onSave: (next) async {
          if (attempts++ == 0) throw StateError('synthetic writer failure');
          return controller.replace(
            DosePreset('1', 'ml'),
            next,
            allowedUnits: {'ml'},
          );
        },
      ),
    );
    await settle(tester);
    await tester.enterText(dialogAmount(), '0.5');
    await choose(tester, dialogAction('Save'));
    expect(
      find.byKey(const ValueKey('dose-preset-edit-failed')),
      findsOneWidget,
    );
    expect(savedValues(f.container, owner), ['1 ml']);
    await choose(tester, dialogAction('Save'));
    await dialog;
    expect(savedValues(f.container, owner), ['0.5 ml']);
    expect(await runIo(tester, f.store.records), isEmpty);
  });

  appTest(
    'saved amount selection and management grow at narrow widths in both themes',
    (tester) async {
      final f = await launch(tester);
      final screenKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: screenKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      final item = (await runIo(
        tester,
        () => createItem(
          f.store,
          name: 'A complete substance name that remains visible',
        ),
      ))!;
      f.container.read(routerProvider).go('/record/${item.id}');
      await settle(tester);
      final owner = (personId: meId, itemId: item.id);
      await runIo(tester, () async {
        for (final value in ['0.000001', '0.5', '1']) {
          await f.container
              .read(dosePresetsProvider(owner).notifier)
              .add(DosePreset(value, 'ml'));
        }
      });
      await settle(tester);
      await tap(tester, 'Configure');
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        f.container.read(appearanceProvider.notifier).setMode(mode);
        tester.view.physicalSize = const Size(390, 844);
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        await settle(tester);
        await choose(tester, preset('0.000001', 'ml'));
        await tester.ensureVisible(amountField());
        await settle(tester);
        await capture(tester, screenKey, '${mode.name}-dose-presets');
        for (final width in [320.0, 390.0, 430.0]) {
          tester.view.physicalSize = Size(width, 844);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          await settle(tester);
          await choose(tester, preset('0.000001', 'ml'));
          expect(find.byType(DosePresetPanel), findsOneWidget);
          expect(
            tester.getSize(preset('0.000001', 'ml')).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.takeException(), isNull);
          if (width == 320) {
            await tester.ensureVisible(find.byType(DosePresetPanel));
            await settle(tester);
            await capture(
              tester,
              screenKey,
              '${mode.name}-dose-presets-narrow-2x',
            );
          }
        }
      }
    },
  );
}
