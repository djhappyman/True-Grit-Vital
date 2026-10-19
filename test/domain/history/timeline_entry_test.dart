import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';

import 'history_test_data.dart';

Matcher modelError(String code) =>
    isA<TimelineModelException>().having((error) => error.code, 'code', code);

CombinedTimelineComponent component(
  int position,
  UseRecord record, {
  bool matched = false,
}) => CombinedTimelineComponent(
  position: position,
  record: record,
  matched: matched,
);

void main() {
  group('TimelineEntryId', () {
    test('round-trips the three prefixed parent identities', () {
      final record = TimelineEntryId.record('record-1');
      final combined = TimelineEntryId.combined('action-1');
      final skipped = TimelineEntryId.skipped('skip-1');

      expect(record.sortKey, 'r:record-1');
      expect(combined.sortKey, 'c:action-1');
      expect(skipped.sortKey, 's:skip-1');
      expect(TimelineEntryId.parse(record.sortKey), record);
      expect(TimelineEntryId.parse(combined.sortKey), combined);
      expect(TimelineEntryId.parse(skipped.sortKey), skipped);
      expect(record.kind, TimelineEntryKind.record);
      expect(combined.kind, TimelineEntryKind.combined);
      expect(skipped.kind, TimelineEntryKind.skipped);
    });

    test('rejects malformed identities', () {
      final tooLong = 'r:${List.filled(257, 'a').join()}';
      for (final value in [
        '',
        'record-1',
        'x:record-1',
        'r:',
        'r:   ',
        tooLong,
      ]) {
        expect(
          () => TimelineEntryId.parse(value),
          throwsA(modelError('entry_identity')),
          reason: value,
        );
      }
      expect(
        () => TimelineEntryId.record(''),
        throwsA(modelError('entry_identity')),
      );
    });

    test('orders by the prefixed key c < r < s', () {
      final combined = TimelineEntryId.combined('z');
      final record = TimelineEntryId.record('a');
      final skipped = TimelineEntryId.skipped('a');

      expect(combined.compareTo(record), lessThan(0));
      expect(record.compareTo(combined), greaterThan(0));
      expect(record.compareTo(skipped), lessThan(0));
      expect(skipped.compareTo(record), greaterThan(0));
      expect(record.compareTo(TimelineEntryId.record('a')), 0);
      expect(record.hashCode, TimelineEntryId.record('a').hashCode);
    });
  });

  group('RecordTimelineEntry', () {
    test('takes identity, owner and time from the current record', () {
      final record = testRecord();
      final entry = RecordTimelineEntry(record: record);

      expect(entry.id.sortKey, 'r:record-1');
      expect(entry.personId, 'me');
      expect(entry.occurredAt, DateTime.utc(2026, 10, 19, 8));
      expect(entry.status, TimelineEntryStatus.recorded);
      expect(entry.dateOnly, isFalse);
      expect(entry.planZone, isNull);
      expect(entry.isTakenDailyAction, isFalse);
      expect(entry.record.actualUnit, 'mg');
    });

    test('maps a voided current revision to voided', () {
      final entry = RecordTimelineEntry(record: testRecord(voided: true));
      expect(entry.status, TimelineEntryStatus.voided);
    });

    test('accepts matching taken-daily-action plan context', () {
      final context = TimelinePlanContext(
        expectation: exactExpectation(),
        planName: 'Morning plan',
        itemName: 'Test item',
      );
      final entry = RecordTimelineEntry(
        record: testRecord(),
        planContext: context,
      );

      expect(entry.isTakenDailyAction, isTrue);
      expect(entry.planContext, same(context));
      expect(entry.id.sortKey, 'r:record-1');
    });

    test('rejects plan context from another person or item', () {
      final otherPerson = TimelinePlanContext(
        expectation: exactExpectation(person: 'adult-2'),
      );
      final otherItem = TimelinePlanContext(
        expectation: exactExpectation(item: 'item-2'),
      );

      expect(
        () =>
            RecordTimelineEntry(record: testRecord(), planContext: otherPerson),
        throwsA(modelError('record_plan_context')),
      );
      expect(
        () => RecordTimelineEntry(record: testRecord(), planContext: otherItem),
        throwsA(modelError('record_plan_context')),
      );
    });

    test('rejects blank plan labels', () {
      expect(
        () =>
            TimelinePlanContext(expectation: exactExpectation(), planName: ''),
        throwsA(modelError('plan_name')),
      );
      expect(
        () => TimelinePlanContext(
          expectation: exactExpectation(),
          itemName: '   ',
        ),
        throwsA(modelError('item_name')),
      );
    });

    test('rejects empty owners and non-UTC ordering instants', () {
      expect(
        () => RecordTimelineEntry(record: testRecord(person: '')),
        throwsA(modelError('entry_owner')),
      );
      expect(
        () => RecordTimelineEntry(
          record: testRecord(actualAt: DateTime(2026, 10, 19, 8)),
        ),
        throwsA(modelError('entry_instant')),
      );
    });
  });

  group('CombinedTimelineEntry', () {
    test('retains the complete group with distinct matched IDs', () {
      final first = testRecord(
        id: 'record-1',
        item: 'item-1',
        combinedActionId: 'action-1',
      );
      final second = testRecord(
        id: 'record-2',
        item: 'item-2',
        unit: 'ml',
        actualAt: DateTime.utc(2026, 10, 19, 8),
        combinedActionId: 'action-1',
      );
      final entry = CombinedTimelineEntry(
        actionId: 'action-1',
        components: [component(0, first), component(1, second, matched: true)],
      );

      expect(entry.id.sortKey, 'c:action-1');
      expect(entry.personId, 'me');
      expect(entry.occurredAt, DateTime.utc(2026, 10, 19, 8));
      expect(entry.status, TimelineEntryStatus.recorded);
      expect(entry.components, hasLength(2));
      expect(entry.records.map((record) => record.id), [
        'record-1',
        'record-2',
      ]);
      expect(entry.matchedRecordIds, ['record-2']);
      expect(entry.representative.id, 'record-1');
    });

    test('returns no matched IDs when only the group matched', () {
      final entry = CombinedTimelineEntry(
        actionId: 'action-1',
        components: [
          component(0, testRecord(id: 'record-1')),
          component(1, testRecord(id: 'record-2')),
        ],
      );

      expect(entry.matchedRecordIds, isEmpty);
    });

    test('marks every matching component but keeps the whole group', () {
      final entry = CombinedTimelineEntry(
        actionId: 'action-1',
        components: [
          component(0, testRecord(id: 'record-1'), matched: true),
          component(1, testRecord(id: 'record-2'), matched: false),
          component(2, testRecord(id: 'record-3'), matched: true),
        ],
      );

      expect(entry.matchedRecordIds, ['record-1', 'record-3']);
      expect(entry.records, hasLength(3));
    });

    test('rejects a blank action identity', () {
      expect(
        () => CombinedTimelineEntry(
          actionId: '',
          components: [
            component(0, testRecord(id: 'record-1')),
            component(1, testRecord(id: 'record-2')),
          ],
        ),
        throwsA(modelError('combined_action')),
      );
    });

    test('requires 2 to 16 components', () {
      expect(
        () => CombinedTimelineEntry(
          actionId: 'action-1',
          components: [component(0, testRecord())],
        ),
        throwsA(modelError('combined_components')),
      );
      expect(
        () => CombinedTimelineEntry(
          actionId: 'action-1',
          components: List.generate(
            17,
            (index) => component(
              index,
              testRecord(id: 'record-$index', combinedActionId: 'action-1'),
            ),
          ),
        ),
        throwsA(modelError('combined_components')),
      );
    });

    test('requires strict membership positions and distinct records', () {
      expect(
        () => CombinedTimelineEntry(
          actionId: 'action-1',
          components: [
            component(1, testRecord(id: 'record-1')),
            component(1, testRecord(id: 'record-2')),
          ],
        ),
        throwsA(modelError('combined_position')),
      );
      expect(
        () => CombinedTimelineEntry(
          actionId: 'action-1',
          components: [
            component(0, testRecord(id: 'record-1')),
            component(1, testRecord(id: 'record-1')),
          ],
        ),
        throwsA(modelError('combined_duplicate')),
      );
      expect(
        () => CombinedTimelineEntry(
          actionId: 'action-1',
          components: [
            component(-1, testRecord(id: 'record-1')),
            component(0, testRecord(id: 'record-2')),
          ],
        ),
        throwsA(modelError('combined_position')),
      );
    });

    test('requires one owner, one corrected time and one status', () {
      expect(
        () => CombinedTimelineEntry(
          actionId: 'action-1',
          components: [
            component(0, testRecord(id: 'record-1', person: 'me')),
            component(1, testRecord(id: 'record-2', person: 'adult-2')),
          ],
        ),
        throwsA(modelError('combined_owner')),
      );
      expect(
        () => CombinedTimelineEntry(
          actionId: 'action-1',
          components: [
            component(0, testRecord(id: 'record-1')),
            component(
              1,
              testRecord(
                id: 'record-2',
                actualAt: DateTime.utc(2026, 10, 19, 8, 0, 1),
              ),
            ),
          ],
        ),
        throwsA(modelError('combined_time')),
      );
      expect(
        () => CombinedTimelineEntry(
          actionId: 'action-1',
          components: [
            component(0, testRecord(id: 'record-1')),
            component(1, testRecord(id: 'record-2', voided: true)),
          ],
        ),
        throwsA(modelError('combined_status')),
      );
    });

    test('rejects a populated membership for a different action', () {
      expect(
        () => CombinedTimelineEntry(
          actionId: 'action-1',
          components: [
            component(
              0,
              testRecord(id: 'record-1', combinedActionId: 'action-1'),
            ),
            component(
              1,
              testRecord(id: 'record-2', combinedActionId: 'action-2'),
            ),
          ],
        ),
        throwsA(modelError('combined_membership')),
      );
    });

    test('uses the component time, not a stale parent time', () {
      final corrected = DateTime.utc(2026, 10, 19, 10);
      final entry = CombinedTimelineEntry(
        actionId: 'action-1',
        components: [
          component(0, testRecord(id: 'record-1', actualAt: corrected)),
          component(1, testRecord(id: 'record-2', actualAt: corrected)),
        ],
      );

      expect(entry.occurredAt, corrected);
      expect(entry.status, TimelineEntryStatus.recorded);
    });

    test('maps a wholly voided group to voided', () {
      final entry = CombinedTimelineEntry(
        actionId: 'action-1',
        components: [
          component(0, testRecord(id: 'record-1', voided: true)),
          component(1, testRecord(id: 'record-2', voided: true)),
        ],
      );

      expect(entry.status, TimelineEntryStatus.voided);
    });
  });

  group('SkippedTimelineEntry', () {
    TimelinePlanContext context(DailyExpectation expectation) =>
        TimelinePlanContext(
          expectation: expectation,
          planName: 'Morning plan',
          itemName: 'Test item',
        );

    test('uses the planned occurrence, not the tap time', () {
      final expectation = exactExpectation();
      final entry = SkippedTimelineEntry(
        action: skipAction(recordedAt: DateTime.utc(2026, 10, 19, 15)),
        context: context(expectation),
      );

      expect(entry.id.sortKey, 's:skip-1');
      expect(entry.personId, 'me');
      expect(entry.occurredAt, expectation.instant);
      expect(entry.occurredAt, isNot(DateTime.utc(2026, 10, 19, 15)));
      expect(entry.status, TimelineEntryStatus.skipped);
      expect(entry.dateOnly, isFalse);
      expect(entry.planZone, 'Europe/London');
      expect(entry.savedDate, CivilDate(2026, 10, 19));
      expect(entry.timeNeedsReview, isFalse);
      expect(entry.amount.quantity.canonical, '1');
      expect(entry.amount.unit, 'mg');
      expect(entry.itemId, 'item-1');
    });

    test('uses the effective date when one is saved', () {
      final entry = SkippedTimelineEntry(
        action: skipAction(),
        context: context(
          untimedExpectation(
            originalDate: CivilDate(2026, 10, 19),
            effectiveDate: CivilDate(2026, 10, 20),
          ),
        ),
      );

      expect(entry.savedDate, CivilDate(2026, 10, 20));
      expect(entry.occurredAt, DateTime.utc(2026, 10, 20));
      expect(entry.dateOnly, isTrue);
    });

    test('orders a date-only skip at the earliest plan-zone day instant', () {
      final utc = SkippedTimelineEntry(
        action: skipAction(),
        context: context(untimedExpectation()),
      );
      expect(utc.occurredAt, DateTime.utc(2026, 10, 19));
      expect(utc.dateOnly, isTrue);
      expect(utc.planZone, 'UTC');

      final london = SkippedTimelineEntry(
        action: skipAction(),
        context: context(
          missingClockExpectation(
            originalDate: CivilDate(2026, 10, 25),
            zone: 'Europe/London',
          ),
        ),
      );
      expect(london.occurredAt, DateTime.utc(2026, 10, 24, 23));
      expect(london.dateOnly, isTrue);
      expect(london.timeNeedsReview, isTrue);
      expect(london.planZone, 'Europe/London');
    });

    test('flags a repeated clock as date-only review', () {
      final entry = SkippedTimelineEntry(
        action: skipAction(),
        context: context(repeatedClockExpectation()),
      );

      expect(entry.dateOnly, isTrue);
      expect(entry.timeNeedsReview, isTrue);
      expect(entry.occurredAt, DateTime.utc(2026, 10, 24, 23));
    });

    test('treats no-alert as date-only without a clock review', () {
      final entry = SkippedTimelineEntry(
        action: skipAction(),
        context: context(noAlertExpectation()),
      );

      expect(entry.dateOnly, isTrue);
      expect(entry.timeNeedsReview, isFalse);
      expect(entry.occurredAt, DateTime.utc(2026, 10, 18, 23));
    });

    test('takes ownership from the expectation, never the browsing scope', () {
      final entry = SkippedTimelineEntry(
        action: skipAction(),
        context: context(untimedExpectation(person: 'adult-2')),
      );

      expect(entry.personId, 'adult-2');
      expect(entry.personId, isNot('me'));
    });

    test('rejects undone skips, linked skips and taken actions', () {
      final expectation = untimedExpectation();
      expect(
        () => SkippedTimelineEntry(
          action: skipAction(undone: true),
          context: context(expectation),
        ),
        throwsA(modelError('skip_action')),
      );
      expect(
        () => SkippedTimelineEntry(
          action: skipAction(recordId: 'record-1'),
          context: context(expectation),
        ),
        throwsA(modelError('skip_action')),
      );
      expect(
        () => SkippedTimelineEntry(
          action: takenAction(),
          context: context(expectation),
        ),
        throwsA(modelError('skip_action')),
      );
    });
  });

  group('Timeline entry order', () {
    test('sorts newest first and ties by prefixed identity', () {
      final older = RecordTimelineEntry(
        record: testRecord(
          id: 'record-3',
          actualAt: DateTime.utc(2026, 10, 19, 7),
        ),
      );
      final record = RecordTimelineEntry(record: testRecord(id: 'record-2'));
      final combined = CombinedTimelineEntry(
        actionId: 'action-1',
        components: [
          component(0, testRecord(id: 'record-1')),
          component(1, testRecord(id: 'record-4')),
        ],
      );
      final skipped = SkippedTimelineEntry(
        action: skipAction(id: 'skip-1'),
        context: TimelinePlanContext(expectation: exactExpectation()),
      );

      final entries = [older, skipped, combined, record]
        ..sort(compareTimelineEntries);

      expect(entries.map((entry) => entry.id.sortKey), [
        'c:action-1',
        'r:record-2',
        's:skip-1',
        'r:record-3',
      ]);
    });

    test('seek comparison matches the page order', () {
      final cursor = TimelineCursor.at(
        occurredAt: DateTime.utc(2026, 10, 19, 8),
        sortKey: 'r:record-2',
        query: TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );
      final after = RecordTimelineEntry(record: testRecord(id: 'record-9'));
      final before = RecordTimelineEntry(record: testRecord(id: 'record-1'));

      expect(timelineEntryIsAfterCursor(after, cursor), isTrue);
      expect(timelineEntryIsAfterCursor(before, cursor), isFalse);
    });
  });
}
