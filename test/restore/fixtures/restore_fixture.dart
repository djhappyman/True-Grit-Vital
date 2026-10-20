import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

const restoreTestKey = <int>[
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  31,
  32,
];

String hexKey(List<int> key) =>
    key.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

/// Writes the frozen synthetic schema19 fixture into an encrypted file, then
/// the real store open path performs the schema20/21 migrations.
void writeFixtureDatabase(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute("PRAGMA cipher='chacha20'");
    db.execute('PRAGMA key="x\'${hexKey(restoreTestKey)}\'"');
    db.execute(
      File('test/data/fixtures/record_store_v19.sql').readAsStringSync(),
    );
  } finally {
    db.close();
  }
}

Future<RecordStore> openFixtureStore(String path) =>
    RecordStore.open(path: path, key: restoreTestKey, isNew: false);

Future<Directory> createRestoreDataDirectory() async {
  final directory = await Directory.systemTemp.createTemp('vital-restore-');
  await Directory('${directory.path}/data').create();
  return directory;
}

/// A byte-for-byte archive source copy made after the live store closed
/// cleanly. It shares the installation key; tests that exercise re-keying pass
/// a real rekey callback.
Future<String> copyClosedDatabase(String source, String target) async {
  await File(source).copy(target);
  return target;
}
