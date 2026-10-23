import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/domain/artifact_transfer.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';

void main() {
  final now = DateTime.utc(2026, 10, 20, 12);
  group('artifact transfer controller', () {
    test('rejected transfers release their adapter-owned source', () async {
      var disposed = 0;
      final gateway = FakeArtifactGateway(
        capabilities: const ArtifactCapabilities(save: false, share: false),
      );
      final container = _container(gateway, now: now);
      final outcome = await container
          .read(artifactTransferControllerProvider.notifier)
          .save(
            ArtifactSource(
              kind: ArtifactKind.generic,
              byteCount: 1,
              openRead: () => Stream.value(Uint8List(1)),
              dispose: () async {
                disposed++;
              },
            ),
          );
      expect(outcome.failed, isTrue);
      expect(disposed, 1);
    });
    for (final duringPublish in [false, true]) {
      test(
        'lock before handoff is rechecked after ${duringPublish ? 'publish' : 'last append'}',
        () async {
          var open = true;
          final gateway = FakeArtifactGateway();
          final container = _container(gateway, now: now, gate: () => open);
          if (duringPublish) {
            gateway.onPublish = () {
              open = false;
            };
          } else {
            gateway.onAppend = (_) {
              open = false;
            };
          }
          final outcome = await container
              .read(artifactTransferControllerProvider.notifier)
              .save(_source([_bytes(8)]));
          expect(outcome.failureCode, 'artifact_transfer_locked');
          expect(gateway.calls, isNot(contains('save')));
          expect(gateway.calls, contains('cancel'));
        },
      );
    }
    test('saves a streamed artifact with bounded progress', () async {
      final gateway = FakeArtifactGateway();
      final container = _container(gateway, now: now);
      final states = <ArtifactTransferState>[];
      container.listen(
        artifactTransferControllerProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      final bytes = _bytes(96 * 1024);
      final outcome = await container
          .read(artifactTransferControllerProvider.notifier)
          .save(
            _source([
              _slice(bytes, 0, 32 * 1024),
              _slice(bytes, 32 * 1024, 64 * 1024),
              _slice(bytes, 64 * 1024, bytes.length),
            ]),
          );

      expect(outcome.completed, isTrue);
      expect(outcome.failureCode, isNull);
      expect(outcome.sha256, sha256.convert(bytes).toString());
      expect(gateway.publishCalled, isTrue);
      expect(gateway.publishedBytes, bytes.length);
      expect(gateway.publishedSha, sha256.convert(bytes).toString());
      expect(gateway.calls.first, 'begin');
      expect(gateway.calls, containsAllInOrder(['publish', 'save', 'cancel']));
      expect(gateway.appendOffsets, [0, 32 * 1024, 64 * 1024]);
      expect(
        states.where(
          (state) =>
              state.phase == ArtifactPhase.staging &&
              state.bytesWritten > 0 &&
              state.bytesWritten < bytes.length,
        ),
        isNotEmpty,
      );
      final last = container.read(artifactTransferControllerProvider);
      expect(last.phase, ArtifactPhase.saved);
      expect(last.kind, ArtifactKind.dataCsv);
      expect(last.progress, 1.0);
      expect(last.retained, isFalse);
    });

    test('a shared receiver keeps the staged copy for its lifetime', () async {
      final gateway = FakeArtifactGateway()..cancelResult = false;
      final container = _container(gateway, now: now);
      final outcome = await container
          .read(artifactTransferControllerProvider.notifier)
          .share(_source([_bytes(8)]));

      expect(outcome.completed, isTrue);
      expect(outcome.retained, isTrue);
      expect(gateway.calls, containsAllInOrder(['share', 'cancel']));
      final state = container.read(artifactTransferControllerProvider);
      expect(state.phase, ArtifactPhase.offered);
      expect(state.retained, isTrue);
    });

    test('a digest mismatch is never published', () async {
      final gateway = FakeArtifactGateway();
      final container = _container(gateway, now: now);
      final source = ArtifactSource(
        kind: ArtifactKind.dataCsv,
        byteCount: 3,
        expectedSha256: '0' * 64,
        openRead: () => Stream.value(Uint8List.fromList([1, 2, 3])),
      );
      final outcome = await container
          .read(artifactTransferControllerProvider.notifier)
          .save(source);

      expect(outcome.failed, isTrue);
      expect(outcome.failureCode, 'artifact_transfer_integrity');
      expect(gateway.publishCalled, isFalse);
      expect(gateway.calls, contains('cancel'));
      expect(
        container.read(artifactTransferControllerProvider).phase,
        ArtifactPhase.failed,
      );
    });

    test(
      'a short producer stream is incomplete, not a saved artifact',
      () async {
        final gateway = FakeArtifactGateway();
        final container = _container(gateway, now: now);
        final source = ArtifactSource(
          kind: ArtifactKind.dataJson,
          byteCount: 100,
          openRead: () => Stream.value(Uint8List(50)),
        );
        final outcome = await container
            .read(artifactTransferControllerProvider.notifier)
            .save(source);

        expect(outcome.failureCode, 'artifact_transfer_incomplete');
        expect(gateway.publishCalled, isFalse);
        expect(gateway.calls, contains('cancel'));
      },
    );

    test('cooperative cancellation stops before publication', () async {
      final gateway = FakeArtifactGateway();
      final container = _container(gateway, now: now);
      late ArtifactTransferController controller;
      gateway.onAppend = (offset) {
        if (offset == 0) controller.cancel();
      };
      controller = container.read(artifactTransferControllerProvider.notifier);
      final bytes = _bytes(64 * 1024);
      final outcome = await controller.save(
        _source([
          _slice(bytes, 0, 32 * 1024),
          _slice(bytes, 32 * 1024, bytes.length),
        ]),
      );

      expect(outcome.cancelled, isTrue);
      expect(outcome.failed, isFalse);
      expect(gateway.publishCalled, isFalse);
      expect(gateway.calls, contains('cancel'));
      expect(
        container.read(artifactTransferControllerProvider).phase,
        ArtifactPhase.cancelled,
      );
    });

    test('losing the unlock gate stops protected staging', () async {
      var open = true;
      final gateway = FakeArtifactGateway();
      final container = _container(gateway, now: now, gate: () => open);
      gateway.onAppend = (offset) {
        if (offset == 0) open = false;
      };
      final outcome = await container
          .read(artifactTransferControllerProvider.notifier)
          .save(_source([_bytes(32 * 1024), _bytes(32 * 1024)]));

      expect(outcome.failureCode, 'artifact_transfer_locked');
      expect(gateway.publishCalled, isFalse);
      expect(gateway.calls, contains('cancel'));
    });

    test('a second handoff is rejected while one is staged', () async {
      final gateway = FakeArtifactGateway();
      final blocker = Completer<void>();
      gateway.onAppend = (_) => blocker.future;
      final container = _container(gateway, now: now);
      final controller = container.read(
        artifactTransferControllerProvider.notifier,
      );
      final first = controller.save(_source([_bytes(8)]));
      await Future<void>.delayed(Duration.zero);
      final second = await controller.save(_source([_bytes(8)]));
      expect(second.failureCode, 'artifact_transfer_busy');
      expect(gateway.calls.where((call) => call == 'begin'), hasLength(1));
      expect(await controller.discardAll(), isFalse);
      expect(gateway.calls, isNot(contains('cleanup')));
      blocker.complete();
      expect((await first).completed, isTrue);
    });

    test('unsupported capability fails before staging', () async {
      final gateway = FakeArtifactGateway(
        capabilities: const ArtifactCapabilities(save: false, share: false),
      );
      final container = _container(gateway, now: now);
      final controller = container.read(
        artifactTransferControllerProvider.notifier,
      );
      expect(
        (await controller.save(_source([_bytes(8)]))).failureCode,
        'artifact_transfer_save_unavailable',
      );
      expect(
        (await controller.share(_source([_bytes(8)]))).failureCode,
        'artifact_transfer_share_unavailable',
      );
      expect(gateway.calls, isEmpty);
    });

    test(
      'discardAll removes every staged copy including offered shares',
      () async {
        final gateway = FakeArtifactGateway();
        final container = _container(gateway, now: now);
        final controller = container.read(
          artifactTransferControllerProvider.notifier,
        );
        expect(await controller.discardAll(), isTrue);
        expect(gateway.calls, ['cleanup']);
        expect(gateway.includedOffered, isTrue);
        expect(
          container.read(artifactTransferControllerProvider).phase,
          ArtifactPhase.idle,
        );
      },
    );

    test('maintenance reclaims staging and reports a real failure', () async {
      final gateway = FakeArtifactGateway();
      final container = _container(gateway, now: now);
      final controller = container.read(
        artifactTransferControllerProvider.notifier,
      );
      await controller.maintenance();
      expect(gateway.calls, ['cleanup']);
      gateway.cleanupFailure = const ArtifactFailure(
        'artifact_transfer_storage',
      );
      await controller.maintenance();
      expect(
        container.read(artifactTransferControllerProvider).failureCode,
        'artifact_transfer_storage',
      );
      gateway.cleanupFailure = null;
      await controller.maintenance();
      expect(
        container.read(artifactTransferControllerProvider).failureCode,
        isNull,
      );
    });

    test('a transfer waits for startup cleanup before staging', () async {
      final gateway = FakeArtifactGateway();
      final cleanupStarted = Completer<void>();
      final cleanupDone = Completer<void>();
      gateway.onCleanup = () {
        cleanupStarted.complete();
        return cleanupDone.future;
      };
      final container = _container(gateway, now: now);
      final controller = container.read(
        artifactTransferControllerProvider.notifier,
      );
      final maintenance = controller.maintenance();
      await cleanupStarted.future;
      final transfer = controller.save(_source([_bytes(8)]));
      await Future<void>.delayed(Duration.zero);
      expect(gateway.calls, ['cleanup']);
      cleanupDone.complete();
      await maintenance;
      expect((await transfer).completed, isTrue);
      expect(gateway.calls, containsAllInOrder(['cleanup', 'begin']));
    });

    test('maintenance stays locked out until the records open', () async {
      var open = false;
      final gateway = FakeArtifactGateway();
      final container = _container(gateway, now: now, gate: () => open);
      final controller = container.read(
        artifactTransferControllerProvider.notifier,
      );
      await controller.maintenance();
      expect(gateway.calls, isEmpty);
      open = true;
      await controller.maintenance();
      expect(gateway.calls, ['cleanup']);
      expect(gateway.preserved, isNull);
    });

    test('the adapter-owned source is disposed exactly once', () async {
      var disposed = 0;
      final gateway = FakeArtifactGateway();
      final container = _container(gateway, now: now);
      final source = ArtifactSource(
        kind: ArtifactKind.summaryPdf,
        byteCount: 3,
        openRead: () => Stream.value(Uint8List.fromList([1, 2, 3])),
        dispose: () async => disposed++,
      );
      await container
          .read(artifactTransferControllerProvider.notifier)
          .save(source);
      expect(disposed, 1);
    });
  });
}

ArtifactSource _source(List<Uint8List> chunks) {
  final bytes = chunks.expand((chunk) => chunk).toList();
  return ArtifactSource(
    kind: ArtifactKind.dataCsv,
    byteCount: bytes.length,
    expectedSha256: sha256.convert(bytes).toString(),
    openRead: () => Stream.fromIterable(chunks),
  );
}

Uint8List _bytes(int length) =>
    Uint8List.fromList(List.generate(length, (index) => index % 251));

Uint8List _slice(Uint8List bytes, int start, int end) =>
    Uint8List.sublistView(bytes, start, end);

ProviderContainer _container(
  FakeArtifactGateway gateway, {
  required DateTime now,
  bool Function()? gate,
}) {
  final container = ProviderContainer(
    overrides: [
      artifactTransferGatewayProvider.overrideWithValue(gateway),
      artifactTransferClockProvider.overrideWithValue(() => now),
      artifactTransferGateProvider.overrideWithValue(gate ?? () => true),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

final class FakeArtifactGateway implements ArtifactTransferGateway {
  FakeArtifactGateway({
    this.capabilities = const ArtifactCapabilities(save: true, share: true),
  });
  @override
  ArtifactCapabilities capabilities;
  final calls = <String>[];
  final appendOffsets = <int>[];
  FutureOr<void> Function(int offset)? onAppend;
  FutureOr<void> Function()? onPublish;
  bool publishCalled = false;
  int? publishedBytes;
  String? publishedSha;
  bool cancelResult = true;
  bool saveResult = true;
  bool shareResult = true;
  Object? cleanupFailure;
  FutureOr<void> Function()? onCleanup;
  String? preserved;
  bool? includedOffered;
  String? begunName;
  String? begunMimeType;

  @override
  Future<void> begin({
    required String id,
    required String name,
    required String mimeType,
    required int byteCount,
    required DateTime expiresAt,
  }) async {
    calls.add('begin');
    begunName = name;
    begunMimeType = mimeType;
  }

  @override
  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  }) async {
    calls.add('append');
    appendOffsets.add(offset);
    await onAppend?.call(offset);
    return offset + bytes.length;
  }

  @override
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) async {
    calls.add('publish');
    publishCalled = true;
    publishedBytes = byteCount;
    publishedSha = sha256;
    await onPublish?.call();
  }

  @override
  Future<bool> save({
    required String id,
    required String name,
    required String mimeType,
  }) async {
    calls.add('save');
    return saveResult;
  }

  @override
  Future<bool> share({
    required String id,
    required String name,
    required String mimeType,
  }) async {
    calls.add('share');
    return shareResult;
  }

  @override
  Future<bool> cancel(String id) async {
    calls.add('cancel');
    return cancelResult;
  }

  @override
  Future<List<String>> cleanup({
    String? preserve,
    bool includeOffered = false,
  }) async {
    calls.add('cleanup');
    preserved = preserve;
    includedOffered = includeOffered;
    await onCleanup?.call();
    final failure = cleanupFailure;
    if (failure != null) throw failure;
    return const [];
  }
}
