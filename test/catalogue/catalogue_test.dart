import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/catalogue/catalogue_manager.dart';

void main() {
  late Directory root;
  late CatalogueManager manager;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vital-catalogue-test-');
    manager = CatalogueManager(
      Directory('${root.path}/catalogues'),
      allowSynthetic: true,
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<CatalogueManifest> fixture(
    String version, {
    int count = 1000,
    bool duplicate = false,
  }) async {
    final notice = File('${root.path}/$version.notice');
    await notice.writeAsString(
      'Synthetic test data only. No medicines or production source.',
    );
    final file = File('${root.path}/$version.jsonl');
    final sink = file.openWrite();
    for (var i = 0; i < count; i++) {
      sink.writeln(
        jsonEncode(
          CatalogueProduct(
            code: 'test-${duplicate ? 0 : i}',
            conceptClass: 'SYNTHETIC',
            name: i == count - 1 ? 'Common rareblend' : 'Common invented$i',
            form: 'tablet',
            strength: '${i + 1} mg',
          ).toJson(),
        ),
      );
    }
    await sink.close();
    return CatalogueManifest(
      version: version,
      sourceId: 'synthetic-test',
      releaseDate: '2026-10-19',
      sourceUrl: 'https://example.invalid/synthetic',
      sourceSha256: '0' * 64,
      projectionSha256: await catalogueFileSha256(file),
      licence: 'Synthetic test fixture',
      attribution: 'Generated synthetic test data',
      licenceSha256: await catalogueFileSha256(notice),
      recordCount: count,
      admissionReference: 'test-only-not-a-source-admission',
      synthetic: true,
    );
  }

  Future<void> stage(CatalogueManifest m, {bool fail = false}) => manager.stage(
    projection: File('${root.path}/${m.version}.jsonl'),
    licenceNotice: File('${root.path}/${m.version}.notice'),
    manifest: m,
    failBeforePublish: fail,
  );

  test('no corpus adopted by default; test admission is explicit', () async {
    expect(await manager.openActive(), isNull);
    final m = await fixture('one');
    final production = CatalogueManager(manager.directory);
    await expectLater(
      production.stage(
        projection: File('${root.path}/one.jsonl'),
        licenceNotice: File('${root.path}/one.notice'),
        manifest: m,
      ),
      throwsStateError,
    );
    expect(await manager.directory.exists(), isFalse);
  });
  test('bounded full-size synthetic corpus, rare intersection, codes, punctuation and no-match', () async {
    const count = 100000;
    final m = await fixture('full', count: count);
    final build = Stopwatch()..start();
    await stage(m);
    build.stop();
    await manager.activate('full');
    final reader = (await manager.openActive())!;
    final query = Stopwatch()..start();
    final rare = await reader.search('Common rareblend');
    query.stop();
    expect(rare.products.single.code, 'test-${count - 1}');
    expect(rare.needsRefinement, isFalse);
    final broad = await reader.search('c');
    expect(broad.products.length, 50);
    expect(broad.needsRefinement, isTrue);
    final missing = await reader.search('absent');
    expect(missing.products, isEmpty);
    expect(missing.needsRefinement, isFalse);
    expect(missing.customEntryName, 'absent');
    final uncertain = await reader.search('common tablet 0');
    // Candidate limits must never turn incomplete work into authoritative no-match.
    if (uncertain.products.isEmpty) expect(uncertain.needsRefinement, isFalse);
    expect(
      (await reader.search('test-99999')).products.first.code,
      'test-99999',
    );
    expect((await reader.search('rareblend" OR *')).products, isEmpty);
    expect(
      (await reader.search('rareblend / tablet')).products.single.code,
      'test-99999',
    );
    expect(reader.manifest.attribution, m.attribution);
    final db = sqlite3.open(reader.path, mode: OpenMode.readOnly);
    try {
      expect(
        () => db.execute('DELETE FROM product'),
        throwsA(isA<SqliteException>()),
      );
      final plan = db.select(
        'EXPLAIN QUERY PLAN SELECT product FROM token WHERE token>=? AND token<? LIMIT 513',
        ['c', 'd'],
      );
      expect(plan.toString(), contains('PRIMARY KEY'));
    } finally {
      db.close();
    }
    // Retained console evidence is a host smoke measurement, never a device budget.
    // ignore: avoid_print
    print(
      'catalogue synthetic rows=$count buildMs=${build.elapsedMilliseconds} rareQueryMs=${query.elapsedMilliseconds} databaseBytes=${await File(reader.path).length()}',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
  test(
    'stage and activation failures preserve active and pinned readers',
    () async {
      final one = await fixture('one');
      await stage(one);
      await manager.activate('one');
      final pinned = (await manager.openActive())!;
      final two = await fixture('two');
      await expectLater(stage(two, fail: true), throwsStateError);
      expect((await manager.openActive())!.manifest.version, 'one');
      expect(
        await Directory('${manager.directory.path}/two.pending').exists(),
        isFalse,
      );
      await stage(two);
      await expectLater(
        manager.activate('two', failBeforeCommit: true),
        throwsStateError,
      );
      final reopened = CatalogueManager(
        manager.directory,
        allowSynthetic: true,
      );
      expect((await reopened.openActive())!.manifest.version, 'one');
      await manager.activate('two');
      expect((await reopened.openActive())!.manifest.version, 'two');
      expect(pinned.manifest.version, 'one');
      expect(
        (await pinned.search('rareblend')).products.single.name,
        'Common rareblend',
      );
      await expectLater(stage(two), throwsStateError);
    },
  );
  test(
    'hash mismatch, malformed line and duplicate identity cannot publish',
    () async {
      final m = await fixture('bad');
      await File('${root.path}/bad.jsonl').writeAsString('corrupt');
      await expectLater(stage(m), throwsFormatException);
      expect(
        await Directory('${manager.directory.path}/bad').exists(),
        isFalse,
      );
      final duplicate = await fixture('duplicate', duplicate: true);
      await expectLater(stage(duplicate), throwsA(isA<SqliteException>()));
      final malformed = await fixture('malformed');
      final f = File('${root.path}/malformed.jsonl');
      await f.writeAsString('{broken}\n');
      final j = malformed.toJson()
        ..['projectionSha256'] = sha256
            .convert(await f.readAsBytes())
            .toString();
      await expectLater(
        stage(CatalogueManifest.fromJson(j)),
        throwsFormatException,
      );
    },
  );
  test('bounded incomplete intersection requests refinement even with no visible match', () async {
    final m = await fixture('clipped', count: 2000);
    final f = File('${root.path}/clipped.jsonl');
    final sink = f.openWrite();
    for (var i = 0; i < 2000; i++) {
      sink.writeln(
        jsonEncode(
          CatalogueProduct(
            code: 'clip-$i',
            conceptClass: 'SYNTHETIC',
            name: i < 1000 || i == 1999 ? 'alpha' : 'beta',
            form: i >= 1500 ? 'beta' : 'neutral',
            strength: i == 1999 ? 'rare' : 'ordinary',
          ).toJson(),
        ),
      );
    }
    await sink.close();
    final j = m.toJson()..['projectionSha256'] = await catalogueFileSha256(f);
    await stage(CatalogueManifest.fromJson(j));
    await manager.activate('clipped');
    final reader = (await manager.openActive())!;
    // Each of these terms has >512 postings; the third rare term must win.
    expect(
      (await reader.search('alpha beta rare')).products.single.code,
      'clip-1999',
    );
    // A term that has no posting proves no-match without scanning any candidates.
    final missing = await reader.search('alpha beta absent');
    expect(missing.products, isEmpty);
    expect(missing.needsRefinement, isFalse);
    final clipped = await reader.search('alpha beta');
    expect(clipped.products, isEmpty);
    expect(clipped.needsRefinement, isTrue);
  });
  test('counts, overlong lines and path traversal are rejected without replacing active', () async {
    final m = await fixture('limits');
    final wrong = m.toJson()..['recordCount'] = 999;
    await expectLater(
      stage(CatalogueManifest.fromJson(wrong)),
      throwsFormatException,
    );
    final f = File('${root.path}/limits.jsonl');
    await f.writeAsString('a' * 16385);
    final oversized = m.toJson()
      ..['projectionSha256'] = await catalogueFileSha256(f);
    await expectLater(
      stage(CatalogueManifest.fromJson(oversized)),
      throwsFormatException,
    );
    await expectLater(manager.activate('../other'), throwsFormatException);
    expect(await manager.openActive(), isNull);
    expect(
      (await manager.directory.list().toList()).every(
        (entry) => entry.path.endsWith('/.update-lock.sqlite'),
      ),
      isTrue,
    );
  });
  test('recovery reclaims only marked interrupted staging and preserves pinned/unknown data', () async {
    final m = await fixture('one');
    await stage(m);
    await manager.activate('one');
    final pinned = (await manager.openActive())!;
    final base = manager.directory.path;
    // On-disk states after a process exits before build/pointer publication.
    for (final name in ['.vital-stage-killed1', '.vital-activation-killed2']) {
      final pending = await Directory('$base/$name').create();
      await File('${pending.path}/.owner')
          .writeAsString('vital-catalogue-stage-1');
      await File(
        '${pending.path}/${name.contains('stage') ? 'catalogue.sqlite-journal' : 'pointer'}',
      ).writeAsString('incomplete');
    }
    final unknown = await Directory('$base/.vital-stage-unknown').create();
    await File('${unknown.path}/keep').writeAsString('unknown data');
    final linked = await Directory('$base/.vital-stage-linked').create();
    await File('${linked.path}/.owner')
        .writeAsString('vital-catalogue-stage-1');
    await Link('${linked.path}/NOTICE').create('${root.path}/one.notice');
    final legacy = await Directory('$base/one.pending-legacy').create();
    await File('${legacy.path}/keep').writeAsString('legacy data');
    final reopened = CatalogueManager(manager.directory, allowSynthetic: true);
    await reopened.recoverStaging();
    expect(await Directory('$base/.vital-stage-killed1').exists(), isFalse);
    expect(
      await Directory('$base/.vital-activation-killed2').exists(),
      isFalse,
    );
    expect(await unknown.exists(), isTrue);
    expect(await linked.exists(), isTrue);
    expect(await legacy.exists(), isTrue);
    expect((await reopened.openActive())!.manifest.version, 'one');
    expect(
      (await pinned.search('rareblend')).products.single.name,
      'Common rareblend',
    );
    expect(await File('${root.path}/one.notice').exists(), isTrue);
  });
  test('another manager cannot clean or update while SQLite mutation lease is held', () async {
    final m = await fixture('one');
    await stage(m);
    final lock = sqlite3.open('${manager.directory.path}/.update-lock.sqlite');
    lock.execute('BEGIN EXCLUSIVE');
    try {
      final other = CatalogueManager(manager.directory, allowSynthetic: true);
      await expectLater(
        other.recoverStaging(),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(other.activate('one'), throwsA(isA<SqliteException>()));
    } finally {
      lock.execute('ROLLBACK');
      lock.close();
    }
    await manager.activate('one');
    expect((await manager.openActive())!.manifest.version, 'one');
  });
  test(
    'process death releases update lease and marked interrupted files recover',
    () async {
      final m = await fixture('one');
      await stage(m);
      await manager.activate('one');
      final pinned = (await manager.openActive())!;
      final child = await Process.start('python3', [
        '-u',
        '-c',
        r"""
import pathlib, sqlite3, sys, signal
root = pathlib.Path(sys.argv[1])
lock = sqlite3.connect(str(root / '.update-lock.sqlite'), timeout=0)
lock.execute('BEGIN EXCLUSIVE')
for name, filename in [('.vital-stage-processdeath', 'catalogue.sqlite-journal'), ('.vital-activation-processdeath', 'pointer')]:
    pending = root / name
    pending.mkdir()
    (pending / '.owner').write_text('vital-catalogue-stage-1')
    (pending / filename).write_text('interrupted')
print('READY', flush=True)
signal.pause()
""",
        manager.directory.path,
      ]);
      try {
        expect(
          await child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 5)),
          'READY',
        );
        final reopened = CatalogueManager(
          manager.directory,
          allowSynthetic: true,
        );
        await expectLater(
          reopened.recoverStaging(),
          throwsA(isA<SqliteException>()),
        );
        expect(child.kill(ProcessSignal.sigkill), isTrue);
        await child.exitCode.timeout(const Duration(seconds: 5));
        await reopened.recoverStaging();
        expect(
          await Directory('${manager.directory.path}/.vital-stage-processdeath')
              .exists(),
          isFalse,
        );
        expect(
          await Directory(
            '${manager.directory.path}/.vital-activation-processdeath',
          ).exists(),
          isFalse,
        );
        expect((await reopened.openActive())!.manifest.version, 'one');
        expect((await pinned.search('rareblend')).products, isNotEmpty);
      } finally {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
      }
    },
    skip: !Platform.isLinux,
  );
  test('rapid typing coalesces work and rejects stale replies', () async {
    final m = await fixture('typing');
    await stage(m);
    await manager.activate('typing');
    final session = CatalogueSearchSession((await manager.openActive())!);
    final first = session.search('common');
    final replaced = session.search('absent');
    final latest = session.search('rareblend');
    expect(await first, isNull);
    expect(await replaced, isNull);
    expect((await latest)!.products.single.name, 'Common rareblend');
    final interrupted = session.search('common');
    session.close();
    expect(await interrupted, isNull);
    expect(() => session.search('another'), throwsStateError);
  });
  test('artifact corruption and oversized queries are rejected', () async {
    final m = await fixture('one');
    await stage(m);
    await manager.activate('one');
    final reader = (await manager.openActive())!;
    await expectLater(reader.search('a' * 129), throwsFormatException);
    await expectLater(
      reader.search(List.generate(17, (i) => 'token$i').join(' ')),
      throwsFormatException,
    );
    await File('${manager.directory.path}/one/NOTICE').writeAsString('changed');
    await expectLater(manager.openActive(), throwsFormatException);
  });
}
