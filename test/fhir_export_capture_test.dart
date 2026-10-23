import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/exports.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/exports/export_pages.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;

const _captureDirectory = String.fromEnvironment('VITAL_FHIR_CAPTURE');

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  if (_captureDirectory.isEmpty) return;
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

DateTime _fixedNow() => DateTime.utc(2026, 10, 22, 12);

Future<ExportDocument> _fhirDocument(
  ExportSelection selection, {
  ExportCancellation? cancellation,
}) async => ExportDocument(
  selection: selection,
  generatedAt: DateTime.utc(2026, 10, 22, 12),
  personName: 'Alex',
  doses: [
    ExportDoseRevision(
      recordId: 'capture-dose',
      itemId: 'capture-item',
      revision: 1,
      currentRevision: 1,
      itemName: 'Synthetic tablet',
      itemForm: 'Tablet',
      itemType: 'Medicine',
      primaryUnit: 'tablet',
      enteredAmount: '1',
      enteredUnit: 'tablet',
      actualAmount: ExactAmount(BigInt.one, BigInt.from(3)),
      actualUnit: 'tablet',
      actualAt: DateTime.utc(2026, 10, 5, 10),
      enteredAt: DateTime.utc(2026, 10, 5, 10, 2),
      isVoided: false,
      source: RecordSource.selfReported,
      contextTags: const ['With food'],
      siteLabel: 'Left thigh',
    ),
  ],
  skipped: [
    ExportSkippedAction(
      actionId: 'capture-skip',
      itemId: 'capture-item',
      itemName: 'Synthetic tablet',
      itemForm: 'Tablet',
      itemType: 'Medicine',
      occurredAt: DateTime.utc(2026, 10, 6, 8),
      recordedAt: DateTime.utc(2026, 10, 6, 8, 5),
      dateOnly: true,
      timeNeedsReview: true,
      savedDate: CivilDate(2026, 10, 6),
      planZone: 'Europe/London',
    ),
  ],
  supporting: [
    ExportSupportingRevision(
      snapshot: LabPanelSnapshot(
        id: SupportingRecordId(id: 'capture-panel', personId: meId),
        title: 'Synthetic panel',
        collectionDate: SupportingDate.day(CivilDate(2026, 10, 2)),
        reportDate: SupportingDate.day(CivilDate(2026, 10, 4)),
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualTranscription,
          laboratoryName: 'Synthetic laboratory',
        ),
        results: [
          LabResultSnapshot(
            id: 'capture-result',
            metricId: 'capture-metric',
            markerName: 'Marker',
            originalMarkerText: 'Source marker',
            value: SupportingValue.numeric('5.5'),
            unit: 'mmol/L',
          ),
        ],
      ),
      revision: 1,
      currentRevision: 1,
      enteredAt: DateTime.utc(2026, 10, 7, 9),
      revisionEnteredAt: DateTime.utc(2026, 10, 7, 9),
      isVoided: false,
    ),
    ExportSupportingRevision(
      snapshot: ObservationSnapshot(
        id: SupportingRecordId(id: 'capture-observation', personId: meId),
        title: 'Synthetic observation',
        measuredDate: SupportingDate.day(CivilDate(2026, 10, 3)),
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualObservation,
        ),
        components: [
          LabResultSnapshot(
            id: 'capture-component',
            metricId: 'capture-component-metric',
            markerName: 'Missing',
            value: SupportingValue.missing(),
          ),
        ],
      ),
      revision: 1,
      currentRevision: 1,
      enteredAt: DateTime.utc(2026, 10, 7, 9, 5),
      revisionEnteredAt: DateTime.utc(2026, 10, 7, 9, 5),
      isVoided: false,
    ),
  ],
);

Future<ProviderContainer> _launch(WidgetTester tester, ThemeMode theme) async {
  final directory = await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-fhir-capture-'),
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
    await store.writeSetting(
      'appearance',
      '{"mode":"${theme.name}","opaque":true,"reduceMotion":false}',
    );
  });
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() => Future.value(store)),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      exportNowProvider.overrideWithValue(_fixedNow),
      exportCaptureProvider.overrideWithValue(_fhirDocument),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
    await directory!.delete(recursive: true);
  });
  return container;
}

Future<void> _openReview(
  WidgetTester tester,
  ProviderContainer container,
  GlobalKey boundaryKey, {
  String? selectionCapture,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
    ),
  );
  await settle(tester);
  container.read(routerProvider).push('/exports');
  await settle(tester);
  await waitForText(tester, 'Export');
  await tap(tester, 'FHIR');
  if (selectionCapture != null) {
    await _capture(tester, boundaryKey, selectionCapture);
  }
  await tap(tester, 'Preview');
  await waitForText(tester, 'FHIR export');
  await tester.ensureVisible(find.text('FHIR export'));
  await settle(tester);
}

Future<void> _captureFull(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
  double width,
) async {
  final scrollable = tester.state<ScrollableState>(
    find
        .descendant(
          of: find
              .byWidgetPredicate(
                (w) =>
                    w is SingleChildScrollView &&
                    w.scrollDirection == Axis.vertical,
              )
              .first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  final viewport = scrollable.position.viewportDimension;
  final content = viewport + scrollable.position.maxScrollExtent;
  tester.view.physicalSize = Size(
    width,
    (900 + math.max(0, content - viewport)).ceilToDouble(),
  );
  await settle(tester);
  await _capture(tester, boundaryKey, name);
}

Future<void> _loadCaptureFonts() async {
  await loadFonts();
  // Flutter's test host has no generic monospace family. The real app resolves
  // the platform family; this capture-only loader makes the JSON excerpt
  // readable without changing the production font choice.
  final mono = File('/usr/share/fonts/noto/NotoSansMono-Regular.ttf');
  if (mono.existsSync()) {
    final bytes = await mono.readAsBytes();
    await (FontLoader(
      'monospace',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

void main() {
  setUpAll(_loadCaptureFonts);

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('FHIR review renders at 390 in ${theme.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final container = await _launch(tester, theme);
      final boundaryKey = GlobalKey();
      await _openReview(
        tester,
        container,
        boundaryKey,
        selectionCapture: '${theme.name}-390-selection',
      );
      expect(container.read(appearanceProvider).mode, theme);
      expect(
        Theme.of(tester.element(find.text('FHIR export'))).brightness,
        theme == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, boundaryKey, '${theme.name}-390-review');
      await _captureFull(
        tester,
        boundaryKey,
        '${theme.name}-390-review-full',
        390,
      );
    });

    appTest('FHIR review renders at 430 in ${theme.name}', (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final container = await _launch(tester, theme);
      final boundaryKey = GlobalKey();
      await _openReview(tester, container, boundaryKey);
      expect(container.read(appearanceProvider).mode, theme);
      expect(
        Theme.of(tester.element(find.text('FHIR export'))).brightness,
        theme == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, boundaryKey, '${theme.name}-430-review');
      await _captureFull(
        tester,
        boundaryKey,
        '${theme.name}-430-review-full',
        430,
      );
    });

    appTest('FHIR review renders at 320 with double text in ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await _launch(tester, theme);
      final boundaryKey = GlobalKey();
      await _openReview(tester, container, boundaryKey);
      expect(container.read(appearanceProvider).mode, theme);
      expect(
        Theme.of(tester.element(find.text('FHIR export'))).brightness,
        theme == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, boundaryKey, '${theme.name}-320-review-2x');
      await _captureFull(
        tester,
        boundaryKey,
        '${theme.name}-320-review-2x-full',
        320,
      );
    });
  }
}
