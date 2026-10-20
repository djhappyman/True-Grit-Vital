import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';

import '../vital_app_test.dart' show appTest, launch, runIo, settle, tap;

Future<EventRecord> _saveEvent(
  WidgetTester tester,
  RecordStore store, {
  required String id,
  required String name,
  required CivilDate start,
  CivilDate? end,
}) async {
  final saved = await runIo(tester, () async {
    final person = (await store.profileById(meId))!;
    return store.saveEvent(
      SaveEventCommand(
        commandId: 'save-$id',
        generation: store.generation,
        expectedRevision: null,
        expectedPersonRevision: person.revision,
        event: EventRecord(
          id: id,
          personId: meId,
          name: name,
          eventType: 'Course',
          zoneId: 'Europe/London',
          revision: 1,
          plannedStart: EventDate.day(start),
          plannedEnd: end == null ? null : EventDate.day(end),
          actualStart: EventDate.day(start),
          actualEnd: end == null ? null : EventDate.day(end),
          completed: end != null,
        ),
      ),
    );
  });
  return saved!;
}

Future<void> _openReports(
  WidgetTester tester,
  ({RecordStore store, ProviderContainer container, String path, List<int> key})
  f,
) async {
  f.container.read(routerProvider).push('/reports');
  await settle(tester);
}

Future<void> _chooseEventReview(WidgetTester tester) async {
  await tester.tap(find.text('Event review').first);
  await settle(tester);
}

