import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';

import 'fixtures/restore_fixture.dart';

void main() {
  late Directory directory;
  late String livePath;
  late RecordStore live;

  const attachmentId = 'fixture-ready-attachment';
  const versionId = 'fixture-ready-version';
  const sha256 =
      '7d57fb98e9a3bd73704590f4b8b3ce7ae9d100a83fa878b2b2afca43be86c904';
  const pagedPrefix = 'page-ready-';
  const pagedReadyCount = 300;
  const corruptTailId = 'zzz-corrupt-attachment';
  final pagedPayload = utf8.encode('Synthetic paged restore content');
  final pagedDigest = crypto.sha256.convert(pagedPayload).toString();

  setUp(() async {
    directory = await createRestoreDataDirectory();
    livePath = '${directory.path}/data/records.sqlite';
    writeFixtureDatabase(livePath);
    live = await openFixtureStore(livePath);
  });

  tearDown(() async {
    try {
      await live.close();
    } catch (_) {
      // Already closed by the test.
    }
    await directory.delete(recursive: true);
  });

  Database raw(String path) {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute('PRAGMA key="x\'${hexKey(restoreTestKey)}\'"');
    return db;
  }

  Map<String, Object?> snapshot(Database db) => Map<String, Object?>.from(
    jsonDecode(
      db.select('SELECT snapshot FROM attachment_record WHERE id=?', [
            attachmentId,
          ]).single['snapshot']
          as String,
    ) as Map,
  );

  Map<String, Map<String, Object?>> readySnapshots(Database db) => {
    for (final row in db.select(
      "SELECT id,snapshot FROM attachment_record WHERE state='ready' ORDER BY id",
    ))
      row['id']! as String: Map<String, Object?>.from(
        jsonDecode(row['snapshot']! as String) as Map,
      ),
  };

  String fixtureItemId(Database db) =>
      db.select('SELECT target FROM attachment_record WHERE id=?', [
            attachmentId,
          ]).single['target']!
          as String;

  void insertReadyAttachment(
    Database db, {
    required String id,
    required String version,
    required String generation,
    required String itemId,
    required int createdAt,
    required String name,
    required List<int> payload,
    required String digest,
  }) {
    db.execute('INSERT INTO attachment_record VALUES (?,?,?,?,?,?,?,?,?)', [
      id,
      'me',
      'item',
      itemId,
      version,
      1,
      'ready',
      createdAt,
      jsonEncode({
        'id': id,
        'generation': generation,
        'personId': 'me',
        'targetKind': 'item',
        'targetId': itemId,
        'targetRevision': 1,
        'revision': 1,
        'versionId': version,
        'name': name,
        'state': 'ready',
        'createdAt': DateTime.fromMicrosecondsSinceEpoch(
          createdAt,
          isUtc: true,
        ).toIso8601String(),
        'inspection': {
          'mediaKind': 'other',
          'byteCount': payload.length,
          'sha256': digest,
          'mimeType': 'application/octet-stream',
          'width': null,
          'height': null,
          'pageCount': null,
          'frameCount': null,
        },
      }),
    ]);
    db.execute('INSERT INTO attachment_link VALUES (?,?,?,?,?)', [
      id,
      'me',
      itemId,
      null,
      null,
    ]);
    db.execute('INSERT INTO attachment_chunk VALUES (?,?,?,?)', [
      version,
      0,
      payload,
      digest,
    ]);
  }

  void insertPagedReady(
    Database db, {
    required String generation,
    bool corruptTail = false,
  }) {
    final itemId = fixtureItemId(db);
    db.execute('BEGIN IMMEDIATE');
    try {
      for (var index = 0; index < pagedReadyCount; index++) {
        final suffix = index.toString().padLeft(4, '0');
        insertReadyAttachment(
          db,
          id: '$pagedPrefix$suffix',
          version: '$pagedPrefix-version-$suffix',
          generation: generation,
          itemId: itemId,
          createdAt: 1792108800000000 + index,
          name: 'Paged original $suffix',
          payload: pagedPayload,
          digest: pagedDigest,
        );
      }
      if (corruptTail) {
        insertReadyAttachment(
          db,
          id: corruptTailId,
          version: 'zzz-corrupt-version',
          generation: 'bad generation',
          itemId: itemId,
          createdAt: 1792108900000000,
          name: 'Corrupt tail',
          payload: pagedPayload,
          digest: pagedDigest,
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  test(
    'rebinds retained ready attachment metadata to the restored generation',
    () async {
      final beforeGeneration = live.generation;
      final original = (await live.attachmentById(attachmentId))!;
      expect(original.generation, beforeGeneration);
      expect(original.versionId, versionId);
      expect(original.inspection!.sha256, sha256);
      final stalePin = await live.pinAttachment(
        id: attachmentId,
        generation: beforeGeneration,
        expectedRevision: original.revision,
        sessionId: 'legacy-session',
      );
      final staleJob = (await live.attachmentJob('fixture-ready'))!;

      await live.close();
      final archivePath = '${directory.path}/restored.sqlite';
      await File(livePath).copy(archivePath);
      live = await openFixtureStore(livePath);

      final before = raw(archivePath);
      final beforeSnapshot = snapshot(before);
      expect(beforeSnapshot['generation'], beforeGeneration);
      expect(beforeSnapshot['versionId'], versionId);
      final beforeChunk = before.select(
        'SELECT offset,bytes,digest FROM attachment_chunk WHERE version=?',
        [versionId],
      ).single;
      // A saved supporting source references the immutable content version,
      // not the dataset generation.
      before.execute('INSERT INTO supporting_source VALUES (?,?,?,?,?,?)', [
        'v19-panel-exact',
        'me',
        1,
        attachmentId,
        versionId,
        1,
      ]);
      before.close();

      final prepared = await live.prepareRestoredDatabase(
        stagedPath: archivePath,
        rekeyTo: (_) async {},
      );
      expect(prepared.generation, isNot(beforeGeneration));
      expect(prepared.attachmentCount, 1);

      // Preparation only edits the staged copy; the live dataset keeps its
      // generation, attachment snapshot and pins until activation.
      expect(live.generation, beforeGeneration);
      expect(
        (await live.attachmentById(attachmentId))!.generation,
        beforeGeneration,
      );

      final staged = raw(archivePath);
      final afterSnapshot = snapshot(staged);
      expect(afterSnapshot['generation'], prepared.generation);
      expect(
        {...afterSnapshot}..remove('generation'),
        {...beforeSnapshot}..remove('generation'),
      );
      final afterChunk = staged.select(
        'SELECT offset,bytes,digest FROM attachment_chunk WHERE version=?',
        [versionId],
      ).single;
      expect(afterChunk['bytes'], beforeChunk['bytes']);
      expect(afterChunk['digest'], beforeChunk['digest']);
      final source = staged.select('SELECT * FROM supporting_source').single;
      expect(source['record'], 'v19-panel-exact');
      expect(source['attachment'], attachmentId);
      expect(source['content_version'], versionId);
      expect(source['metadata_revision'], 1);
      expect(
        staged.select('SELECT count(*) c FROM attachment_job').single['c'],
        0,
      );
      expect(
        staged.select('SELECT count(*) c FROM attachment_pin').single['c'],
        0,
      );
      expect(
        staged
            .select(
              "SELECT count(*) c FROM attachment_chunk WHERE version='fixture-staged-version'",
            )
            .single['c'],
        0,
      );
      expect(
        staged
            .select(
              "SELECT count(*) c FROM operation WHERE result<>'{\"invalidated\":true}'",
            )
            .single['c'],
        0,
      );
      staged.close();

      final restored = await openFixtureStore(archivePath);
      try {
        expect(restored.generation, prepared.generation);
        final current = (await restored.attachmentById(attachmentId))!;
        expect(current.generation, prepared.generation);
        expect(current.versionId, original.versionId);
        expect(current.revision, original.revision);
        expect(current.targetId, original.targetId);
        expect(current.inspection!.sha256, sha256);

        final pin = await restored.pinAttachment(
          id: attachmentId,
          generation: prepared.generation,
          expectedRevision: current.revision,
          sessionId: 'restored-session',
        );
        final bytes = await restored
            .readAttachmentPin(pin)
            .expand((chunk) => chunk)
            .toList();
        expect(utf8.decode(bytes), 'Synthetic protected fixture original');

        final renamed = await restored.renameAttachment(
          commandId: 'restored-rename',
          attachment: current,
          expectedPersonRevision: 1,
          name: 'Restored original',
        );
        expect(renamed.name, 'Restored original');
        expect(renamed.generation, prepared.generation);
        expect(renamed.versionId, versionId);
        expect(
          (await restored.attachmentById(attachmentId))!.revision,
          renamed.revision,
        );

        await restored.deleteAttachment(
          commandId: 'restored-delete',
          attachment: renamed,
          expectedPersonRevision: 1,
        );
        expect(await restored.attachmentById(attachmentId), isNull);
        await restored.releaseAttachmentPin(pin);

        // Pre-restore objects and commands remain rejected against the new
        // generation before their old payloads could be replayed.
        await expectLater(
          restored.pinAttachment(
            id: attachmentId,
            generation: beforeGeneration,
            expectedRevision: original.revision,
          ),
          throwsA(
            isA<CommandConflict>().having(
              (error) => error.code,
              'code',
              'generation',
            ),
          ),
        );
        await expectLater(
          restored.renameAttachment(
            commandId: 'stale-rename',
            attachment: original,
            expectedPersonRevision: 1,
            name: 'Stale rename',
          ),
          throwsA(
            isA<CommandConflict>().having(
              (error) => error.code,
              'code',
              'generation',
            ),
          ),
        );
        await expectLater(
          restored.deleteAttachment(
            commandId: 'stale-delete',
            attachment: original,
            expectedPersonRevision: 1,
          ),
          throwsA(
            isA<CommandConflict>().having(
              (error) => error.code,
              'code',
              'generation',
            ),
          ),
        );
        await expectLater(
          restored.readAttachmentPin(stalePin),
          emitsError(
            isA<CommandConflict>().having(
              (error) => error.code,
              'code',
              'generation',
            ),
          ),
        );
        await expectLater(
          restored.beginAttachment(
            BeginAttachmentCommand(commandId: 'stale-begin', job: staleJob),
          ),
          throwsA(
            isA<CommandConflict>().having(
              (error) => error.code,
              'code',
              'generation',
            ),
          ),
        );

        final reclaimed = raw(archivePath);
        try {
          expect(
            reclaimed.select(
              'SELECT count(*) c FROM attachment_chunk WHERE version=?',
              [versionId],
            ).single['c'],
            0,
          );
          expect(
            reclaimed
                .select('SELECT count(*) c FROM attachment_record')
                .single['c'],
            0,
          );
        } finally {
          reclaimed.close();
        }
      } finally {
        await restored.close();
      }
    },
  );

  test(
    'rejects a retained ready attachment with invalid snapshot metadata',
    () async {
      final beforeGeneration = live.generation;
      await live.close();
      final archivePath = '${directory.path}/damaged-attachment.sqlite';
      await File(livePath).copy(archivePath);
      live = await openFixtureStore(livePath);
      final db = raw(archivePath);
      try {
        db.execute(
          "UPDATE attachment_record SET snapshot=json_set(snapshot,'\$.generation','bad generation') WHERE id=?",
          [attachmentId],
        );
      } finally {
        db.close();
      }
      await expectLater(
        live.prepareRestoredDatabase(
          stagedPath: archivePath,
          rekeyTo: (_) async {},
        ),
        throwsA(
          isA<RestoreFailure>().having(
            (error) => error.code,
            'code',
            RestoreCodes.corrupt,
          ),
        ),
      );
      expect(live.generation, beforeGeneration);
    },
  );

  test('rebinds every retained ready manifest across keyset pages and keeps '
      'the last usable', () async {
    final beforeGeneration = live.generation;
    await live.close();
    final archivePath = '${directory.path}/paged.sqlite';
    await File(livePath).copy(archivePath);
    live = await openFixtureStore(livePath);

    final database = raw(archivePath);
    insertPagedReady(database, generation: beforeGeneration);
    final inserted = readySnapshots(database);
    expect(
      database
          .select(
            "SELECT count(*) c FROM attachment_record WHERE state='ready'",
          )
          .single['c'],
      pagedReadyCount + 1,
    );
    database.close();

    final prepared = await live.prepareRestoredDatabase(
      stagedPath: archivePath,
      rekeyTo: (_) async {},
    );
    expect(prepared.generation, isNot(beforeGeneration));
    expect(prepared.attachmentCount, pagedReadyCount + 1);

    final staged = raw(archivePath);
    try {
      final after = readySnapshots(staged);
      expect(after.length, pagedReadyCount + 1);
      // The fixture manifest is on the first page; the synthetic tail is
      // several keyset pages later.
      expect(after.keys.first, attachmentId);
      expect(after.keys.last, '${pagedPrefix}0299');
      for (final entry in after.entries) {
        expect(
          entry.value['generation'],
          prepared.generation,
          reason: entry.key,
        );
      }
      for (final entry in inserted.entries) {
        expect(
          {...after[entry.key]!}..remove('generation'),
          {...entry.value}..remove('generation'),
          reason: entry.key,
        );
      }
    } finally {
      staged.close();
    }

    // Preparation only edits the staged copy.
    expect(live.generation, beforeGeneration);

    final restored = await openFixtureStore(archivePath);
    try {
      final current = (await restored.attachmentById('${pagedPrefix}0299'))!;
      expect(current.generation, prepared.generation);
      expect(current.versionId, '$pagedPrefix-version-0299');
      expect(current.revision, 1);
      final pin = await restored.pinAttachment(
        id: current.id,
        generation: prepared.generation,
        expectedRevision: current.revision,
        sessionId: 'paged-session',
      );
      final bytes = await restored
          .readAttachmentPin(pin)
          .expand((chunk) => chunk)
          .toList();
      expect(utf8.decode(bytes), utf8.decode(pagedPayload));
      await restored.releaseAttachmentPin(pin);
    } finally {
      await restored.close();
    }
  });

  test(
    'rolls back every rebound page when a later retained manifest is corrupt',
    () async {
      final beforeGeneration = live.generation;
      await live.close();
      final archivePath = '${directory.path}/paged-corrupt.sqlite';
      await File(livePath).copy(archivePath);
      live = await openFixtureStore(livePath);

      final database = raw(archivePath);
      final before = readySnapshots(database);
      insertPagedReady(
        database,
        generation: beforeGeneration,
        corruptTail: true,
      );
      final pinsBefore = database
          .select('SELECT count(*) c FROM attachment_pin')
          .single['c'];
      database.close();

      await expectLater(
        live.prepareRestoredDatabase(
          stagedPath: archivePath,
          rekeyTo: (_) async {},
        ),
        throwsA(
          isA<RestoreFailure>().having(
            (error) => error.code,
            'code',
            RestoreCodes.corrupt,
          ),
        ),
      );

      expect(live.generation, beforeGeneration);
      expect(
        (await live.attachmentById(attachmentId))!.generation,
        beforeGeneration,
      );

      final staged = raw(archivePath);
      try {
        final after = readySnapshots(staged);
        expect(after.length, before.length + pagedReadyCount + 1);
        // Manifests from earlier pages were updated before the malformed tail
        // was reached; the transaction must restore their original snapshots.
        for (final entry in after.entries.where(
          (entry) => entry.key != corruptTailId,
        )) {
          expect(
            entry.value['generation'],
            beforeGeneration,
            reason: entry.key,
          );
        }
        expect(after[corruptTailId]!['generation'], 'bad generation');
        // The transaction's staging deletes rolled back with the rebind.
        expect(
          staged
              .select(
                "SELECT count(*) c FROM attachment_record WHERE id='fixture-staged-attachment'",
              )
              .single['c'],
          1,
        );
        expect(
          staged.select('SELECT count(*) c FROM attachment_pin').single['c'],
          pinsBefore,
        );
      } finally {
        staged.close();
      }
    },
  );

  test(
    'rejects a staged dataset beyond the existing archive attachment bound',
    () async {
      final beforeGeneration = live.generation;
      await live.close();
      final archivePath = '${directory.path}/oversized.sqlite';
      await File(livePath).copy(archivePath);
      live = await openFixtureStore(livePath);

      final database = raw(archivePath);
      try {
        final itemId = fixtureItemId(database);
        database.execute('BEGIN IMMEDIATE');
        for (var index = 0; index < BackupLimits.maxAttachmentCount; index++) {
          final suffix = index.toString().padLeft(5, '0');
          final id = 'bulk-ready-$suffix';
          database.execute(
            'INSERT INTO attachment_record VALUES (?,?,?,?,?,?,?,?,?)',
            [
              id,
              'me',
              'item',
              itemId,
              'bulk-version-$suffix',
              1,
              'ready',
              1792108800000000,
              '{}',
            ],
          );
          database.execute('INSERT INTO attachment_link VALUES (?,?,?,?,?)', [
            id,
            'me',
            itemId,
            null,
            null,
          ]);
        }
        database.execute('COMMIT');
      } finally {
        database.close();
      }

      await expectLater(
        live.prepareRestoredDatabase(
          stagedPath: archivePath,
          rekeyTo: (_) async {},
        ),
        throwsA(
          isA<RestoreFailure>().having(
            (error) => error.code,
            'code',
            RestoreCodes.tooLarge,
          ),
        ),
      );
      expect(live.generation, beforeGeneration);
    },
  );
}
