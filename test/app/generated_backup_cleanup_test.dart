import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/app/backup.dart';
import 'package:true_grit_vital/app/generated_artifacts.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/domain/artifact_transfer.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';

import 'artifact_transfer_controller_test.dart' show FakeArtifactGateway;

const _password = 'a long enough password';

final class _TestLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  @override
  void lock() => state = state.copy(locked: true);
}

/// A deletion held open until the test settles it, so lifecycle outcomes
/// are decided with deterministic completers instead of sleeps.
final class _PendingDiscard {
  _PendingDiscard(this.creation, {required this.fails});
  final BackupCreation creation;
  final bool fails;
  final Completer<void> completion = Completer<void>();
}

/// Deterministic [BackupOperations]: deletions are held open in [pending]
/// until the test completes or fails them and saves can be held through
/// [saveGate]. No timers, no sleeps.
final class _HarnessOperations implements BackupOperations {
  _HarnessOperations({required this.nextCreation, List<bool>? discardOutcomes})
    : discardOutcomes = discardOutcomes ?? const [];

  BackupCreation nextCreation;
  Completer<BackupCreation>? createGate;
  Completer<BackupSaveStatus>? saveGate;
  int creates = 0, discards = 0, saves = 0;
  final List<_PendingDiscard> pending = [];
  List<bool> discardOutcomes = const [];

  _PendingDiscard get held {
    expect(pending, hasLength(1), reason: 'one held deletion expected');
    return pending.single;
  }

  @override
  bool get destinationSupported => true;

  @override
  Future<BackupCreation> createBackup({
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) {
    creates++;
    final gate = createGate;
    if (gate != null) return gate.future;
    return Future<BackupCreation>.value(nextCreation);
  }

  @override
  Future<void> discard(BackupCreation creation) {
    final fails = discardOutcomes.isNotEmpty
        ? discardOutcomes.removeAt(0)
        : false;
    final held = _PendingDiscard(creation, fails: fails);
    pending.add(held);
    discards++;
    unawaited(
      held.completion.future
          .whenComplete(() => pending.remove(held))
          .catchError((Object _) {}),
    );
    return held.completion.future.then((_) {
      if (held.fails) throw const BackupFailure('backup_failed');
    });
  }

  @override
  Future<BackupSaveStatus> save(BackupCreation creation) {
    saves++;
    final gate = saveGate;
    if (gate == null) {
      return Future<BackupSaveStatus>.value(BackupSaveStatus.saved);
    }
    return gate.future;
  }

  @override
  Future<StagedBackup> validateArchive({
    required File archive,
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) async => throw UnsupportedError('not used by this cleanup test');

  @override
  Future<void> cleanupAbandoned() async {}
}

/// An OS handoff whose save is held open so data-change preparation meets a
/// genuinely busy, undeletable handoff.
final class _HeldSaveGateway implements ArtifactTransferGateway {
  _HeldSaveGateway();
  final Completer<bool> saveOutcome = Completer<bool>();
  int saves = 0;
  final List<bool> cleanups = [];

  @override
  ArtifactCapabilities get capabilities =>
      const ArtifactCapabilities(save: true, share: false);

  @override
  Future<void> begin({
    required String id,
    required String name,
    required String mimeType,
    required int byteCount,
    required DateTime expiresAt,
  }) async {}

  @override
  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  }) async => offset + bytes.length;

  @override
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) async {}

  @override
  Future<bool> save({
    required String id,
    required String name,
    required String mimeType,
  }) async {
    saves++;
    return saveOutcome.future;
  }

  @override
  Future<bool> share({
    required String id,
    required String name,
    required String mimeType,
  }) async => false;

  @override
  Future<bool> cancel(String id) async => true;

  @override
  Future<List<String>> cleanup({
    String? preserve,
    bool includeOffered = false,
  }) async {
    cleanups.add(includeOffered);
    return const [];
  }
}

