import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

// Synthetic fixture credential only. Production must supply a fresh random key.
const fixtureKey = 'g02-synthetic-only-not-a-production-key';
const marker = 'G02_SYNTHETIC_PERSON_AND_PRODUCT_SNAPSHOT';
const maxScaled = 9000000000000000;

void configure(Database db, String? key) {
  if (key == null || key.isEmpty) throw StateError('Missing key');
  if (db.select('PRAGMA cipher').isEmpty) {
    throw StateError('Encryption backend missing');
  }
  db.execute("PRAGMA cipher = 'chacha20'");
  db.execute("PRAGMA key = '${key.replaceAll("'", "''")}'");
  // Force decoding now, before allowing any create/migration/recovery work.
  db.select('SELECT count(*) FROM sqlite_master');
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('PRAGMA busy_timeout = 5000');
  db.execute('PRAGMA synchronous = FULL');
  db.execute('PRAGMA temp_store = MEMORY');
  if (db.select('PRAGMA foreign_keys').single.values.single != 1) {
    throw StateError('Foreign keys unavailable');
  }
}

Database openProtected(String path, {String? key = fixtureKey}) {
  // Check key BEFORE open(), which otherwise creates an empty file.
  if (key == null || key.isEmpty) throw StateError('Missing key');
  checkedFile(File(path));
  final db = sqlite3.open(path);
  try {
    configure(db, key);
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

File checkedFile(File file) {
  if (file.existsSync()) {
    if (file.lengthSync() < 16) throw StateError('Truncated dataset refused');
    final input = file.openSync();
    final header = input.readSync(16);
    input.closeSync();
    if (utf8
        .decode(header, allowMalformed: true)
        .startsWith('SQLite format 3')) {
      throw StateError('Plaintext dataset refused');
    }
  }
  return file;
}

void createV1(Database db) {
  db.execute('''
CREATE TABLE dataset(generation TEXT PRIMARY KEY) STRICT;
INSERT INTO dataset VALUES ('generation-1');
CREATE TABLE person(id TEXT PRIMARY KEY, name TEXT NOT NULL) STRICT;
INSERT INTO person VALUES ('me', '$marker'), ('other', 'Synthetic other');
CREATE TABLE administration(
 id TEXT PRIMARY KEY, person TEXT NOT NULL REFERENCES person(id),
 slot TEXT UNIQUE, revision INTEGER NOT NULL,
 amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= $maxScaled),
 entered TEXT NOT NULL, unit TEXT NOT NULL CHECK(unit IN ('mg', 'ml', 'count')),
 snapshot TEXT NOT NULL, UNIQUE(id, person)) STRICT;
CREATE TABLE operation(id TEXT PRIMARY KEY, payload TEXT NOT NULL, result TEXT NOT NULL) STRICT;
CREATE TABLE revision(record TEXT NOT NULL, person TEXT NOT NULL, revision INTEGER NOT NULL,
 amount INTEGER NOT NULL, entered TEXT NOT NULL, snapshot TEXT NOT NULL,
 PRIMARY KEY(record, revision), FOREIGN KEY(record, person) REFERENCES administration(id, person)) STRICT;
CREATE TABLE movement(operation TEXT PRIMARY KEY REFERENCES operation(id), record TEXT NOT NULL,
 person TEXT NOT NULL, delta INTEGER NOT NULL,
 FOREIGN KEY(record, person) REFERENCES administration(id, person)) STRICT;
CREATE TABLE outbox(operation TEXT PRIMARY KEY REFERENCES operation(id), intent TEXT NOT NULL) STRICT;
PRAGMA user_version = 1;
''');
}

void migrateV2(Database db, {bool fail = false}) {
  db.execute('BEGIN IMMEDIATE');
  try {
    db.execute(
      "ALTER TABLE administration ADD COLUMN provenance TEXT NOT NULL DEFAULT 'reported'",
    );
    if (fail) throw StateError('Injected migration interruption');
    db.execute('PRAGMA user_version = 2');
    if (db.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw StateError('Broken ownership');
    }
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

int parseScaled(String input) {
  // Locale parsing belongs before this canonical storage boundary.
  if (!RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(input)) {
    throw FormatException('Canonical decimal required');
  }
  final p = input.split('.');
  final value =
      BigInt.parse(p[0]) * BigInt.from(1000000) +
      BigInt.parse(p.length == 1 ? '0' : p[1].padRight(6, '0'));
  if (value <= BigInt.zero || value > BigInt.from(maxScaled)) {
    throw RangeError('Outside storage range');
  }
  return value.toInt();
}

/// Minimal probe command; not the proposed complete application schema.
String command(
  Database db, {
  required String operation,
  required String record,
  required String person,
  required int expectedRevision,
  required String entered,
  String? slot,
  String generation = 'generation-1',
  bool failBeforeCommit = false,
  bool abruptBeforeCommit = false,
}) {
  final amount = parseScaled(entered);
  final payload = jsonEncode([
    generation,
    record,
    person,
    expectedRevision,
    entered,
    slot,
  ]);
  db.execute('BEGIN IMMEDIATE');
  try {
    if (db.select('SELECT generation FROM dataset').single.values.single !=
        generation) {
      throw StateError('Stale generation');
    }
    final prior = db.select(
      'SELECT payload, result FROM operation WHERE id = ?',
      [operation],
    );
    if (prior.isNotEmpty) {
      if (prior.single['payload'] != payload) {
        throw StateError('Operation conflict');
      }
      db.execute('COMMIT');
      return 'already-committed:${prior.single['result']}';
    }
    final old = db.select('SELECT * FROM administration WHERE id = ?', [
      record,
    ]);
    int previous = 0;
    if (old.isEmpty) {
      if (expectedRevision != 0) throw StateError('Revision conflict');
      db.execute(
        'INSERT INTO administration(id, person, slot, revision, amount, entered, unit, snapshot) VALUES (?, ?, ?, 1, ?, ?, ?, ?)',
        [record, person, slot, amount, entered, 'mg', marker],
      );
    } else {
      final row = old.single;
      if (row['revision'] != expectedRevision || row['person'] != person) {
        throw StateError('Revision or ownership conflict');
      }
      previous = row['amount'] as int;
      db.execute(
        'UPDATE administration SET amount = ?, entered = ?, revision = revision + 1 WHERE id = ?',
        [amount, entered, record],
      );
    }
    final result = '$record:${expectedRevision + 1}';
    db.execute('INSERT INTO operation VALUES (?, ?, ?)', [
      operation,
      payload,
      result,
    ]);
    db.execute('INSERT INTO revision VALUES (?, ?, ?, ?, ?, ?)', [
      record,
      person,
      expectedRevision + 1,
      amount,
      entered,
      marker,
    ]);
    db.execute('INSERT INTO movement VALUES (?, ?, ?, ?)', [
      operation,
      record,
      person,
      previous - amount,
    ]);
    db.execute('INSERT INTO outbox VALUES (?, ?)', [
      operation,
      'reconcile:$record',
    ]);
    if (failBeforeCommit) throw StateError('Injected before commit');
    if (abruptBeforeCommit) exit(71);
    db.execute('COMMIT');
    return 'committed:$result';
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

BigInt exactTotal(Database db, String sql) => db
    .select(sql)
    .fold(
      BigInt.zero,
      (total, row) => total + BigInt.from(row.values.single as int),
    );

class DriftProbe extends drift.GeneratedDatabase {
  DriftProbe(File file)
    : super(
        NativeDatabase(
          checkedFile(file),
          setup: (db) => configure(db, fixtureKey),
        ),
      );
  @override
  int get schemaVersion => 1;
  @override
  Iterable<drift.TableInfo<drift.Table, Object?>> get allTables => const [];
  @override
  List<drift.DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  drift.MigrationStrategy get migration => drift.MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE roundtrip(value TEXT NOT NULL) STRICT',
      );
    },
  );
}

Future<String> competeOnIsolate(String path, String id) => Isolate.run(() {
  final connection = openProtected(path);
  try {
    return command(
      connection,
      operation: id,
      record: 'r1',
      person: 'me',
      expectedRevision: 1,
      entered: '0.2',
    );
  } on StateError {
    return 'conflict';
  } finally {
    connection.close();
  }
});

(BigInt, BigInt) convertExact(
  int scaled,
  int concentrationNumerator,
  int concentrationDenominator,
) {
  if (scaled <= 0 ||
      concentrationNumerator <= 0 ||
      concentrationDenominator <= 0) {
    throw RangeError('Positive known concentration required');
  }
  final numerator = BigInt.from(scaled) * BigInt.from(concentrationNumerator);
  final denominator =
      BigInt.from(1000000) * BigInt.from(concentrationDenominator);
  final gcd = numerator.gcd(denominator);
  return (numerator ~/ gcd, denominator ~/ gcd);
}
