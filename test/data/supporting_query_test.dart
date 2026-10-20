import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

/// Bounded chronology and query-plan checks for supporting records.
///
/// The chronology is deliberately one contract across filter, order and
/// cursor: exact instants use the requested display-zone date, day-only
/// records keep their supplied civil day, and unknown/partial dates are an
/// explicit unpositioned section. Entry is audit browsing only.
void main() {
  late Directory directory;
  late String path;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);

  Database raw() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  SupportingProvenance provenance() => SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryId: 'lab',
    laboratoryName: 'Synthetic laboratory',
    methodId: 'method',
    methodText: 'Synthetic method',
    specimenId: 'serum',
    specimenText: 'Serum',
  );

  LabResultSnapshot result(
    String id, {
    String metric = 'metric',
    String value = '1',
    String? unit = 'mg/L',
  }) => LabResultSnapshot(
    id: id,
    metricId: metric,
    markerName: 'Synthetic marker',
    value: SupportingValue.numeric(value),
    unit: unit,
  );

  LabPanelSnapshot panel(
    String id, {
    SupportingDate? date,
    String metric = 'metric',
    List<LabResultSnapshot>? results,
    SupportingDate? report,
  }) => LabPanelSnapshot(
    id: SupportingRecordId(id: id, personId: meId),
    title: 'Synthetic $id',
    collectionDate: date ?? SupportingDate.day(CivilDate(2026, 10, 1)),
    reportDate: report ?? SupportingDate.unknown(),
    provenance: provenance(),
    results: results ?? [result('$id-result', metric: metric)],
  );

  SupportingDate exact(
    DateTime instant, {
    String zone = 'UTC',
    int offset = 0,
  }) => SupportingDate.exact(instant, zoneId: zone, utcOffsetMinutes: offset);

  Future<SupportingRevision> save(LabPanelSnapshot value) => store.saveLabPanel(
    SaveLabPanelCommand(
      commandId: 'save-${value.id.id}',
      generation: store.generation,
      expectedPersonRevision: 1,
      panel: value,
    ),
  );

  Future<List<String>> pageIds(
    SupportingQuery query, {
    int maxPages = 100,
  }) async {
    final ids = <String>[];
    SupportingCursor? cursor;
    for (var page = 0; page < maxPages; page++) {
      final result = await store.supportingRecords(query, cursor: cursor);
      ids.addAll(result.entries.map((e) => e.id.id));
      if (!result.hasMore) return ids;
      cursor = result.next;
    }
    throw StateError('page_loop');
  }

  List<String> plan(Database db, String sql, [List<Object?> args = const []]) =>
      db
          .select('EXPLAIN QUERY PLAN $sql', args)
          .map((r) => r['detail'] as String)
          .toList();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-support-query-');
    path = '${directory.path}/db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('trends use current revision results after a correction', () async {
    await save(panel('corrected', results: [result('marker', value: '1')]));
    await store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: 'correct-result',
        generation: store.generation,
        expectedPersonRevision: 1,
        expectedRevision: 1,
        panel: panel('corrected', results: [result('marker', value: '9')]),
      ),
    );
    final query = SupportingTrendQuery(
      personId: meId,
      metricId: 'metric',
      fromDate: CivilDate(2026, 10, 1),
      beforeDate: CivilDate(2026, 10, 2),
      displayZone: 'UTC',
    );
    final page = await store.supportingTrend(query);
    expect(page.sourceCount, 1);
    expect(page.groups.single.entries.single.result.value.originalText, '9');
    expect(page.groups.single.entries.single.record.revision, 2);
    final filtered = await store.supportingTrend(
      SupportingTrendQuery(
        personId: meId,
        metricId: 'metric',
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 2),
        displayZone: 'UTC',
        comparisonGroup: page.groups.single.key.identity,
      ),
    );
    expect(filtered.sourceCount, 1);
    expect(
      filtered.groups.single.entries.single.result.value.originalText,
      '9',
    );
  });
  test(
    'legacy saved-offset day rows still follow display chronology',
    () async {
      await save(
        panel(
          'newer',
          date: exact(
            DateTime.utc(2026, 10, 1, 23),
            zone: 'Saved west',
            offset: -12 * 60,
          ),
        ),
      );
      await save(
        panel(
          'older',
          date: exact(
            DateTime.utc(2026, 10, 1, 13),
            zone: 'Saved east',
            offset: 14 * 60,
          ),
        ),
      );
      // Schema19 rows could carry these saved-offset projections. The exact
      // branch must ignore them and use the requested display zone.
      final db = raw();
      db.execute(
        "UPDATE supporting_record SET collection_day='2026-10-01' WHERE id='newer'",
      );
      db.execute(
        "UPDATE supporting_record SET collection_day='2026-10-02' WHERE id='older'",
      );
      db.close();
      final query = SupportingQuery(
        personId: meId,
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 2),
        includeUnknownDates: false,
        displayZone: 'UTC',
        limit: 1,
      );
      final first = await store.supportingRecords(query);
      expect(first.entries.single.id.id, 'newer');
      final second = await store.supportingRecords(query, cursor: first.next);
      expect(second.entries.single.id.id, 'older');
      expect(second.hasMore, isFalse);
    },
  );

  test('saved-offset day never outranks the display-zone instant', () async {
    // Reproduced ordering defect: the older instant was saved with a +14h
    // offset, so its saved-offset day was 2 October while the newer instant
    // saved with -12h stayed on 1 October.
    await save(
      panel(
        'newer',
        date: exact(
          DateTime.utc(2026, 10, 1, 23),
          zone: 'Saved west',
          offset: -12 * 60,
        ),
      ),
    );
    await save(
      panel(
        'older',
        date: exact(
          DateTime.utc(2026, 10, 1, 13),
          zone: 'Saved east',
          offset: 14 * 60,
        ),
      ),
    );
    final query = SupportingQuery(
      personId: meId,
      fromDate: CivilDate(2026, 10, 1),
      beforeDate: CivilDate(2026, 10, 2),
      includeUnknownDates: false,
      displayZone: 'UTC',
    );
    expect(await pageIds(query), ['newer', 'older']);
    final first = await store.supportingRecords(
      SupportingQuery(
        personId: meId,
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 2),
        includeUnknownDates: false,
        displayZone: 'UTC',
        limit: 1,
      ),
    );
    expect(first.entries.single.id.id, 'newer');
    final second = await store.supportingRecords(
      SupportingQuery(
        personId: meId,
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 2),
        includeUnknownDates: false,
        displayZone: 'UTC',
        limit: 1,
      ),
      cursor: first.next,
    );
    expect(second.entries.single.id.id, 'older');
    expect(second.hasMore, isFalse);
  });

  test(
    'exact instants move with the display zone while civil days stay put',
    () async {
      await save(
        panel('instant', date: exact(DateTime.utc(2026, 10, 1, 23, 30))),
      );
      await save(
        panel(
          'civil',
          date: SupportingDate.day(
            CivilDate(2026, 10, 2),
            zoneId: 'Asia/Tokyo',
          ),
        ),
      );
      await save(panel('unknown', date: SupportingDate.unknown()));
      await save(
        panel(
          'partial',
          date: SupportingDate.partial(year: 2026, originalText: '2026'),
        ),
      );
      final tokyo = await pageIds(
        SupportingQuery(
          personId: meId,
          fromDate: CivilDate(2026, 10, 2),
          beforeDate: CivilDate(2026, 10, 3),
          includeUnknownDates: false,
          displayZone: 'Asia/Tokyo',
          limit: 1,
        ),
      );
      // Exact display day 2 October sorts before the supplied day because an
      // instant outranks a day-only record within one civil day.
      expect(tokyo, ['instant', 'civil']);
      final honolulu = await pageIds(
        SupportingQuery(
          personId: meId,
          fromDate: CivilDate(2026, 10, 1),
          beforeDate: CivilDate(2026, 10, 2),
          includeUnknownDates: false,
          displayZone: 'Pacific/Honolulu',
        ),
      );
      expect(honolulu, ['instant']);
      final unknown = await pageIds(
        SupportingQuery(
          personId: meId,
          includeUnknownDates: true,
          displayZone: 'UTC',
        ),
      );
      expect(unknown.sublist(unknown.length - 2), ['partial', 'unknown']);
    },
  );

  test(
    'mixed exact, civil and unpositioned pages are complete and tie-stable',
    () async {
      for (var i = 0; i < 9; i++) {
        await save(
          panel('exact-$i', date: exact(DateTime.utc(2026, 10, 2, 12, i))),
        );
      }
      for (var i = 0; i < 9; i++) {
        await save(
          panel('civil-$i', date: SupportingDate.day(CivilDate(2026, 10, 2))),
        );
      }
      for (var i = 0; i < 5; i++) {
        await save(panel('unknown-$i', date: SupportingDate.unknown()));
      }
      for (var i = 0; i < 5; i++) {
        await save(
          panel(
            'partial-$i',
            date: SupportingDate.partial(year: 2026, originalText: '2026'),
          ),
        );
      }
      final query = SupportingQuery(
        personId: meId,
        fromDate: CivilDate(2026, 10, 2),
        beforeDate: CivilDate(2026, 10, 3),
        includeUnknownDates: true,
        displayZone: 'UTC',
        limit: 4,
      );
      final seen = <String>[];
      SupportingCursor? cursor;
      for (var page = 0; page < 100; page++) {
        final result = await store.supportingRecords(query, cursor: cursor);
        seen.addAll(result.entries.map((e) => e.id.id));
        if (!result.hasMore) break;
        cursor = result.next;
      }
      expect(seen, hasLength(28));
      expect(seen.toSet(), hasLength(28));
      expect(seen.take(18).toList(), [
        for (var i = 8; i >= 0; i--) 'exact-$i',
        for (var i = 0; i < 9; i++) 'civil-$i',
      ]);
      expect(seen.skip(18).toSet(), {
        for (var i = 0; i < 5; i++) 'unknown-$i',
        for (var i = 0; i < 5; i++) 'partial-$i',
      });
      // A narrow date range excludes the unpositioned section on request.
      final knownOnly = await pageIds(
        SupportingQuery(
          personId: meId,
          fromDate: CivilDate(2026, 10, 2),
          beforeDate: CivilDate(2026, 10, 3),
          includeUnknownDates: false,
          displayZone: 'UTC',
        ),
      );
      expect(knownOnly, hasLength(18));
    },
  );

  test(
    'display-zone day boundaries follow DST gaps and repeated clocks',
    () async {
      // Europe/London ends BST on 25 October 2026 and starts it on 29 March.
      await save(
        panel('autumn-bst', date: exact(DateTime.utc(2026, 10, 25, 0, 30))),
      );
      await save(
        panel('autumn-gmt', date: exact(DateTime.utc(2026, 10, 25, 1, 30))),
      );
      await save(
        panel('spring-utc', date: exact(DateTime.utc(2026, 3, 29, 0, 30))),
      );
      await save(
        panel('spring-bst', date: exact(DateTime.utc(2026, 3, 29, 1, 30))),
      );
      await save(
        panel(
          'spring-next-day',
          date: exact(DateTime.utc(2026, 3, 29, 23, 30)),
        ),
      );
      await save(
        panel('spring-civil', date: SupportingDate.day(CivilDate(2026, 3, 29))),
      );
      final autumn = await pageIds(
        SupportingQuery(
          personId: meId,
          fromDate: CivilDate(2026, 10, 25),
          beforeDate: CivilDate(2026, 10, 26),
          includeUnknownDates: false,
          displayZone: 'Europe/London',
        ),
      );
      expect(autumn, ['autumn-gmt', 'autumn-bst']);
      final springDay = await pageIds(
        SupportingQuery(
          personId: meId,
          fromDate: CivilDate(2026, 3, 29),
          beforeDate: CivilDate(2026, 3, 30),
          includeUnknownDates: false,
          displayZone: 'Europe/London',
          limit: 2,
        ),
      );
      expect(springDay, ['spring-bst', 'spring-utc', 'spring-civil']);
      final springNext = await pageIds(
        SupportingQuery(
          personId: meId,
          fromDate: CivilDate(2026, 3, 30),
          beforeDate: CivilDate(2026, 3, 31),
          includeUnknownDates: false,
          displayZone: 'Europe/London',
        ),
      );
      expect(springNext, ['spring-next-day']);
    },
  );

  test('entry is an audit instant feed in the display zone', () async {
    await save(panel('first', date: exact(DateTime.utc(2026, 10, 1, 23, 30))));
    await save(panel('second', date: exact(DateTime.utc(2026, 10, 2, 0, 30))));
    final db = raw();
    db.execute(
      "UPDATE supporting_record SET entered_at=?,entry_day='2026-10-01' WHERE id='first'",
      [DateTime.utc(2026, 10, 1, 23, 30).microsecondsSinceEpoch],
    );
    db.execute(
      "UPDATE supporting_record SET entered_at=?,entry_day='2026-10-02' WHERE id='second'",
      [DateTime.utc(2026, 10, 2, 0, 30).microsecondsSinceEpoch],
    );
    db.close();
    final firstDay = await pageIds(
      SupportingQuery(
        personId: meId,
        dateBasis: SupportingDateBasis.entry,
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 2),
        displayZone: 'Europe/London',
      ),
    );
    expect(firstDay, isEmpty);
    final secondDay = await pageIds(
      SupportingQuery(
        personId: meId,
        dateBasis: SupportingDateBasis.entry,
        fromDate: CivilDate(2026, 10, 2),
        beforeDate: CivilDate(2026, 10, 3),
        displayZone: 'Europe/London',
        limit: 1,
      ),
    );
    expect(secondDay, ['second', 'first']);
    await expectLater(
      () => store.supportingTrend(
        SupportingTrendQuery(
          personId: meId,
          metricId: 'metric',
          fromDate: CivilDate(2026, 10, 1),
          beforeDate: CivilDate(2026, 10, 3),
          dateBasis: SupportingDateBasis.entry,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'narrow trend succeeds over a large unrelated lifetime history',
    () async {
      await save(
        panel(
          'current',
          date: SupportingDate.day(CivilDate(2026, 10, 1)),
          results: [for (var i = 0; i < 1000; i++) result('current-$i')],
        ),
      );
      final db = raw();
      db.execute('BEGIN');
      for (var i = 0; i < 20; i++) {
        final id = 'old-$i';
        db.execute(
          "INSERT INTO supporting_record SELECT ?,person,kind,revision,entered_at,entry_day,voided,'2024-01-01',NULL,report_day,report_at FROM supporting_record WHERE id='current'",
          [id],
        );
        db.execute(
          "INSERT INTO supporting_revision SELECT ?,person,revision,?,entered_at,json_set(snapshot,'\$.snapshot.id.id',?,'\$.snapshot.collectionDate.civilDate','2024-01-01','\$.operationId',?),json_set(header,'\$.snapshot.id.id',?,'\$.snapshot.collectionDate.civilDate','2024-01-01','\$.operationId',?) FROM supporting_revision WHERE record='current'",
          [id, 'op-$i', id, 'op-$i', id, 'op-$i'],
        );
        db.execute(
          "INSERT INTO supporting_result SELECT ?,person,revision,id,position,metric,unit,value_kind,numerator,denominator,snapshot FROM supporting_result WHERE record='current'",
          [id],
        );
      }
      db.execute('COMMIT');
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      db.close();
      final narrow = await store.supportingTrend(
        SupportingTrendQuery(
          personId: meId,
          metricId: 'metric',
          fromDate: CivilDate(2026, 10, 1),
          beforeDate: CivilDate(2026, 10, 2),
        ),
      );
      expect(narrow.sourceCount, 1000);
      await expectLater(
        store.supportingTrend(
          SupportingTrendQuery(
            personId: meId,
            metricId: 'metric',
            fromDate: CivilDate(2023, 1, 1),
            beforeDate: CivilDate(2027, 1, 1),
          ),
        ),
        throwsA(isA<SupportingLimitException>()),
      );
    },
  );

  test(
    'report dates page by shown day and keep unknown reports unpositioned',
    () async {
      await save(
        panel(
          'report-exact',
          date: SupportingDate.unknown(),
          report: exact(DateTime.utc(2026, 10, 4, 23, 30)),
        ),
      );
      await save(
        panel(
          'report-civil',
          date: SupportingDate.unknown(),
          report: SupportingDate.day(
            CivilDate(2026, 10, 5),
            zoneId: 'Asia/Tokyo',
          ),
        ),
      );
      await save(
        panel(
          'report-unknown',
          date: SupportingDate.unknown(),
          report: SupportingDate.unknown(),
        ),
      );
      final query = SupportingQuery(
        personId: meId,
        dateBasis: SupportingDateBasis.report,
        fromDate: CivilDate(2026, 10, 5),
        beforeDate: CivilDate(2026, 10, 6),
        includeUnknownDates: false,
        displayZone: 'Asia/Tokyo',
        limit: 1,
      );
      final first = await store.supportingRecords(query);
      expect(first.entries.single.id.id, 'report-exact');
      final second = await store.supportingRecords(query, cursor: first.next);
      expect(second.entries.single.id.id, 'report-civil');
      expect(second.hasMore, isFalse);
      final withUnknown = await pageIds(
        SupportingQuery(
          personId: meId,
          dateBasis: SupportingDateBasis.report,
          includeUnknownDates: true,
          displayZone: 'Asia/Tokyo',
        ),
      );
      expect(withUnknown.last, 'report-unknown');
    },
  );

  test('comparison-group cap ignores a larger unrelated group first', () async {
    await save(
      panel(
        'current',
        date: SupportingDate.day(CivilDate(2026, 10, 1)),
        results: [for (var i = 0; i < 100; i++) result('current-$i')],
      ),
    );
    // Lexically earlier records with 11,000 results in a different unit.
    // They are fully unrelated to the requested group but still inside the
    // requested date window, so a pre-filter SQL LIMIT would reject the
    // small valid query before reaching it. Each panel stays within the
    // domain's 1,000-result save bound.
    final db = raw();
    db.execute('BEGIN');
    for (var record = 0; record < 11; record++) {
      final id = 'aa-other-$record';
      db.execute(
        "INSERT INTO supporting_record SELECT ?,person,kind,revision,entered_at,entry_day,voided,collection_day,collection_at,report_day,report_at FROM supporting_record WHERE id='current'",
        [id],
      );
      db.execute(
        "INSERT INTO supporting_revision SELECT ?,person,revision,?,entered_at,json_set(snapshot,'\$.snapshot.id.id',?,'\$.operationId',?,'\$.snapshot.results[0].id',?,'\$.snapshot.results[0].unit','mmol/L'),json_set(header,'\$.snapshot.id.id',?,'\$.operationId',?) FROM supporting_revision WHERE record='current'",
        [id, 'op-$id', id, 'op-$id', 'other-$record-0', id, 'op-$id'],
      );
      for (var i = 0; i < 1000; i++) {
        final resultId = 'other-$record-$i';
        db.execute(
          "INSERT INTO supporting_result SELECT ?,person,revision,?,?,metric,'mmol/L',value_kind,numerator,denominator,json_set(snapshot,'\$.id',?,'\$.unit','mmol/L') FROM supporting_result WHERE record='current' AND position=0",
          [id, resultId, i, resultId],
        );
      }
    }
    db.execute('COMMIT');
    db.close();
    final current = (await store.supportingRecord(meId, 'current'))!;
    final other = (await store.supportingRecord(meId, 'aa-other-0'))!;
    expect(current.snapshot.results.first.unit, 'mg/L');
    expect(other.snapshot.results.first.unit, 'mmol/L');
    final chosen = SupportingComparisonKey.forResult(
      current,
      current.snapshot.results.first,
    ).identity;
    final unrelated = SupportingComparisonKey.forResult(
      other,
      other.snapshot.results.first,
    ).identity;
    expect(chosen, isNot(unrelated));
    final narrow = await store.supportingTrend(
      SupportingTrendQuery(
        personId: meId,
        metricId: 'metric',
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 2),
        comparisonGroup: chosen,
      ),
    );
    expect(narrow.sourceCount, 100);
    expect(narrow.groups.single.key.identity, chosen);
    await expectLater(
      store.supportingTrend(
        SupportingTrendQuery(
          personId: meId,
          metricId: 'metric',
          fromDate: CivilDate(2026, 10, 1),
          beforeDate: CivilDate(2026, 10, 2),
        ),
      ),
      throwsA(isA<SupportingLimitException>()),
    );
    await expectLater(
      store.supportingTrend(
        SupportingTrendQuery(
          personId: meId,
          metricId: 'metric',
          fromDate: CivilDate(2026, 10, 1),
          beforeDate: CivilDate(2026, 10, 2),
          comparisonGroup: unrelated,
        ),
      ),
      throwsA(isA<SupportingLimitException>()),
    );
  });

  test('first and cursor pages use date-bounded indexes', () async {
    await save(panel('exact', date: exact(DateTime.utc(2026, 10, 1, 12))));
    await save(
      panel('civil', date: SupportingDate.day(CivilDate(2026, 10, 1))),
    );
    await save(panel('unknown', date: SupportingDate.unknown()));
    final db = raw();
    final collectionExact = plan(
      db,
      '''
      SELECT s.id,s.collection_at AS ordering_day,s.collection_at AS ordering_at
      FROM supporting_record s
      WHERE s.person=? AND s.voided=0 AND s.collection_at IS NOT NULL
        AND s.collection_at>=? AND s.collection_at<?
      ORDER BY s.collection_at DESC,s.id LIMIT ?''',
      [
        meId,
        DateTime.utc(2026, 10, 1).microsecondsSinceEpoch,
        DateTime.utc(2026, 10, 2).microsecondsSinceEpoch,
        3,
      ],
    );
    final collectionExactSql = collectionExact.join(' ');
    expect(
      collectionExactSql,
      allOf(
        contains('supporting_collection_instant'),
        contains('collection_at>?'),
        contains('collection_at<?'),
        isNot(contains('SCAN s')),
      ),
    );
    final collectionCursor = plan(
      db,
      '''
      SELECT s.id,s.collection_at AS ordering_day,s.collection_at AS ordering_at
      FROM supporting_record s
      WHERE s.person=? AND s.voided=0 AND s.collection_at IS NOT NULL
        AND s.collection_at>=? AND s.collection_at<?
        AND (s.collection_at<? OR (s.collection_at=? AND s.id>?))
      ORDER BY s.collection_at DESC,s.id LIMIT ?''',
      [
        meId,
        DateTime.utc(2026, 10, 1).microsecondsSinceEpoch,
        DateTime.utc(2026, 10, 2).microsecondsSinceEpoch,
        DateTime.utc(2026, 10, 1, 12).microsecondsSinceEpoch,
        DateTime.utc(2026, 10, 1, 12).microsecondsSinceEpoch,
        'exact',
        3,
      ],
    );
    expect(
      collectionCursor.join(' '),
      contains('supporting_collection_instant'),
    );
    final civil = plan(
      db,
      '''
      SELECT s.id,s.collection_day AS ordering_day,NULL AS ordering_at
      FROM supporting_record s
      WHERE s.person=? AND s.voided=0 AND s.collection_at IS NULL
        AND s.collection_day IS NOT NULL AND s.collection_day>=? AND s.collection_day<?
      ORDER BY s.collection_day DESC,s.id LIMIT ?''',
      [meId, '2026-10-01', '2026-10-02', 3],
    );
    expect(civil.join(' '), contains('supporting_collection_civil'));
    final unpositioned = plan(
      db,
      '''
      SELECT s.id,NULL AS ordering_day,NULL AS ordering_at
      FROM supporting_record s
      WHERE s.person=? AND s.voided=0
        AND s.collection_at IS NULL AND s.collection_day IS NULL
      ORDER BY s.id LIMIT ?''',
      [meId, 3],
    );
    final unpositionedSql = unpositioned.join(' ');
    expect(
      unpositionedSql,
      anyOf(
        contains('supporting_collection_unpositioned'),
        contains('supporting_collection_feed'),
      ),
    );
    expect(unpositionedSql, isNot(contains('SCAN s')));
    expect(unpositionedSql, isNot(contains('TEMP B-TREE')));
    final reportExact = plan(
      db,
      '''
      SELECT s.id,s.report_at AS ordering_day,s.report_at AS ordering_at
      FROM supporting_record s
      WHERE s.person=? AND s.voided=0 AND s.report_at IS NOT NULL
        AND s.report_at>=? AND s.report_at<?
      ORDER BY s.report_at DESC,s.id LIMIT ?''',
      [
        meId,
        DateTime.utc(2026, 10, 1).microsecondsSinceEpoch,
        DateTime.utc(2026, 10, 2).microsecondsSinceEpoch,
        3,
      ],
    );
    expect(reportExact.join(' '), contains('supporting_report_instant'));
    final entry = plan(
      db,
      '''
      SELECT s.id,s.entered_at AS ordering_at
      FROM supporting_record s
      WHERE s.person=? AND s.voided=0 AND s.entered_at>=? AND s.entered_at<?
      ORDER BY s.entered_at DESC,s.id LIMIT ?''',
      [
        meId,
        DateTime.utc(2026, 10, 1).microsecondsSinceEpoch,
        DateTime.utc(2026, 10, 2).microsecondsSinceEpoch,
        3,
      ],
    );
    final entryPlan = entry.join(' ');
    expect(entryPlan, contains('supporting_entry_feed'));
    expect(entryPlan, isNot(contains('TEMP B-TREE')));
    db.close();
  });

  test(
    'a sparse one-day feed succeeds over a large skewed lifetime history',
    () async {
      await save(panel('inside', date: exact(DateTime.utc(2026, 10, 1, 12))));
      await save(
        panel('base-day', date: SupportingDate.day(CivilDate(2024, 1, 1))),
      );
      await save(
        panel('base-exact', date: exact(DateTime.utc(2024, 1, 1, 12))),
      );
      await save(panel('base-unknown', date: SupportingDate.unknown()));
      final db = raw();
      db.execute('BEGIN');
      void copy(String source, String id) {
        db.execute(
          "INSERT INTO supporting_record SELECT ?,person,kind,revision,entered_at,entry_day,voided,collection_day,collection_at,report_day,report_at FROM supporting_record WHERE id=?",
          [id, source],
        );
        db.execute(
          "INSERT INTO supporting_revision SELECT ?,person,revision,?,entered_at,json_set(snapshot,'\$.snapshot.id.id',?,'\$.operationId',?),json_set(header,'\$.snapshot.id.id',?,'\$.operationId',?) FROM supporting_revision WHERE record=?",
          [id, 'op-$id', id, 'op-$id', id, 'op-$id', source],
        );
        db.execute(
          "INSERT INTO supporting_result SELECT ?,person,revision,?||'-'||id,position,metric,unit,value_kind,numerator,denominator,json_set(snapshot,'\$.id',?||'-'||id) FROM supporting_result WHERE record=?",
          [id, id, id, source],
        );
      }

      for (var i = 0; i < 3000; i++) {
        copy('base-day', 'day-$i');
      }
      for (var i = 0; i < 3000; i++) {
        copy('base-exact', 'exact-$i');
      }
      for (var i = 0; i < 500; i++) {
        copy('base-unknown', 'unknown-$i');
      }
      db.execute('COMMIT');
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      db.close();
      final query = SupportingQuery(
        personId: meId,
        fromDate: CivilDate(2026, 10, 1),
        beforeDate: CivilDate(2026, 10, 2),
        includeUnknownDates: false,
        displayZone: 'UTC',
        limit: 1,
      );
      final first = await store.supportingRecords(query);
      expect(first.entries.single.id.id, 'inside');
      expect(first.hasMore, isFalse);
      final withUnknown = await pageIds(
        SupportingQuery(
          personId: meId,
          fromDate: CivilDate(2026, 10, 1),
          beforeDate: CivilDate(2026, 10, 2),
          includeUnknownDates: true,
          displayZone: 'UTC',
          limit: 50,
        ),
      );
      expect(withUnknown, hasLength(502));
      expect(withUnknown.toSet(), hasLength(502));
      final rawDb = raw();
      final exactPlan = plan(
        rawDb,
        '''
        SELECT s.id FROM supporting_record s
        WHERE s.person=? AND s.voided=0 AND s.collection_at IS NOT NULL
          AND s.collection_at>=? AND s.collection_at<?
        ORDER BY s.collection_at DESC,s.id LIMIT ?''',
        [
          meId,
          DateTime.utc(2026, 10, 1).microsecondsSinceEpoch,
          DateTime.utc(2026, 10, 2).microsecondsSinceEpoch,
          2,
        ],
      ).join(' ');
      expect(exactPlan, contains('supporting_collection_instant'));
      expect(exactPlan, contains('collection_at>?'));
      expect(exactPlan, contains('collection_at<?'));
      expect(exactPlan, isNot(contains('SCAN s')));
      final cursorPlan = plan(
        rawDb,
        '''
        SELECT s.id FROM supporting_record s
        WHERE s.person=? AND s.voided=0 AND s.collection_at IS NOT NULL
          AND s.collection_at>=? AND s.collection_at<?
          AND (s.collection_at<? OR (s.collection_at=? AND s.id>?))
        ORDER BY s.collection_at DESC,s.id LIMIT ?''',
        [
          meId,
          DateTime.utc(2026, 10, 1).microsecondsSinceEpoch,
          DateTime.utc(2026, 10, 2).microsecondsSinceEpoch,
          DateTime.utc(2026, 10, 1, 12).microsecondsSinceEpoch,
          DateTime.utc(2026, 10, 1, 12).microsecondsSinceEpoch,
          'inside',
          2,
        ],
      ).join(' ');
      expect(cursorPlan, contains('supporting_collection_instant'));
      expect(cursorPlan, isNot(contains('SCAN s')));
      rawDb.close();
    },
  );

  test('trend plan bounds the head window before result lookup', () async {
    await save(panel('current', date: exact(DateTime.utc(2026, 10, 1, 12))));
    final db = raw();
    final trend = plan(
      db,
      '''
      WITH matched AS MATERIALIZED (
        SELECT s.id,s.person,s.revision FROM supporting_record s
          INDEXED BY supporting_collection_instant
          WHERE s.person=? AND s.voided=0 AND
            (s.collection_at IS NOT NULL AND s.collection_at>=? AND s.collection_at<?)
        UNION ALL
        SELECT s.id,s.person,s.revision FROM supporting_record s
          INDEXED BY supporting_collection_civil
          WHERE s.person=? AND s.voided=0 AND
            (s.collection_at IS NULL AND s.collection_day IS NOT NULL
             AND s.collection_day>=? AND s.collection_day<?)
        UNION ALL
        SELECT s.id,s.person,s.revision FROM supporting_record s
          INDEXED BY supporting_collection_unpositioned
          WHERE s.person=? AND s.voided=0 AND
            (s.collection_at IS NULL AND s.collection_day IS NULL))
      SELECT r.record AS id,r.position,v.header,r.snapshot
      FROM supporting_result r INDEXED BY supporting_result_metric
      JOIN matched m ON m.id=r.record AND m.person=r.person AND m.revision=r.revision
      JOIN supporting_revision v ON v.record=m.id AND v.person=m.person AND v.revision=m.revision
      WHERE r.person=? AND r.metric=? LIMIT ?''',
      [
        meId,
        DateTime.utc(2026, 10, 1).microsecondsSinceEpoch,
        DateTime.utc(2026, 10, 2).microsecondsSinceEpoch,
        meId,
        '2026-10-01',
        '2026-10-02',
        meId,
        meId,
        'metric',
        10001,
      ],
    );
    final joined = trend.join(' ');
    expect(joined, contains('MATERIALIZE matched'));
    expect(joined, contains('supporting_result_metric'));
    expect(joined, contains('supporting_collection_instant'));
    expect(joined, contains('supporting_collection_civil'));
    expect(joined, contains('supporting_collection_unpositioned'));
    expect(joined, isNot(contains('SCAN r')));
    // The result lookup is driven by the bounded head window, not by a scan of
    // the metric's lifetime rows.
    expect(
      joined,
      contains(
        'SEARCH r USING INDEX supporting_result_metric (person=? AND metric=? AND record=? AND revision=?)',
      ),
    );
    final reportTrend = plan(
      db,
      '''
      WITH matched AS MATERIALIZED (
        SELECT s.id,s.person,s.revision FROM supporting_record s
          INDEXED BY supporting_report_instant
          WHERE s.person=? AND s.voided=0 AND
            (s.report_at IS NOT NULL AND s.report_at>=? AND s.report_at<?)
        UNION ALL
        SELECT s.id,s.person,s.revision FROM supporting_record s
          INDEXED BY supporting_report_civil
          WHERE s.person=? AND s.voided=0 AND
            (s.report_at IS NULL AND s.report_day IS NOT NULL
             AND s.report_day>=? AND s.report_day<?)
        UNION ALL
        SELECT s.id,s.person,s.revision FROM supporting_record s
          INDEXED BY supporting_report_unpositioned
          WHERE s.person=? AND s.voided=0 AND
            (s.report_at IS NULL AND s.report_day IS NULL))
      SELECT r.record AS id,r.position,v.header,r.snapshot
      FROM supporting_result r INDEXED BY supporting_result_metric
      JOIN matched m ON m.id=r.record AND m.person=r.person AND m.revision=r.revision
      JOIN supporting_revision v ON v.record=m.id AND v.person=m.person AND v.revision=m.revision
      WHERE r.person=? AND r.metric=? LIMIT ?''',
      [
        meId,
        DateTime.utc(2026, 10, 1).microsecondsSinceEpoch,
        DateTime.utc(2026, 10, 2).microsecondsSinceEpoch,
        meId,
        '2026-10-01',
        '2026-10-02',
        meId,
        meId,
        'metric',
        10001,
      ],
    );
    final reportJoined = reportTrend.join(' ');
    expect(reportJoined, contains('supporting_report_instant'));
    expect(reportJoined, contains('supporting_report_civil'));
    expect(reportJoined, contains('supporting_report_unpositioned'));
    expect(reportJoined, contains('MATERIALIZE matched'));
    expect(
      reportJoined,
      contains(
        'SEARCH r USING INDEX supporting_result_metric (person=? AND metric=? AND record=? AND revision=?)',
      ),
    );
    db.close();
  });

  test('explicit unknown dates are never given an invented instant', () async {
    await save(
      panel(
        'unknown',
        date: SupportingDate.unknown(originalText: 'Source did not say'),
      ),
    );
    await save(
      panel(
        'partial',
        date: SupportingDate.partial(year: 2026, originalText: '2026'),
      ),
    );
    final db = raw();
    final rows = db
        .select(
          'SELECT id,collection_at,collection_day,report_at,report_day FROM supporting_record ORDER BY id',
        )
        .map((r) => r.values.toList())
        .toList();
    expect(rows, [
      ['partial', null, null, null, null],
      ['unknown', null, null, null, null],
    ]);
    db.close();
    final snapshot = (await store.supportingRecord(meId, 'unknown'))!;
    expect(snapshot.snapshot.collectionDate.instant, isNull);
    expect(snapshot.snapshot.collectionDate.originalText, 'Source did not say');
  });

  test(
    'exact instants keep source zone facts while ordering by display day',
    () async {
      await save(
        panel(
          'saved',
          date: exact(
            DateTime.utc(2026, 10, 1, 23),
            zone: 'America/Los_Angeles',
            offset: -7 * 60,
          ),
        ),
      );
      final saved = (await store.supportingRecord(meId, 'saved'))!;
      expect(saved.snapshot.collectionDate.zoneId, 'America/Los_Angeles');
      expect(saved.snapshot.collectionDate.utcOffsetMinutes, -7 * 60);
      expect(
        saved.snapshot.collectionDate.instant,
        DateTime.utc(2026, 10, 1, 23),
      );
      final db = raw();
      final row = db
          .select(
            "SELECT collection_day,collection_at FROM supporting_record WHERE id='saved'",
          )
          .single;
      // The projection stores the instant, not a saved-offset day.
      expect(row['collection_day'], isNull);
      expect(
        row['collection_at'],
        DateTime.utc(2026, 10, 1, 23).microsecondsSinceEpoch,
      );
      db.close();
    },
  );

  test(
    'json-shaped source snapshot survives a report display filter',
    () async {
      await save(
        panel(
          'report',
          date: SupportingDate.unknown(),
          report: exact(DateTime.utc(2026, 10, 4, 9), zone: 'UTC'),
        ),
      );
      final report = await pageIds(
        SupportingQuery(
          personId: meId,
          dateBasis: SupportingDateBasis.report,
          fromDate: CivilDate(2026, 10, 4),
          beforeDate: CivilDate(2026, 10, 5),
          includeUnknownDates: false,
          displayZone: 'UTC',
        ),
      );
      expect(report, ['report']);
      final decoded = jsonDecode(
        jsonEncode(
          (await store.supportingRecord(meId, 'report'))!.snapshot.toJson(),
        ),
      ) as Map<String, dynamic>;
      expect(
        (decoded['reportDate'] as Map<String, dynamic>)['instant'],
        DateTime.utc(2026, 10, 4, 9).microsecondsSinceEpoch,
      );
    },
  );
}