void main() {
  appTest('a historical event keeps its identity and explains the date gap', (
    tester,
  ) async {
    final f = await launch(tester);
    final year = DateTime.now().year - 1;
    final start = CivilDate(year, 2, 3);
    final end = CivilDate(year, 2, 5);
    final event = await _saveEvent(
      tester,
      f.store,
      id: 'historical-event',
      name: 'Historical course',
      start: start,
      end: end,
    );
    await _openReports(tester, f);
    await _chooseEventReview(tester);
    await tap(tester, event.name);

    final selection = f.container.read(reportControllerProvider).selection!;
    expect(selection.eventId, event.id);
    expect(selection.fromDate, CivilDate(DateTime.now().year, 1, 1));

    expect(find.text('Event: Historical course'), findsWidgets);
    expect(find.text('Event zone: Europe/London'), findsOneWidget);
    final rangeMessage =
        'The selected dates do not include this event. '
        'Apply $start to $end to cover its recorded start and end.';
    expect(find.text(rangeMessage), findsOneWidget);

    await tap(tester, 'Apply');

    final corrected = f.container.read(reportControllerProvider).selection!;
    expect(corrected.eventId, event.id);
    expect(corrected.fromDate, start);
    expect(corrected.beforeDate, end.addDays(1));
    expect(find.text(rangeMessage), findsNothing);

    final capture = await runIo(
      tester,
      () => f.store.captureTemplateReport(
        selection: corrected,
        now: () => DateTime.now().toUtc(),
      ),
    );
    expect(capture, isNotNull);
    await capture!.releasePins?.call();
  });

  appTest(
    'applying the event dates retains edited inputs and private options',
    (tester) async {
      final f = await launch(tester);
      final year = DateTime.now().year - 1;
      final start = CivilDate(year, 4, 7);
      final end = CivilDate(year, 4, 9);
      final event = await _saveEvent(
        tester,
        f.store,
        id: 'retained-event',
        name: 'Retained course',
        start: start,
        end: end,
      );
      final item = await runIo(tester, () async {
        final person = (await f.store.profileById(meId))!;
        return f.store.createItem(
          commandId: 'retained-item',
          name: 'Example item',
          form: 'tablet',
          unit: 'mg',
          type: 'Medicine',
          expectedPersonRevision: person.revision,
        );
      });
      await _openReports(tester, f);
      await _chooseEventReview(tester);
      await tap(tester, event.name);
      await tap(tester, item!.name);
      await tester.enterText(find.byType(TextField).at(2), 'Course review');
      await settle(tester);
      await tap(tester, 'Supporting records');
      await tap(tester, 'Private notes');
      await tap(tester, 'Apply');

      final selection = f.container.read(reportControllerProvider).selection!;
      expect(selection.eventId, event.id);
      expect(selection.fromDate, start);
      expect(selection.beforeDate, end.addDays(1));
      expect(selection.reportName, 'Course review');
      expect(selection.itemIds, {item.id});
      expect(selection.includeSupporting, isTrue);
      expect(selection.includeNotes, isTrue);
      expect(selection.includeAttachments, isFalse);
    },
  );

  appTest('an ongoing event keeps the entered end date', (tester) async {
    final f = await launch(tester);
    final year = DateTime.now().year - 1;
    final start = CivilDate(year, 6, 12);
    final event = await _saveEvent(
      tester,
      f.store,
      id: 'ongoing-event',
      name: 'Ongoing course',
      start: start,
    );
    await _openReports(tester, f);
    await _chooseEventReview(tester);
    await tap(tester, event.name);

    final today = DateTime.now();
    final enteredThrough = CivilDate(today.year, today.month, today.day);
    final before = f.container.read(reportControllerProvider).selection!;
    expect(before.fromDate, CivilDate(today.year, 1, 1));
    expect(before.beforeDate, enteredThrough.addDays(1));
    expect(
      find.text(
        'The selected dates do not include this event. '
        'Apply $start to $enteredThrough to cover its recorded dates.',
      ),
      findsOneWidget,
    );

    await tap(tester, 'Apply');

    final corrected = f.container.read(reportControllerProvider).selection!;
    expect(corrected.fromDate, start);
    expect(corrected.beforeDate, enteredThrough.addDays(1));
    expect(corrected.eventId, event.id);
  });

  appTest('generation retains the zone shown in the selected draft', (
    tester,
  ) async {
    final f = await launch(tester);
    final year = DateTime.now().year - 1;
    final event = await _saveEvent(
      tester,
      f.store,
      id: 'visible-zone-event',
      name: 'Visible zone course',
      start: CivilDate(year, 3, 3),
      end: CivilDate(year, 3, 5),
    );
    await _openReports(tester, f);
    await _chooseEventReview(tester);
    await tap(tester, event.name);
    final controller = f.container.read(reportControllerProvider.notifier);
    controller.select(
      f.container
          .read(reportControllerProvider)
          .selection!
          .copyWith(
            fromDate: CivilDate(year, 3, 1),
            beforeDate: CivilDate(year, 3, 8),
            displayZone: 'Pacific/Kiritimati',
          ),
    );
    await settle(tester);
    expect(find.textContaining('Pacific/Kiritimati'), findsWidgets);
    final preview = find.text('Preview');
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    // Capture starts asynchronously. Check its immutable selection and cancel
    // before the native PDF preview is opened.
    final selectedZone = f.container
        .read(reportControllerProvider)
        .selection!
        .displayZone;
    controller.cancel();
    await settle(tester);
    expect(selectedZone, 'Pacific/Kiritimati');
  });

  appTest('a stale event is named without starting a report', (tester) async {
    final f = await launch(tester);
    await _openReports(tester, f);
    f.container
        .read(reportControllerProvider.notifier)
        .select(
          ReportSelection(
            template: ReportTemplateId.r03EventReview,
            personId: meId,
            fromDate: CivilDate(DateTime.now().year, 1, 1),
            beforeDate: CivilDate(DateTime.now().year, 1, 2),
            displayZone: 'Europe/London',
            eventId: 'missing-event',
          ),
        );
    await settle(tester);

    expect(
      find.text('This event is no longer available. Choose another event.'),
      findsOneWidget,
    );
    expect(f.container.read(reportControllerProvider).phase, ReportPhase.idle);
  });
}
