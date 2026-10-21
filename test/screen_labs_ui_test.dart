import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/reports/reports_page.dart';
import 'package:true_grit_vital/features/supporting/screen_labs_widgets.dart';
import 'package:true_grit_vital/features/supporting/screen_labs_collection.dart';
import 'package:true_grit_vital/features/supporting/screen_labs_latest.dart';

import 'design_system_test.dart' show host;

import 'package:true_grit_vital/features/supporting/supporting_form.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_trends.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const _marker = 'Vitamin D (25-OH)';

SupportingProvenance _source({String laboratory = 'Source laboratory'}) =>
    SupportingProvenance(
      mode: SupportingProvenanceMode.manualTranscription,
      laboratoryId: 'lab-a',
      laboratoryName: laboratory,
      methodId: 'method-a',
      methodText: 'Method A',
      specimenId: 'specimen-a',
      specimenText: 'Serum',
    );

LabResultSnapshot _value(
  String id,
  String metric,
  String name,
  String value,
  String unit, {
  SourceReferenceRange? range,
  String? flag,
}) => LabResultSnapshot(
  id: id,
  metricId: metric,
  markerName: name,
  value: SupportingValue.numeric(value),
  unit: unit,
  referenceRange: range,
  sourceFlag: flag,
);

Future<SupportingRevision> _savePanel(
  WidgetTester tester,
  RecordStore store, {
  required String id,
  required String title,
  required SupportingDate collection,
  required List<LabResultSnapshot> results,
  List<SupportingContextLink> links = const [],
  String laboratory = 'Source laboratory',
}) async {
  final owner = (await runIo(tester, () => store.profileById(meId)))!;
  return (await runIo(
    tester,
    () => store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: 'save-$id',
        generation: store.generation,
        expectedPersonRevision: owner.revision,
        panel: LabPanelSnapshot(
          id: SupportingRecordId(id: id, personId: meId),
          title: title,
          collectionDate: collection,
          reportDate: collection,
          provenance: _source(laboratory: laboratory),
          results: results,
          contextLinks: links,
        ),
      ),
    ),
  ))!;
}

Future<SupportingRevision> _saveObservation(
  WidgetTester tester,
  RecordStore store, {
  required String id,
  required String title,
  required SupportingDate measured,
  required List<LabResultSnapshot> results,
}) async {
  final owner = (await runIo(tester, () => store.profileById(meId)))!;
  return (await runIo(
    tester,
    () => store.saveObservation(
      SaveObservationCommand(
        commandId: 'save-$id',
        generation: store.generation,
        expectedPersonRevision: owner.revision,
        observation: ObservationSnapshot(
          id: SupportingRecordId(id: id, personId: meId),
          title: title,
          measuredDate: measured,
          provenance: _source(),
          components: results,
        ),
      ),
    ),
  ))!;
}

Future<void> _void(WidgetTester tester, RecordStore store, String id) async {
  final owner = (await runIo(tester, () => store.profileById(meId)))!;
  final record = (await runIo(tester, () => store.supportingRecord(meId, id)))!;
  await runIo(
    tester,
    () => store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: 'void-$id',
        generation: store.generation,
        personId: meId,
        id: id,
        expectedPersonRevision: owner.revision,
        expectedRevision: record.revision,
      ),
    ),
  );
}

Future<
  ({RecordStore store, ProviderContainer container, String path, List<int> key})
