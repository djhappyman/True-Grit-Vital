import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/domain/records.dart';

import 'history_test_data.dart';

Matcher modelError(String code) =>
    isA<TimelineModelException>().having((error) => error.code, 'code', code);

Matcher cursorError(String code) =>
    isA<TimelineCursorException>().having((error) => error.code, 'code', code);

TimelineFilter filters({
  FeedScope scope = const FeedScope.everyone(),
  TimelineStatus status = TimelineStatus.all,
}) => TimelineFilter(scope: scope, status: status);

TimelineQuery query({
  TimelineFilter? filter,
  int limit = TimelineLimits.defaultPageSize,
  TimelineCursor? cursor,
}) => TimelineQuery(
  filter: filter ?? filters(),
  displayZone: 'Europe/London',
  limit: limit,
  cursor: cursor,
);

RecordTimelineEntry recordEntry(
  String id, {
  int hour = 8,
  String person = 'me',
}) => RecordTimelineEntry(
  record: testRecord(
    id: id,
    person: person,
    actualAt: DateTime.utc(2026, 10, 19, hour),
  ),
);

void main() {
  group('TimelinePage construction', () {
    test('keeps a bounded ordered page and exposes its identity', () {
      final read = query(limit: 2);
      final page = TimelinePage(
        query: read,
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
        entries: [recordEntry('record-2', hour: 9), recordEntry('record-1')],
        hasMore: true,
      );

      expect(page.entries, hasLength(2));
      expect(page.queryIdentity, read.identity);
      expect(page.isFirstPage, isTrue);
      expect(page.hasMore, isTrue);
      expect(page.next, isNotNull);
      expect(page.next!.occurredAt, DateTime.utc(2026, 10, 19, 8));
      expect(page.next!.sortKey, 'r:record-1');
      expect(page.next!.queryHash, read.identity);
      expect(page.next!.schemaVersion, 16);
      expect(page.next!.datasetGeneration, 'generation-1');
    });

    test('has no next cursor on the final page', () {
      final page = TimelinePage(
        query: query(),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
        entries: [recordEntry('record-1')],
      );

      expect(page.hasMore, isFalse);
      expect(page.next, isNull);
    });

    test('rejects more entries than the page limit', () {
      expect(
        () => TimelinePage(
          query: query(limit: 1),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
          entries: [recordEntry('record-2', hour: 9), recordEntry('record-1')],
        ),
        throwsA(modelError('page_limit')),
      );
    });

    test('rejects duplicate parent identities', () {
      final entry = recordEntry('record-1');
      expect(
        () => TimelinePage(
          query: query(),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
          entries: [entry, entry],
        ),
        throwsA(modelError('page_duplicate')),
      );
    });

    test('rejects an order that is not occurredAt DESC, sortKey ASC', () {
      expect(
        () => TimelinePage(
          query: query(),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
          entries: [recordEntry('record-1'), recordEntry('record-2', hour: 9)],
        ),
        throwsA(modelError('page_order')),
      );
      expect(
        () => TimelinePage(
          query: query(),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
          entries: [
            recordEntry('record-2', hour: 9),
            recordEntry('record-1', hour: 9),
          ],
        ),
        throwsA(modelError('page_order')),
      );
    });
  });

  group('TimelinePage validation', () {
    test('requires a positive schema and a non-empty dataset generation', () {
      expect(
        () => TimelinePage(
          query: query(),
          schemaVersion: 0,
          datasetGeneration: 'generation-1',
          entries: const [],
        ),
        throwsA(modelError('page_schema')),
      );
      expect(
        () => TimelinePage(
          query: query(),
          schemaVersion: 16,
          datasetGeneration: '   ',
          entries: const [],
        ),
        throwsA(modelError('page_generation')),
      );
      expect(
        () => TimelinePage(
          query: query(),
          schemaVersion: 16,
          datasetGeneration: List.filled(257, 'a').join(),
          entries: const [],
        ),
        throwsA(modelError('page_generation')),
      );
    });

    test('rejects an entry at or before the cursor', () {
      final cursor = TimelineCursor.at(
        occurredAt: DateTime.utc(2026, 10, 19, 9),
        sortKey: 'r:record-5',
        query: query(),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );
      final read = query(cursor: cursor);

      expect(
        () => TimelinePage(
          query: read,
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
          entries: [recordEntry('record-4', hour: 9)],
        ),
        throwsA(modelError('page_cursor')),
      );
      expect(
        () => TimelinePage(
          query: read,
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
          entries: [recordEntry('record-9', hour: 10)],
        ),
        throwsA(modelError('page_cursor')),
      );
    });

    test('accepts entries strictly after the cursor and chains pages', () {
      final first = query(limit: 2);
      final firstPage = TimelinePage(
        query: first,
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
        entries: [recordEntry('record-3', hour: 9), recordEntry('record-2')],
        hasMore: true,
      );
      final second = first.withCursor(firstPage.next!);
      final secondPage = TimelinePage(
        query: second,
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
        entries: [recordEntry('record-1', hour: 7)],
      );

      expect(second.cursor, isNotNull);
      expect(secondPage.isFirstPage, isFalse);
      expect(secondPage.hasMore, isFalse);
      expect(secondPage.next, isNull);
      expect(secondPage.entries.single.id.sortKey, 'r:record-1');
    });

    test('rejects a person-scoped entry owned by someone else', () {
      expect(
        () => TimelinePage(
          query: query(
            filter: filters(scope: const FeedScope.person('adult-1')),
          ),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
          entries: [recordEntry('record-1', person: 'me')],
        ),
        throwsA(modelError('page_scope')),
      );
    });

    test('allows everyone scope to mix owners', () {
      final page = TimelinePage(
        query: query(filter: filters()),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
        entries: [
          recordEntry('record-1', person: 'me'),
          recordEntry('record-2', hour: 7, person: 'adult-2'),
        ],
      );

      expect(page.entries.map((entry) => entry.personId), ['me', 'adult-2']);
    });

    test('rejects an entry excluded by the status filter', () {
      final skipped = SkippedTimelineEntry(
        action: skipAction(),
        context: TimelinePlanContext(expectation: untimedExpectation()),
      );

      expect(
        () => TimelinePage(
          query: query(filter: filters(status: TimelineStatus.recorded)),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
          entries: [skipped],
        ),
        throwsA(modelError('page_status')),
      );
    });

    test('rejects hasMore without a parent row to point at', () {
      expect(
        () => TimelinePage(
          query: query(),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
          entries: const [],
          hasMore: true,
        ),
        throwsA(modelError('page_next')),
      );
    });

    test('expires a cursor from another schema or generation', () {
      final cursor = TimelineCursor.at(
        occurredAt: DateTime.utc(2026, 10, 19, 9),
        sortKey: 'r:record-1',
        query: query(),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );
      final read = query(cursor: cursor);

      expect(
        () => TimelinePage(
          query: read,
          schemaVersion: 17,
          datasetGeneration: 'generation-1',
          entries: const [],
        ),
        throwsA(cursorError('cursor_expired')),
      );
      expect(
        () => TimelinePage(
          query: read,
          schemaVersion: 16,
          datasetGeneration: 'generation-2',
          entries: const [],
        ),
        throwsA(cursorError('cursor_expired')),
      );
    });
  });
}
