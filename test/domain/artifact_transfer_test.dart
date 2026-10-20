import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/artifact_transfer.dart';

void main() {
  group('artifact naming and media contract', () {
    test('every kind has a neutral name and a matching media type', () {
      expect(ArtifactKind.summaryPdf.neutralName, 'vital-summary.pdf');
      expect(ArtifactKind.summaryPdf.mimeType, 'application/pdf');
      expect(ArtifactKind.dataJson.neutralName, 'vital-export.json');
      expect(ArtifactKind.dataJson.mimeType, 'application/json');
      expect(ArtifactKind.dataCsv.neutralName, 'vital-export.csv');
      expect(ArtifactKind.dataCsv.mimeType, 'text/csv');
      expect(ArtifactKind.backup.neutralName, 'vital-backup.vitalbak');
      expect(ArtifactKind.backup.mimeType, 'application/octet-stream');
      expect(ArtifactKind.generic.neutralName, 'vital-artifact.bin');
      for (final kind in ArtifactKind.values) {
        expect(() => artifactNeutralName(kind.neutralName), returnsNormally);
        expect(() => artifactMimeType(kind.mimeType), returnsNormally);
        expect(kind.neutralName, isNot(contains(' ')));
      }
    });

    test('hostile names, identities and media types fail closed', () {
      for (final name in [
        '',
        '../alice.pdf',
        'alice..pdf',
        '/tmp/alice.pdf',
        'Alice Report.pdf',
        '${'a' * 81}.pdf',
      ]) {
        expect(
          () => artifactNeutralName(name),
          throwsA(_failure('artifact_transfer_input')),
          reason: name,
        );
      }
      for (final id in ['', '../one', 'one/two', 'one two']) {
        expect(
          () => artifactIdentity(id),
          throwsA(_failure('artifact_transfer_identity')),
          reason: id,
        );
      }
      for (final mime in ['', 'pdf', 'application', 'application/pdf; x=1']) {
        expect(
          () => artifactMimeType(mime),
          throwsA(_failure('artifact_transfer_input')),
          reason: mime,
        );
      }
      expect(
        () => artifactDigest('ABC'),
        throwsA(_failure('artifact_transfer_input')),
      );
    });
  });

  group('artifact source', () {
    test('bytes source bounds the input and computes its digest', () {
      final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 251));
      final source = ArtifactSource.bytes(bytes, kind: ArtifactKind.dataCsv);
      expect(source.byteCount, 4096);
      // Transfer hashes while streaming; the bytes factory does not block the
      // caller with a second full pass.
      expect(source.expectedSha256, isNull);
      expect(source.kind.mimeType, 'text/csv');
      expect(
        () => ArtifactSource.bytes(Uint8List(0), kind: ArtifactKind.generic),
        throwsA(_failure('artifact_transfer_input')),
      );
      expect(
        () => ArtifactSource(
          kind: ArtifactKind.dataJson,
          byteCount: 0,
          openRead: () => const Stream.empty(),
        ),
        throwsA(_failure('artifact_transfer_input')),
      );
      expect(
        () => ArtifactSource(
          kind: ArtifactKind.dataJson,
          byteCount: ArtifactLimits.maxBytes + 1,
          openRead: () => const Stream.empty(),
        ),
        throwsA(_failure('artifact_transfer_input')),
      );
      expect(
        () => ArtifactSource(
          kind: ArtifactKind.dataJson,
          byteCount: 4,
          expectedSha256: 'not-a-digest',
          openRead: () => const Stream.empty(),
        ),
        throwsA(_failure('artifact_transfer_input')),
      );
    });

    test('file source captures length without loading the file', () async {
      final directory = await Directory.systemTemp.createTemp('artifact-src-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/synthetic.bin');
      await file.writeAsBytes(List.generate(1024 * 96, (i) => i % 127));
      final source = await ArtifactSource.file(file, kind: ArtifactKind.backup);
      expect(source.byteCount, 1024 * 96);
      expect(source.expectedSha256, isNull);
      var total = 0;
      await for (final chunk in source.openRead()) {
        total += chunk.length;
      }
      expect(total, source.byteCount);
    });
  });

  group('bounded chunks', () {
    test('splits oversized producer chunks at the native bound', () async {
      final bytes = Uint8List.fromList(
        List.generate(ArtifactLimits.chunkBytes * 2 + 5, (i) => i % 251),
      );
      final chunks = await boundedArtifactChunks(
        Stream.value(bytes),
        byteCount: bytes.length,
      ).toList();
      expect(chunks.map((chunk) => chunk.length), [
        ArtifactLimits.chunkBytes,
        ArtifactLimits.chunkBytes,
        5,
      ]);
      expect(chunks.expand((chunk) => chunk).toList(), bytes);
    });

    test('rejects overlong and empty-only streams truthfully', () async {
      await expectLater(
        boundedArtifactChunks(
          Stream.value(Uint8List(16)),
          byteCount: 8,
        ).toList(),
        throwsA(_failure('artifact_transfer_incomplete')),
      );
      expect(
        await boundedArtifactChunks(
          Stream.fromIterable([<int>[], <int>[]]),
          byteCount: 8,
        ).toList(),
        isEmpty,
      );
    });
  });

  group('lifetime and state', () {
    final now = DateTime.utc(2026, 10, 20, 12);
    test('lifetime is exactly one bounded day', () {
      final expires = artifactLifetimeFrom(now);
      expect(expires, now.add(ArtifactLimits.lifetime));
      expect(() => artifactExpiry(now, expires), returnsNormally);
      expect(
        () => artifactExpiry(now, now.subtract(const Duration(seconds: 1))),
        throwsA(_failure('artifact_transfer_input')),
      );
      expect(
        () => artifactExpiry(now, now.add(ArtifactLimits.lifetime * 2)),
        throwsA(_failure('artifact_transfer_input')),
      );
      expect(
        () => artifactExpiry(DateTime(2026, 10, 20, 12), expires),
        throwsA(_failure('artifact_transfer_input')),
      );
    });

    test('progress is bounded and only active phases are busy', () {
      const idle = ArtifactTransferState();
      expect(idle.busy, isFalse);
      expect(idle.progress, isNull);
      const staging = ArtifactTransferState(
        phase: ArtifactPhase.staging,
        byteCount: 200,
        bytesWritten: 50,
      );
      expect(staging.busy, isTrue);
      expect(staging.progress, 0.25);
      expect(staging.copy(bytesWritten: 400).progress, 1.0);
      expect(
        const ArtifactTransferState(
          phase: ArtifactPhase.saved,
          byteCount: 10,
          bytesWritten: 10,
        ).busy,
        isFalse,
      );
    });

    test('outcomes distinguish failure, cancellation and completion', () {
      expect(const ArtifactTransferOutcome.failure('x').failed, isTrue);
      expect(const ArtifactTransferOutcome.cancelled().cancelled, isTrue);
      const done = ArtifactTransferOutcome(completed: true, retained: true);
      expect(done.failed, isFalse);
      expect(done.retained, isTrue);
    });
  });
}

Matcher _failure(String code) =>
    isA<ArtifactFailure>().having((error) => error.code, 'code', code);
