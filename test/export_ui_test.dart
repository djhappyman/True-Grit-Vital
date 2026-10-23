import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/exports.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/exports/export_pages.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;

ExportDocument _emptyDocument(
  ExportSelection selection, {
  ExportUndatedOmission? undatedCollection,
}) => ExportDocument(
  selection: selection,
  generatedAt: DateTime.utc(2026, 10, 20, 12),
  personName: 'Alex',
  doses: const [],
  supporting: const [],
  undatedCollection: undatedCollection,
);

Future<ExportDocument> _capture(
  ExportSelection selection, {
  ExportCancellation? cancellation,
}) async => _emptyDocument(selection);

Future<ExportDocument> _skipCapture(
  ExportSelection selection, {
  ExportCancellation? cancellation,
}) async => ExportDocument(
  selection: selection,
  generatedAt: DateTime.utc(2026, 10, 21, 12),
  personName: 'Alex',
  doses: const [],
  supporting: const [],
  skipped: [
    ExportSkippedAction(
      actionId: 'saved-skip-action',
      itemId: 'item',
      itemName: 'Synthetic substance',
      itemForm: 'tablet',
      itemType: 'medicine',
      occurredAt: DateTime.utc(
        selection.fromDay.year,
        selection.fromDay.month,
        selection.fromDay.day,
      ),
      recordedAt: DateTime.utc(2026, 10, 21, 8),
      dateOnly: true,
      timeNeedsReview: false,
      savedDate: selection.fromDay,
      planZone: 'UTC',
    ),
  ],
);