/// Captures the helper with its live [Ref], the way restore and privacy
/// call into it.
final _prepareForDataChange = Provider<Future<void> Function()>((ref) {
  return () => prepareGeneratedArtifactsForDataChange(ref);
});

Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// The harness's held deletion for exactly [creation], when several are
/// pending at once.
_PendingDiscard _pending(
  _HarnessOperations operations,
  BackupCreation creation,
) => operations.pending.singleWhere(
  (pending) => identical(pending.creation, creation),
);

/// How many transfer cleanups ran through the shared fake gateway.
int _cleanups(FakeArtifactGateway gateway) =>
    gateway.calls.where((call) => call == 'cleanup').length;

final Matcher _throwsWorkBusy = throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    'generated_work_busy',
  ),
);

final Matcher _throwsCleanupFailed = throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    'generated_work_cleanup_failed',
  ),
);

Future<BackupCreation> _creation(
  Directory root,
  String name,
  String sha,
) async {
  final archive = File('${root.path}/$name.vitalbackup');
  await archive.writeAsBytes(Uint8List(16));
  final bytes = await archive.length();
  final inventory = BackupInventory(
    generation: name,
    schemaVersion: 21,
    people: const [BackupPerson(id: 'me', name: 'Me', archived: false)],
    peopleCount: 1,
    recordCount: 4,
    itemCount: 2,
    supportingCount: 1,
    attachmentCount: 3,
    attachmentBytes: 4096,
    attachmentSha256: sha,
    earliestRecord: DateTime.utc(2026, 1, 1),
    latestRecord: DateTime.utc(2026, 10, 20),
  );
  return BackupCreation(
    archive: archive,
    fileName: archive.uri.pathSegments.last,
    byteCount: bytes,
    sha256: sha,
    createdAt: DateTime.utc(2026, 10, 20, 12),
    inventory: inventory,
    summary: inventory.summaryFor(bytes, sha),
  );
}

