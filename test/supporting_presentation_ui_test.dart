import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_trends.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

Future<void> enter(WidgetTester tester, String label, String value) async {
  final field = find
      .byWidgetPredicate((w) => w is LabelledInput && w.label == label)
      .first;
  await tester.ensureVisible(field);
  await settle(tester);
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(TextField)),
    value,
  );
  await tester.pump();
}

LabPanelSnapshot panel(
  String id, {
  required String title,
  String labId = 'lab-a',
  String labName = 'Lab One',
  String methodId = 'method-a',
  String specimenId = 'specimen-a',
  SupportingDate? collection,
  String value = '1',
  SupportingProvenance? provenance,
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: title,
  collectionDate: collection ?? SupportingDate.day(CivilDate(2026, 10, 1)),
  reportDate: SupportingDate.day(CivilDate(2026, 10, 5)),
  provenance:
      provenance ??
      SupportingProvenance(
        mode: SupportingProvenanceMode.manualTranscription,
        laboratoryId: labId,
        laboratoryName: labName,
        methodId: methodId,
        methodText: 'Method A',
        specimenId: specimenId,
        specimenText: 'Serum',
      ),
  results: [
    LabResultSnapshot(
      id: 'result-$id',
      metricId: 'metric',
      markerName: 'Marker',
      originalMarkerText: 'Marker',
      value: SupportingValue.numeric(value),
      unit: 'mg/L',
      referenceRange: SourceReferenceRange(originalText: '3 to 7'),
    ),
  ],
);

Future<SupportingRevision> save(
  WidgetTester tester,
  RecordStore store,
  LabPanelSnapshot snapshot, {
  int? expectedRevision,
}) async {
  final person = (await runIo(tester, () => store.profileById(meId)))!;
  return (await runIo(
    tester,
    () => store.saveLabPanel(
      SaveLabPanelCommand(
        commandId:
            'save-${snapshot.id.id}-${snapshot.collectionDate.precision.name}',
        generation: store.generation,
        expectedPersonRevision: person.revision,
        expectedRevision: expectedRevision,
        panel: snapshot,
      ),
    ),
  ))!;
}

void main() {
  appTest('supporting load failure names this view and retries in place', (
    tester,
  ) async {
    final f = await launch(tester);
    f.store.suspendWrites(true);
    f.container.read(routerProvider).go('/supporting?person=$meId');
    await settle(tester);
    expect(
      find.text('Unable to load supporting records. Retry this view.'),
      findsOneWidget,
    );
    f.store.suspendWrites(false);
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(
      find.text('Unable to load supporting records. Retry this view.'),
      findsNothing,
    );
    expect(find.text('Supporting records'), findsOneWidget);
  });

  appTest(
    'observation form hides laboratory-only fields and marker pickers open per row',
    (tester) async {
      final f = await launch(tester);
      f.container.read(routerProvider).go('/supporting/$meId/add-observation');
      await settle(tester);
      await tap(tester, 'Add');
      expect(find.text('Component'), findsOneWidget);
      expect(find.text('Original marker'), findsNothing);
      expect(find.text('Source range'), findsNothing);
      expect(find.text('Source flag'), findsNothing);
      expect(find.text('Original unit'), findsOneWidget);
      final valueField = tester.widget<TextField>(
        find.descendant(
          of: find
              .byWidgetPredicate(
                (w) => w is LabelledInput && w.label == 'Original value',
              )
              .first,
          matching: find.byType(TextField),
        ),
      );
      expect(valueField.maxLines, 2);

      await tap(tester, 'Details');
      expect(find.text('Laboratory'), findsNothing);
      expect(find.text('Method'), findsNothing);
      expect(find.text('Specimen'), findsNothing);
      expect(find.text('Source text'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      final notesField = tester.widget<TextField>(
        find.descendant(
          of: find
              .byWidgetPredicate(
                (w) => w is LabelledInput && w.label == 'Notes',
              )
              .first,
          matching: find.byType(TextField),
        ),
      );
      expect(notesField.maxLines, 5);

      await tap(tester, 'Add');
      expect(find.text('Markers'), findsNWidgets(2));
      expect(find.text('Search markers'), findsNothing);
      await tester.ensureVisible(find.text('Markers').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markers').first);
      await settle(tester);
      expect(find.text('Search markers'), findsOneWidget);
      await tester.ensureVisible(find.text('Markers').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markers').last);
      await settle(tester);
      expect(find.text('Search markers'), findsNWidgets(2));

      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Choose marker for result 1')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Choose marker for result 2')),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel(RegExp('Choose marker for result 1')),
            )
            .getSemanticsData()
            .flagsCollection
            .isExpanded,
        Tristate.isTrue,
      );
      semantics.dispose();
    },
  );

  appTest(
    'trend table is first, chronological and keeps source identity and undated rows separate',
    (tester) async {
      final f = await launch(tester);
      await save(
        tester,
        f.store,
        panel(
          'a1',
          title: 'Earlier lab one',
          collection: SupportingDate.day(CivilDate(2026, 10, 2)),
        ),
      );
      await save(
        tester,
        f.store,
        panel(
          'b1',
          title: 'Earlier lab two',
          labId: 'lab-b',
          labName: 'Lab Two',
          collection: SupportingDate.day(CivilDate(2026, 10, 1)),
        ),
      );
      await save(
        tester,
        f.store,
        panel(
          'a2',
          title: 'Later lab one',
          collection: SupportingDate.day(CivilDate(2026, 10, 3)),
        ),
      );
      await save(
        tester,
        f.store,
        panel(
          'u1',
          title: 'Undated panel',
          labId: 'lab-c',
          labName: 'Lab Three',
          collection: SupportingDate.unknown(originalText: 'Date not given'),
        ),
      );
      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await settle(tester);

      expect(find.byType(SupportingTrendsPage), findsOneWidget);
      expect(find.text('Display zone: Europe/London.'), findsOneWidget);
      expect(find.textContaining('Laboratory: Lab One (lab-a)'), findsWidgets);
      expect(find.textContaining('Laboratory: Lab Two (lab-b)'), findsWidgets);
      expect(find.text('Undated results'), findsOneWidget);
      expect(find.text('Undated panel'), findsOneWidget);
      expect(find.text('Undated group'), findsOneWidget);

      final first = tester.getTopLeft(find.text('Earlier lab two')).dy;
      final second = tester.getTopLeft(find.text('Earlier lab one')).dy;
      final third = tester.getTopLeft(find.text('Later lab one')).dy;
      expect(first, lessThan(second));
      expect(second, lessThan(third));
      expect(
        tester.getTopLeft(find.text('Table')).dy,
        lessThan(tester.getTopLeft(find.text('Chart')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Undated results')).dy,
        lessThan(tester.getTopLeft(find.text('Chart')).dy),
      );
    },
  );

  appTest(
    'trend table shows shared display date and saved source zone separately',
    (tester) async {
      final f = await launch(tester);
      await save(
        tester,
        f.store,
        panel(
          'exact',
          title: 'Exact time panel',
          collection: SupportingDate.exact(
            DateTime.utc(2026, 10, 19, 23, 30),
            zoneId: 'Pacific/Auckland',
            utcOffsetMinutes: 780,
            originalText: '2026-10-20T12:30+13:00',
          ),
        ),
      );
      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await settle(tester);
      expect(find.text('Display zone: Europe/London.'), findsOneWidget);
      expect(
        find.text(
          'Saved source: 2026-10-20T12:30+13:00, Pacific/Auckland, UTC+13:00.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('00:30'), findsWidgets);
    },
  );
}
