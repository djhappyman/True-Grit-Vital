import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/events/events.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/reports/reports.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';

import '../history/history_test_data.dart';

final _items = [
  ReportItemDescriptor(
    itemId: 'item-1',
    name: 'Example prescribed item',
    form: 'tablet',
    type: 'Medicines',
    unit: 'count',
  ),
  ReportItemDescriptor(
    itemId: 'item-2',
    name: 'Example supplement',
    form: 'capsule',
    type: 'Supplements',
    unit: 'count',
  ),
];

UseRecord useRecord({
  required String id,
  String itemId = 'item-1',
  String name = 'Example prescribed item',
  String form = 'tablet',
  String type = 'Medicines',
  String unit = 'count',
  int day = 19,
  int hour = 8,
  int revision = 1,
}) => UseRecord(
  id: id,
  personId: 'me',
  itemId: itemId,
  name: name,
  form: form,
  unit: unit,
  type: type,
  enteredAmount: '1',
  actualAt: DateTime.utc(2026, 10, day, hour),
  enteredAt: DateTime.utc(2026, 10, day, hour, 2),
  revision: revision,
  isVoided: false,
);

EventRecord event({
  String id = 'event-1',
  String person = 'me',
  EventDate? actualStart,
  EventDate? actualEnd,
  bool completed = false,
  List<EventMembership>? memberships,
}) => EventRecord(
  id: id,
  personId: person,
  name: 'Example recorded course',
  eventType: 'Course',
  zoneId: 'Europe/London',
  revision: 1,
  plannedStart: EventDate.day(CivilDate(2026, 10, 18)),
  plannedEnd: EventDate.day(CivilDate(2026, 10, 21)),
  actualStart: actualStart,
  actualEnd: actualEnd,
  completed: completed,
  memberships:
      memberships ??
      [
        EventMembership(
          id: 'member-1',
          itemId: 'item-1',
          personId: person,
          effectiveFrom: DateTime.utc(2026, 10, 18),
          revision: 1,
        ),
        EventMembership(
          id: 'member-2',
          itemId: 'item-2',
          personId: person,
          effectiveFrom: DateTime.utc(2026, 10, 18),
          revision: 1,
        ),
      ],
);

ReportSnapshot snapshot({
  required EventRecord event,
  Iterable<UseRecord> records = const [],
  String person = 'me',
  Iterable<String> itemIds = const [],
}) => ReportSnapshot.build(
  selection: ReportSelection(
    template: ReportTemplateId.r03EventReview,
    personId: person,
    fromDate: CivilDate(2026, 10, 18),
    beforeDate: CivilDate(2026, 10, 21),
    displayZone: 'Europe/London',
    eventId: event.id,
    itemIds: itemIds,
  ),
  cutoff: ReportCutoff(
    generatedAt: DateTime.utc(2026, 10, 20, 12),
    datasetGeneration: 'generation-1',
    personRevision: 1,
    schemaVersion: 21,
  ),
  person: ReportPerson(id: person, name: 'Alex Morgan'),
  records: records.map(ReportRecord.fromUseRecord),
);