/// The holder stays mutable so a test can replace the backend and drive the
/// provider's current operations without touching the backup panel itself.
({
  ProviderContainer container,
  FakeArtifactGateway gateway,
  List<BackupOperations> holder,
})
_harness(BackupOperations operations, {ArtifactTransferGateway? transfer}) {
  final holder = <BackupOperations>[operations];
  final gateway = FakeArtifactGateway();
  final container = ProviderContainer(
    overrides: [
      backupOperationsProvider.overrideWith((ref) => holder.single),
      artifactTransferGatewayProvider.overrideWithValue(transfer ?? gateway),
      artifactTransferGateProvider.overrideWithValue(() => true),
      appLockProvider.overrideWith(_TestLock.new),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, gateway: gateway, holder: holder);
}

BackupState _stateOf(ProviderContainer container) =>
    container.read(backupProvider);

/// Reaches a ready panel holding [creation] in one synchronous step.
Future<void> _readyWith(
  ProviderContainer container,
  _HarnessOperations operations,
  BackupCreation creation,
) async {
  operations.nextCreation = creation;
  await container
      .read(backupProvider.notifier)
      .create(password: _password, confirmation: _password);
  final state = _stateOf(container);
  expect(state.phase, BackupPhase.ready, reason: 'setup reached ready');
  expect(identical(state.creation, creation), isTrue);
}

void main() {
  Directory? directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-backup-cleanup-');
  });

  tearDown(() async {
    await directory?.delete(recursive: true);
    directory = null;
  });

  group('staged archive release before a data change', () {
    test('a running UI discard is shared without a second deletion', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: creation);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);

      final notifier = container.read(backupProvider.notifier);
      final uiDiscard = notifier.discard();
      final uiRetry = notifier.discard();
      final prepare = container.read(_prepareForDataChange)();
      await _flush();

      expect(operations.discards, 1, reason: 'one shared deletion only');
      expect(_stateOf(container).phase, BackupPhase.ready);
      expect(
        _cleanups(gateway),
        0,
        reason: 'downstream cleanup waits for the actual deletion',
      );

      operations.held.completion.complete();
      await uiDiscard;
      await uiRetry;
      await prepare;

      expect(operations.discards, 1);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).errorCode, isNull);
      expect(_stateOf(container).creation, isNull);
      expect(_cleanups(gateway), 1);
      expect(gateway.includedOffered, isTrue);
      expect(identical(holder.single, operations), isTrue);
    });

    test('repeated preparation waits for the same deletion', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: creation);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);

      final first = container.read(_prepareForDataChange)();
      await _flush();
      final second = container.read(_prepareForDataChange)();
      await _flush();

      expect(operations.discards, 1, reason: 'no duplicate deletion');
      expect(_cleanups(gateway), 0, reason: 'nothing proceeds early');

      operations.held.completion.complete();
      await first;
      // The second caller shared the deletion and so cannot proceed early,
      // but cleanup steps cannot run twice at once: it is refused truthfully
      // instead of racing the same cleanup pass.
      await expectLater(second, _throwsWorkBusy);

      expect(operations.discards, 1);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_cleanups(gateway), 1);
      expect(gateway.includedOffered, isTrue);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a failed shared deletion blocks the preparation', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(
        nextCreation: creation,
        discardOutcomes: [true],
      );
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);

      final notifier = container.read(backupProvider.notifier);
      final uiDiscard = notifier.discard();
      final prepare = container.read(_prepareForDataChange)();
      await _flush();
      expect(operations.discards, 1);

      operations.held.completion.complete();
      await expectLater(prepare, _throwsCleanupFailed);
      await uiDiscard;

      expect(_stateOf(container).phase, BackupPhase.ready);
      expect(identical(_stateOf(container).creation, creation), isTrue);
      expect(_stateOf(container).errorCode, 'backup_failed');
      expect(_cleanups(gateway), 0);
      expect(operations.discards, 1);

      // The normal UI retry still works after the failed preparation.
      final retry = notifier.discard();
      operations.held.completion.complete();
      await retry;
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).errorCode, isNull);
      expect(operations.discards, 2);
      expect(_cleanups(gateway), 0);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a deletion started by the preparation fails truthfully', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(
        nextCreation: creation,
        discardOutcomes: [true],
      );
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);

      final prepare = container.read(_prepareForDataChange)();
      await _flush();
      operations.held.completion.complete();
      await expectLater(prepare, _throwsCleanupFailed);

      final state = _stateOf(container);
      expect(state.phase, BackupPhase.ready);
      expect(identical(state.creation, creation), isTrue);
      expect(state.errorCode, 'backup_failed');
      expect(_cleanups(gateway), 0);
      expect(operations.discards, 1);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a late provider replacement never uses the new backend', () async {
      final older = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: older);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, older);

      final replaced = _HarnessOperations(
        nextCreation: await _creation(directory!, 'two', 'b' * 64),
      );
      holder[0] = replaced;
      // Only the operations provider is refreshed; the panel still owns
      // its creation, which was staged by the original backend.
      container.invalidate(backupOperationsProvider);
      expect(container.read(backupOperationsProvider), same(replaced));

      final release = container
          .read(backupProvider.notifier)
          .releaseForDataChange();
      await _flush();
      expect(operations.discards, 1);
      expect(replaced.discards, 0, reason: 'origin backend owns the deletion');

      operations.pending.single.completion.complete();
      expect(await release, BackupRelease.released);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).creation, isNull);
      expect(replaced.discards, 0);
      expect(_cleanups(gateway), 0, reason: 'direct release, not the helper');
    });

    test(
      'a newer attempt survives a shared deletion and blocks preparation',
      () async {
        final older = await _creation(directory!, 'one', 'a' * 64);
        final newer = await _creation(directory!, 'two', 'b' * 64);
        final operations = _HarnessOperations(nextCreation: older);
        final (:container, :gateway, :holder) = _harness(operations);
        await _readyWith(container, operations, older);

        final notifier = container.read(backupProvider.notifier);
        final uiDiscard = notifier.discard();
        final prepare = container.read(_prepareForDataChange)();
        await _flush();

        // Newly owned work appears while the old deletion is still open.
        operations.nextCreation = newer;
        final createGate = Completer<BackupCreation>();
        operations.createGate = createGate;
        final pendingCreate = notifier.create(
          password: _password,
          confirmation: _password,
        );
        createGate.complete(newer);
        await pendingCreate;
        expect(_stateOf(container).phase, BackupPhase.ready);
        expect(identical(_stateOf(container).creation, newer), isTrue);

        operations.held.completion.complete();
        await expectLater(prepare, _throwsWorkBusy);
        await uiDiscard;

        expect(_stateOf(container).phase, BackupPhase.ready);
        expect(identical(_stateOf(container).creation, newer), isTrue);
        expect(_stateOf(container).errorCode, isNull);
        expect(operations.discards, 1);
        expect(_cleanups(gateway), 0);
        expect(identical(holder.single, operations), isTrue);
      },
    );

    test('an active capture is cancelled and preparation refused', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: creation);
      final (:container, :gateway, :holder) = _harness(operations);
      final createGate = Completer<BackupCreation>();
      operations.createGate = createGate;
      final nonce = container.read(backupProvider.notifier);
      final pendingCreate = nonce.create(
        password: _password,
        confirmation: _password,
      );
      await _flush();
      expect(_stateOf(container).phase, BackupPhase.preparing);

      await expectLater(
        container.read(_prepareForDataChange)(),
        _throwsWorkBusy,
      );
      expect(operations.creates, 1);
      expect(operations.discards, 0);
      expect(_cleanups(gateway), 0);

      createGate.complete(creation);
      await _flush();
      expect(operations.discards, 1, reason: 'cancelled capture self-releases');
      operations.pending.single.completion.complete();
      await pendingCreate;
      // The cancelled capture released its own staging artifact once.
      expect(_stateOf(container).phase, BackupPhase.cancelled);
      expect(_stateOf(container).errorCode, 'backup_cancelled');

      // Once idle with nothing owned, preparation succeeds cleanly.
      await container.read(_prepareForDataChange)();
      expect(operations.discards, 1);
      expect(_cleanups(gateway), 1);
      expect(gateway.includedOffered, isTrue);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a busy OS handoff must finish before preparation', () async {
      final transfer = _HeldSaveGateway();
      final operations = _HarnessOperations(
        nextCreation: await _creation(directory!, 'one', 'a' * 64),
      );
      final (:container, :gateway, :holder) = _harness(
        operations,
        transfer: transfer,
      );
      final transferSave = container
          .read(artifactTransferControllerProvider.notifier)
          .save(
            ArtifactSource.bytes(
              Uint8List.fromList([1, 2, 3, 4]),
              kind: ArtifactKind.backup,
              fileName: 'vital-backup.vitalbak',
            ),
          );
      await _flush();
      expect(
        container.read(artifactTransferControllerProvider).busy,
        isTrue,
        reason: 'setup owns a running handoff',
      );

      await expectLater(
        container.read(_prepareForDataChange)(),
        _throwsWorkBusy,
      );
      expect(operations.discards, 0);
      expect(transfer.cleanups, isEmpty);

      // The handoff completes with a saved external copy; only then can
      // generated cleanup run.
      transfer.saveOutcome.complete(true);
      await transferSave;
      expect(transfer.saves, 1);

      await container.read(_prepareForDataChange)();
      expect(operations.discards, 0);
      expect(transfer.cleanups, [true]);
      expect(_cleanups(gateway), 0, reason: 'unused default gateway');
      expect(identical(holder.single, operations), isTrue);
    });

    test('a saved panel blocks nothing and deletes no copy', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: creation);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);

      final archive = creation.archive;
      final before = await archive.readAsBytes();
      await container.read(backupProvider.notifier).save();
      final state = _stateOf(container);
      expect(state.phase, BackupPhase.saved);
      expect(state.savedName, creation.fileName);

      await container.read(_prepareForDataChange)();

      expect(operations.saves, 1);
      expect(operations.discards, 0);
      expect(await archive.exists(), isTrue);
      expect(await archive.readAsBytes(), before);
      expect(_cleanups(gateway), 1);
      expect(gateway.includedOffered, isTrue);
      expect(state.savedName, creation.fileName);
      expect(identical(holder.single, operations), isTrue);
    });

    test('reset-owned cleanup is awaited before downstream cleanup', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: creation);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);

      container.read(backupProvider.notifier).reset();
      expect(operations.discards, 1);

      final prepare = container.read(_prepareForDataChange)();
      await _flush();
      expect(operations.discards, 1, reason: 'reset already owns the delete');
      expect(
        _cleanups(gateway),
        0,
        reason: 'an unsettled reset deletion blocks downstream cleanup',
      );
      // A cleared panel alone is not proof the artifact is gone.
      expect(_stateOf(container).phase, BackupPhase.idle);

      operations.pending.single.completion.complete();
      await prepare;

      expect(_cleanups(gateway), 1);
      expect(gateway.includedOffered, isTrue);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(operations.discards, 1);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a reset-owned deletion failure blocks the preparation', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(
        nextCreation: creation,
        discardOutcomes: [true],
      );
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);

      container.read(backupProvider.notifier).reset();
      final prepare = container.read(_prepareForDataChange)();
      await _flush();
      expect(operations.discards, 1);

      operations.pending.single.completion.complete();
      await expectLater(prepare, _throwsCleanupFailed);

      expect(_cleanups(gateway), 0);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).creation, isNull);
      expect(identical(holder.single, operations), isTrue);

      // The retained failed deletion is retried on its origin operations
      // and only a successful retry releases the data change.
      final retry = container.read(_prepareForDataChange)();
      expect(operations.discards, 2, reason: 'failed cleanup retried');
      expect(identical(operations.pending.single.creation, creation), isTrue);
      operations.pending.single.completion.complete();
      await retry;

      expect(_cleanups(gateway), 1);
      expect(gateway.includedOffered, isTrue);
      expect(operations.discards, 2);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a lock-started deletion failure blocks the preparation', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(
        nextCreation: creation,
        discardOutcomes: [true],
      );
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);

      container.read(appLockProvider.notifier).lock();
      expect(operations.discards, 1);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).creation, isNull);

      final prepare = container.read(_prepareForDataChange)();
      await _flush();
      operations.pending.single.completion.complete();
      await expectLater(prepare, _throwsCleanupFailed);

      expect(_cleanups(gateway), 0);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a rebuild-started deletion failure blocks the preparation', () async {
      final older = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(
        nextCreation: older,
        discardOutcomes: [true],
      );
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, older);

      final replaced = _HarnessOperations(
        nextCreation: await _creation(directory!, 'two', 'b' * 64),
      );
      holder[0] = replaced;
      container.refresh(backupProvider);
      await _flush();
      expect(operations.discards, 1);

      final prepare = container.read(_prepareForDataChange)();
      await _flush();
      expect(_cleanups(gateway), 0, reason: 'drains before downstream work');
      operations.pending.single.completion.complete();
      await expectLater(prepare, _throwsCleanupFailed);

      expect(_cleanups(gateway), 0);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).creation, isNull);

      // The failed deletion stays bound to its origin operations: the
      // replaced backend never deletes anything of this panel.
      final retry = container.read(_prepareForDataChange)();
      expect(operations.discards, 2);
      expect(identical(operations.pending.single.creation, older), isTrue);
      operations.pending.single.completion.complete();
      await retry;

      expect(_cleanups(gateway), 1);
      expect(replaced.discards, 0);
      expect(replaced.pending, isEmpty);
    });

    test('a pending UI discard survives reset and is awaited', () async {
      final creation = await _creation(directory!, 'one', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: creation);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);

      final uiDiscard = container.read(backupProvider.notifier).discard();
      await _flush();
      container.read(backupProvider.notifier).reset();
      await _flush();
      expect(operations.discards, 1, reason: 'reset shares the running one');

      final prepare = container.read(_prepareForDataChange)();
      await _flush();
      expect(_cleanups(gateway), 0, reason: 'waits for the pending deletion');

      operations.pending.single.completion.complete();
      await uiDiscard;
      await prepare;

      expect(_cleanups(gateway), 1);
      expect(gateway.includedOffered, isTrue);
      expect(operations.discards, 1);
      expect(identical(holder.single, operations), isTrue);
    });

    test('superseding work while draining refuses erasure', () async {
      final older = await _creation(directory!, 'one', 'a' * 64);
      final newer = await _creation(directory!, 'two', 'b' * 64);
      final operations = _HarnessOperations(nextCreation: older);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, older);

      container.read(backupProvider.notifier).reset();
      final prepare = container.read(_prepareForDataChange)();
      await _flush();

      operations.nextCreation = newer;
      final createGate = Completer<BackupCreation>();
      operations.createGate = createGate;
      final pendingCreate = container
          .read(backupProvider.notifier)
          .create(password: _password, confirmation: _password);
      createGate.complete(newer);
      await pendingCreate;
      expect(identical(_stateOf(container).creation, newer), isTrue);

      operations.pending.single.completion.complete();
      await expectLater(prepare, _throwsWorkBusy);

      expect(
        identical(_stateOf(container).creation, newer),
        isTrue,
        reason: 'the newer artifact is never erased by old work',
      );
      expect(_cleanups(gateway), 0);
      expect(operations.discards, 1);
      expect(identical(holder.single, operations), isTrue);
    });

    test(
      'a failed older deletion blocks preparation under a newer panel',
      () async {
        final older = await _creation(directory!, 'one', 'a' * 64);
        final newer = await _creation(directory!, 'two', 'b' * 64);
        final operations = _HarnessOperations(
          nextCreation: older,
          discardOutcomes: [true, false, true, false],
        );
        final (:container, :gateway, :holder) = _harness(operations);
        await _readyWith(container, operations, older);

        final uiDiscard = container.read(backupProvider.notifier).discard();
        await _flush();
        operations.nextCreation = newer;
        await container
            .read(backupProvider.notifier)
            .create(password: _password, confirmation: _password);
        expect(identical(_stateOf(container).creation, newer), isTrue);

        _pending(operations, older).completion.complete();
        await uiDiscard;
        expect(operations.discards, 1, reason: 'the older deletion failed');

        final prepare = container.read(_prepareForDataChange)();
        await _flush();
        // The preparation starts the newer deletion and retries the
        // retained failed older deletion on its own origin operations.
        expect(operations.discards, 3);
        _pending(operations, newer).completion.complete();
        expect(
          _cleanups(gateway),
          0,
          reason: 'not enough: the older one is still around',
        );

        _pending(operations, older).completion.complete();
        await expectLater(
          prepare,
          _throwsCleanupFailed,
          reason: 'the retained older deletion failed again, so no cleanup',
        );
        expect(_cleanups(gateway), 0);
        expect(_stateOf(container).phase, BackupPhase.idle);
        expect(_stateOf(container).creation, isNull);

        // One more preparation retries the retained deletion; only its
        // success releases the data change.
        final retry = container.read(_prepareForDataChange)();
        await _flush();
        expect(operations.discards, 4, reason: 'the retained one retries');
        _pending(operations, older).completion.complete();
        await retry;

        expect(_cleanups(gateway), 1);
        expect(gateway.includedOffered, isTrue);
        expect(identical(holder.single, operations), isTrue);
      },
    );

    test(
      'an empty panel releases without touching the archive owner',
      () async {
        final operations = _HarnessOperations(
          nextCreation: await _creation(directory!, 'one', 'a' * 64),
        );
        final (:container, :gateway, :holder) = _harness(operations);
        await container.read(_prepareForDataChange)();

        expect(operations.discards, 0);
        expect(operations.creates, 0);
        expect(_cleanups(gateway), 1);
        expect(gateway.includedOffered, isTrue);
        expect(_stateOf(container).phase, BackupPhase.idle);
        expect(identical(holder.single, operations), isTrue);
      },
    );

    test('a later reset deletion refuses a draining preparation', () async {
      final older = await _creation(directory!, 'old', 'a' * 64);
      final newer = await _creation(directory!, 'new', 'b' * 64);
      final operations = _HarnessOperations(nextCreation: older);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, older);

      final notifier = container.read(backupProvider.notifier);
      notifier.reset();
      final release = notifier.releaseForDataChange();
      operations.nextCreation = newer;
      await notifier.create(password: _password, confirmation: _password);
      notifier.reset();
      expect(
        operations.discards,
        2,
        reason: 'the newer release starts its own deletion',
      );

      _pending(operations, older).completion.complete();
      await _flush();
      expect(
        _cleanups(gateway),
        0,
        reason: 'the newer deletion still blocks downstream cleanup',
      );

      // The drain refuses instead of claiming the newer release safe or
      // discarding it. A later deletion is never pre-consumed or claimed
      // done by the old drain either.
      expect(await release, BackupRelease.busy);

      _pending(operations, newer).completion.complete();
      await _flush();
      // A repeated call may then drain what this one refused.
      expect(await notifier.releaseForDataChange(), BackupRelease.released);

      expect(_cleanups(gateway), 0, reason: 'direct release, not the helper');
      expect(operations.discards, 2);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a save cannot hand off an artifact a deletion owns', () async {
      final creation = await _creation(directory!, 'own', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: creation);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);
      final notifier = container.read(backupProvider.notifier);

      final deletion = notifier.discard();
      await _flush();
      await notifier.save();

      expect(operations.saves, 0, reason: 'the deletion owns the archive');
      expect(_stateOf(container).phase, BackupPhase.ready);
      expect(_stateOf(container).savedName, isNull);

      operations.held.completion.complete();
      await deletion;

      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(operations.discards, 1);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a retained failed deletion blocks a save until retried', () async {
      final creation = await _creation(directory!, 'own', 'a' * 64);
      final operations = _HarnessOperations(
        nextCreation: creation,
        discardOutcomes: [true, false],
      );
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);
      final notifier = container.read(backupProvider.notifier);

      final deletion = notifier.discard();
      operations.held.completion.complete();
      await deletion;
      expect(_stateOf(container).errorCode, 'backup_failed');

      await notifier.save();
      expect(
        operations.saves,
        0,
        reason: 'the failed deletion still owns the archive',
      );
      expect(_stateOf(container).phase, BackupPhase.ready);
      expect(_stateOf(container).savedName, isNull);

      final retry = container.read(_prepareForDataChange)();
      expect(operations.discards, 2, reason: 'the failure is retried');
      operations.pending.single.completion.complete();
      await retry;

      expect(_cleanups(gateway), 1);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a lock defers cleanup until an in-flight save settles', () async {
      final creation = await _creation(directory!, 'lock', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: creation);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, creation);
      final notifier = container.read(backupProvider.notifier);

      operations.saveGate = Completer<BackupSaveStatus>();
      final pendingSave = notifier.save();
      await _flush();
      expect(_stateOf(container).phase, BackupPhase.saving);

      container.read(appLockProvider.notifier).lock();
      await _flush();
      expect(
        operations.discards,
        0,
        reason: 'the OS save still owns the archive',
      );
      expect(_stateOf(container).phase, BackupPhase.idle);

      await expectLater(
        container.read(_prepareForDataChange)(),
        _throwsWorkBusy,
        reason: 'the handoff must finish before a data change',
      );
      expect(_cleanups(gateway), 0);

      operations.saveGate!.complete(BackupSaveStatus.saved);
      await pendingSave;
      await _flush();
      expect(operations.discards, 1, reason: 'the deferred release runs now');

      operations.pending.single.completion.complete();
      await container.read(_prepareForDataChange)();

      expect(_cleanups(gateway), 1);
      expect(gateway.includedOffered, isTrue);
      expect(operations.saves, 1);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(identical(holder.single, operations), isTrue);
    });

    test('a rebuild defers cleanup until an in-flight save settles', () async {
      final older = await _creation(directory!, 'holder', 'a' * 64);
      final operations = _HarnessOperations(nextCreation: older);
      final (:container, :gateway, :holder) = _harness(operations);
      await _readyWith(container, operations, older);
      final notifier = container.read(backupProvider.notifier);

      operations.saveGate = Completer<BackupSaveStatus>();
      final pendingSave = notifier.save();
      await _flush();

      final replaced = _HarnessOperations(
        nextCreation: await _creation(directory!, 'repl', 'b' * 64),
      );
      holder[0] = replaced;
      container.refresh(backupProvider);
      await _flush();
      expect(
        operations.discards,
        0,
        reason: 'the OS save still owns the archive',
      );
      expect(replaced.discards, 0, reason: 'the origin backend keeps cleanup');

      await expectLater(
        container.read(_prepareForDataChange)(),
        _throwsWorkBusy,
      );

      operations.saveGate!.complete(BackupSaveStatus.saved);
      await pendingSave;
      await _flush();
      expect(operations.discards, 1, reason: 'the deferred release runs now');
      expect(replaced.discards, 0);

      operations.pending.single.completion.complete();
      await container.read(_prepareForDataChange)();

      expect(_cleanups(gateway), 1);
      expect(replaced.discards, 0);
      expect(replaced.pending, isEmpty);
      expect(identical(holder.single, replaced), isTrue);
    });

    for (final rebuild in [false, true]) {
      test(
        'a pending capture stays owned after ${rebuild ? 'rebuild' : 'lock'}',
        () async {
          final creation = await _creation(directory!, 'pending', 'a' * 64);
          final operations = _HarnessOperations(
            nextCreation: creation,
            discardOutcomes: [true, false],
          );
          final (:container, :gateway, holder: _) = _harness(operations);
          final createGate = operations.createGate =
              Completer<BackupCreation>();
          final notifier = container.read(backupProvider.notifier);
          final capture = notifier.create(
            password: _password,
            confirmation: _password,
          );
          if (rebuild) {
            container.refresh(backupProvider);
          } else {
            container.read(appLockProvider.notifier).lock();
          }
          expect(_stateOf(container).creation, isNull);
          expect(await notifier.releaseForDataChange(), BackupRelease.busy);
          expect(_cleanups(gateway), 0);

          createGate.complete(creation);
          await capture;
          expect(operations.discards, 1);
          final release = notifier.releaseForDataChange();
          operations.held.completion.complete();
          expect(await release, BackupRelease.failed);
          expect(_cleanups(gateway), 0);

          final retry = notifier.releaseForDataChange();
          expect(operations.discards, 2);
          operations.held.completion.complete();
          expect(await retry, BackupRelease.released);
        },
      );
    }

    test(
      'a cancelled capture cleanup failure blocks the preparation',
      () async {
        final creation = await _creation(directory!, 'cap', 'a' * 64);
        final operations = _HarnessOperations(
          nextCreation: creation,
          discardOutcomes: [true, false],
        );
        final (:container, :gateway, :holder) = _harness(operations);
        final createGate = Completer<BackupCreation>();
        operations.createGate = createGate;
        final pendingCreate = container
            .read(backupProvider.notifier)
            .create(password: _password, confirmation: _password);
        await _flush();
        expect(_stateOf(container).phase, BackupPhase.preparing);

        // The data change cancels the capture and is refused.
        await expectLater(
          container.read(_prepareForDataChange)(),
          _throwsWorkBusy,
        );
        expect(operations.creates, 1);
        expect(operations.discards, 0);

        createGate.complete(creation);
        await _flush();
        expect(
          operations.discards,
          1,
          reason: 'the cancelled capture self-releases through the tracker',
        );

        final prepare = container.read(_prepareForDataChange)();
        await _flush();
        expect(_cleanups(gateway), 0, reason: 'the deletion is unsettled');
        operations.pending.single.completion.complete();
        await expectLater(prepare, _throwsCleanupFailed);

        // The attempt itself still reports cancellation truthfully while the
        // retained failed cleanup blocks erasure for the next release.
        await pendingCreate;
        expect(_stateOf(container).phase, BackupPhase.cancelled);
        expect(_stateOf(container).errorCode, 'backup_cancelled');
        expect(_cleanups(gateway), 0);

        final retry = container.read(_prepareForDataChange)();
        expect(operations.discards, 2, reason: 'the retained failure retries');
        operations.pending.single.completion.complete();
        await retry;

        expect(_cleanups(gateway), 1);
        expect(gateway.includedOffered, isTrue);
        expect(identical(holder.single, operations), isTrue);
      },
    );
  });
}
