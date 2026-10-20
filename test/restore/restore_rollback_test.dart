import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';
import 'package:true_grit_vital/restore/restore_activation.dart';

import 'fixtures/restore_fixture.dart';

void main() {
  late Directory directory;
  late String livePath;

  setUp(() async {
    directory = await createRestoreDataDirectory();
    livePath = '${directory.path}/data/records.sqlite';
    writeFixtureDatabase(livePath);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'a replacement that cannot reopen rolls back the previous dataset',
    () async {
      var live = await openFixtureStore(livePath);
      final previousGeneration = live.generation;
      await live.close();
      final source = '${directory.path}/source.sqlite';
      await File(livePath).copy(source);
      live = await openFixtureStore(livePath);
      final prepared = await live.prepareRestoredDatabase(
        stagedPath: source,
        rekeyTo: (_) async {},
      );
      await live.close();

      final activation = RestoreActivation(
        databasePath: livePath,
        checkpoint: (phase) async {
          if (phase != RestoreJournalPhase.ready) return;
          // Corrupt the already-verified staged snapshot after the journal is
          // durable but before the atomic replacement.
          final staged = File(
            '${directory.path}/data/restore/${RestoreLimits.stagedFile}',
          );
          final bytes = await staged.readAsBytes();
          for (
            var index = 1024;
            index < 1280 && index < bytes.length;
            index++
          ) {
            bytes[index] = 0;
          }
          await staged.writeAsBytes(bytes, flush: true);
        },
      );
      await expectLater(
        activation.activate(
          preparedPath: prepared.path,
          previousGeneration: prepared.previousGeneration,
          newGeneration: prepared.generation,
          previousNamespace: prepared.previousNamespace ?? '',
          reminderNamespace: prepared.reminderNamespace,
          key: restoreTestKey,
          closeLive: () async {},
        ),
        throwsA(isA<RestoreFailure>()),
      );

      final reopened = await RecordStore.open(
        path: livePath,
        key: restoreTestKey,
        isNew: false,
      );
      try {
        expect(reopened.generation, previousGeneration);
        expect(await reopened.drafts(), isNotEmpty);
      } finally {
        await reopened.close();
      }
      expect(
        await Directory('${directory.path}/data/restore').exists(),
        isFalse,
      );
    },
  );
}
