import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/restore.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';

import 'fixtures/restore_fixture.dart';

final class _UnlockedAppLock extends AppLockController {
  @override
  AppLockState build() =>
      const AppLockState(ready: true, enabled: false, locked: false);
}

final class _LifecycleGateway implements RestoreGateway {
  @override
  bool supported = true;
  @override
  int currentSchemaVersion = 21;

  late RestorePick pick;
  late RestoreArchive archive;
  late RestorePreparedDatabase prepared;
  Completer<void>? prepareGate;
  BackupCancellationToken? prepareToken;
  bool ignoreCancellation = false;
  bool failActivation = false;
  int prepareCalls = 0;
  int activateCalls = 0;
  int discardArchiveCalls = 0;
  int archiveDiscards = 0;

  @override
  Future<RestorePick?> chooseArchive() async => pick;

  @override
  Future<void> discardPick(RestorePick pick) async {}

  @override
  Future<RestoreArchive> validateArchive({
    required RestorePick pick,
    required String password,
    required BackupCancellationToken token,
    void Function(RestoreProgress progress)? onProgress,
  }) async => archive;

  @override
  Future<void> discardArchive(RestoreArchive archive) async {
    discardArchiveCalls++;
    await archive.discard();
  }

  @override
  Future<RestorePreparedDatabase> prepare(
    RestoreArchive archive, {
    BackupCancellationToken? token,
  }) async {
    prepareCalls++;
    prepareToken = token;
    final gate = prepareGate;
    if (gate != null) await gate.future;
    if (!ignoreCancellation && (token?.isCancelled ?? false)) {
      throw const RestoreFailure(RestoreCodes.cancelled);
    }
    return prepared;
  }

  @override
  Future<RestoreActivationOutcome> activate({
    required RestoreArchive archive,
    required RestorePreparedDatabase prepared,
    void Function(RestoreProgress progress)? onProgress,
  }) async {
    activateCalls++;
    if (failActivation) throw const RestoreFailure(RestoreCodes.storage);
    return RestoreActivationOutcome(
      result: RestoreActivationResult(
        previousGeneration: prepared.previousGeneration,
        newGeneration: prepared.generation,
        previousNamespace: prepared.previousNamespace,
        reminderNamespace: prepared.reminderNamespace,
      ),
      remindersInvalidated: true,
    );
  }

  @override
  Future<void> refresh() async {}
}

BackupHeader _header() => BackupHeader(
  createdAt: DateTime.utc(2026, 10, 20, 9, 30),
  schemaVersion: 21,
  generation: 'gggggggggggggggg',
  kdf: BackupKdfParameters(
    memoryKiB: 65536,
    iterations: 3,
    parallelism: 1,
    hashLength: 32,
    salt: Uint8List.fromList(List<int>.filled(16, 1)),
  ),
  cipher: BackupCipherParameters(
    chunkBytes: 262144,
    noncePrefix: Uint8List.fromList(List<int>.filled(16, 2)),
  ),
  snapshot: BackupSnapshotSummary(
    bytes: 1024,
    sha256: 'a' * 64,
    attachmentCount: 1,
    attachmentBytes: 100,
    attachmentSha256: 'b' * 64,
  ),
);

BackupInventory _inventory() => BackupInventory(
  generation: 'gggggggggggggggg',
  schemaVersion: 21,
  people: const [BackupPerson(id: 'me', name: 'Me', archived: false)],
  peopleCount: 1,
  recordCount: 3,
  itemCount: 5,
  supportingCount: 3,
  attachmentCount: 1,
  attachmentBytes: 100,
  attachmentSha256: 'b' * 64,
  coverage: const [
    BackupPersonCoverage(
      person: BackupPerson(id: 'me', name: 'Me', archived: false),
      recordCount: 2,
      attachmentCount: 1,
      earliestRecord: null,
      latestRecord: null,
    ),
  ],
  earliestRecord: DateTime.utc(2026, 9, 1),
  latestRecord: DateTime.utc(2026, 10, 19),
);

