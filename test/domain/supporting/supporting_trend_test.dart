import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'supporting_test_data.dart';

void main() {
  test('measurements remain individual including repeated same-day zero and negatives', () {
    final page = trend([
      record(
        id: 'b',
        results: [result(text: '-1')],
      ),
      record(
        id: 'a',
        results: [result(text: '0')],
      ),
      record(
        id: 'c',
        results: [result(text: '2')],
      ),
    ]);
    expect(page.sourceCount, 3);
    expect(page.groups.single.entries.map((e) => e.record.id.id), [
      'a',
      'b',
      'c',
    ]);
    expect(page.groups.single.entries.map((e) => e.numericValue.toString()), [
      '0/1',
      '-1/1',
      '2/1',
    ]);
    expect(page.groups.single.runs.map((r) => r.length), [1, 1, 1]);
  });
  test('qualified qualitative and missing rows break a line without boundary points', () {
    final page = trend([
      record(
        id: 'a',
        collection: SupportingDate.day(CivilDate(2026, 10, 1)),
        results: [result(id: 'a', text: '1')],
      ),
      record(
        id: 'b',
        collection: SupportingDate.day(CivilDate(2026, 10, 2)),
        results: [
          result(id: 'b', text: '2'),
          result(id: 'c', value: SupportingValue.numeric('<3')),
          result(id: 'd', text: '4'),
          result(id: 'e', value: SupportingValue.qualitative('Not detected')),
          result(id: 'f', value: SupportingValue.missing()),
        ],
      ),
    ]);
    final group = page.groups.single;
    expect(group.entries, hasLength(6));
    expect(group.entries.where((e) => e.isGap), hasLength(3));
    expect(group.runs.map((r) => r.length), [2, 1]);
    expect(group.entries[2].numericValue, isNull);
    expect(
      group.entries[2].result.value.exactAmount,
      parseSupportingNumber('3'),
    );
  });
  test('original units and explicit lab method specimen identities separate groups', () {
    final page = trend([
      record(id: 'base'),
      record(
        id: 'unit',
        results: [result(unit: 'mg/dl')],
      ),
      record(
        id: 'lab',
        source: provenance(lab: 'other_lab'),
      ),
      record(
        id: 'method',
        source: provenance(method: 'other_method'),
      ),
      record(
        id: 'specimen',
        source: provenance(specimen: 'other_specimen'),
      ),
    ]);
    expect(page.groups, hasLength(5));
    expect(page.groups.every((g) => g.canConnect), isTrue);
  });
  test(
    'exact saved source words are the local identity without explicit ids',
    () {
      SupportingProvenance words({
        String lab = 'Lab A',
        String? method = 'Immunoassay',
        String? specimen = 'Serum',
      }) => SupportingProvenance(
        mode: SupportingProvenanceMode.manualTranscription,
        laboratoryName: lab,
        methodText: method,
        specimenText: specimen,
      );
      final page = trend([
        record(id: 'a', source: words()),
        record(id: 'b', source: words()),
        record(
          id: 'case',
          source: words(lab: 'lab A'),
        ),
        record(
          id: 'space',
          source: words(lab: 'Lab A '),
        ),
        record(id: 'missing', source: words(specimen: null)),
        record(id: 'unit', source: words(), results: [result(unit: null)]),
      ]);
      expect(page.groups, hasLength(5));
      expect(page.groups.where((g) => g.canConnect), hasLength(3));
      expect(page.groups.where((g) => !g.canConnect), hasLength(2));
      // Exact words connect, but case and whitespace variants stay separate.
      expect(
        page.groups.singleWhere((g) => g.entries.length == 2).canConnect,
        isTrue,
      );
    },
  );
  test('an explicit identity never merges with the same saved words alone', () {
    final page = trend([
      record(
        id: 'id',
        source: SupportingProvenance(
          mode: SupportingProvenanceMode.manualTranscription,
          laboratoryId: 'lab-1',
          laboratoryName: 'Lab A',
          methodText: 'Immunoassay',
          specimenText: 'Serum',
        ),
      ),
      record(
        id: 'words',
        source: SupportingProvenance(
          mode: SupportingProvenanceMode.manualTranscription,
          laboratoryName: 'Lab A',
          methodText: 'Immunoassay',
          specimenText: 'Serum',
        ),
      ),
    ]);
    expect(page.groups, hasLength(2));
    expect(page.groups.every((g) => g.canConnect), isTrue);
  });
  test('per-result unknown provenance never fills identities from parent', () {
    final page = trend([
      record(
        results: [
          result(id: 'a'),
          result(
            id: 'b',
            source: SupportingProvenance(
              mode: SupportingProvenanceMode.manualTranscription,
            ),
          ),
        ],
      ),
    ]);
    expect(page.groups, hasLength(2));
    expect(page.groups.where((g) => g.canConnect), hasLength(1));
  });
  test('unknown partial dates remain unpositioned and entry date never substitutes collection', () {
    final rows = [
      record(id: 'unknown', collection: SupportingDate.unknown()),
      record(
        id: 'partial',
        collection: SupportingDate.partial(year: 2026, originalText: '2026'),
      ),
    ];
    final collection = trend(rows);
    expect(collection.groups, isEmpty);
    expect(collection.unpositioned, hasLength(2));
    expect(
      collection.unpositioned.every(
        (e) => e.day == null && e.exactInstant == null,
      ),
      isTrue,
    );
    expect(
      () => trend(rows, request: query(basis: SupportingDateBasis.entry)),
      throwsArgumentError,
    );
    expect(
      trend(
        rows,
        request: query(basis: SupportingDateBasis.report),
      ).groups.single.entries.first.day,
      CivilDate(2026, 10, 4),
    );
  });
  test('saved civil day stays unchanged across zones while exact instants use shown zone', () {
    final rows = [
      record(
        id: 'day',
        collection: SupportingDate.day(
          CivilDate(2026, 10, 1),
          zoneId: 'Asia/Tokyo',
        ),
      ),
      record(
        id: 'exact',
        collection: SupportingDate.exact(
          DateTime.utc(2026, 10, 1, 23, 30),
          zoneId: 'UTC',
          utcOffsetMinutes: 0,
        ),
      ),
    ];
    final page = trend(rows, request: query(zone: 'Asia/Tokyo'));
    expect(page.groups.single.entries[0].day, CivilDate(2026, 10, 1));
    expect(page.groups.single.entries[0].exactInstant, isNull);
    expect(page.groups.single.entries[1].day, CivilDate(2026, 10, 2));
  });
  test('an exact instant precedes a day-only record on the same shown day', () {
    final page = trend([
      record(id: 'day', collection: SupportingDate.day(CivilDate(2026, 10, 2))),
      record(
        id: 'exact',
        collection: SupportingDate.exact(
          DateTime.utc(2026, 10, 2, 12),
          zoneId: 'UTC',
          utcOffsetMinutes: 0,
        ),
      ),
    ], request: query(zone: 'UTC'));
    expect(page.groups.single.entries.map((e) => e.record.id.id), [
      'exact',
      'day',
    ]);
  });
  test('range is half-open and voided/current revisions are never pooled', () {
    final page = trend([
      record(
        id: 'before',
        collection: SupportingDate.day(CivilDate(2026, 9, 30)),
      ),
      record(id: 'first'),
      record(id: 'end', collection: SupportingDate.day(CivilDate(2026, 11, 1))),
      record(id: 'void', voided: true),
    ]);
    expect(page.sourceCount, 1);
    expect(page.groups.single.entries.single.record.id.id, 'first');
    expect(
      () => trend([
        record(),
        record(revision: 2, corrected: DateTime.utc(2026, 10, 20)),
      ]),
      throwsArgumentError,
    );
    expect(() => trend([record(person: 'other')]), throwsArgumentError);
  });
  test('each saved range is retained rather than pooled across the trend', () {
    final one = SourceReferenceRange(originalText: 'Source range A'),
        two = SourceReferenceRange(originalText: 'Source range B');
    final page = trend([
      record(
        id: 'one',
        results: [result(range: one)],
      ),
      record(
        id: 'two',
        results: [result(range: two)],
      ),
    ]);
    expect(
      page.groups.single.entries.map(
        (e) => e.result.referenceRange!.originalText,
      ),
      ['Source range A', 'Source range B'],
    );
  });
  test(
    'query identity includes person metric group basis dates and display zone',
    () {
      final original = query();
      expect(
        SupportingTrendQuery.fromJson(original.toJson()).identity,
        original.identity,
      );
      expect(
        [
          query(person: 'other'),
          query(metric: 'other'),
          query(basis: SupportingDateBasis.report),
          query(zone: 'Europe/London'),
          query(group: 'group'),
        ].every((q) => q.identity != original.identity),
        isTrue,
      );
    },
  );
  test('stale same-query person schema dataset and lock completions cannot publish', () {
    final guard = SupportingTrendRequestGuard();
    final first = guard.begin(
      query(),
      schemaVersion: 19,
      datasetGeneration: 'old',
    );
    final second = guard.begin(
      query(),
      schemaVersion: 19,
      datasetGeneration: 'old',
    );
    expect(guard.accepts(first), isFalse);
    expect(guard.accepts(second), isTrue);
    final next = guard.begin(
      query(person: 'other'),
      schemaVersion: 20,
      datasetGeneration: 'new',
    );
    expect(guard.accepts(second), isFalse);
    for (final token in [
      SupportingTrendToken(
        queryIdentity: next.queryIdentity,
        schemaVersion: 19,
        datasetGeneration: 'new',
        requestGeneration: next.requestGeneration,
      ),
      SupportingTrendToken(
        queryIdentity: next.queryIdentity,
        schemaVersion: 20,
        datasetGeneration: 'old',
        requestGeneration: next.requestGeneration,
      ),
    ]) {
      expect(guard.accepts(token), isFalse);
    }
    guard.invalidate();
    expect(guard.accepts(next), isFalse);
  });
  test('host oracle retains 10000 signed source rows and rejects overflow without truncation', () {
    final rows = [
      for (var parent = 0; parent < 10; parent++)
        record(
          id: 'p$parent',
          results: [
            for (var i = 0; i < 1000; i++)
              result(id: 'r$i', text: '${parent * 1000 + i - 5000}'),
          ],
        ),
    ];
    final time = Stopwatch()..start();
    final page = trend(rows);
    time.stop();
    final actual = page.groups.single.entries
        .map((e) => e.numericValue!.numerator.toInt())
        .toSet();
    expect(actual, {for (var i = -5000; i < 5000; i++) i});
    expect(page.sourceCount, 10000);
    expect(page.groups.single.entries, hasLength(10000));
    expect(
      () => trend([...rows, record(id: 'overflow')]),
      throwsA(
        isA<SupportingLimitException>().having(
          (e) => e.code,
          'code',
          'trend_rows',
        ),
      ),
    );
    stdout.writeln(
      'SUPPORTING_TREND_PROBE ${jsonEncode({'rows': 10000, 'buildMs': time.elapsedMilliseconds, 'oracle': 'all individual integers -5000 through 4999, no aggregation', 'overflow': 'rejected'})}',
    );
  });
  test('unavailable display zone exposes the UTC fallback without changing source dates', () {
    final exact = SupportingDate.exact(
      DateTime.utc(2026, 10, 1, 23, 30),
      zoneId: 'Europe/London',
      utcOffsetMinutes: 60,
    );
    final entry = trend([
      record(collection: exact),
    ], request: query(zone: 'Not/AZone')).groups.single.entries.single;
    expect(entry.positionZoneId, 'UTC');
    expect(entry.positionZoneFallback, isTrue);
    expect(entry.date.zoneId, 'Europe/London');
    expect(entry.date.utcOffsetMinutes, 60);
    expect(entry.exactInstant, exact.instant);
  });
  test('explicit group filtering retains its exact sources and excludes other units', () {
    final records = [
      record(id: 'one'),
      record(
        id: 'two',
        results: [result(unit: 'mmol/L')],
      ),
    ];
    final first = trend(records).groups.first;
    final filtered = trend(records, request: query(group: first.key.identity));
    expect(filtered.groups, hasLength(1));
    expect(filtered.groups.single.key, first.key);
    expect(filtered.sourceCount, 1);
  });
  test('repeated day-only results stay separate markers while distinct instants connect', () {
    final dayOnly = trend([
      record(
        results: [
          result(id: 'a', text: '1'),
          result(id: 'b', text: '2'),
        ],
      ),
    ]);
    expect(dayOnly.groups.single.runs.map((r) => r.length), [1, 1]);

    final instants = trend([
      record(
        id: 'a',
        collection: SupportingDate.exact(
          DateTime.utc(2026, 10, 1, 8),
          zoneId: 'UTC',
          utcOffsetMinutes: 0,
        ),
      ),
      record(
        id: 'b',
        collection: SupportingDate.exact(
          DateTime.utc(2026, 10, 1, 12),
          zoneId: 'UTC',
          utcOffsetMinutes: 0,
        ),
      ),
    ]);
    expect(instants.groups.single.runs.single, hasLength(2));
  });
  test(
    'an unpositioned matching result marks its positioned group incomplete',
    () {
      final page = trend([
        record(id: 'positioned'),
        record(id: 'undated', collection: SupportingDate.unknown()),
      ]);
      expect(page.groups.single.entries, hasLength(1));
      expect(page.unpositioned, hasLength(1));
      expect(page.groups.single.hasUnpositionedGap, isTrue);
    },
  );
}