void main() {
  group('ReportEventData', () {
    test(
      'selected event members exclude unselected item rows and identity',
      () {
        final e = event();
        final data = ReportEventData.build(
          snapshot: snapshot(
            event: e,
            itemIds: ['item-2'],
            records: [
              useRecord(id: 'one'),
              useRecord(id: 'two', itemId: 'item-2'),
            ],
          ),
          event: e,
          items: _items,
        );
        expect(data.members.map((member) => member.itemId), ['item-2']);
        expect(data.entries.map((entry) => entry.itemId), ['item-2']);
      },
    );

    test('reports before an ongoing event do not cover its start', () {
      final e = event();
      final selection = ReportSelection(
        template: ReportTemplateId.r03EventReview,
        personId: 'me',
        eventId: e.id,
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 2),
        displayZone: 'Europe/London',
      );
      expect(eventSelectionCovers(e, selection), isFalse);
    });
    test('exact event bounds are compared in the selected display zone', () {
      final e = event(
        actualStart: EventDate.exact(DateTime.utc(2026, 10, 17, 23, 5)),
        actualEnd: EventDate.exact(DateTime.utc(2026, 10, 17, 23, 30)),
      );
      final selection = ReportSelection(
        template: ReportTemplateId.r03EventReview,
        personId: 'me',
        eventId: e.id,
        fromDate: CivilDate(2026, 10, 17),
        beforeDate: CivilDate(2026, 10, 18),
        displayZone: 'UTC',
      );
      expect(eventSelectionCovers(e, selection), isTrue);
    });
    test(
      'member administration count preserves incompatible quantity groups',
      () {
        final e = event();
        final data = ReportEventData.build(
          snapshot: snapshot(
            event: e,
            records: [
              useRecord(id: 'one', unit: 'mg'),
              useRecord(id: 'two', unit: 'count'),
            ],
          ),
          event: e,
          items: _items,
        );
        final member = data.members.firstWhere(
          (member) => member.itemId == 'item-1',
        );
        expect(member.administrations, 2);
        expect(member.quantities.map((quantity) => quantity.unit).toSet(), {
          'mg',
          'count',
        });
        expect(reportEventMemberUse(member), contains('1 mg'));
        expect(reportEventMemberUse(member), contains('1 count'));
      },
    );

    test('keeps an ongoing event and open member use separate from an end', () {
      final e = event();
      final captured = snapshot(
        event: e,
        records: [
          useRecord(id: 'record-1', day: 18, hour: 9),
          useRecord(id: 'record-2', day: 19, hour: 8),
        ],
      );
      final data = ReportEventData.build(
        snapshot: captured,
        event: e,
        items: _items,
        usePeriods: [
          RecordedUsePeriod(
            id: 'period-1',
            personId: 'me',
            itemId: 'item-1',
            revision: 1,
            start: EventDate.day(CivilDate(2026, 10, 18)),
          ),
          RecordedUsePeriod(
            id: 'period-2',
            personId: 'me',
            itemId: 'item-2',
            revision: 1,
            start: EventDate.day(CivilDate(2026, 10, 1)),
            end: EventDate.day(CivilDate(2026, 10, 10)),
          ),
        ],
        skipped: [
          SkippedTimelineEntry(
            action: skipAction(id: 'skip-1'),
            context: TimelinePlanContext(
              expectation: exactExpectation(
                item: 'item-1',
                instant: DateTime.utc(2026, 10, 19, 7),
              ),
              itemName: 'Example prescribed item',
            ),
          ),
        ],
      );

      expect(data.ongoing, isTrue);
      expect(data.members.length, 2);
      final prescribed = data.members.firstWhere(
        (member) => member.itemId == 'item-1',
      );
      expect(prescribed.administrations, 2);
      expect(prescribed.useStatus, ReportUseStatus.ongoing);
      final supplement = data.members.firstWhere(
        (member) => member.itemId == 'item-2',
      );
      expect(supplement.administrations, 0);
      expect(supplement.useStatus, ReportUseStatus.ended);
      expect(supplement.usePeriodEnd, isNotNull);
      expect(data.skippedCount, 1);
      expect(data.entries.length, 2);

      final text = data.structuredText(captured, use24Hour: true);
      expect(text, startsWith('Event review'));
      expect(text, contains('Event state: Ongoing'));
      expect(text, contains('Ongoing separately'));
      expect(text, contains('Use period ended'));
      expect(text, contains('does not mean every included item stopped'));
    });

    test('marks a recorded end as ended and counts it', () {
      final e = event(
        actualStart: EventDate.day(CivilDate(2026, 10, 18)),
        actualEnd: EventDate.day(CivilDate(2026, 10, 20)),
        completed: true,
      );
      final captured = snapshot(event: e);
      final data = ReportEventData.build(
        snapshot: captured,
        event: e,
        items: _items,
      );
      expect(data.ongoing, isFalse);
      expect(
        data.structuredText(captured, use24Hour: true),
        contains('Event state: Ended'),
      );
    });

    test('keeps a member ongoing when any open use period exists', () {
      final e = event();
      final captured = snapshot(event: e);
      final data = ReportEventData.build(
        snapshot: captured,
        event: e,
        items: _items,
        usePeriods: [
          RecordedUsePeriod(
            id: 'period-open',
            personId: 'me',
            itemId: 'item-1',
            revision: 1,
            start: EventDate.day(CivilDate(2026, 10, 1)),
          ),
          RecordedUsePeriod(
            id: 'period-closed',
            personId: 'me',
            itemId: 'item-1',
            revision: 1,
            start: EventDate.day(CivilDate(2026, 9, 1)),
            end: EventDate.day(CivilDate(2026, 9, 20)),
          ),
        ],
      );
      final member = data.members.firstWhere(
        (member) => member.itemId == 'item-1',
      );
      expect(member.useStatus, ReportUseStatus.ongoing);
      expect(member.usePeriodEnd, isNull);
    });

    test('uses the completion instant when no actual end was saved', () {
      final e = EventRecord(
        id: 'event-1',
        personId: 'me',
        name: 'Example recorded course',
        eventType: 'Course',
        zoneId: 'Europe/London',
        revision: 1,
        plannedStart: EventDate.day(CivilDate(2026, 10, 18)),
        plannedEnd: EventDate.day(CivilDate(2026, 10, 21)),
        completed: true,
        completedAt: DateTime.utc(2026, 10, 20, 16),
        memberships: [
          EventMembership(
            id: 'member-1',
            itemId: 'item-1',
            personId: 'me',
            effectiveFrom: DateTime.utc(2026, 10, 18),
            revision: 1,
          ),
        ],
      );
      final captured = snapshot(event: e);
      final data = ReportEventData.build(
        snapshot: captured,
        event: e,
        items: _items,
      );
      expect(data.ongoing, isFalse);
      expect(data.recordedEnd, isNotNull);
      final text = data.structuredText(captured, use24Hour: true);
      expect(text, contains('Event state: Ended'));
      expect(text, isNot(contains('Actual: Not recorded to Ongoing')));
    });

    test('requires the selected event and its owner', () {
      final e = event();
      final captured = snapshot(event: e);
      expect(
        () => ReportEventData.build(
          snapshot: captured,
          event: event(id: 'event-2'),
        ),
        throwsA(isA<ReportSelectionFailure>()),
      );
      expect(
        () => ReportEventData.build(
          snapshot: captured,
          event: event(person: 'adult-2'),
        ),
        throwsA(isA<ReportSelectionFailure>()),
      );
    });

    test('rejects a period that cuts off the event start or recorded end', () {
      final selection = ReportSelection(
        template: ReportTemplateId.r03EventReview,
        personId: 'me',
        fromDate: CivilDate(2026, 10, 19),
        beforeDate: CivilDate(2026, 10, 21),
        displayZone: 'Europe/London',
        eventId: 'event-1',
      );
      // Planned start on 18 October is before the selected first day.
      expect(eventSelectionCovers(event(), selection), isFalse);
      final ended = event(
        actualEnd: EventDate.day(CivilDate(2026, 10, 21)),
        completed: true,
      );
      final wider = ReportSelection(
        template: ReportTemplateId.r03EventReview,
        personId: 'me',
        fromDate: CivilDate(2026, 10, 18),
        beforeDate: CivilDate(2026, 10, 21),
        displayZone: 'Europe/London',
        eventId: 'event-1',
      );
      // The recorded end on 21 October is the excluded last boundary.
      expect(eventSelectionCovers(ended, wider), isFalse);
      expect(
        eventSelectionCovers(
          event(),
          ReportSelection(
            template: ReportTemplateId.r03EventReview,
            personId: 'me',
            fromDate: CivilDate(2026, 10, 18),
            beforeDate: CivilDate(2026, 10, 21),
            displayZone: 'Europe/London',
            eventId: 'event-1',
          ),
        ),
        isTrue,
      );
    });

    test('rejects another adult in skipped data', () {
      final e = event();
      final captured = snapshot(event: e);
      expect(
        () => ReportEventData.build(
          snapshot: captured,
          event: e,
          skipped: [
            SkippedTimelineEntry(
              action: skipAction(id: 'skip-1'),
              context: TimelinePlanContext(
                expectation: exactExpectation(person: 'adult-2'),
                itemName: 'Other item',
              ),
            ),
          ],
        ),
        throwsA(
          isA<ReportSelectionFailure>().having(
            (error) => error.code,
            'code',
            'report_owner',
          ),
        ),
      );
    });
  });
}
