import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  final me = meId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-chart-phase-end-');
    path = '${directory.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Database rawDatabase() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  /// Writes saved end metadata for chart context. The optional instant also
  /// exercises the current writer's combined date and exact-boundary shape.
  Future<void> insertPhaseEnds({
    int distantEnds = 0,
    DateTime? savedDateOnlyInstant,
    List<({String id, String zone, String lastDate})> dateOnlyEnds = const [],
    List<({String id, DateTime instant})> exactEnds = const [],
  }) async {
    await store.close();
    final db = rawDatabase();
    final insertItem = db.prepare(
      'INSERT INTO item(id,person,name,form,unit,type) VALUES (?,?,?,?,?,?)',
    );
    final insertPlan = db.prepare(
      'INSERT INTO daily_plan(id,person,item,revision) VALUES (?,?,?,?)',
    );
    final insertEnd = db.prepare(
      'INSERT INTO phase_plan(plan,person,snapshot) VALUES (?,?,?)',
    );
    void add(String planId, String zone, {String? lastDate, int? instant}) {
      final itemId = '$planId-item';
      insertItem.execute([
        itemId,
        me,
        'Saved item $planId',
        'tablet',
        'mg',
        'Medicine',
      ]);
      insertPlan.execute([planId, me, itemId, 1]);
      insertEnd.execute([
        planId,
        me,
        jsonEncode({
          'end': {'zone': zone, 'instant': ?instant, 'lastDate': lastDate},
        }),
      ]);
    }

    try {
      db.execute('BEGIN');
      for (var index = 0; index < distantEnds; index++) {
        add('distant-plan-$index', 'UTC', lastDate: '1900-01-01');
      }
      for (final end in dateOnlyEnds) {
        add(
          end.id,
          end.zone,
          lastDate: end.lastDate,
          instant: savedDateOnlyInstant?.microsecondsSinceEpoch,
        );
      }
      for (final end in exactEnds) {
        add(end.id, 'UTC', instant: end.instant.microsecondsSinceEpoch);
      }
      db.execute('COMMIT');
    } finally {
      insertItem.close();
      insertPlan.close();
      insertEnd.close();
      db.close();
    }
    store = await RecordStore.open(path: path, key: key, isNew: false);
  }

  Future<ChartContextBatch> contextFor({
    required DateTime from,
    required DateTime before,
    required String displayZone,
  }) => store.chartContext(
    ChartQuery(
      personId: me,
      viewport: ChartViewport(
        fromInstant: from,
        beforeInstant: before,
        displayZone: displayZone,
        bucketSize: ChartBucketSize.day,
      ),
    ),
  );

  test(
    'a saved last day remains visible before its exact end boundary',
    () async {
      await insertPhaseEnds(
        savedDateOnlyInstant: DateTime.utc(2026, 10, 25),
        dateOnlyEnds: [
          (id: 'current-writer-end', zone: 'UTC', lastDate: '2026-10-24'),
        ],
      );
      final context = await contextFor(
        from: DateTime.utc(2026, 10, 24, 12),
        before: DateTime.utc(2026, 10, 24, 13),
        displayZone: 'UTC',
      );
      expect(context.complete, isTrue);
      final end = context.annotations.singleWhere(
        (annotation) => annotation.kind == ChartAnnotationKind.planEnd,
      );
      expect(end.sourceId, 'current-writer-end');
      expect(end.at.civilDate, CivilDate(2026, 10, 24));
      expect(end.at.zoneId, 'UTC');
      expect(end.at.instant, isNull);
    },
  );

  test(
    'distant date-only phase ends cannot consume the context candidate cap',
    () async {
      await insertPhaseEnds(
        distantEnds: 1001,
        dateOnlyEnds: [
          (
            id: 'z-relevant-plan',
            zone: 'Pacific/Auckland',
            lastDate: '2026-10-24',
          ),
        ],
      );
      final from = DateTime.utc(2026, 10, 23, 9);
      final before = DateTime.utc(2026, 10, 23, 12);
      final context = await contextFor(
        from: from,
        before: before,
        displayZone: 'Pacific/Pago_Pago',
      );
      expect(context.complete, isTrue);
      final ends = context.annotations
          .where((a) => a.kind == ChartAnnotationKind.planEnd)
          .toList();
      expect(ends, hasLength(1));
      final end = ends.single;
      expect(end.sourceId, 'z-relevant-plan');
      expect(end.at.isDateOnly, isTrue);
      expect(end.at.civilDate, CivilDate(2026, 10, 24));
      expect(end.at.zoneId, 'Pacific/Auckland');
      expect(end.at.instant, isNull);
      expect(
        ChartAnnotationSet.bounded(
          viewport: ChartViewport(
            fromInstant: from,
            beforeInstant: before,
            displayZone: 'Pacific/Pago_Pago',
            bucketSize: ChartBucketSize.day,
          ),
          personId: me,
          annotations: context.annotations,
        ).visible,
        hasLength(1),
      );

      // The same bounded query still declares incompleteness when genuinely
      // dense in-range boundaries exceed the candidate cap.
      await store.close();
      final db = rawDatabase();
      db.execute(
        "UPDATE phase_plan SET snapshot=json_set(snapshot,'\$.end.lastDate','2026-10-23','\$.end.zone','UTC') WHERE plan LIKE 'distant-plan-%'",
      );
      db.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final dense = await contextFor(
        from: from,
        before: before,
        displayZone: 'Pacific/Pago_Pago',
      );
      expect(dense.complete, isFalse);
      expect(
        dense.annotations.where((a) => a.kind == ChartAnnotationKind.planEnd),
        hasLength(1000),
      );
      final bounded = ChartAnnotationSet.bounded(
        viewport: ChartViewport(
          fromInstant: from,
          beforeInstant: before,
          displayZone: 'Pacific/Pago_Pago',
          bucketSize: ChartBucketSize.day,
        ),
        personId: me,
        annotations: dense.annotations,
      );
      expect(bounded.visible, hasLength(200));
      expect(bounded.hiddenCount, 800);
    },
  );

  test('date-only end keeps its saved civil day across a source DST fold while exact ends stay half-open', () async {
    final foldEnd = DateTime.utc(2026, 4, 5, 12);
    await insertPhaseEnds(
      dateOnlyEnds: [
        (
          id: 'auckland-date-only',
          zone: 'Pacific/Auckland',
          lastDate: '2026-04-05',
        ),
      ],
      exactEnds: [(id: 'exact-end', instant: foldEnd)],
    );
    final viewport = ChartViewport(
      fromInstant: DateTime.utc(2026, 4, 4, 10),
      beforeInstant: DateTime.utc(2026, 4, 5, 13),
      displayZone: 'Pacific/Kiritimati',
      bucketSize: ChartBucketSize.day,
    );
    final context = await store.chartContext(
      ChartQuery(personId: me, viewport: viewport),
    );
    expect(context.complete, isTrue);
    final dateOnly = context.annotations.singleWhere(
      (a) => a.sourceId == 'auckland-date-only',
    );
    expect(dateOnly.at.isDateOnly, isTrue);
    expect(dateOnly.at.civilDate, CivilDate(2026, 4, 5));
    expect(dateOnly.at.zoneId, 'Pacific/Auckland');
    expect(dateOnly.at.instant, isNull);
    expect(
      context.annotations
          .singleWhere((a) => a.sourceId == 'exact-end')
          .at
          .instant,
      foldEnd,
    );
    expect(
      ChartAnnotationSet.bounded(
        viewport: viewport,
        personId: me,
        annotations: context.annotations,
      ).visible.map((a) => a.sourceId).toSet(),
      {'auckland-date-only', 'exact-end'},
    );

    // Starting exactly at the saved exclusive instant includes the exact end
    // and excludes the date-only end whose civil day ends at that instant.
    final atStart = ChartViewport(
      fromInstant: foldEnd,
      beforeInstant: foldEnd.add(const Duration(hours: 1)),
      displayZone: 'Pacific/Kiritimati',
      bucketSize: ChartBucketSize.day,
    );
    expect(
      ChartAnnotationSet.bounded(
        viewport: atStart,
        personId: me,
        annotations: context.annotations,
      ).visible.map((a) => a.sourceId),
      ['exact-end'],
    );

    // Ending exactly at that instant excludes the exact end and keeps the
    // date-only civil day, whose range still overlaps the viewport.
    final atEnd = ChartViewport(
      fromInstant: foldEnd.subtract(const Duration(hours: 1)),
      beforeInstant: foldEnd,
      displayZone: 'Pacific/Kiritimati',
      bucketSize: ChartBucketSize.day,
    );
    expect(
      ChartAnnotationSet.bounded(
        viewport: atEnd,
        personId: me,
        annotations: context.annotations,
      ).visible.map((a) => a.sourceId),
      ['auckland-date-only'],
    );
  });

  test('unreadable phase end still declares incomplete context', () async {
    await store.close();
    final db = rawDatabase();
    try {
      db.execute('BEGIN');
      db.execute(
        'INSERT INTO item(id,person,name,form,unit,type) VALUES (?,?,?,?,?,?)',
        ['unreadable-item', me, 'Unreadable', 'tablet', 'mg', 'Medicine'],
      );
      db.execute(
        'INSERT INTO daily_plan(id,person,item,revision) VALUES (?,?,?,?)',
        ['unreadable-plan', me, 'unreadable-item', 1],
      );
      db.execute(
        'INSERT INTO phase_plan(plan,person,snapshot) VALUES (?,?,?)',
        [
          'unreadable-plan',
          me,
          jsonEncode({
            'end': {
              'zone': 'UTC',
              'instant': '2026-04-05T12:00:00.000Z',
              'lastDate': null,
            },
          }),
        ],
      );
      db.execute('COMMIT');
    } finally {
      db.close();
    }
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final context = await contextFor(
      from: DateTime.utc(2026, 4, 4, 10),
      before: DateTime.utc(2026, 4, 5, 13),
      displayZone: 'Pacific/Kiritimati',
    );
    expect(context.complete, isFalse);
    expect(context.annotations, isEmpty);
  });
}
