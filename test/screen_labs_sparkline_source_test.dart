import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_source_link.dart';
import 'package:true_grit_vital/features/supporting/supporting_sparkline.dart';

import 'app_lock_controller_test.dart' show ControlledAuth;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const _marker = 'Spark marker';
const _value = '2.00';

SupportingRevision _panel(
  String id, {
  required String title,
  int day = 15,
  String value = _value,
}) => SupportingRevision(
  snapshot: LabPanelSnapshot(
    id: SupportingRecordId(id: id, personId: meId),
    title: title,
    collectionDate: SupportingDate.day(CivilDate(2026, 10, day)),
    reportDate: SupportingDate.unknown(),
    provenance: SupportingProvenance(
      mode: SupportingProvenanceMode.manualTranscription,
      laboratoryId: 'lab',
      methodId: 'method',
      specimenId: 'serum',
    ),
    results: [
      LabResultSnapshot(
        id: 'result-$id',
        metricId: 'spark',
        markerName: _marker,
        value: SupportingValue.numeric(value),
        unit: 'mg/L',
      ),
    ],
  ),
  revision: 1,
  operationId: '$id-1',
  enteredAt: DateTime.utc(2026),
  revisionEnteredAt: DateTime.utc(2026),
);

Future<void> _save(
  WidgetTester tester,
  RecordStore store,
  List<SupportingRevision> records,
) async {
  final owner = (await runIo(tester, () => store.profileById(meId)))!;
  for (final record in records) {
    await runIo(
      tester,
      () => store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'save-${record.id.id}',
          generation: store.generation,
          expectedPersonRevision: owner.revision,
          panel: record.snapshot as LabPanelSnapshot,
        ),
      ),
    );
  }
}

Future<void> _openTable(WidgetTester tester) async {
  await waitForText(tester, _marker);
  await tap(tester, 'Table');
  await waitForText(tester, '$_value mg/L');
}

Key _sourceKey(String id) => ValueKey('spark-source-$id-result-$id');

