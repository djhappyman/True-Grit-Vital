import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';
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
}