Future<ExportDocument> _fhirCapture(
  ExportSelection selection, {
  ExportCancellation? cancellation,
}) async => ExportDocument(
  selection: selection,
  generatedAt: DateTime.utc(2026, 10, 20, 12),
  personName: 'Alex',
  doses: [
    ExportDoseRevision(
      recordId: 'fhir-dose',
      itemId: 'fhir-item',
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
    ),
  ],
  skipped: [
    ExportSkippedAction(
      actionId: 'fhir-skip',
      itemId: 'fhir-item',
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
        id: SupportingRecordId(id: 'fhir-panel', personId: meId),
        title: 'Synthetic panel',
        collectionDate: SupportingDate.day(CivilDate(2026, 10, 2)),
        reportDate: SupportingDate.day(CivilDate(2026, 10, 4)),
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualTranscription,
          laboratoryName: 'Synthetic laboratory',
        ),
        results: [
          LabResultSnapshot(
            id: 'fhir-result',
            metricId: 'fhir-metric',
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
        id: SupportingRecordId(id: 'fhir-observation', personId: meId),
        title: 'Synthetic observation',
        measuredDate: SupportingDate.day(CivilDate(2026, 10, 3)),
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualObservation,
        ),
        components: [
          LabResultSnapshot(
            id: 'fhir-component',
            metricId: 'fhir-component-metric',
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

Future<ExportDocument> _undatedCapture(
  ExportSelection selection, {
  ExportCancellation? cancellation,
}) async => _emptyDocument(
  selection,
  undatedCollection: const ExportUndatedOmission.counted(2),
);

Future<ExportDocument> _uncountedCapture(
  ExportSelection selection, {
  ExportCancellation? cancellation,
}) async => _emptyDocument(
  selection,
  undatedCollection: const ExportUndatedOmission.uncounted(),
);

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

String _fieldText(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

DateTime _fixedNow() => DateTime.utc(2026, 10, 22, 12);

Future<ProviderContainer> _launch(
  WidgetTester tester, {
  ExportCapture capture = _capture,
  ExportHandoff? handoff,
  DateTime Function()? now,
  String zoneId = 'Europe/London',
  String? displayZone,
  Stream<DeviceZoneObservation>? zoneChanges,
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
        (ref) =>
            zoneChanges ?? Stream.value(DeviceZoneObservation.fromId(zoneId)),
      ),
      if (displayZone != null)
        displayZoneProvider.overrideWithValue(displayZone),
      if (now != null) exportNowProvider.overrideWithValue(now),
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
  appTest('export review counts skips separately from doses', (tester) async {
    final handoff = FakeHandoff();
    await _launch(tester, capture: _skipCapture, handoff: handoff);
    await waitForText(tester, 'Export');
    expect(
      find.text(
        'Include substance and saved plan instructions, notes and skip reasons. Files stay excluded.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Preview');
    await waitForText(tester, 'Review');
    expect(find.text('No dose records'), findsOneWidget);
    expect(find.text('1 skipped action'), findsOneWidget);
    expect(find.text('Private text excluded.'), findsOneWidget);
    await tap(tester, 'Save');
    await waitForText(tester, 'Saved.');
    expect(handoff.received!.preview.skippedActions, 1);
    expect(
      handoff.received!.document.skipped.single.actionId,
      'saved-skip-action',
    );
  });

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
    expect(find.text('Private text excluded.'), findsOneWidget);
    expect(
      find.textContaining('left out of this file'),
      findsNothing,
      reason: 'no omission is claimed when none was counted',
    );
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

  appTest('the review discloses supporting records it cannot place', (
    tester,
  ) async {
    await _launch(tester, capture: _undatedCapture);
    await waitForText(tester, 'Export');
    await tap(tester, 'Preview');
    await waitForText(
      tester,
      '2 supporting records have unknown or partial collection dates and are'
      ' left out of this file.',
    );
    await tap(tester, 'Change');
    await waitForText(tester, 'Content');
  });

  appTest('an uncounted surplus says so without a fabricated number', (
    tester,
  ) async {
    await _launch(tester, capture: _uncountedCapture);
    await waitForText(tester, 'Export');
    await tap(tester, 'Preview');
    await waitForText(
      tester,
      'Supporting records with unknown or partial collection dates were not all'
      ' counted and are left out of this file.',
    );
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

  appTest('date shortcuts update the visible range and need a new review', (
    tester,
  ) async {
    final selections = <ExportSelection>[];
    final handoff = FakeHandoff();
    Future<ExportDocument> capture(
      ExportSelection selection, {
      ExportCancellation? cancellation,
    }) async {
      selections.add(selection);
      return _emptyDocument(selection);
    }

    await _launch(tester, capture: capture, handoff: handoff, now: _fixedNow);
    await waitForText(tester, 'Export');
    expect(find.text('Date shortcuts'), findsOneWidget);
    expect(_fieldText(tester, 0), '2026-09-23');
    expect(_fieldText(tester, 1), '2026-10-23');

    final semantics = tester.ensureSemantics();
    await settle(tester);
    expect(
      find.bySemanticsLabel('Last 30 days, including today'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Last 90 days, including today'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Year to date'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Year to date'))
          .getSemanticsData()
          .flagsCollection
          .isButton,
      isTrue,
    );

    semantics.dispose();
    await tap(tester, '90d');
    expect(_fieldText(tester, 0), '2026-07-25');
    expect(_fieldText(tester, 1), '2026-10-23');
    expect(selections, isEmpty, reason: 'a shortcut never generates a file');
    await tap(tester, 'Year');
    expect(_fieldText(tester, 0), '2026-01-01');
    await tap(tester, '30d');
    expect(_fieldText(tester, 0), '2026-09-23');
    expect(selections, isEmpty);

    await tap(tester, 'CSV');
    await tap(tester, 'Notes');
    expect(tester.widget<Switch>(find.byType(Switch).at(2)).value, isTrue);

    await tap(tester, 'Preview');
    await waitForText(tester, 'Review');
    expect(selections, hasLength(1));
    expect(selections.single.fromDay, CivilDate(2026, 9, 23));
    expect(selections.single.beforeDay, CivilDate(2026, 10, 23));
    expect(selections.single.format, ExportFormat.csv);
    expect(selections.single.includeNotes, isTrue);
    expect(handoff.received, isNull, reason: 'review never saves by itself');

    await tap(tester, 'Change');
    await waitForText(tester, 'Content');
    expect(find.text('Review'), findsNothing);
    await tap(tester, '90d');
    expect(_fieldText(tester, 0), '2026-07-25');
    expect(find.text('Review'), findsNothing);
    await tap(tester, 'Preview');
    await waitForText(tester, 'Review');
    expect(selections, hasLength(2));
    expect(selections.last.fromDay, CivilDate(2026, 7, 25));
    expect(selections.last.beforeDay, CivilDate(2026, 10, 23));
    expect(selections.last.format, ExportFormat.csv);
    expect(selections.last.includeNotes, isTrue);
    expect(selections.last.contents, {
      ExportContent.doses,
      ExportContent.supporting,
    });
    expect(selections.last.identity, isNot(selections.first.identity));

    await tap(tester, 'Save');
    await waitForText(tester, 'Saved.');
    expect(
      handoff.received!.document.selection.fromDay,
      CivilDate(2026, 7, 25),
    );
    expect(handoff.received!.document.selection.includeNotes, isTrue);
  });

  appTest('a late zone observation seeds the actual local day', (tester) async {
    final zones = StreamController<DeviceZoneObservation>.broadcast();
    addTearDown(zones.close);
    await _launch(
      tester,
      now: () => DateTime.utc(2026, 10, 22, 23, 30),
      zoneChanges: zones.stream,
    );
    expect(_fieldText(tester, 0), isEmpty);
    expect(find.textContaining('Dates use UTC.'), findsNothing);
    zones.add(DeviceZoneObservation.fromId('Pacific/Kiritimati'));
    await settle(tester);
    expect(_fieldText(tester, 0), '2026-09-24');
    expect(_fieldText(tester, 1), '2026-10-24');
  });

  appTest('late zone defaults preserve dates already typed', (tester) async {
    final zones = StreamController<DeviceZoneObservation>.broadcast();
    addTearDown(zones.close);
    await _launch(tester, zoneChanges: zones.stream);
    await tester.enterText(find.byType(TextField).at(0), '2026-01-02');
    await tester.enterText(find.byType(TextField).at(1), '2026-02-03');
    zones.add(DeviceZoneObservation.fromId('Pacific/Kiritimati'));
    await settle(tester);
    expect(_fieldText(tester, 0), '2026-01-02');
    expect(_fieldText(tester, 1), '2026-02-03');
  });

  appTest('an unavailable zone does not silently use another day', (
    tester,
  ) async {
    await _launch(tester, displayZone: 'Not/AZone');
    await waitForText(tester, 'Export');
    expect(_fieldText(tester, 0), isEmpty);
    expect(_fieldText(tester, 1), isEmpty);
    expect(
      find.text(
        'The display time zone is unavailable. Check the device time zone,'
        ' then try again.',
      ),
      findsOneWidget,
    );

    await tap(tester, '30d');
    expect(_fieldText(tester, 0), isEmpty);
    expect(_fieldText(tester, 1), isEmpty);
    expect(
      find.text(
        'The display time zone is unavailable. Check the device time zone,'
        ' then try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Review'), findsNothing);
  });

  appTest('an unrepresentable device date explains the range failure', (
    tester,
  ) async {
    await _launch(
      tester,
      now: () => DateTime.utc(9999, 12, 31, 12),
      displayZone: 'UTC',
    );
    await waitForText(tester, 'Export');
    expect(_fieldText(tester, 0), isEmpty);
    expect(
      find.text(
        'The date range cannot be shown. Check the device date, then try again.',
      ),
      findsOneWidget,
    );

    await tap(tester, 'Year');
    expect(_fieldText(tester, 0), isEmpty);
    expect(
      find.text(
        'The date range cannot be shown. Check the device date, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Review'), findsNothing);
  });

  appTest('invalid date edits keep the selection and explain the range', (
    tester,
  ) async {
    await _launch(tester, now: _fixedNow);
    await waitForText(tester, 'Export');
    await tap(tester, '30d');
    await tester.enterText(find.byType(TextField).at(0), '2026-10-23');
    await tester.enterText(find.byType(TextField).at(1), '2026-10-23');
    await tap(tester, 'Preview');
    await waitForText(
      tester,
      'Enter valid dates. Before must be later than From.',
    );
    expect(find.text('Review'), findsNothing);

    await tap(tester, '90d');
    expect(_fieldText(tester, 0), '2026-07-25');
    expect(
      find.text('Enter valid dates. Before must be later than From.'),
      findsNothing,
    );
  });

  appTest('shortcuts are unavailable while preparation is pending', (
    tester,
  ) async {
    await _launch(tester, capture: _slowCapture);
    await waitForText(tester, 'Export');
    final retained = tester
        .widget<Semantics>(find.bySemanticsLabel('Year to date'))
        .properties
        .onTap!;
    await tap(tester, 'Preview');
    await waitForText(tester, 'Preparing');
    retained();
    await settle(tester);
    expect(find.text('Preparing'), findsOneWidget);
    expect(find.text('Date shortcuts'), findsNothing);
    expect(find.text('30d'), findsNothing);

    await tap(tester, 'Cancel');
    await waitForText(tester, 'Export cancelled. Nothing was saved.');
    expect(find.text('Date shortcuts'), findsOneWidget);
    expect(_fieldText(tester, 0), isNotEmpty);
    expect(find.text('Review'), findsNothing);
  });

  appTest('shortcuts stay usable at narrow widths in both themes', (
    tester,
  ) async {
    final container = await _launch(tester, now: _fixedNow);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.reset);

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      container.read(appearanceProvider.notifier).setMode(mode);
      await settle(tester);
      for (final width in [320.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        await settle(tester);
        expect(find.text('Date shortcuts'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$mode at $width');
        await tap(tester, '90d');
        expect(_fieldText(tester, 0), '2026-07-25');
        await tap(tester, 'Year');
        expect(_fieldText(tester, 0), '2026-01-01');
        expect(tester.takeException(), isNull, reason: '$mode at $width');
      }
    }
  });

  appTest('FHIR review discloses the mapping and saves the exact bytes', (
    tester,
  ) async {
    final handoff = FakeHandoff();
    await _launch(tester, capture: _fhirCapture, handoff: handoff);
    await waitForText(tester, 'Export');
    await tap(tester, 'FHIR');
    expect(
      find.text(
        'FHIR R4 JSON for health records. Review the mapping and omissions before Save.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Preview');
    await waitForText(tester, 'FHIR export');
    for (final text in [
      'FHIR R4 4.0.1 collection Bundle.',
      'Patient name and local identifier only. No birth date, sex or verification.',
      'Medication use is patient-reported.',
      'Lab panels group member results. Quick observations use components.',
      'Codes are text only. No clinical codes or UCUM unit codes are added.',
      'Times use UTC. Date-only values stay dates.',
      'One medication statement.',
      'One not-taken statement.',
      '3 observations.',
      '3 date-only times.',
      'One planned time needs review.',
      'One exact quantity is kept as text.',
      'One observation has no value.',
      'One report date has no time and is not added.',
      'Not included: report names, product labels, stock containers, plan names and substance type.',
      'Source labels other than self-reported and component provenance are not included.',
      'Files and attachment references are not included.',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }

    await tap(tester, 'Save');
    await waitForText(tester, 'Saved.');
    final artifact = handoff.received!;
    expect(artifact.format, ExportFormat.fhir);
    expect(artifact.mimeType, 'application/fhir+json');
    expect(artifact.preview.fhir, isNotNull);
    expect(artifact.preview.fhir!.medicationStatements, 1);
    expect(artifact.preview.fhir!.skippedStatements, 1);
    expect(artifact.preview.fhir!.observations, 3);
    expect(artifact.preview.sha256, artifact.sha256);
    expect(
      artifact.bytes,
      orderedEquals(utf8.encode(encodeFhirR4(artifact.document).json)),
    );
  });
}
