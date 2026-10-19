import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/domain/records.dart';

Matcher queryError(String code) =>
    isA<TimelineQueryException>().having((error) => error.code, 'code', code);

Matcher cursorError(String code) =>
    isA<TimelineCursorException>().having((error) => error.code, 'code', code);

void main() {
  final from = DateTime.utc(2026, 10, 1);
  final before = DateTime.utc(2026, 11, 1);

  TimelineFilter filters({
    FeedScope scope = const FeedScope.everyone(),
    DateTime? fromInstant,
    DateTime? beforeInstant,
    String? itemId,
    Iterable<String> typeIds = const [],
    String? actualUnit,
    Iterable<String> eventIds = const [],
    TimelineStatus status = TimelineStatus.all,
  }) => TimelineFilter(
    scope: scope,
    fromInstant: fromInstant,
    beforeInstant: beforeInstant,
    itemId: itemId,
    typeIds: typeIds,
    actualUnit: actualUnit,
    eventIds: eventIds,
    status: status,
  );

  TimelineQuery query({
    TimelineFilter? filter,
    String zone = 'Europe/London',
    int limit = TimelineLimits.defaultPageSize,
    TimelineCursor? cursor,
    String? anchorId,
  }) => TimelineQuery(
    filter: filter ?? filters(),
    displayZone: zone,
    limit: limit,
    cursor: cursor,
    anchorId: anchorId,
  );

  group('TimelineFilter', () {
    test('canonicalises bounded type and event groups', () {
      final value = filters(
        typeIds: ['type-b', 'type-a', 'type-b'],
        eventIds: ['event-2', 'event-1', 'event-2'],
      );
      expect(value.typeIds, ['type-a', 'type-b']);
      expect(value.eventIds, ['event-1', 'event-2']);
      expect(() => value.typeIds.add('type-c'), throwsUnsupportedError);
      expect(() => value.eventIds.add('event-3'), throwsUnsupportedError);
      expect(value.hasIdentityFilters, isTrue);
      expect(value.hasDateRange, isFalse);
      expect(value.isUnfiltered, isFalse);
    });

    test('rejects non-UTC and inverted ranges', () {
      expect(
        () => filters(fromInstant: DateTime(2026, 10, 1)),
        throwsA(queryError('invalid_range')),
      );
      expect(
        () => filters(fromInstant: before, beforeInstant: before),
        throwsA(queryError('invalid_range')),
      );
      expect(
        () => filters(fromInstant: from, beforeInstant: from),
        throwsA(queryError('invalid_range')),
      );
    });

    test('rejects over-broad groups instead of truncating', () {
      expect(
        () => filters(
          typeIds: List.generate(TimelineLimits.maxTypeIds + 1, (i) => 't$i'),
        ),
        throwsA(queryError('query_too_broad')),
      );
      expect(
        () => filters(
          eventIds: List.generate(TimelineLimits.maxEventIds + 1, (i) => 'e$i'),
        ),
        throwsA(queryError('query_too_broad')),
      );
      expect(
        filters(typeIds: List.generate(TimelineLimits.maxTypeIds, (i) => 't$i'))
            .typeIds,
        hasLength(TimelineLimits.maxTypeIds),
      );
    });

    test('rejects empty filter identities', () {
      expect(
        () => filters(scope: const FeedScope.person('')),
        throwsA(queryError('invalid_filter')),
      );
      expect(() => filters(itemId: ''), throwsA(queryError('invalid_filter')));
      expect(
        () => filters(actualUnit: '   '),
        throwsA(queryError('invalid_filter')),
      );
      expect(
        () => filters(typeIds: ['']),
        throwsA(queryError('invalid_filter')),
      );
    });

    test('restart clears a date or identity filter explicitly', () {
      final value = filters(
        fromInstant: from,
        beforeInstant: before,
        itemId: 'item-1',
        actualUnit: 'mg',
      );
      expect(value.restart(clearFrom: true).fromInstant, isNull);
      expect(value.restart(clearBefore: true).beforeInstant, isNull);
      expect(value.restart(clearItem: true).itemId, isNull);
      expect(value.restart(clearUnit: true).actualUnit, isNull);
      expect(value.restart(typeIds: const []).typeIds, isEmpty);
      expect(value.restart(eventIds: const []).eventIds, isEmpty);
    });
  });

  group('TimelineQuery', () {
    test('accepts the page bounds and rejects invalid limits', () {
      expect(query(limit: 1).limit, 1);
      expect(query(limit: TimelineLimits.maxPageSize).limit, 50);
      expect(() => query(limit: 0), throwsA(queryError('invalid_limit')));
      expect(
        () => query(limit: TimelineLimits.maxPageSize + 1),
        throwsA(queryError('invalid_limit')),
      );
      expect(() => query(zone: ''), throwsA(queryError('invalid_zone')));
    });

    test('identity changes for each semantic filter', () {
      final base = query().identity;
      expect(
        query(filter: filters(scope: const FeedScope.me())).identity,
        isNot(base),
      );
      expect(
        query(filter: filters(scope: const FeedScope.person('adult-2')))
            .identity,
        isNot(base),
      );
      expect(query(filter: filters(fromInstant: from)).identity, isNot(base));
      expect(
        query(filter: filters(beforeInstant: before)).identity,
        isNot(base),
      );
      expect(query(filter: filters(itemId: 'item-1')).identity, isNot(base));
      expect(query(filter: filters(typeIds: ['type-1'])).identity, isNot(base));
      expect(query(filter: filters(actualUnit: 'mg')).identity, isNot(base));
      expect(
        query(filter: filters(eventIds: ['event-1'])).identity,
        isNot(base),
      );
      expect(
        query(filter: filters(status: TimelineStatus.voided)).identity,
        isNot(base),
      );
      expect(query(zone: 'UTC').identity, isNot(base));
    });

    test('canonical group order has one identity', () {
      final first = query(filter: filters(typeIds: ['type-a', 'type-b']))
          .identity;
      final second = query(filter: filters(typeIds: ['type-b', 'type-a']))
          .identity;
      expect(second, first);
    });

    test('page limit and anchor do not change identity', () {
      final base = query().identity;
      expect(query(limit: 50).identity, base);
      expect(query(anchorId: 'entry-123').identity, base);
    });

    test('firstPage and restart drop the cursor', () {
      final first = query();
      final cursor = TimelineCursor.at(
        occurredAt: DateTime.utc(2026, 10, 19, 8),
        sortKey: 'r:record-1',
        query: first,
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );
      final second = first.withCursor(cursor);
      expect(second.cursor, same(cursor));
      expect(second.firstPage.cursor, isNull);
      expect(second.restart().cursor, isNull);
      expect(
        second.restart(filter: filters(status: TimelineStatus.recorded)).cursor,
        isNull,
      );
    });

    test('a filter change resets the cursor and preserves scope', () {
      final scoped = query(
        filter: filters(
          scope: const FeedScope.person('adult-2'),
          typeIds: ['type-1'],
        ),
      );
      final cursor = TimelineCursor.at(
        occurredAt: DateTime.utc(2026, 10, 19, 8),
        sortKey: 'r:record-1',
        query: scoped,
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );
      final withCursor = scoped.withCursor(cursor);
      final restarted = withCursor.restart(
        filter: withCursor.filter.restart(typeIds: const []),
      );

      expect(restarted.cursor, isNull);
      expect(restarted.filter.scope, const FeedScope.person('adult-2'));
      expect(restarted.filter.typeIds, isEmpty);
      expect(restarted.displayZone, 'Europe/London');
    });

    test('a cursor from another query is rejected at construction', () {
      final first = query();
      final cursor = TimelineCursor.at(
        occurredAt: DateTime.utc(2026, 10, 19, 8),
        sortKey: 'r:record-1',
        query: first,
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );
      expect(
        () => query(filter: filters(itemId: 'item-2')).withCursor(cursor),
        throwsA(cursorError('cursor_expired')),
      );
      expect(
        () => query(zone: 'UTC').withCursor(cursor),
        throwsA(cursorError('cursor_expired')),
      );
    });
  });
}
