import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_trends.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

/// The comparison selection is an exact identity, not a row number in the
/// sorted group list. Adding, correcting, voiding or filtering a group must
/// never silently move the selection to a different unit or source.
LabPanelSnapshot panel(
  String id, {
  required String title,
  required String labId,
  required String labName,
  required String unit,
  required String value,
  required SupportingDate collection,
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: title,
  collectionDate: collection,
  reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryId: labId,
    laboratoryName: labName,
    methodId: 'method-a',
    methodText: 'Method A',
    specimenId: 'specimen-a',
    specimenText: 'Serum',
  ),
  results: [
    LabResultSnapshot(
      id: 'result-$id',
      metricId: 'metric',
      markerName: 'Marker',
      originalMarkerText: 'Marker',
      value: SupportingValue.numeric(value),
      unit: unit,
      referenceRange: SourceReferenceRange(originalText: '3 to 7'),
    ),
  ],
);

Future<SupportingRevision> savePanel(
  WidgetTester tester,
  RecordStore store,
  LabPanelSnapshot snapshot, {
  required String command,
  int? expectedRevision,
}) async {
  final person = (await runIo(tester, () => store.profileById(meId)))!;
  return (await runIo(
    tester,
    () => store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: command,
        generation: store.generation,
        expectedPersonRevision: person.revision,
        expectedRevision: expectedRevision,
        panel: snapshot,
      ),
    ),
  ))!;
}

Future<SupportingRevision> setVoided(
  WidgetTester tester,
  RecordStore store,
  SupportingRevision revision, {
  required String command,
  required bool voided,
}) async {
  final person = (await runIo(tester, () => store.profileById(meId)))!;
  return (await runIo(
    tester,
    () => store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: command,
        generation: store.generation,
        personId: meId,
        id: revision.id.id,
        expectedPersonRevision: person.revision,
        expectedRevision: revision.revision,
        isVoided: voided,
      ),
    ),
  ))!;
}

String identityOf(SupportingRevision revision) =>
    SupportingComparisonKey.forResult(
      revision,
      revision.snapshot.results.single,
    ).identity;

SupportingTrendGroup selectedGroup(WidgetTester tester) =>
    tester.widget<SupportingPlot>(find.byType(SupportingPlot)).group;

Future<void> selectGroup(WidgetTester tester, String unit) async {
  final target = find.textContaining('Unit: $unit').first;
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

/// Live refresh crosses the store generation and provider rebuild, which can
/// take longer than one [settle]. Wait for a positive on-screen signal instead
/// of asserting against the previous model.
Future<void> waitForWidget(WidgetTester tester, Finder finder) async {
  final elapsed = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw TestFailure('Expected widget did not appear: $finder');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> applyRange(
  WidgetTester tester, {
  required String from,
  required String before,
}) async {
  await tester.enterText(
    find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is LabelledInput && w.label == 'From date',
      ),
      matching: find.byType(TextField),
    ),
    from,
  );
  await tester.pump();
  await tester.enterText(
    find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is LabelledInput && w.label == 'Before date',
      ),
      matching: find.byType(TextField),
    ),
    before,
  );
  await tester.pump();
  await tap(tester, 'Apply');
}

