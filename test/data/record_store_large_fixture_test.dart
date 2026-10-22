import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  test('100k encrypted fixture uses indexed bounded first pages', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vital-100k-fixture-',
    );
    final path = '${directory.path}/records.db';
    final key = List.generate(32, (i) => i + 1);
    var store = await RecordStore.open(path: path, key: key, isNew: true);
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic workload',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    final generation = store.generation;
    await store.close();
    final raw = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute("PRAGMA key=\"x'$hex'\"");
    raw.execute('PRAGMA foreign_keys=ON');
    final head = raw.prepare(
      'INSERT INTO administration VALUES (?, ?, ?, 1, ?)',
    );
    final revision = raw.prepare(
      'INSERT INTO revision(record,person,revision,name,form,unit,type,amount,entered,actual,entered_at,voided) VALUES (?,?,1,?,?,?,?,?,?,?,?,0)',
    );
    final operation = raw.prepare('INSERT INTO operation VALUES (?,?,?)');
    final day = DateTime.utc(2026, 10, 19);
    try {
      raw.execute('BEGIN');
      for (var i = 0; i < 100000; i++) {
        final id = 'fixture-${i.toString().padLeft(6, '0')}';
        final actual =
            (i < 95000 ? day : day.subtract(Duration(days: i - 94999)))
                .microsecondsSinceEpoch;
        head.execute([id, meId, item.id, actual]);
        revision.execute([
          id,
          meId,
          item.name,
          item.form,
          item.unit,
          item.type,
          125000,
          '0.125000',
          actual,
          actual + 10,
        ]);
        final result = {
          'id': id,
          'person': meId,
          'item': item.id,
          'revision': 1,
          'name': item.name,
          'form': item.form,
          'unit': item.unit,
          'type': item.type,
          'amount': 125000,
          'entered': '0.125000',
          'actual': actual,
          'entered_at': actual + 10,
          'voided': 0,
        };
        operation.execute([
          'fixture-operation-$i',
          jsonEncode([generation, 'record', meId, item.id, '0.125000', actual]),
          jsonEncode(result),
        ]);
      }
      raw.execute('COMMIT');
    } finally {
      head.close();
      revision.close();
      operation.close();
    }
    final plans = <String, List<String>>{};
    const projection =
        'SELECT a.id,a.item,r.* FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision';
    for (final (name, filter, args) in [
      ('feed', 'a.person=?', [meId]),
      (
        'day',
        'a.person=? AND a.actual>=? AND a.actual<?',
        [
          meId,
          day.microsecondsSinceEpoch,
          day.add(const Duration(days: 1)).microsecondsSinceEpoch,
        ],
      ),
      ('item', 'a.person=? AND a.item=?', [meId, item.id]),
    ]) {
      final plan = raw
          .select(
            'EXPLAIN QUERY PLAN $projection WHERE $filter ORDER BY a.actual DESC,a.id LIMIT 50',
            args,
          )
          .map((r) => r['detail'] as String)
          .toList();
      expect(
        plan.join(' '),
        contains(
          name == 'item' ? 'administration_item_feed' : 'administration_feed',
        ),
      );
      expect(plan.join(' '), isNot(contains('TEMP B-TREE')));
      plans[name] = plan;
    }
    raw.close();
    final timer = Stopwatch()..start();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final measurements = <String, Object?>{
      'platform': Platform.operatingSystem,
      'runtime': Platform.version,
      'scope': '100k synthetic single-person host fixture; no Android budgets',
      'records': 100000,
      'same_day_records': 95000,
      'open_us': timer.elapsedMicroseconds,
      'query_plans': plans,
    };
    try {
      for (final (name, load) in <(String, Future<List<UseRecord>> Function())>[
        ('first_page', () => store.records(limit: 50)),
        (
          'today_first_page',
          () => store.records(
            actualFrom: day,
            actualBefore: day.add(const Duration(days: 1)),
            limit: 50,
          ),
        ),
        ('item_first_page', () => store.records(itemId: item.id, limit: 50)),
      ]) {
        timer.reset();
        final rows = await load();
        measurements['${name}_us'] = timer.elapsedMicroseconds;
        expect(rows.length, 50);
      }
      expect((await store.records()).length, 100);
      final page1 = await store.records(limit: 50);
      final page2 = await store.records(limit: 50, offset: 50);
      expect(
        {...page1.map((r) => r.id), ...page2.map((r) => r.id)}.length,
        100,
      );
      expect((await store.recordById('fixture-099999'))?.id, 'fixture-099999');
      expect(await store.recordById('fixture-099999', personId: 'other'), null);
      timer.reset();
      final all = <UseRecord>[];
      for (var offset = 0; offset < 100000; offset += 500) {
        all.addAll(await store.records(limit: 500, offset: offset));
      }
      measurements['explicit_full_materialisation_us'] =
          timer.elapsedMicroseconds;
      expect(all.length, 100000);
      timer.reset();
      await store.record(
        commandId: 'measured-save',
        itemId: item.id,
        amount: '0.125000',
        actualAt: day,
      );
      measurements['save_us'] = timer.elapsedMicroseconds;
      measurements['file_bytes'] = await File(path).length();
      stdout.writeln('RECORD_STORE_100K ${jsonEncode(measurements)}');
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