>
_seed(WidgetTester tester) async {
  final fixture = await launch(tester);
  final owner = (await runIo(tester, () => fixture.store.profileById(meId)))!;
  final item = (await runIo(
    tester,
    () => fixture.store.createItem(
      commandId: 'item',
      expectedPersonRevision: owner.revision,
      name: 'Telmisartan 40 mg',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    ),
  ))!;
  await _savePanel(
    tester,
    fixture.store,
    id: 'earlier',
    title: 'Earlier panel',
    collection: SupportingDate.day(CivilDate(2026, 10, 1)),
    results: [
      _value('earlier-vitamin', 'vitamin', _marker, '32.0', 'ng/mL'),
      _value('earlier-crp', 'crp', 'hs-CRP', '0.55', 'mg/L'),
    ],
  );
  await _savePanel(
    tester,
    fixture.store,
    id: 'complete',
    title: 'Complete panel',
    collection: SupportingDate.day(CivilDate(2026, 10, 19)),
    links: [
      SupportingContextLink(
        id: item.id,
        personId: meId,
        kind: SupportingContextKind.item,
      ),
    ],
    results: [
      _value(
        'complete-vitamin',
        'vitamin',
        _marker,
        '58.4',
        'ng/mL',
        range: SourceReferenceRange(originalText: '40 to 70'),
        flag: 'H',
      ),
      _value('complete-crp', 'crp', 'hs-CRP', '0.45', 'mg/L'),
    ],
  );
  await _savePanel(
    tester,
    fixture.store,
    id: 'undated',
    title: 'Undated panel',
    collection: SupportingDate.unknown(),
    results: [_value('undated-crp', 'crp', 'hs-CRP', '0.60', 'mg/L')],
  );
  await _saveObservation(
    tester,
    fixture.store,
    id: 'observation',
    title: 'Home observation',
    measured: SupportingDate.day(CivilDate(2026, 10, 10)),
    results: [_value('obs-pulse', 'pulse', 'Resting pulse', '64', 'bpm')],
  );
  await _void(tester, fixture.store, 'observation');
  return fixture;
}

