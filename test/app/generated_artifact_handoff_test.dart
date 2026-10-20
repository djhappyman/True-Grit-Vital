import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/app/backup.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/domain/artifact_transfer.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

import 'artifact_transfer_controller_test.dart' show FakeArtifactGateway;

void main() {
  late ProviderContainer container;
  late FakeArtifactGateway gateway;
  late Directory directory;
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  late ReportArtifact report;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-handoff-test-');
    gateway = FakeArtifactGateway();
    container = ProviderContainer(
      overrides: [
        artifactTransferGatewayProvider.overrideWithValue(gateway),
        artifactTransferGateProvider.overrideWithValue(() => true),
      ],
    );
    report = ReportArtifact(
      selectionIdentity: 'selection',
      artifactId: 'artifact',
      templateId: 'R01',
      templateVersion: '1.0',
      templateTitle: 'Substance summary',
      personName: 'Synthetic adult',
      periodText: '2026-10-01 to 2026-10-20',
      generatedAt: DateTime.utc(2026, 10, 20),
      bytes: bytes,
      text: 'Reviewed structured text',
      fileName: 'vital-summary.pdf',
      textFileName: 'vital-summary.txt',
      pageCount: 1,
      sha256: sha256.convert(bytes).toString(),
      fontsEmbedded: true,
      use24Hour: true,
    );
  });
  tearDown(() async {
    container.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'report save preserves the exact PDF and text hashes and filenames',
    () async {
      final handoff = container.read(reportArtifactGatewayProvider);
      expect(
        (await handoff.save(report)).outcome,
        ReportHandoffOutcome.completed,
      );
      expect(gateway.publishedSha, report.sha256);
      expect(gateway.begunName, report.fileName);
      expect(
        (await handoff.save(report, asText: true)).outcome,
        ReportHandoffOutcome.completed,
      );
      expect(gateway.publishedSha, sha256.convert(report.textBytes).toString());
      expect(gateway.begunName, report.textFileName);
    },
  );

  test('report share says offered without asserting receipt', () async {
    final result = await container
        .read(reportArtifactGatewayProvider)
        .share(report);
    expect(result.outcome, ReportHandoffOutcome.offered);
    expect(result.completed, isFalse);
  });

  Future<BackupArtifact> backup() async {
    final file = File('${directory.path}/backup.vitalbackup');
    await file.writeAsBytes(bytes);
    return BackupArtifact(
      file: file,
      name: 'backup.vitalbackup',
      byteCount: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      createdAt: DateTime.utc(2026),
    );
  }

  test('backup adapter streams and verifies the reviewed archive', () async {
    final artifact = await backup();
    expect(
      await container.read(backupDestinationProvider).save(artifact),
      BackupSaveStatus.saved,
    );
    expect(gateway.publishedSha, artifact.sha256);
    expect(gateway.begunName, artifact.name);
    expect(
      await artifact.file.exists(),
      isTrue,
      reason: 'Service owns source cleanup',
    );
  });

  test('changed backup bytes never reach the destination', () async {
    final artifact = await backup();
    await artifact.file.writeAsBytes([4, 3, 2, 1]);
    await expectLater(
      container.read(backupDestinationProvider).save(artifact),
      throwsA(isA<BackupFailure>()),
    );
    expect(gateway.calls, isNot(contains('save')));
    expect(await artifact.file.exists(), isTrue);
  });

  test('backup respects the actual host save ceiling before staging', () async {
    gateway.capabilities = const ArtifactCapabilities(
      save: true,
      share: false,
      maxBytes: 2,
    );
    final artifact = await backup();
    await expectLater(
      container.read(backupDestinationProvider).save(artifact),
      throwsA(
        isA<BackupFailure>().having((e) => e.code, 'code', 'backup_save_limit'),
      ),
    );
    expect(gateway.calls, isEmpty);
  });
}
