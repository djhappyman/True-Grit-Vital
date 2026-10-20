import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/backup.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

const _password = 'a long enough password';

final class _TestLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  @override
  void lock() => state = state.copy(locked: true);
}

/// A deletion started by the controller but held open so the test can decide
/// the outcome after newer lifecycle events have happened.
final class _PendingDiscard {
  _PendingDiscard(this.creation, {required this.fails});
  final BackupCreation creation;
  final bool fails;
  final Completer<void> completion = Completer<void>();
}

/// Deterministic [BackupOperations]: deletions are held open in [pending]
/// until the test completes or fails them, without timers or sleeps.
final class _LifecycleOperations implements BackupOperations {
  _LifecycleOperations({
    required this.nextCreation,
    this.discardOutcomes = const [],
  });

  /// Creation handed back by the next [createBackup]; set [createGate] when
  /// the create must stay observable while an old discard is still pending.
  BackupCreation nextCreation;
  Completer<BackupCreation>? createGate;
  int creates = 0, discards = 0;
  final List<_PendingDiscard> pending = [];
  List<bool> discardOutcomes;

  _PendingDiscard takePending() {
    expect(pending, hasLength(1), reason: 'exactly one held discard expected');
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
    return held.completion.future;
  }

  @override
  Future<BackupSaveStatus> save(BackupCreation creation) async =>
      BackupSaveStatus.saved;

  @override
  Future<StagedBackup> validateArchive({
    required File archive,
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) async => throw UnsupportedError('not used by this controller test');

  @override
  Future<void> cleanupAbandoned() async {}
}

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

// The holder stays mutable so a test can replace the backend and drive a
// real provider rebuild through an explicit refresh.
({ProviderContainer container, List<BackupOperations> holder}) _harness(
  BackupOperations initial,
) {
  final holder = <BackupOperations>[initial];
  final container = ProviderContainer(
    overrides: [
      backupOperationsProvider.overrideWith((ref) => holder.single),
      appLockProvider.overrideWith(_TestLock.new),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, holder: holder);
}

BackupState _stateOf(ProviderContainer container) =>
    container.read(backupProvider);

BackupController _controllerOf(ProviderContainer container) =>
    container.read(backupProvider.notifier);

/// Reaches a ready panel holding [creation] in one synchronous step.
Future<void> _readyWith(
  ProviderContainer container,
  BackupCreation creation,
) async {
  final operations =
      container.read(backupOperationsProvider) as _LifecycleOperations;
  operations.nextCreation = creation;
  await _controllerOf(container)
      .create(password: _password, confirmation: _password);
  final state = _stateOf(container);
  expect(state.phase, BackupPhase.ready, reason: 'setup reached ready');
  expect(identical(state.creation, creation), isTrue);
}

void main() {
  Directory? directory;
  BackupCreation? older, newer;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-backup-discard-');
    older = await _creation(directory!, 'backup-one', 'a' * 64);
    newer = await _creation(directory!, 'backup-two', 'b' * 64);
  });

  tearDown(() async {
    await directory?.delete(recursive: true);
    directory = null;
  });

  group('delayed old discard against newer panel work', () {
    test('delayed success cannot clear a newer create', () async {
      final operations = _LifecycleOperations(nextCreation: older!);
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final oldDiscard = _controllerOf(container).discard();
      final held = operations.takePending();

      // A newer create starts while the old deletion is still open. The ready
      // panel is not busy, so this is reachable through the controller API.
      operations.nextCreation = newer!;
      await _controllerOf(container)
          .create(password: _password, confirmation: _password);
      expect(_stateOf(container).phase, BackupPhase.ready);
      expect(identical(_stateOf(container).creation, newer), isTrue);

      held.completion.complete();
      await oldDiscard;

      expect(
        identical(_stateOf(container).creation, newer),
        isTrue,
        reason: 'the old discard must not drop the newer attempt',
      );
      expect(_stateOf(container).phase, BackupPhase.ready);
      expect(_stateOf(container).errorCode, isNull);
    });

    test('delayed failure cannot corrupt a newer creating attempt', () async {
      final operations = _LifecycleOperations(
        nextCreation: older!,
        discardOutcomes: [true],
      );
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final oldDiscard = _controllerOf(container).discard();
      final held = operations.takePending();

      // Hold the new create so its preparing state is observable while the
      // old deletion finishes.
      operations.nextCreation = newer!;
      final createGate = Completer<BackupCreation>();
      operations.createGate = createGate;
      final pendingCreate = _controllerOf(container)
          .create(password: _password, confirmation: _password);
      expect(_stateOf(container).phase, BackupPhase.preparing);

      held.completion.completeError(const BackupFailure('backup_failed'));
      await oldDiscard;

      expect(_stateOf(container).errorCode, isNull);
      expect(_stateOf(container).phase, BackupPhase.preparing);

      createGate.complete(newer);
      await pendingCreate;
      expect(_stateOf(container).phase, BackupPhase.ready);
      expect(identical(_stateOf(container).creation, newer), isTrue);
    });

    test('delayed success cannot clear a newer save', () async {
      final operations = _LifecycleOperations(nextCreation: older!);
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final oldDiscard = _controllerOf(container).discard();
      operations.takePending();

      await _controllerOf(container).save();
      expect(_stateOf(container).phase, BackupPhase.saved);
      expect(_stateOf(container).savedName, older!.fileName);

      operations.pending.single.completion.complete();
      await oldDiscard;

      expect(_stateOf(container).phase, BackupPhase.saved);
      expect(_stateOf(container).savedName, older!.fileName);
    });

    test('delayed failure cannot resurrect the form after reset', () async {
      final operations = _LifecycleOperations(
        nextCreation: older!,
        discardOutcomes: [true],
      );
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final oldDiscard = _controllerOf(container).discard();
      operations.takePending();

      _controllerOf(container).reset();
      expect(_stateOf(container).phase, BackupPhase.idle);

      operations.pending.single.completion.completeError(
        const BackupFailure('backup_failed'),
      );
      await oldDiscard;

      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).errorCode, isNull);
      expect(_stateOf(container).creation, isNull);
    });

