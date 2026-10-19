import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/domain/records.dart';

Matcher cursorError(String code) =>
    isA<TimelineCursorException>().having((error) => error.code, 'code', code);

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

String envelope(Map<String, Object?> payload) =>
    base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');

Map<String, Object?> validPayload({
  int version = TimelineCursor.envelopeVersion,
  int? atMicros,
  String key = 'r:record-1',
  String? hash,
  int schema = 16,
  String dataset = 'generation-1',
}) => <String, Object?>{
  'v': version,
  'a': atMicros ?? DateTime.utc(2026, 10, 19, 8).microsecondsSinceEpoch,
  'k': key,
  'q': hash ?? query().identity,
  's': schema,
  'd': dataset,
};

void main() {
  final at = DateTime.utc(2026, 10, 19, 8, 30, 15, 123, 456);

  group('TimelineCursor envelope', () {
    test('round-trips every field without padding', () {
      final first = query();
      final cursor = TimelineCursor.at(
        occurredAt: at,
        sortKey: 'r:record-1',
        query: first,
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );

      final encoded = cursor.encode();
      expect(encoded, isNot(contains('=')));

      final decoded = TimelineCursor.decode(encoded);
      expect(decoded.occurredAt, at);
      expect(decoded.occurredAt.isUtc, isTrue);
      expect(decoded.sortKey, 'r:record-1');
      expect(decoded.queryHash, first.identity);
      expect(decoded.schemaVersion, 16);
      expect(decoded.datasetGeneration, 'generation-1');
    });

    test('encodes a versioned JSON payload with no row snapshot', () {
      final cursor = TimelineCursor.at(
        occurredAt: at,
        sortKey: 'c:action-1',
        query: query(),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor.encode()))),
      ) as Map<String, dynamic>;

      expect(payload, {
        'v': 1,
        'a': at.microsecondsSinceEpoch,
        'k': 'c:action-1',
        'q': query().identity,
        's': 16,
        'd': 'generation-1',
      });
    });

    test('accepts padded input and normalises it', () {
      final cursor = TimelineCursor.at(
        occurredAt: at,
        sortKey: 's:skip-1',
        query: query(),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );

      final encoded = cursor.encode();
      final padded = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');
      expect(TimelineCursor.decode(padded).sortKey, 's:skip-1');
    });

    test('converts the supplied instant to UTC without shifting it', () {
      final local = DateTime(2026, 10, 19, 8, 30);
      final cursor = TimelineCursor.at(
        occurredAt: local,
        sortKey: 'r:record-1',
        query: query(),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );

      expect(cursor.occurredAt.isUtc, isTrue);
      expect(
        cursor.occurredAt.microsecondsSinceEpoch,
        local.microsecondsSinceEpoch,
      );
    });
  });

  group('TimelineCursor validation', () {
    test('rejects malformed and unsupported envelopes', () {
      expect(
        () => TimelineCursor.decode(''),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.decode('not base64!'),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.decode(List.filled(4097, 'A').join()),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.decode(envelope({})),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.decode(
          envelope(validPayload(version: TimelineCursor.envelopeVersion + 1)),
        ),
        throwsA(cursorError('cursor_version')),
      );
      expect(
        () => TimelineCursor.decode(envelope(validPayload(key: 'x:record-1'))),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.decode(envelope(validPayload(hash: 'abc'))),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.decode(envelope(validPayload(schema: 0))),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.decode(envelope(validPayload(dataset: '  '))),
        throwsA(cursorError('cursor_malformed')),
      );
    });

    test('rejects instants outside the supported civil range', () {
      final yearZero = DateTime.utc(0, 1, 1).microsecondsSinceEpoch;
      expect(
        () => TimelineCursor.decode(envelope(validPayload(atMicros: yearZero))),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.at(
          occurredAt: DateTime.utc(0, 1, 1),
          sortKey: 'r:record-1',
          query: query(),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
        ),
        throwsA(cursorError('cursor_malformed')),
      );
    });

    test('rejects invalid construction input', () {
      expect(
        () => TimelineCursor.at(
          occurredAt: at,
          sortKey: 'record-1',
          query: query(),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
        ),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.at(
          occurredAt: at,
          sortKey: 'r:',
          query: query(),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
        ),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.at(
          occurredAt: at,
          sortKey: 'r:record-1',
          query: query(),
          schemaVersion: 0,
          datasetGeneration: 'generation-1',
        ),
        throwsA(cursorError('cursor_malformed')),
      );
      expect(
        () => TimelineCursor.at(
          occurredAt: at,
          sortKey: 'r:record-1',
          query: query(),
          schemaVersion: 16,
          datasetGeneration: '',
        ),
        throwsA(cursorError('cursor_malformed')),
      );
    });

    test('expires on a changed query, schema or dataset generation', () {
      final first = query();
      final cursor = TimelineCursor.at(
        occurredAt: at,
        sortKey: 'r:record-1',
        query: first,
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );

      expect(
        cursor.validateFor(
          query: first,
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
        ),
        same(cursor),
      );
      expect(
        () => cursor.validateFor(
          query: first,
          schemaVersion: 17,
          datasetGeneration: 'generation-1',
        ),
        throwsA(cursorError('cursor_expired')),
      );
      expect(
        () => cursor.validateFor(
          query: first,
          schemaVersion: 16,
          datasetGeneration: 'generation-2',
        ),
        throwsA(cursorError('cursor_expired')),
      );
      expect(
        () => cursor.validateFor(
          query: query(filter: filters(itemId: 'item-2')),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
        ),
        throwsA(cursorError('cursor_expired')),
      );
      expect(
        () => cursor.validateFor(
          query: query(zone: 'UTC'),
          schemaVersion: 16,
          datasetGeneration: 'generation-1',
        ),
        throwsA(cursorError('cursor_expired')),
      );
    });

    test('stays valid across a page-size or anchor change', () {
      final first = query();
      final cursor = TimelineCursor.at(
        occurredAt: at,
        sortKey: 'r:record-1',
        query: first,
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );

      final resized = query(limit: TimelineLimits.maxPageSize);
      expect(() => resized.withCursor(cursor), returnsNormally);
      expect(resized.withCursor(cursor).cursor, same(cursor));

      final anchored = query(anchorId: 'r:record-9');
      expect(() => anchored.withCursor(cursor), returnsNormally);
    });

    test('is rejected by a query with a different identity', () {
      final cursor = TimelineCursor.at(
        occurredAt: at,
        sortKey: 'r:record-1',
        query: query(),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );

      expect(
        () =>
            query(filter: filters(status: TimelineStatus.voided))
                .withCursor(cursor),
        throwsA(cursorError('cursor_expired')),
      );
      expect(
        () => query(filter: filters(typeIds: ['type-1'])).withCursor(cursor),
        throwsA(cursorError('cursor_expired')),
      );
    });
  });

  group('TimelineCursor ordering', () {
    test('seeks strictly older rows and larger keys at an equal instant', () {
      final cursor = TimelineCursor.at(
        occurredAt: DateTime.utc(2026, 10, 19, 12),
        sortKey: 'r:r5',
        query: query(),
        schemaVersion: 16,
        datasetGeneration: 'generation-1',
      );

      expect(
        cursor.isAfterCursor(
          occurredAt: DateTime.utc(2026, 10, 19, 11, 59, 59),
          sortKey: 'r:r1',
        ),
        isTrue,
      );
      expect(
        cursor.isAfterCursor(
          occurredAt: DateTime.utc(2026, 10, 19, 12),
          sortKey: 'r:r4',
        ),
        isFalse,
      );
      expect(
        cursor.isAfterCursor(
          occurredAt: DateTime.utc(2026, 10, 19, 12),
          sortKey: 'r:r6',
        ),
        isTrue,
      );
      expect(
        cursor.isAfterCursor(
          occurredAt: DateTime.utc(2026, 10, 19, 12),
          sortKey: 's:skip-1',
        ),
        isTrue,
      );
      expect(
        cursor.isAfterCursor(
          occurredAt: DateTime.utc(2026, 10, 19, 12),
          sortKey: 'c:action-9',
        ),
        isFalse,
      );
      expect(
        cursor.isAfterCursor(
          occurredAt: DateTime.utc(2026, 10, 19, 12, 0, 0, 0, 1),
          sortKey: 's:skip-1',
        ),
        isFalse,
      );
    });

    test('compares descending instant then ascending prefixed key', () {
      final newest = DateTime.utc(2026, 10, 19, 12);
      final older = DateTime.utc(2026, 10, 19, 11);

      expect(
        TimelineCursor.comparePositions(
          aAt: newest,
          aKey: 'r:r9',
          bAt: older,
          bKey: 'r:r1',
        ),
        lessThan(0),
      );
      expect(
        TimelineCursor.comparePositions(
          aAt: older,
          aKey: 'r:r1',
          bAt: newest,
          bKey: 'r:r9',
        ),
        greaterThan(0),
      );
      expect(
        TimelineCursor.comparePositions(
          aAt: newest,
          aKey: 'r:r2',
          bAt: newest,
          bKey: 'r:r1',
        ),
        greaterThan(0),
      );
      expect(
        TimelineCursor.comparePositions(
          aAt: newest,
          aKey: 'c:a',
          bAt: newest,
          bKey: 'r:a',
        ),
        lessThan(0),
      );
      expect(
        TimelineCursor.comparePositions(
          aAt: newest,
          aKey: 'r:a',
          bAt: newest,
          bKey: 's:a',
        ),
        lessThan(0),
      );
      expect(
        TimelineCursor.comparePositions(
          aAt: newest,
          aKey: 'r:a',
          bAt: newest,
          bKey: 'r:a',
        ),
        0,
      );
    });
  });
}