void _configure(_LifecycleGateway gateway, Directory directory) {
  gateway.pick = RestorePick(
    name: 'synthetic-backup.vitalbackup',
    file: File('${directory.path}/synthetic-backup.vitalbackup'),
    byteCount: 3,
  );
  gateway.archive = RestoreArchive(
    databasePath: '${directory.path}/staged.sqlite',
    header: _header(),
    inventory: _inventory(),
    archiveBytes: 4096,
    rekey: (_) async {},
    discard: () async => gateway.archiveDiscards++,
  );
  gateway.prepared = RestorePreparedDatabase(
    path: gateway.archive.databasePath,
    previousGeneration: 'aaaaaaaaaaaaaaaa',
    generation: 'bbbbbbbbbbbbbbbb',
    previousNamespace: 'cccccccccccccccc',
    reminderNamespace: 'dddddddddddddddd',
    schemaVersion: 21,
    peopleCount: 1,
    recordCount: 3,
    itemCount: 5,
    supportingCount: 3,
    attachmentCount: 1,
  );
}

Future<void> _moveToConfirmedPreview(
  ProviderContainer container,
  RestoreController controller,
) async {
  await controller.choose();
  await controller.check('synthetic password');
  controller.setConfirmed(true);
}

void main() {
  late Directory directory;
  late String livePath;
  late RecordStore live;

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

  Future<String> copyClosedSnapshot(String name) async {
    await live.close();
    final path = '${directory.path}/$name';
    await File(livePath).copy(path);
    live = await openFixtureStore(livePath);
    return path;
  }

  group('preparation cancellation', () {
    test(
      'a pre-cancelled preparation never re-keys or stamps the stage',
      () async {
        final beforeGeneration = live.generation;
        final archivePath = await copyClosedSnapshot('pre-cancelled.sqlite');
        var rekeys = 0;
        final token = BackupCancellationToken()..cancel();

        await expectLater(
          live.prepareRestoredDatabase(
            stagedPath: archivePath,
            rekeyTo: (key) async {
              rekeys++;
            },
            token: token,
          ),
          throwsA(
            isA<RestoreFailure>().having(
              (error) => error.code,
              'code',
              RestoreCodes.cancelled,
            ),
          ),
        );

        expect(rekeys, 0);
        expect(live.generation, beforeGeneration);
        final staged = raw(archivePath);
        try {
          expect(
            staged
                .select('SELECT generation FROM dataset')
                .single['generation'],
            beforeGeneration,
          );
          expect(
            staged.select('SELECT count(*) c FROM ordinary_draft').single['c'],
            1,
          );
        } finally {
          staged.close();
        }
      },
    );

    test(
      'cancelling after the first manifest batch rolls back scrub and stamping',
      () async {
        final beforeGeneration = live.generation;
        final archivePath = await copyClosedSnapshot('batch-cancelled.sqlite');
        final before = raw(archivePath);
        final beforeNamespace = before
            .select('SELECT namespace FROM reminder_meta WHERE id=1')
            .single['namespace'];
        final beforeDrafts = before
            .select('SELECT count(*) c FROM ordinary_draft')
            .single['c'];
        final beforeValidOperations = before
            .select(
              "SELECT count(*) c FROM operation WHERE result<>'{\"invalidated\":true}'",
            )
            .single['c'];
        final beforeSnapshot = jsonDecode(
          before.select('SELECT snapshot FROM attachment_record WHERE id=?', [
                'fixture-ready-attachment',
              ]).single['snapshot']
              as String,
        ) as Map;
        before.close();

        final token = BackupCancellationToken();
        var batches = 0;
        await expectLater(
          live.prepareRestoredDatabase(
            stagedPath: archivePath,
            rekeyTo: (_) async {},
            token: token,
            onManifestBatch: () {
              batches++;
              token.cancel();
            },
          ),
          throwsA(
            isA<RestoreFailure>().having(
              (error) => error.code,
              'code',
              RestoreCodes.cancelled,
            ),
          ),
        );

        expect(batches, 1);
        expect(live.generation, beforeGeneration);
        final staged = raw(archivePath);
        try {
          expect(
            staged
                .select('SELECT generation FROM dataset')
                .single['generation'],
            beforeGeneration,
          );
          expect(
            staged.select('SELECT count(*) c FROM ordinary_draft').single['c'],
            beforeDrafts,
          );
          expect(
            staged
                .select(
                  "SELECT count(*) c FROM operation WHERE result<>'{\"invalidated\":true}'",
                )
                .single['c'],
            beforeValidOperations,
          );
          expect(
            staged
                .select('SELECT namespace FROM reminder_meta WHERE id=1')
                .single['namespace'],
            beforeNamespace,
          );
          final snapshot = jsonDecode(
            staged.select('SELECT snapshot FROM attachment_record WHERE id=?', [
                  'fixture-ready-attachment',
                ]).single['snapshot']
                as String,
          ) as Map;
          expect(snapshot['generation'], beforeSnapshot['generation']);
          expect(
            staged.select('PRAGMA integrity_check').single.values.single,
            'ok',
          );
        } finally {
          staged.close();
        }
        expect(File('$archivePath-wal').existsSync(), isFalse);
      },
    );

    test('a live token still prepares and rebinds every manifest', () async {
      final beforeGeneration = live.generation;
      final archivePath = await copyClosedSnapshot('normal.sqlite');
      var batches = 0;

      final prepared = await live.prepareRestoredDatabase(
        stagedPath: archivePath,
        rekeyTo: (_) async {},
        token: BackupCancellationToken(),
        onManifestBatch: () => batches++,
      );

      expect(batches, 1);
      expect(prepared.previousGeneration, beforeGeneration);
      expect(prepared.generation, isNot(beforeGeneration));
      final staged = raw(archivePath);
      try {
        expect(
          staged.select('SELECT generation FROM dataset').single['generation'],
          prepared.generation,
        );
        final snapshot = jsonDecode(
          staged.select('SELECT snapshot FROM attachment_record WHERE id=?', [
                'fixture-ready-attachment',
              ]).single['snapshot']
              as String,
        ) as Map;
        expect(snapshot['generation'], prepared.generation);
      } finally {
        staged.close();
      }
    });
  });

  group('controller lifecycle', () {
    test(
      'disposal cancels preparation and never activates a late result',
      () async {
        final gateway = _LifecycleGateway()..prepareGate = Completer<void>();
        _configure(gateway, directory);
        final container = ProviderContainer(
          overrides: [
            restoreGatewayProvider.overrideWithValue(gateway),
            appLockProvider.overrideWith(_UnlockedAppLock.new),
          ],
        );
        var disposed = false;
        addTearDown(() {
          if (!disposed) container.dispose();
        });
        container.listen(restoreProvider, (_, _) {});
        final controller = container.read(restoreProvider.notifier);
        await _moveToConfirmedPreview(container, controller);

        final pending = controller.replace();
        expect(gateway.prepareToken, isNotNull);
        container.dispose();
        disposed = true;

        expect(gateway.prepareToken!.isCancelled, isTrue);
        gateway.prepareGate!.complete();
        await pending;

        expect(gateway.activateCalls, 0);
        expect(gateway.archiveDiscards, 1);
        expect(gateway.discardArchiveCalls, 0);
      },
    );

    test(
      'a late successful preparation is discarded instead of activated',
      () async {
        final gateway = _LifecycleGateway()
          ..prepareGate = Completer<void>()
          ..ignoreCancellation = true;
        _configure(gateway, directory);
        final container = ProviderContainer(
          overrides: [
            restoreGatewayProvider.overrideWithValue(gateway),
            appLockProvider.overrideWith(_UnlockedAppLock.new),
          ],
        );
        var disposed = false;
        addTearDown(() {
          if (!disposed) container.dispose();
        });
        container.listen(restoreProvider, (_, _) {});
        final controller = container.read(restoreProvider.notifier);
        await _moveToConfirmedPreview(container, controller);

        final pending = controller.replace();
        container.dispose();
        disposed = true;

        gateway.prepareGate!.complete();
        await pending;

        expect(gateway.activateCalls, 0);
        expect(gateway.discardArchiveCalls, 1);
        expect(gateway.archiveDiscards, 1);
      },
    );
  });
}