    test('delayed success after reset stays cleared', () async {
      final operations = _LifecycleOperations(nextCreation: older!);
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final oldDiscard = _controllerOf(container).discard();
      operations.takePending();
      _controllerOf(container).reset();

      operations.pending.single.completion.complete();
      await oldDiscard;

      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).errorCode, isNull);
    });
  });

  group('replacement and lock cleanup', () {
    test(
      'replacement releases the held creation on its origin operations',
      () async {
        final operations = _LifecycleOperations(nextCreation: older!);
        final (:container, holder: holder) = _harness(operations);
        await _readyWith(container, older!);

        final replaced = _LifecycleOperations(nextCreation: newer!);
        holder[0] = replaced;
        // Refresh flushes the rebuild immediately; no timer or sleep needed.
        container.refresh(backupProvider);

        // The held staging artifact is not silently leaked: its originating
        // operations clean it up, and the replacement deletes nothing.
        final cleanup = operations.pending.single;
        expect(operations.discards, 1);
        expect(identical(cleanup.creation, older), isTrue);
        expect(replaced.discards, 0);

        cleanup.completion.complete();
        expect(_stateOf(container).phase, BackupPhase.idle);
        expect(_stateOf(container).creation, isNull);
      },
    );

    test('replacement skips a discard that is already running', () async {
      final operations = _LifecycleOperations(nextCreation: older!);
      final (:container, holder: holder) = _harness(operations);
      await _readyWith(container, older!);

      final oldDiscard = _controllerOf(container).discard();
      final held = operations.takePending();

      final replaced = _LifecycleOperations(nextCreation: newer!);
      holder[0] = replaced;
      expect(operations.discards, 1);
      container.refresh(backupProvider);

      // No duplicate deletion raced out of the rebuild.
      expect(operations.discards, 1, reason: 'no duplicate deletion');
      expect(replaced.pending, isEmpty);

      held.completion.complete();
      await oldDiscard;

      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).errorCode, isNull);
    });

    test('lock discards the held creation on its origin operations', () async {
      final operations = _LifecycleOperations(nextCreation: older!);
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      container.read(appLockProvider.notifier).lock();

      final cleanup = operations.pending.single;
      expect(identical(cleanup.creation, older), isTrue);
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).creation, isNull);

      cleanup.completion.complete();
      expect(_stateOf(container).phase, BackupPhase.idle);
    });

    test('lock does not duplicate an already running discard', () async {
      final operations = _LifecycleOperations(nextCreation: older!);
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final oldDiscard = _controllerOf(container).discard();
      final held = operations.takePending();

      container.read(appLockProvider.notifier).lock();

      expect(operations.discards, 1, reason: 'repeated deletion is a defect');
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).creation, isNull);

      held.completion.complete();
      await oldDiscard;

      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).errorCode, isNull);
    });

    test('delayed failure after lock stays cleared', () async {
      final operations = _LifecycleOperations(
        nextCreation: older!,
        discardOutcomes: [true],
      );
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final oldDiscard = _controllerOf(container).discard();
      final held = operations.takePending();

      container.read(appLockProvider.notifier).lock();

      held.completion.completeError(const BackupFailure('backup_failed'));
      await oldDiscard;

      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).errorCode, isNull);
      expect(_stateOf(container).creation, isNull);
    });
  });

  group('repeated and retried discard', () {
    test('repeated discard taps issue one deletion', () async {
      final operations = _LifecycleOperations(nextCreation: older!);
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final first = _controllerOf(container).discard();
      operations.takePending();
      // The second request arrives while the first deletion is held open.
      final second = _controllerOf(container).discard();
      expect(operations.discards, 1);

      operations.pending.single.completion.complete();
      await first;
      await second;
      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(operations.discards, 1);
    });

    test('a failed discard is truthful and retryable', () async {
      final operations = _LifecycleOperations(nextCreation: older!);
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final first = _controllerOf(container).discard();
      final held = operations.takePending();
      held.completion.completeError(const BackupFailure('backup_failed'));
      await first;

      expect(_stateOf(container).phase, BackupPhase.ready);
      expect(_stateOf(container).errorCode, 'backup_failed');
      expect(identical(_stateOf(container).creation, older), isTrue);

      final second = _controllerOf(container).discard();
      final retry = operations.pending.single;
      expect(operations.discards, 2);
      expect(identical(retry.creation, older), isTrue);
      retry.completion.complete();
      await second;

      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).creation, isNull);
      expect(_stateOf(container).errorCode, isNull);
    });

    test('an uneventful discard returns the create form', () async {
      final operations = _LifecycleOperations(nextCreation: older!);
      final (:container, holder: _) = _harness(operations);
      await _readyWith(container, older!);

      final oldDiscard = _controllerOf(container).discard();
      operations.takePending();
      operations.pending.single.completion.complete();
      await oldDiscard;

      expect(_stateOf(container).phase, BackupPhase.idle);
      expect(_stateOf(container).creation, isNull);
      expect(_stateOf(container).errorCode, isNull);
      expect(operations.discards, 1);
    });
  });
}
