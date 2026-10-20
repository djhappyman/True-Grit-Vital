import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/exports.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/supporting/supporting.dart';

class TestLock extends AppLockController {
  @override
  AppLockState build() =>
      const AppLockState(ready: true, enabled: true, locked: false);
}

class DelayedHandoff implements ExportHandoff {
  final result = Completer<ExportDelivery>();
  void Function(double)? progress;
  int calls = 0;
  @override
  bool get isAvailable => true;
  @override
  Future<ExportDelivery> deliver(
    ExportArtifact artifact, {
    ExportCancellation? cancellation,
    void Function(double)? onProgress,
  }) {
    calls++;
    progress = onProgress;
    return result.future;
  }
}

ExportSelection selection() => ExportSelection(
  personId: meId,
  fromDay: CivilDate(2026, 10, 1),
  beforeDay: CivilDate(2026, 11, 1),
  zoneId: 'UTC',
  contents: const [ExportContent.doses],
);
ExportDocument document() => ExportDocument(
  selection: selection(),
  generatedAt: DateTime.utc(2026, 10, 20),
  personName: 'Synthetic adult',
  doses: const [],
  supporting: const [],
);

void main() {
  final provider = exportControllerProvider('test');
  late ProviderContainer container;
  late DelayedHandoff handoff;
  setUp(() {
    handoff = DelayedHandoff();
    container = ProviderContainer(
      overrides: [
        appLockProvider.overrideWith(TestLock.new),
        exportCaptureProvider.overrideWithValue(
          (selection, {cancellation}) async => document(),
        ),
        exportHandoffProvider.overrideWithValue(handoff),
      ],
    );
    container.listen(provider, (_, _) {}, fireImmediately: true);
  });
  tearDown(() => container.dispose());

  test('editing discards late destination progress and completion', () async {
    final controller = container.read(provider.notifier);
    await controller.generate(selection());
    final save = controller.save();
    controller.edit();
    handoff.progress!(0.5);
    expect(container.read(provider).artifact, isNull);
    handoff.result.complete(ExportDelivery.saved);
    await save;
    expect(container.read(provider).stage, ExportStage.editing);
    expect(container.read(provider).artifact, isNull);
  });

  test('locking discards late failed destination result', () async {
    final controller = container.read(provider.notifier);
    await controller.generate(selection());
    final save = controller.save();
    container.read(appLockProvider.notifier).lock();
    handoff.result.completeError(StateError('synthetic failure'));
    await save;
    expect(container.read(provider).stage, ExportStage.editing);
    expect(container.read(provider).artifact, isNull);
    expect(container.read(provider).errorCode, isNull);
  });

  test('one save dispatches at most one destination request', () async {
    final controller = container.read(provider.notifier);
    await controller.generate(selection());
    final first = controller.save();
    final second = controller.save();
    expect(handoff.calls, 1);
    handoff.result.complete(ExportDelivery.saved);
    await Future.wait([first, second]);
  });

  test('old capture cancellation cannot replace a newer preview', () async {
    final capture = Completer<ExportDocument>();
    var calls = 0;
    container.dispose();
    container = ProviderContainer(
      overrides: [
        appLockProvider.overrideWith(TestLock.new),
        exportCaptureProvider.overrideWithValue((selection, {cancellation}) {
          return calls++ == 0 ? capture.future : Future.value(document());
        }),
      ],
    );
    container.listen(provider, (_, _) {}, fireImmediately: true);
    final controller = container.read(provider.notifier);
    final old = controller.generate(selection());
    controller.edit();
    await controller.generate(selection());
    final artifact = container.read(provider).artifact;
    capture.complete(document());
    await old;
    expect(container.read(provider).stage, ExportStage.preview);
    expect(container.read(provider).artifact, same(artifact));
  });
}