void main() {
  appTest(
    'trend selection keeps the exact comparison identity through insert, correction and void',
    (tester) async {
      final f = await launch(tester);
      final a = await savePanel(
        tester,
        f.store,
        panel(
          'a',
          title: 'Lab one',
          labId: 'lab-a',
          labName: 'Lab One',
          unit: 'mg/L',
          value: '1',
          collection: SupportingDate.day(CivilDate(2026, 10, 5)),
        ),
        command: 'save-a',
      );
      final b = await savePanel(
        tester,
        f.store,
        panel(
          'b',
          title: 'Lab two',
          labId: 'lab-b',
          labName: 'Lab Two',
          unit: 'g/L',
          value: '2',
          collection: SupportingDate.day(CivilDate(2026, 10, 10)),
        ),
        command: 'save-b',
      );

      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await settle(tester);

      // The first visit may choose the earliest group once.
      expect(selectedGroup(tester).key.identity, identityOf(a));
      expect(selectedGroup(tester).key.unit, 'mg/L');

      await selectGroup(tester, 'g/L');
      expect(selectedGroup(tester).key.identity, identityOf(b));
      expect(selectedGroup(tester).key.laboratoryId, 'id:lab-b');

      // An earlier, different source inserts in front of the chosen group.
      // The chosen identity must stay selected even though its list position moves.
      final c = await savePanel(
        tester,
        f.store,
        panel(
          'c',
          title: 'Earlier lab three',
          labId: 'lab-c',
          labName: 'Lab Three',
          unit: 'umol/L',
          value: '3',
          collection: SupportingDate.day(CivilDate(2026, 10, 1)),
        ),
        command: 'save-c',
      );
      // The bounded watcher re-reads the same query when the store commits.
      // The page state, including the chosen comparison identity, survives it.
      await waitForWidget(
        tester,
        find.textContaining('Group 1 of 3. Marker. Unit: umol/L'),
      );
      await settle(tester);
      expect(identityOf(c), isNot(identityOf(b)));
      expect(selectedGroup(tester).key.identity, identityOf(b));
      expect(
        selectedGroup(tester).entries.single.record.snapshot.title,
        'Lab two',
      );
      expect(
        find.textContaining('Group 3 of 3. Marker. Unit: g/L'),
        findsNWidgets(2),
      );
      expect(
        find.textContaining('Group 1 of 3. Marker. Unit: umol/L'),
        findsOneWidget,
      );
      final unchanged = tester
          .getSemantics(find.textContaining('Unit: g/L').first)
          .getSemanticsData();
      expect(unchanged.flagsCollection.isSelected, Tristate.isTrue);
      expect(
        tester.getTopLeft(find.text('Earlier lab three')).dy,
        lessThan(tester.getTopLeft(find.text('Lab one')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Lab one')).dy,
        lessThan(tester.getTopLeft(find.text('Lab two')).dy),
      );

      // Correcting the chosen record moves it ahead of every group. Its
      // position becomes first, not the selection that was second.
      final corrected = await savePanel(
        tester,
        f.store,
        panel(
          'b',
          title: 'Lab two',
          labId: 'lab-b',
          labName: 'Lab Two',
          unit: 'g/L',
          value: '2.5',
          collection: SupportingDate.day(CivilDate(2026, 9, 1)),
        ),
        command: 'correct-b',
        expectedRevision: b.revision,
      );
      await waitForWidget(
        tester,
        find.textContaining('Group 1 of 3. Marker. Unit: g/L'),
      );
      await settle(tester);
      expect(selectedGroup(tester).key.identity, identityOf(corrected));
      expect(
        selectedGroup(tester).entries.single.record.snapshot.title,
        'Lab two',
      );
      expect(
        find.textContaining('Group 1 of 3. Marker. Unit: g/L'),
        findsNWidgets(2),
      );

      // Voiding the chosen record leaves its identity and readable label in
      // place with no plot. Another group's line must not appear.
      final voided = await setVoided(
        tester,
        f.store,
        corrected,
        command: 'void-b',
        voided: true,
      );
      await waitForWidget(
        tester,
        find.text(
          'This group has no results in the selected dates. '
          'Choose another group or change the dates.',
        ),
      );
      await settle(tester);
      expect(find.byType(SupportingPlot), findsNothing);
      expect(
        find.text(
          'This group has no results in the selected dates. '
          'Choose another group or change the dates.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Unit: g/L'), findsOneWidget);
      expect(
        find.textContaining('Group 1 of 3. Marker. Unit: g/L'),
        findsNothing,
      );
      expect(
        find.textContaining('Group 1 of 2. Marker. Unit: umol/L'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Group 2 of 2. Marker. Unit: mg/L'),
        findsOneWidget,
      );

      // Restoring the same identity returns it as the selection without a tap.
      final restored = await setVoided(
        tester,
        f.store,
        voided,
        command: 'restore-b',
        voided: false,
      );
      await waitForWidget(tester, find.byType(SupportingPlot));
      await settle(tester);
      expect(selectedGroup(tester).key.identity, identityOf(restored));
      expect(
        selectedGroup(tester).entries.single.record.snapshot.title,
        'Lab two',
      );
    },
  );

  appTest(
    'range changes keep the chosen identity and show it absent instead of another group',
    (tester) async {
      final f = await launch(tester);
      final a = await savePanel(
        tester,
        f.store,
        panel(
          'a',
          title: 'Lab one',
          labId: 'lab-a',
          labName: 'Lab One',
          unit: 'mg/L',
          value: '1',
          collection: SupportingDate.day(CivilDate(2026, 10, 5)),
        ),
        command: 'save-a',
      );
      final b = await savePanel(
        tester,
        f.store,
        panel(
          'b',
          title: 'Lab two',
          labId: 'lab-b',
          labName: 'Lab Two',
          unit: 'g/L',
          value: '2',
          collection: SupportingDate.day(CivilDate(2026, 10, 10)),
        ),
        command: 'save-b',
      );

      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await settle(tester);
      await selectGroup(tester, 'g/L');
      expect(selectedGroup(tester).key.identity, identityOf(b));

      await applyRange(tester, from: '2026-10-09', before: '2026-10-11');
      await waitForWidget(
        tester,
        find.textContaining('Group 1 of 1. Marker. Unit: g/L'),
      );
      expect(selectedGroup(tester).key.identity, identityOf(b));
      expect(
        find.textContaining('Group 1 of 1. Marker. Unit: g/L'),
        findsOneWidget,
      );

      // The chosen group has no points here. Do not substitute the group that
      // does, and keep the chosen identity named.
      await applyRange(tester, from: '2026-10-01', before: '2026-10-06');
      await waitForWidget(
        tester,
        find.text(
          'This group has no results in the selected dates. '
          'Choose another group or change the dates.',
        ),
      );
      await settle(tester);
      expect(find.byType(SupportingPlot), findsNothing);
      expect(
        find.text(
          'This group has no results in the selected dates. '
          'Choose another group or change the dates.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Unit: g/L'), findsOneWidget);
      expect(
        find.textContaining('Group 1 of 1. Marker. Unit: mg/L'),
        findsOneWidget,
      );

      // Returning to a range with data restores the same identity by itself.
      await applyRange(tester, from: '2026-10-09', before: '2026-10-11');
      await waitForWidget(tester, find.byType(SupportingPlot));
      expect(selectedGroup(tester).key.identity, identityOf(b));
      expect(find.byType(SupportingPlot), findsOneWidget);

      // A deliberate choice of the only other group is reachable while the
      // chosen identity is absent, and it then stays chosen.
      await applyRange(tester, from: '2026-10-01', before: '2026-10-06');
      await waitForWidget(
        tester,
        find.textContaining('Group 1 of 1. Marker. Unit: mg/L'),
      );
      await selectGroup(tester, 'mg/L');
      expect(selectedGroup(tester).key.identity, identityOf(a));
      await applyRange(tester, from: '2026-10-09', before: '2026-10-11');
      await waitForWidget(
        tester,
        find.text(
          'This group has no results in the selected dates. '
          'Choose another group or change the dates.',
        ),
      );
      await settle(tester);
      expect(find.byType(SupportingPlot), findsNothing);
      expect(find.textContaining('Unit: mg/L'), findsOneWidget);
      expect(
        find.textContaining('Group 1 of 1. Marker. Unit: g/L'),
        findsOneWidget,
      );
    },
  );
}
