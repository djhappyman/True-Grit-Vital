import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/exports.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;

ExportDocument _emptyDocument(ExportSelection selection) => ExportDocument(
  selection: selection,
  generatedAt: DateTime.utc(2026, 10, 20, 12),
  personName: 'Alex',
  doses: const [],
  supporting: const [],
);

Future<ExportDocument> _capture(
  ExportSelection selection, {
  ExportCancellation? cancellation,
}) async => _emptyDocument(selection);

Future<ExportDocument> _slowCapture(
  ExportSelection selection, {
  ExportCancellation? cancellation,
}) async {
  while (cancellation?.isCancelled != true) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw const ExportCancelled();
}

Future<ExportDocument> _tooLarge(
  ExportSelection selection, {
  ExportCancellation? cancellation,
}) async => throw const ExportLimitException('export_dose_records');

final class SlowHandoff implements ExportHandoff {
  ExportArtifact? received;

  @override
  bool get isAvailable => true;

  @override
  Future<ExportDelivery> deliver(
    ExportArtifact artifact, {
    ExportCancellation? cancellation,
    void Function(double progress)? onProgress,
  }) async {
    received = artifact;
    while (cancellation?.isCancelled != true) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return ExportDelivery.cancelled;
  }
}

final class FakeHandoff implements ExportHandoff {
  FakeHandoff({this.available = true, this.delivery = ExportDelivery.saved});
  final bool available;
  final ExportDelivery delivery;
  ExportArtifact? received;

  @override
  bool get isAvailable => available;

  @override
  Future<ExportDelivery> deliver(
    ExportArtifact artifact, {
    ExportCancellation? cancellation,
    void Function(double progress)? onProgress,
  }) async {
    received = artifact;
    onProgress?.call(1);
    return delivery;
  }
}

Future<ProviderContainer> _launch(
  WidgetTester tester, {
  ExportCapture capture = _capture,
  ExportHandoff? handoff,
}) async {
  final directory = await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-export-widget-'),
  );
  final key = List.generate(32, (i) => i + 1);
  final store = (await runIo(
    tester,
    () => RecordStore.open(
      path: '${directory!.path}/test.db',
      key: key,
      isNew: true,
    ),
  ))!;
  await runIo(tester, () async {
    await store.editProfile(
      commandId: 'fixture-adult',
      personId: meId,
      expectedRevision: 1,
      name: 'Alex',
      adultConfirmed: true,
    );
    await store.saveBrowsingScope(const FeedScope.me());
  });
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() => Future.value(store)),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      exportCaptureProvider.overrideWithValue(capture),
      exportHandoffProvider.overrideWithValue(handoff ?? FakeHandoff()),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
    await directory!.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  container.read(routerProvider).push('/exports');
  await settle(tester);
  return container;
}

void main() {
  appTest('export reviews and saves the exact artifact', (tester) async {
    final handoff = FakeHandoff();
    await _launch(tester, handoff: handoff);
    await waitForText(tester, 'Export');

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(3));
    expect(switches[2].value, isFalse, reason: 'notes stay private by default');

    await tap(tester, 'Preview');
    await waitForText(tester, 'Review');
    expect(find.text('No dose records'), findsOneWidget);
    expect(find.text('Supporting notes excluded.'), findsOneWidget);
    expect(find.text('SHA-256'), findsOneWidget);

    await tap(tester, 'Save');
    await waitForText(tester, 'Saved.');
    expect(handoff.received, isNotNull);
    final artifact = handoff.received!;
    expect(artifact.document.selection.personId, meId);
    expect(artifact.preview.sha256, artifact.sha256);
    expect(find.text(artifact.sha256), findsOneWidget);

    await tap(tester, 'Change');
    await waitForText(tester, 'Content');
    expect(find.text('Review'), findsNothing);
  });

  appTest('unavailable handoff disables Save and says so', (tester) async {
    await _launch(tester, handoff: FakeHandoff(available: false));
    await waitForText(tester, 'Export');
    await tap(tester, 'Preview');
    await waitForText(tester, 'Review');

    final save = tester.widget<VitalButton>(
      find.widgetWithText(VitalButton, 'Save'),
    );
    expect(save.onPressed, isNull);
    expect(
      find.text('Saving is not available on this device. Preview only.'),
      findsOneWidget,
    );
  });

  appTest('cancelling preparation saves nothing', (tester) async {
    final handoff = FakeHandoff();
    await _launch(tester, capture: _slowCapture, handoff: handoff);
    await waitForText(tester, 'Export');
    await tap(tester, 'Preview');
    await waitForText(tester, 'Preparing');
    await tap(tester, 'Cancel');
    await waitForText(tester, 'Export cancelled. Nothing was saved.');
    expect(handoff.received, isNull);
  });

  appTest('cancelling the destination handoff copies nothing', (tester) async {
    final handoff = SlowHandoff();
    await _launch(tester, handoff: handoff);
    await waitForText(tester, 'Export');
    await tap(tester, 'Preview');
    await waitForText(tester, 'Review');
    await tap(tester, 'Save');
    await waitForText(tester, 'Saving the reviewed file.');
    await tap(tester, 'Cancel');
    await waitForText(tester, 'Save cancelled. The preview is unchanged.');
    expect(handoff.received, isNotNull);
  });

  appTest('large text keeps selection and review readable', (tester) async {
    await _launch(tester);
    await waitForText(tester, 'Export');
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await settle(tester);
    await tap(tester, 'Preview');
    await waitForText(tester, 'Review');
    expect(tester.takeException(), isNull);
    await tap(tester, 'Change');
    await waitForText(tester, 'Content');
    expect(tester.takeException(), isNull);
  });

  appTest('a reached bound is explained without a preview', (tester) async {
    await _launch(tester, capture: _tooLarge);
    await waitForText(tester, 'Export');
    await tap(tester, 'Preview');
    await waitForText(
      tester,
      'This selection is too large. Choose a shorter date range or less content.',
    );
    expect(find.text('Review'), findsNothing);
  });
}