void main() {
  appTest('an empty list does not hide a failed latest-value read', (
    tester,
  ) async {
    final fixture = await launch(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: ProviderScope(
          overrides: [
            screenLabsLatestProvider.overrideWith(
              (ref, request) =>
                  Stream<ScreenLabsLatest>.error(StateError('unavailable')),
            ),
          ],
          child: host(const ScreenLabsCollectionPage(location: '/supporting')),
        ),
      ),
    );
    await settle(tester);
    await waitForText(
      tester,
      'Unable to load supporting records. Retry this view.',
    );
    expect(
      find.text('Unable to load supporting records. Retry this view.'),
      findsOneWidget,
    );
    expect(find.text('No lab records'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  appTest('labs collection keeps exact values, units, dates and sources', (
    tester,
  ) async {
    final fixture = await _seed(tester);
    fixture.container.read(routerProvider).go('/supporting');
    await settle(tester);
    await waitForText(tester, 'Biomarkers & Labs');

    expect(find.text('Biomarkers & Labs'), findsOneWidget);
    expect(find.text('Person: Me'), findsNothing);
    expect(find.text('2 markers'), findsOneWidget);
    expect(
      find.text('From the 2 most recent dated records, newest first.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Records without a complete date, and voided records, are not included.',
      ),
      findsOneWidget,
    );
    expect(find.text(_marker), findsOneWidget);
    expect(find.text('58.4'), findsOneWidget);
    expect(find.text('ng/mL'), findsOneWidget);
    expect(find.textContaining('Previous value: 32.0 ng/mL'), findsOneWidget);
    expect(find.textContaining('Change: +26.4 ng/mL'), findsOneWidget);
    expect(find.text('Source range: 40 to 70'), findsOneWidget);
    expect(find.text('Source flag: H'), findsOneWidget);
    expect(find.text('Laboratory: Source laboratory'), findsWidgets);
    expect(find.text('From Complete panel.'), findsNWidgets(2));
    expect(find.text('Linked: Telmisartan 40 mg'), findsOneWidget);

    expect(find.text('3 records on this page'), findsOneWidget);
    expect(find.text('Complete panel'), findsOneWidget);
    expect(find.text('Earlier panel'), findsOneWidget);
    expect(find.text('Undated panel'), findsOneWidget);
    expect(find.textContaining('Date unknown'), findsWidgets);
    expect(find.text('2 results'), findsNWidgets(2));
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Source file saved'), findsNothing);

    for (final forbidden in [
      'Optimal',
      'Low Risk',
      'In Target',
      'Cryptographically Verified',
      'SHA-256',
      'Synced Archives',
      'Zero out-of-range',
    ]) {
      expect(
        find.textContaining(forbidden),
        findsNothing,
        reason: 'No invented clinical, cryptographic or sync claim: $forbidden',
      );
    }

    expect(
      tester.getSize(find.widgetWithText(StitchButton, 'Add')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.widgetWithText(StitchButton, 'Filters').first).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.widgetWithText(StitchButton, 'Trends').first).height,
      greaterThanOrEqualTo(48),
    );

    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'Vitamin D \(25-OH\).*Value: 58.4 ng/mL.*Source range: 40 to 70.*Collection date: .*From Complete panel.*Laboratory: Source laboratory.*Source flag: H',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Open linked record Telmisartan 40 mg')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  appTest('labs filters preserve kind, empty, voided and date states', (
    tester,
  ) async {
    final fixture = await _seed(tester);
    fixture.container.read(routerProvider).go('/supporting');
    await settle(tester);
    await waitForText(tester, 'Complete panel');

    await tap(tester, 'Observations');
    await waitForText(tester, 'No records in this view');
    expect(find.text('No records in this view'), findsOneWidget);
    expect(find.text('Change the filters or add a record.'), findsOneWidget);

    await tap(tester, 'Clear');
    await waitForText(tester, 'Complete panel');
    expect(find.text('Complete panel'), findsOneWidget);

    await tap(tester, 'Filters');
    await tap(tester, 'Include voided');
    await tap(tester, 'Apply');
    await waitForText(tester, 'Home observation');
    expect(find.text('Home observation'), findsOneWidget);
    expect(find.text('Voided'), findsOneWidget);
    expect(find.text('4 records on this page'), findsOneWidget);

    // The latest-value projection keeps excluding voided records.
    expect(find.text('2 markers'), findsOneWidget);
    expect(
      find.text(
        'Records without a complete date, and voided records, are not included.',
      ),
      findsOneWidget,
    );
  });

  appTest(
    'labs collection opens existing add, trends, files, detail and reports',
    (tester) async {
      final fixture = await launch(tester);
      await _savePanel(
        tester,
        fixture.store,
        id: 'only',
        title: 'Only complete panel',
        collection: SupportingDate.day(CivilDate(2026, 10, 19)),
        results: [
          _value('only-vitamin', 'vitamin', _marker, '58.4', 'ng/mL'),
          _value('only-crp', 'crp', 'hs-CRP', '0.45', 'mg/L'),
        ],
      );
      final router = fixture.container.read(routerProvider);
      router.go('/supporting');
      await settle(tester);
      await waitForText(tester, 'Only complete panel');
      final before = (await runIo(
        tester,
        () => fixture.store.supportingRecords(SupportingQuery(personId: meId)),
      ))!.entries.length;

      await tap(tester, 'Trends');
      expect(find.byType(SupportingTrendsPage), findsOneWidget);
      router.go('/supporting');
      await settle(tester);
      await waitForText(tester, 'Only complete panel');

      await tap(tester, 'Files');
      await waitForText(tester, 'Supporting record: Only complete panel');
      router.go('/supporting');
      await settle(tester);
      await waitForText(tester, 'Only complete panel');

      await tap(tester, 'Open');
      await settle(tester);
      expect(find.byType(SupportingDetailPage), findsOneWidget);
      router.go('/supporting');
      await settle(tester);
      await waitForText(tester, 'Only complete panel');

      await tap(tester, 'Reports');
      expect(find.byType(ReportsPage), findsOneWidget);
      router.go('/supporting');
      await settle(tester);
      await waitForText(tester, 'Only complete panel');

      await tap(tester, 'Add');
      expect(find.byType(SupportingForm), findsOneWidget);

      final after = (await runIo(
        tester,
        () => fixture.store.supportingRecords(SupportingQuery(personId: meId)),
      ))!.entries.length;
      expect(after, before);
    },
  );

  appTest('an undated record keeps a labelled no-latest state', (tester) async {
    final fixture = await launch(tester);
    await _savePanel(
      tester,
      fixture.store,
      id: 'undated-only',
      title: 'Undated source record',
      collection: SupportingDate.unknown(),
      results: [_value('undated-only-value', 'crp', 'hs-CRP', '0.45', 'mg/L')],
    );
    fixture.container.read(routerProvider).go('/supporting');
    await settle(tester);
    await waitForText(tester, 'No dated results');
    expect(find.text('No dated results'), findsOneWidget);
    expect(
      find.text('Add a panel with a collection date to see a latest value.'),
      findsOneWidget,
    );
    expect(find.text('Undated source record'), findsOneWidget);
    expect(find.text('0.45'), findsNothing);
  });

  appTest('labs collection preserves paging cursors', (tester) async {
    final fixture = await launch(tester);
    for (var index = 1; index <= 26; index++) {
      await _savePanel(
        tester,
        fixture.store,
        id: 'page-$index',
        title: 'Panel ${index.toString().padLeft(2, '0')}',
        collection: SupportingDate.day(CivilDate(2026, 9, index)),
        results: [
          _value(
            'page-value-$index',
            'marker',
            'Saved marker',
            '$index',
            'mg/L',
          ),
        ],
      );
    }
    final router = fixture.container.read(routerProvider);
    router.go('/supporting');
    await settle(tester);
    await waitForText(tester, 'Panel 26');
    expect(find.text('25 records on this page'), findsOneWidget);
    expect(find.text('Panel 02'), findsOneWidget);
    expect(find.text('Panel 01'), findsNothing);
    expect(find.text('1 marker'), findsOneWidget);

    await tap(tester, 'Next');
    await waitForText(tester, 'Panel 01');
    expect(find.text('1 record on this page'), findsOneWidget);
    expect(find.text('Panel 26'), findsNothing);

    await tap(tester, 'Previous');
    await waitForText(tester, 'Panel 26');
    expect(find.text('25 records on this page'), findsOneWidget);
  });

  appTest('labs collection keeps actions intact at 430px', (tester) async {
    final fixture = await launch(tester);
    tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _savePanel(
      tester,
      fixture.store,
      id: 'wide',
      title: 'Wide layout panel with a complete saved title',
      collection: SupportingDate.day(CivilDate(2026, 10, 19)),
      results: [_value('wide-vitamin', 'vitamin', _marker, '58.4', 'ng/mL')],
    );
    fixture.container.read(routerProvider).go('/supporting');
    await settle(tester);
    await waitForText(tester, '58.4');
    expect(tester.takeException(), isNull);
    expect(find.text('58.4'), findsOneWidget);
    expect(find.text('ng/mL'), findsOneWidget);
    expect(
      find.text('Wide layout panel with a complete saved title'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.widgetWithText(StitchButton, 'Open').first).height,
      greaterThanOrEqualTo(48),
    );
  });

  appTest('labs collection stacks at 320px and 200 percent without overflow', (
    tester,
  ) async {
    final fixture = await launch(tester);
    tester.binding.setSurfaceSize(const Size(320, 760));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await _savePanel(
      tester,
      fixture.store,
      id: 'narrow',
      title: 'A complete panel with a deliberately long saved source title',
      collection: SupportingDate.day(CivilDate(2026, 10, 19)),
      laboratory: 'A very long source laboratory name that must stay complete',
      results: [
        _value(
          'narrow-vitamin',
          'vitamin',
          'A deliberately long marker name that must stay complete',
          '58.4',
          'ng/mL',
        ),
      ],
    );
    fixture.container.read(routerProvider).go('/supporting');
    await settle(tester);
    await waitForText(tester, 'LATEST RESULTS');
    expect(tester.takeException(), isNull);
    expect(
      find.text('A deliberately long marker name that must stay complete'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find
          .textContaining(
            'A very long source laboratory name that must stay complete',
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ScreenLabsLatestCard), findsOneWidget);
    expect(find.byType(ScreenLabsRecordCard), findsOneWidget);
  });
}
