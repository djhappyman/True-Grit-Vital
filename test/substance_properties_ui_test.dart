import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'screen_settings_hub_test.dart' show loadFonts;
import 'settings_vault_ui_test.dart' show capture;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

Finder field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);
Future<void> enter(WidgetTester t, String label, String value) async {
  final f = field(label);
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await settle(t);
}

Future<void> choose(WidgetTester t, String label) async {
  final f = find.text(label).last;
  await t.ensureVisible(f);
  await settle(t);
  await t.tap(f);
  await settle(t);
}

void main() {
  setUpAll(loadFonts);
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('guided substance and exact recording in ${mode.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final f = await launch(tester);
      final router = f.container.read(routerProvider);
      final key = GlobalKey();
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: key, child: const VitalApp()),
        ),
      );
      router.go('/create');
      await waitForText(tester, 'New substance');
      await enter(tester, 'Full name', 'Synthetic tablet');
      await enter(tester, 'Type', 'Medicine');
      await choose(tester, 'Oral');
      expect(find.text('Oil-based'), findsNothing);
      await choose(tester, 'Tablet');
      await enter(tester, 'Strength per tablet/capsule', '250');
      await choose(tester, 'micrograms');
      await choose(tester, 'Tablet');
      expect(
        tester
            .widget<TextField>(field('Strength per tablet/capsule'))
            .controller!
            .text,
        '250',
      );
      await choose(tester, 'Half-life');
      await enter(tester, 'Half-life value', '12');
      await enter(tester, 'Ingredient / formulation', 'Synthetic tablet, oral');
      await tester.ensureVisible(find.text('Taken as'));
      await settle(tester);
      await capture(tester, key, '${mode.name}-substance-form');
      final save = find.widgetWithText(VitalButton, 'Save');
      // Create uses StitchButton; its visible Create label is the canonical action.
      expect(save, findsNothing);
      await choose(tester, 'Create');
      await waitForText(tester, 'Setup');
      final items = (await runIo(tester, () => f.store.items()))!;
      final item = items.single;
      expect(item.unit, 'count');
      expect(
        (await runIo(
          tester,
          () => f.store.itemDetail(item.id),
        ))!.profile!.strengthMg,
        ExactAmount.parseEntry('0.25'),
      );
      router.go('/record/${item.id}');
      await waitForText(tester, 'Saved strength');
      await tester.enterText(find.byType(TextField).first, '2');
      await settle(tester);
      expect(find.textContaining('0.5'), findsWidgets);
      await capture(tester, key, '${mode.name}-tablet-dose');
      await choose(tester, 'Save');
      await waitForText(tester, 'Saved for Me: Synthetic tablet, 2 count.');
      final dose = (await runIo(tester, f.store.records))!.single;
      expect(dose.labelledStrength!.mgPerCount, ExactAmount.parseEntry('0.25'));
      expect(dose.actualUnit, 'count');
      expect(dose.originalEntry, '2');
      expect(tester.takeException(), isNull);
    });
  }
  appTest(
    'mixed vial saves its own totals and narrow large-text form remains usable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 880);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      f.container.read(appearanceProvider.notifier).setReduceMotion(true);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: key, child: const VitalApp()),
        ),
      );
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: 'mixed-item',
          name: 'Synthetic mixed vial',
          form: 'Powder',
          unit: 'ml',
          type: 'Medicine',
          expectedPersonRevision: 2,
          profile: SubstanceProfile(
            route: SubstanceRoute.injectable,
            form: SubstanceForm.powderToMix,
          ),
        ),
      ))!;
      f.container.read(routerProvider).go('/stock/me/create?item=${item.id}');
      await waitForText(tester, 'Powder amount');
      await enter(tester, 'Container name', 'Vial A');
      await enter(tester, 'Powder amount', '24');
      await enter(tester, 'Final volume (ml)', '12');
      expect(find.text('1 ml contains approximately 2 mg.'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Final volume (ml)'));
      await settle(tester);
      await capture(tester, key, 'mixed-vial-large-text');
      await choose(tester, 'Mixing details');
      await enter(tester, 'Mixing liquid (optional)', 'Entered mixing liquid');
      await enter(tester, 'Liquid added (ml)', '11.8');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      await choose(tester, 'Create');
      await waitForText(tester, 'Vial A');
      final containers = (await runIo(
        tester,
        () => f.store.stockContainers(personId: meId, itemId: item.id),
      ))!;
      expect(containers.single.strength.mgPerMl, ExactAmount.parseEntry('2'));
      expect(containers.single.strength.preparation!.addedVolumeMl, '11.8');
      expect(tester.takeException(), isNull);
    },
  );
}
