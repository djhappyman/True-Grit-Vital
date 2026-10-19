import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:vital_storage_gate_probe/probe.dart';

void main() {
  late Directory dir;
  late String path;
  late Database db;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vital-g02-');
    path = '${dir.path}/encrypted.db';
    db = openProtected(path);
    createV1(db);
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  String save({
    String op = 'op1',
    String record = 'r1',
    int revision = 0,
    String amount = '0.1',
    String person = 'me',
    String? slot,
    bool fail = false,
  }) => command(
    db,
    operation: op,
    record: record,
    person: person,
    expectedRevision: revision,
    entered: amount,
    slot: slot,
    failBeforeCommit: fail,
  );

  test(
    'native engine identity, encrypted database/WAL, and key fail closed',
    () {
      print(
        'sqlite=${db.select('SELECT sqlite_version()').single.values.single}; '
        'cipher=${db.select('PRAGMA cipher')}; '
        'mc=${db.select('SELECT sqlite3mc_version()')}',
      );
      db.execute('PRAGMA journal_mode = WAL');
      save();
      for (final file in dir.listSync().whereType<File>()) {
        final bytes = file.readAsBytesSync();
        final text = latin1.decode(bytes);
        expect(text.contains(marker), isFalse, reason: file.path);
        expect(text.startsWith('SQLite format 3'), isFalse, reason: file.path);
      }
      final before = File(path).readAsBytesSync();
      expect(() => openProtected(path, key: null), throwsStateError);
      expect(
        () => openProtected(path, key: 'wrong'),
        throwsA(isA<SqliteException>()),
      );
      expect(File(path).readAsBytesSync(), before);
      expect(
        () => openProtected('${dir.path}/missing.db', key: null),
        throwsStateError,
      );
      expect(File('${dir.path}/missing.db').existsSync(), isFalse);
      final plain = sqlite3.open(path);
      expect(
        () => plain.select('SELECT * FROM administration'),
        throwsA(isA<SqliteException>()),
      );
      plain.close();
    },
  );
  test('plaintext is rejected instead of converted, reset or accepted', () {
    final p = '${dir.path}/plaintext.db';
    final plain = sqlite3.open(p)..execute('CREATE TABLE secret(value TEXT)');
    plain.close();
    final bytes = File(p).readAsBytesSync();
    expect(() => openProtected(p), throwsStateError);
    expect(File(p).readAsBytesSync(), bytes);
  });
  test(
    'Drift NativeDatabase uses the actual encrypted backend and restarts',
    () async {
      final file = File('${dir.path}/drift.db');
      final drift = DriftProbe(file);
      await drift.customStatement('INSERT INTO roundtrip VALUES (?)', [marker]);
      await drift.close();
      expect(latin1.decode(file.readAsBytesSync()).contains(marker), isFalse);
      final reopened = DriftProbe(file);
      expect(
        (await reopened.customSelect('SELECT value FROM roundtrip').getSingle())
            .read<String>('value'),
        marker,
      );
      await reopened.close();
    },
  );
  test(
    'retry after restart returns one durable result, changed payload conflicts',
    () {
      expect(save(), 'committed:r1:1');
      db.close();
      db = openProtected(path);
      expect(save(), 'already-committed:r1:1');
      expect(() => save(amount: '0.2'), throwsStateError);
      for (final table in [
        'administration',
        'revision',
        'movement',
        'outbox',
        'operation',
      ]) {
        expect(
          db.select('SELECT count(*) FROM $table').single.values.single,
          1,
        );
      }
      expect(
        db
            .select('SELECT person, entered, snapshot FROM administration')
            .single
            .values,
        ['me', '0.1', marker],
      );
    },
  );
  test('failed command rolls back all effects and can retry', () {
    expect(() => save(fail: true), throwsStateError);
    for (final table in [
      'administration',
      'revision',
      'movement',
      'outbox',
      'operation',
    ]) {
      expect(db.select('SELECT count(*) FROM $table').single.values.single, 0);
    }
    expect(save(), 'committed:r1:1');
  });
  test(
    'stale correction cannot reverse later changes; explicit reversal balances',
    () {
      save();
      save(op: 'correct', revision: 1, amount: '0.3');
      expect(
        () => save(op: 'stale', revision: 1, amount: '0.2'),
        throwsStateError,
      );
      save(op: 'reverse', revision: 2, amount: '0.1');
      expect(
        exactTotal(db, 'SELECT delta FROM movement'),
        BigInt.from(-100000),
      );
      expect(
        save(op: 'reverse', revision: 2, amount: '0.1'),
        'already-committed:r1:3',
      );
      expect(
        db
            .select('SELECT amount FROM revision ORDER BY revision')
            .map((r) => r['amount']),
        [100000, 300000, 100000],
      );
    },
  );
  test('ownership, slot uniqueness and generation enforced', () {
    save(slot: 'slot1');
    expect(
      () => save(op: 'other-person', revision: 1, person: 'other'),
      throwsStateError,
    );
    expect(
      () => save(op: 'other-slot', record: 'r2', slot: 'slot1'),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute('INSERT INTO revision VALUES (?, ?, ?, ?, ?, ?)', [
        'r1',
        'other',
        2,
        1,
        '0.000001',
        marker,
      ]),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => command(
        db,
        operation: 'old-generation',
        record: 'r2',
        person: 'me',
        expectedRevision: 0,
        entered: '1',
        generation: 'old',
      ),
      throwsStateError,
    );
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
  });
  test(
    'two independent connections competing on the same revision commit once',
    () async {
      save();
      final result = await Future.wait([
        competeOnIsolate(path, 'a'),
        competeOnIsolate(path, 'b'),
      ]);
      expect(result.where((r) => r == 'committed:r1:2'), hasLength(1));
      expect(result.where((r) => r == 'conflict'), hasLength(1));
      expect(
        db.select('SELECT count(*) FROM movement').single.values.single,
        2,
      );
    },
  );
  test('six-place exact decimal boundaries and canonical input', () {
    expect(parseScaled('0.000001'), 1);
    expect(parseScaled('9000000000'), maxScaled);
    expect(parseScaled('12.345678'), 12345678);
    for (final input in [
      '0',
      '-1',
      '9000000000.000001',
      '0.0000001',
      '1,5',
      'NaN',
      '1e2',
    ]) {
      expect(
        () => parseScaled(input),
        throwsA(anyOf(isA<FormatException>(), isA<RangeError>())),
      );
    }
    expect(
      () => db.execute(
        'INSERT INTO administration VALUES (?, ?, NULL, 1, ?, ?, ?, ?)',
        ['invalid', 'me', maxScaled + 1, 'out-of-range', 'mg', marker],
      ),
      throwsA(isA<SqliteException>()),
    );
  });
  test('fractional totals and deficits stay exact; SQL integer SUM overflow is rejected', () {
    db.execute('CREATE TABLE amounts(value INTEGER NOT NULL) STRICT');
    db.execute('BEGIN');
    for (var i = 0; i < 2000; i++) {
      db.execute('INSERT INTO amounts VALUES (?)', [maxScaled]);
    }
    db.execute('COMMIT');
    expect(
      () => db.select('SELECT SUM(value) FROM amounts'),
      throwsA(isA<SqliteException>()),
    );
    expect(
      exactTotal(db, 'SELECT value FROM amounts').toString(),
      '18000000000000000000',
    );
    db.execute('DELETE FROM amounts');
    for (var i = 0; i < 1000; i++) {
      db.execute('INSERT INTO amounts VALUES (?)', [-parseScaled('0.1')]);
    }
    db.execute('INSERT INTO amounts VALUES (?)', [parseScaled('10')]);
    expect(exactTotal(db, 'SELECT value FROM amounts'), BigInt.from(-90000000));
  });
  test('populated migration preserves ownership, snapshots, history, operations and stock', () {
    save();
    save(op: 'correct', revision: 1, amount: '0.2');
    final before = {
      for (final table in [
        'administration',
        'revision',
        'movement',
        'operation',
        'outbox',
      ])
        table: db
            .select('SELECT * FROM $table')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
    };
    expect(() => migrateV2(db, fail: true), throwsStateError);
    expect(db.select('PRAGMA user_version').single.values.single, 1);
    migrateV2(db);
    expect(db.select('PRAGMA user_version').single.values.single, 2);
    for (final entry in before.entries) {
      final after = db
          .select('SELECT * FROM ${entry.key}')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      if (entry.key == 'administration') {
        for (final row in after) {
          expect(row.remove('provenance'), 'reported');
        }
      }
      expect(after, entry.value);
    }
    db.close();
    db = openProtected(path);
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
  });
  test(
    'process exits before commit roll back; exits after commit replay once',
    () async {
      final before = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/interrupt.dart',
        path,
        'before',
      ]);
      expect(before.exitCode, 71, reason: '${before.stderr}');
      expect(
        db.select('SELECT count(*) FROM operation').single.values.single,
        0,
      );
      final after = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/interrupt.dart',
        path,
        'after',
      ]);
      expect(after.exitCode, 72, reason: '${after.stderr}');
      expect(save(), 'already-committed:r1:1');
      expect(
        db.select('SELECT count(*) FROM movement').single.values.single,
        1,
      );
    },
  );
  test('rational conversions match independent Python Fraction fixtures', () {
    final fixtures = jsonDecode(
      File('test/fractions.json').readAsStringSync(),
    ) as List<Object?>;
    for (final fixture in fixtures.cast<Map<String, Object?>>()) {
      final (n, d) = convertExact(
        parseScaled(fixture['entered']! as String),
        fixture['concentrationNumerator']! as int,
        fixture['concentrationDenominator']! as int,
      );
      expect('$n/$d', fixture['expected']);
    }
    expect(() => convertExact(1, 1, 0), throwsRangeError);
  });
  test(
    'corrupt encrypted bytes are preserved and never replaced with empty data',
    () {
      final corrupt = '${dir.path}/corrupt.db';
      final connection = openProtected(corrupt);
      createV1(connection);
      connection.close();
      final bytes = File(corrupt).readAsBytesSync();
      bytes[0] ^= 0xff;
      File(corrupt).writeAsBytesSync(bytes, flush: true);
      expect(() => openProtected(corrupt), throwsA(isA<SqliteException>()));
      expect(File(corrupt).readAsBytesSync(), bytes);
    },
  );
  test('existing truncated file is an error; no silent fresh dataset', () {
    final truncated = File('${dir.path}/truncated.db')..writeAsBytesSync([]);
    expect(() => openProtected(truncated.path), throwsStateError);
    expect(() => DriftProbe(truncated), throwsStateError);
    expect(truncated.lengthSync(), 0);
  });
}
