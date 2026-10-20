import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/domain/artifact_transfer.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';

void main() {
  testWidgets('protected staging cleanup runs at startup and on resume', (
    tester,
  ) async {
    final gateway = _CleanupGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artifactTransferGatewayProvider.overrideWithValue(gateway),
          artifactTransferGateProvider.overrideWithValue(() => true),
        ],
        child: const ArtifactTransferRuntime(child: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    expect(gateway.cleanups, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(gateway.cleanups, 2);
  });
}

final class _CleanupGateway implements ArtifactTransferGateway {
  int cleanups = 0;

  @override
  ArtifactCapabilities get capabilities =>
      const ArtifactCapabilities(save: true, share: true);

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
  }) async => true;

  @override
  Future<bool> share({
    required String id,
    required String name,
    required String mimeType,
  }) async => true;

  @override
  Future<bool> cancel(String id) async => true;

  @override
  Future<List<String>> cleanup({
    String? preserve,
    bool includeOffered = false,
  }) async {
    cleanups++;
    return const [];
  }
}
