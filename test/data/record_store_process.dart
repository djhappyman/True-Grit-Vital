// Standalone child-process fixture; synthetic key/data, never used by the app.
import 'dart:io';

import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final path = '${args[0]}/records.db';
  final mode = args[1];
  final store = await RecordStore.open(
    path: path,
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  if (mode == 'init') {
    await store.createItem(
      commandId: 'item',
      name: 'Synthetic process fixture',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
  } else if (mode == 'before' || mode == 'after') {
    await store.record(
      commandId: 'take',
      itemId: (await store.items()).single.id,
      amount: '0.125000',
      actualAt: DateTime.utc(2026, 10, 19),
      beforeCommit: mode == 'before'
          ? () async {
              exit(71);
            }
          : null,
    );
    exit(72); // Commit succeeded but no caller received a result.
  } else if (mode == 'verify-empty') {
    if ((await store.records()).isNotEmpty) {
      throw StateError('partial_commit');
    }
  } else if (mode == 'verify-retry') {
    final record = await store.record(
      commandId: 'take',
      itemId: (await store.items()).single.id,
      amount: '0.125000',
      actualAt: DateTime.utc(2026, 10, 19),
    );
    if (!record.alreadyCommitted ||
        (await store.records()).length != 1 ||
        (await store.history(record.id)).length != 1) {
      throw StateError('lost_response_duplicate');
    }
  } else {
    throw ArgumentError('mode');
  }
  await store.close();
  stdout.writeln('PASS $mode');
}