void main() {
  setUpAll(loadFonts);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'spark table opens identical saved points by identity and returns in ${mode.name}',
      (tester) async {
        final handle = tester.ensureSemantics();
        final f = await launch(tester);
        await _save(tester, f.store, [
          _panel('alpha', title: 'Alpha panel'),
          _panel('beta', title: 'Beta panel'),
        ]);
        f.container.read(appearanceProvider.notifier).setMode(mode);
        f.container
            .read(routerProvider)
            .go('/supporting?person=me&kind=labPanel');
        await _openTable(tester);

        final spark = find.byType(ScreenLabsSparkline);
        expect(spark, findsOneWidget);
        final opens = find.descendant(of: spark, matching: find.text('Open'));
        expect(opens, findsNWidgets(2));
        for (final id in ['alpha', 'beta']) {
          expect(
            tester.getSize(find.byKey(_sourceKey(id))).height,
            greaterThanOrEqualTo(48),
          );
        }

        // Both points have the same saved date and value. The accessible name
        // and the opened record still follow the saved record identity.
        final alphaData = tester
            .getSemantics(find.byKey(_sourceKey('alpha')))
            .getSemanticsData();
        expect(alphaData.hasAction(SemanticsAction.tap), isTrue);
        expect(alphaData.label, contains('Alpha panel'));
        expect(alphaData.label, contains('$_value mg/L'));
        final betaLabel = tester
            .getSemantics(find.byKey(_sourceKey('beta')))
            .getSemanticsData()
            .label;
        expect(betaLabel, contains('Beta panel'));

        final alpha = find.byKey(_sourceKey('alpha'));
        await tester.ensureVisible(alpha);
        await settle(tester);
        final focusNode = Focus.of(
          tester.element(
            find.descendant(of: alpha, matching: find.text('Open')),
          ),
        );
        focusNode.requestFocus();
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);

        var detail = tester.widget<SupportingDetailPage>(
          find.byType(SupportingDetailPage),
        );
        expect(detail.id, 'alpha');
        expect(detail.personId, meId);
        expect(detail.returnLocation, contains('kind=labPanel'));
        expect(detail.returnLocation, contains('person=me'));
        expect(find.text('Alpha panel'), findsOneWidget);

        await tap(tester, 'Back');
        await settle(tester);
        expect(find.byType(SupportingDetailPage), findsNothing);
        expect(find.text('$_value mg/L'), findsNWidgets(2));
        expect(f.container.read(routerProvider).canPop(), isFalse);

        final beta = find.byKey(_sourceKey('beta'));
        await tester.ensureVisible(beta);
        await settle(tester);
        await tester.tap(beta);
        await settle(tester);
        detail = tester.widget<SupportingDetailPage>(
          find.byType(SupportingDetailPage),
        );
        expect(detail.id, 'beta');
        expect(find.text('Beta panel'), findsOneWidget);

        // Opening a source is navigation only: no revision or draft changes.
        expect(
          (await runIo(
            tester,
            () => f.store.supportingRecord(meId, 'alpha'),
          ))!.revision,
          1,
        );
        expect(
          (await runIo(
            tester,
            () => f.store.supportingRecord(meId, 'beta'),
          ))!.revision,
          1,
        );
        expect((await runIo(tester, f.store.drafts))!, isEmpty);
        handle.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('spark source rows fit 320px double text in ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final f = await launch(tester);
      await _save(tester, f.store, [
        _panel(
          'narrow-alpha',
          title: 'A complete panel title that stays readable when it wraps',
        ),
        _panel(
          'narrow-beta',
          title: 'Another complete panel title that stays readable',
        ),
      ]);
      f.container.read(appearanceProvider.notifier).setMode(mode);
      f.container
          .read(routerProvider)
          .go('/supporting?person=me&kind=labPanel');
      await _openTable(tester);
      expect(tester.takeException(), isNull);
      for (final id in ['narrow-alpha', 'narrow-beta']) {
        final source = find.byKey(_sourceKey(id));
        await tester.ensureVisible(source);
        await settle(tester);
        expect(tester.getSize(source).height, greaterThanOrEqualTo(48));
      }
      final source = find.byKey(_sourceKey('narrow-alpha'));
      await tester.ensureVisible(source);
      await settle(tester);
      await tester.tap(source);
      await settle(tester);
      expect(
        tester
            .widget<SupportingDetailPage>(find.byType(SupportingDetailPage))
            .id,
        'narrow-alpha',
      );
      expect(
        find.text('A complete panel title that stays readable when it wraps'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  appTest('locked source detail hides the saved record', (tester) async {
    final f = await launch(tester, auth: ControlledAuth());
    await _save(tester, f.store, [_panel('locked', title: 'Locked panel')]);
    f.container.read(routerProvider).go('/supporting?person=me&kind=labPanel');
    await _openTable(tester);
    await tester.tap(find.byKey(_sourceKey('locked')));
    await settle(tester);
    expect(
      tester.widget<SupportingDetailPage>(find.byType(SupportingDetailPage)).id,
      'locked',
    );
    expect(find.text('Locked panel'), findsOneWidget);

    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Unlock'), findsWidgets);
    expect(find.text('Locked panel'), findsNothing);
    expect(find.text('$_value mg/L'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('an unavailable saved point keeps established no-content recovery', (
    tester,
  ) async {
    final f = await launch(tester);
    final location = supportingSourceLocation(
      SupportingRecordId(id: 'deleted', personId: meId),
      returnLocation: '/supporting?person=me&kind=labPanel',
    );
    expect(location, contains('/supporting/me/deleted'));
    expect(location, contains('return='));
    f.container.read(routerProvider).go(location);
    await waitForText(
      tester,
      'This supporting record is unavailable for this person.',
    );
    expect(find.text('$_value mg/L'), findsNothing);
    expect((await runIo(tester, f.store.drafts))!, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
