import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/settings_toggle_row.dart';
import 'package:true_grit_vital/app/vital_app.dart';

import 'vital_app_test.dart' show launch, settle, tap, appTest;

void main() {
  testWidgets(
    'settings row exposes one switch; label, thumb, semantics and Space change once',
    (tester) async {
      final semantics = tester.ensureSemantics();

      var changes = 0;
      var value = false;
      await tester.pumpWidget(
        ShadcnApp(
          home: StatefulBuilder(
            builder: (context, setState) => SettingsToggleRow(
              label: 'Opaque surfaces',
              description: 'Use solid backgrounds.',
              value: value,
              reduceMotion: true,
              onChanged: (next) => setState(() {
                value = next;
                changes++;
              }),
            ),
          ),
        ),
      );
      final target = find.bySemanticsLabel('Opaque surfaces');
      expect(target, findsOneWidget);
      final node = tester.getSemantics(target);
      expect(
        node.getSemanticsData().flagsCollection.isToggled,
        Tristate.isFalse,
      );
      await tester.tap(find.text('Opaque surfaces'));
      await tester.pump();
      expect(changes, 1);
      expect(value, true);
      await tester.tapAt(tester.getCenter(find.byType(Switch)));
      await tester.pump();
      expect(changes, 2);
      expect(value, false);
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pump();
      expect(changes, 3);
      expect(value, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(changes, 4);
      expect(value, false);
      semantics.dispose();
    },
  );
  appTest('system brightness and reduced effects compose with saved choices', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final f = await launch(tester);
    expect(
      Theme.of(tester.element(find.byType(VitalShell))).brightness,
      Brightness.dark,
    );
    await tap(tester, 'Appearance');
    await tap(tester, 'Light');
    expect(
      Theme.of(tester.element(find.byType(AppearancePage))).brightness,
      Brightness.light,
    );
    await tap(tester, 'System');
    expect(
      Theme.of(tester.element(find.byType(AppearancePage))).brightness,
      Brightness.dark,
    );
    await tester.ensureVisible(find.text('Reduced motion is active.'));
    await tester.pump();
    expect(find.text('Reduced motion is active.'), findsOneWidget);
    expect(f.container.read(appearanceProvider).reduceMotion, false);
    expect(find.byKey(const ValueKey('opaque-sample')), findsOneWidget);
  });
  appTest('Appearance direct route returns to Today', (tester) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/appearance');
    await settle(tester);
    expect(f.container.read(routerProvider).canPop(), false);
    await tap(tester, 'Back');
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Nothing recorded'), findsOneWidget);
  });
  test('effective effects honour system and validation combinations', () {
    for (final opaque in [false, true]) {
      for (final systemOpaque in [false, true]) {
        for (final validated in [false, true]) {
          for (final motion in [false, true]) {
            for (final systemMotion in [false, true]) {
              final effective = EffectiveAppearance.compose(
                preferences: AppearancePreferences(
                  opaque: opaque,
                  reduceMotion: motion,
                ),
                systemReduceMotion: systemMotion,
                systemReduceTransparency: systemOpaque,
                glassValidated: validated,
              );
              expect(effective.opaque, opaque || systemOpaque || !validated);
              expect(effective.reduceMotion, motion || systemMotion);
            }
          }
        }
      }
    }
  });
}
