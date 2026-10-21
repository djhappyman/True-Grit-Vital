import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/dose_preset_panel.dart';
import 'package:true_grit_vital/features/recording/dose_presets.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';

import 'screen_record_dose_test.dart'
    show createItem, createContainer, enterAmount, selectSource;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder preset(String amount, String unit) =>
    find.byKey(ValueKey('dose-preset-$amount\u0000$unit'));
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
