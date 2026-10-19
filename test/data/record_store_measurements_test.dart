import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  test('measure synthetic normal and skewed encrypted host fixtures', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vital-measurements-',
    );
    final path = '${directory.path}/records.db';
    final key = List.generate(32, (i) => i + 1);
    final samples = <String, Object?>{
      'platform': Platform.operatingSystem,
      'runtime': Platform.version,
      'scope': 'host test, not Android budgets',
    };
    final timer = Stopwatch()..start();
    var store = await RecordStore.open(path: path, key: key, isNew: true);
    samples['fresh_open_us'] = timer.elapsedMicroseconds;
    try {
      final item = await store.createItem(
        commandId: 'item',
        name: 'Synthetic workload',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      for (final (label, count) in [('normal', 100), ('skewed', 1100)]) {
        for (var i = 0; i < count; i++) {
          await store.record(
            commandId: '$label-$i',
            itemId: item.id,
            amount: label == 'normal' ? '0.125000' : '9000000000',
            actualAt: label == 'normal'
                ? DateTime.utc(2026, 1, 1).add(Duration(days: i))
                : DateTime.utc(2026, 10, 19),
          );
        }
        timer.reset();
        final rows = await store.records();
        samples['${label}_query_us'] = timer.elapsedMicroseconds;
        samples['${label}_first_page_records'] = rows.length;
        samples['${label}_total_records'] = await store.recordCount();
        timer.reset();
        await store.record(
          commandId: '$label-measured',
          itemId: item.id,
          amount: '0.000001',
          actualAt: DateTime.utc(2026, 10, 19),
        );
        samples['${label}_save_us'] = timer.elapsedMicroseconds;
      }
      await store.close();
      timer.reset();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      samples['populated_reopen_us'] = timer.elapsedMicroseconds;
      expect(await store.recordCount(), 1202);
      // This exact aggregate cannot fit SQLite's signed 64-bit SUM envelope.
      var sum = BigInt.zero;
      for (var offset = 0; offset < 1202; offset += 500) {
        for (final r in await store.records(limit: 500, offset: offset)) {
          sum += BigInt.from(r.amount.scaled);
        }
      }
      expect(
        sum,
        BigInt.from(1100) * BigInt.from(ExactQuantity.maxScaled) +
            BigInt.from(100 * 125000 + 2),
      );
      samples['database_bytes'] = await File(path).length();
      stdout.writeln('RECORD_STORE_MEASUREMENTS ${jsonEncode(samples)}');
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  });
}
