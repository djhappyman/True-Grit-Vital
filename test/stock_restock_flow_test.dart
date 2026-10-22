import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/stock/restock_sheet.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'stock_ui_test.dart' show item, container, enter, field;
import 'private_drafts_ui_test.dart' show FakeAuth;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

void main() {
  appTest(
    'guided restock adds an exact amount to the same physical container',
    (tester) async {
      final f = await launch(tester);
      final medicine = (await runIo(tester, () => item(f.store)))!;
      final pack = (await runIo(tester, () => container(f.store, medicine)))!;
      f.container.read(routerProvider).go('/stock/$meId?item=${medicine.id}');
      await waitForText(tester, pack.label);
      final action = find.byKey(ValueKey('stock-restock-${pack.id}'));
      await tester.ensureVisible(action);
      await settle(tester);
      await tester.tap(action);
      await waitForText(tester, 'New pack');
      expect(find.byType(RestockSheet), findsOneWidget);
      expect(find.byType(VitalTaskFrame), findsOneWidget);
      await tap(tester, 'Add');
      await waitForText(tester, 'Amount');
      expect(find.byType(VitalTaskFrame), findsOneWidget);
      await enter(tester, 'Amount', '0.125');
      await tap(tester, 'Save');
      await waitForText(tester, 'Remaining: 2.125 ml');
      final saved = (await runIo(
        tester,
        () => f.store.stockContainerById(personId: meId, containerId: pack.id),
      ))!;
      expect(saved.balance.value, ExactAmount.parseEntry('2.125'));
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainers(personId: meId),
        ))!.length,
        1,
      );
      expect((await runIo(tester, () => f.store.records()))!, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('a new pack keeps independent strength, balance and batch facts', (
    tester,
  ) async {
    final f = await launch(tester);
    final medicine = (await runIo(tester, () => item(f.store)))!;
    final pack = (await runIo(tester, () => container(f.store, medicine)))!;
    await runIo(
      tester,
      () => f.store.updateStockMetadata(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: 2,
        expectedGeneration: f.store.generation,
        containerId: pack.id,
        expectedContainerRevision: pack.revision,
        lot: 'ORIGINAL',
        expiryDate: CivilDate(2027, 1, 1),
        capacity: ExactAmount.parseEntry('10'),
      ),
    );
    f.container.read(routerProvider).push('/stock/$meId/restock/${pack.id}');
    await waitForText(tester, 'New pack');
    await tap(tester, 'Create');
    await waitForText(tester, 'Container name');
    expect(
      tester.widget<TextField>(field('Container name')).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<TextField>(field('Labelled strength')).controller!.text,
      isEmpty,
    );
    await enter(tester, 'Container name', 'New separate vial');
    await enter(tester, 'Labelled strength', 'New label, strength unknown');
    await tap(tester, 'Create');
    await waitForText(tester, 'New separate vial');
    final packs = (await runIo(
      tester,
      () => f.store.stockContainers(personId: meId),
    ))!;
    expect(packs.length, 2);
    final added = packs.singleWhere((c) => c.id != pack.id);
    final original = packs.singleWhere((c) => c.id == pack.id);
    expect(added.lot, isNull);
    expect(added.expiryDate, isNull);
    expect(added.capacity, isNull);
    expect(added.balance.value, isNull);
    expect(added.strength.mgPerMl, isNull);
    expect(original.lot, 'ORIGINAL');
    expect(original.expiryDate, CivilDate(2027, 1, 1));
    expect(original.balance.value, ExactAmount.parseEntry('2'));
    expect((await runIo(tester, () => f.store.records()))!, isEmpty);
    expect(tester.takeException(), isNull);
  });

  appTest(
    'cancelling the chooser and an unavailable source make no stock changes',
    (tester) async {
      final f = await launch(tester);
      final medicine = (await runIo(tester, () => item(f.store)))!;
      final pack = (await runIo(tester, () => container(f.store, medicine)))!;
      final router = f.container.read(routerProvider);
      router.push('/stock/$meId/restock/${pack.id}');
      await waitForText(tester, 'New pack');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(RestockSheet), findsNothing);
      router.push('/stock/$meId/restock/not-a-container');
      await settle(tester);
      expect(find.text('New pack'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(RestockSheet),
          matching: find.text('Add'),
        ),
        findsNothing,
      );
      final after = (await runIo(
        tester,
        () => f.store.stockContainerById(personId: meId, containerId: pack.id),
      ))!;
      expect(after.revision, pack.revision);
      expect(after.balance.value, pack.balance.value);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'restock choices stay reachable at 320px and 2x text in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final f = await launch(tester);
        f.container.read(appearanceProvider.notifier).setMode(mode);
        final medicine = (await runIo(tester, () => item(f.store)))!;
        final pack = (await runIo(
          tester,
          () => container(
            f.store,
            medicine,
            label: 'Long container name with its original identity',
          ),
        ))!;
        f.container
            .read(routerProvider)
            .push('/stock/$meId/restock/${pack.id}');
        await waitForText(tester, 'New pack');
        await tap(tester, 'Add');
        await waitForText(tester, 'Amount');
        await enter(tester, 'Amount', '0.25');
        expect(tester.takeException(), isNull);
      },
    );
  }
  appTest(
    'restock chooser hides names under lock and preserves an existing movement draft',
    (tester) async {
      final f = await launch(tester, auth: FakeAuth());
      final medicine = (await runIo(tester, () => item(f.store)))!;
      final pack = (await runIo(tester, () => container(f.store, medicine)))!;
      final router = f.container.read(routerProvider);
      router.go('/stock/$meId/adjust/${pack.id}');
      await settle(tester);
      await tap(tester, 'Waste');
      await enter(tester, 'Amount', '0.250000');
      router.go('/today');
      await settle(tester);
      router.push('/stock/$meId/restock/${pack.id}');
      await waitForText(tester, 'New pack');
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      expect(find.text(pack.label), findsNothing);
      expect(find.text('New pack'), findsNothing);
      await tap(tester, 'Unlock');
      await waitForText(tester, 'New pack');
      await tap(tester, 'Add');
      await waitForText(tester, 'Amount');
      expect(
        tester.widget<TextField>(field('Amount')).controller!.text,
        '0.250000',
      );
      expect(
        find.text(
          'An unfinished stock change has been restored. Review it before saving.',
        ),
        findsOneWidget,
      );
      // The previous draft's explicit intent wins over a new entry shortcut.
      await tap(tester, 'Save');
      await waitForText(tester, 'Remaining: 1.75 ml');
      final saved = (await runIo(
        tester,
        () => f.store.stockContainerById(personId: meId, containerId: pack.id),
      ))!;
      expect(saved.balance.value, ExactAmount.parseEntry('1.75'));
      expect(tester.takeException(), isNull);
    },
  );

  appTest('capture the restock chooser in both themes', (tester) async {
    const output = String.fromEnvironment('VITAL_RESTOCK_CAPTURES');
    if (output.isEmpty) return;
    await loadFonts();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await launch(tester);
    final medicine = (await runIo(
      tester,
      () => item(f.store, name: 'Example medicine'),
    ))!;
    final pack = (await runIo(
      tester,
      () => container(f.store, medicine, label: 'Current bottle'),
    ))!;
    final key = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: RepaintBoundary(key: key, child: const VitalApp()),
      ),
    );
    f.container.read(routerProvider).push('/stock/$meId/restock/${pack.id}');
    await waitForText(tester, 'New pack');
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$output/${mode.name}-restock.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
