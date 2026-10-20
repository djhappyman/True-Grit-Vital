import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/app/exports.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/supporting/supporting.dart';

import 'artifact_transfer_controller_test.dart' show FakeArtifactGateway;

void main() {
  late ProviderContainer container;
  late FakeArtifactGateway gateway;
  late ExportArtifact artifact;
  setUp(() {
    gateway = FakeArtifactGateway();
    container = ProviderContainer(
      overrides: [
        artifactTransferGatewayProvider.overrideWithValue(gateway),
        artifactTransferGateProvider.overrideWithValue(() => true),
      ],
    );
    artifact = ExportArtifact.build(
      ExportDocument(
        selection: ExportSelection(
          personId: meId,
          fromDay: CivilDate(2026, 10, 1),
          beforeDay: CivilDate(2026, 11, 1),
          zoneId: 'UTC',
          contents: const [ExportContent.doses],
        ),
        generatedAt: DateTime.utc(2026, 10, 20),
        personName: 'Synthetic adult',
        doses: const [],
        supporting: const [],
      ),
    );
  });
  tearDown(() => container.dispose());

  test(
    'default export adapter stages the exact reviewed file and checksum',
    () async {
      final progress = <double>[];
      final result = await container
          .read(exportHandoffProvider)
          .deliver(artifact, onProgress: progress.add);
      expect(result, ExportDelivery.saved);
      expect(gateway.begunName, artifact.fileName);
      expect(gateway.publishedBytes, artifact.byteCount);
      expect(gateway.publishedSha, artifact.sha256);
      expect(progress.last, 1);
    },
  );

  test('export cancellation stops staging before destination opens', () async {
    final token = ExportCancellation();
    gateway.onAppend = (_) => token.cancel();
    final result = await container
        .read(exportHandoffProvider)
        .deliver(artifact, cancellation: token);
    expect(result, ExportDelivery.cancelled);
    expect(gateway.calls, isNot(contains('save')));
    expect(gateway.calls, contains('cancel'));
  });
}
