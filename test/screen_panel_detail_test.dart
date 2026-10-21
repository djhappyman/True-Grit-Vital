import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/supporting.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/exports/export_pages.dart';

import 'design_system_test.dart' show host;

import 'package:true_grit_vital/features/supporting/screen_panel_widgets.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'supporting_ui_test.dart' as supporting;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

LabPanelSnapshot exactPanel(String id) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: 'Source report',
  collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
  reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryName: 'Source laboratory',
  ),
  results: [
    LabResultSnapshot(
      id: 'result-$id',
      metricId: 'metric-$id',
      markerName: 'Fasting glucose',
      value: SupportingValue.numeric('4.4'),
      unit: 'mmol/L',
      referenceRange: SourceReferenceRange(originalText: '3.5 - 5.1'),
      sourceFlag: 'H',
    ),
  ],
);

LabPanelSnapshot linkedPanel(
  String id, {
  required String itemId,
  required String eventId,
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: 'Source panel with linked records',
  collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
  reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryName: 'Source laboratory',
  ),
  results: [
    LabResultSnapshot(
      id: 'result-$id',
      metricId: 'metric-$id',
      markerName: 'Marker with a complete source name',
      value: SupportingValue.numeric('4.4'),
      unit: 'mmol/L',
      referenceRange: SourceReferenceRange(originalText: '3.5 - 5.1'),
      sourceFlag: 'H',
    ),
  ],
  contextLinks: [
    SupportingContextLink(
      id: itemId,
      personId: meId,
      kind: SupportingContextKind.item,
    ),
    SupportingContextLink(
      id: eventId,
      personId: meId,
      kind: SupportingContextKind.event,
    ),
  ],
);

void main() {
  testWidgets('source range applicability remains accessible', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        host(
          ScreenPanelResultCard(
            result: LabResultSnapshot(
              id: 'source-range',
              metricId: 'source-range',
              markerName: 'Source marker',
              value: SupportingValue.numeric('4.4'),
              unit: 'mmol/L',
              referenceRange: SourceReferenceRange(
                originalText: '3.5 to 5.1',
                applicabilityText: 'Adults aged 18 and over',
              ),
            ),
            onTrends: () {},
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp('Adults aged 18 and over')),
        findsOneWidget,
      );
    } finally {
      handle.dispose();
    }
  });

  appTest('observation hero identifies its measured date', (tester) async {
    final f = await launch(tester);
    await runIo(
      tester,
      () => f.store.saveObservation(
        SaveObservationCommand(
          commandId: 'measured-observation',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          observation: ObservationSnapshot(
            id: SupportingRecordId(id: 'measured-observation', personId: meId),
            title: 'Measured observation',
            measuredDate: SupportingDate.day(CivilDate(2026, 10, 19)),
            provenance: SupportingProvenance(
              mode: SupportingProvenanceMode.manualTranscription,
            ),
            components: exactPanel('measured-observation').results,
          ),
        ),
      ),
    );
    f.container
        .read(routerProvider)
        .go('/supporting/$meId/measured-observation');
    await settle(tester);
    expect(
      find.descendant(
        of: find.byType(ScreenPanelHero),
        matching: find.textContaining('Measured date:'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Collected'), findsNothing);
  });

  appTest('panel detail shows exact values and recorded file checksum', (
    tester,
  ) async {
    final f = await launch(tester);
    final saved = (await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'checksum-panel',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: exactPanel('checksum-panel'),
        ),
      ),
    ))!;
    final file = (await runIo(
      tester,
      () => supporting.seedSupportingFile(f.store, saved),
    ))!;
    f.container.read(routerProvider).go('/supporting/$meId/checksum-panel');
    await settle(tester);

    expect(find.byType(SupportingDetailPage), findsOneWidget);
    expect(find.text('Source report'), findsOneWidget);
    expect(find.text('4.4 mmol/L'), findsOneWidget);
    expect(find.text('Source range: 3.5 - 5.1'), findsOneWidget);
    expect(find.text('Source flag: H'), findsOneWidget);
    expect(find.text('File: ${file.name}'), findsOneWidget);
    expect(find.text(file.inspection!.sha256), findsOneWidget);
    expect(find.textContaining('Validated'), findsNothing);
    expect(find.text('File checksums'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    await supporting.tap(tester, 'Export');
    final location = tester
        .widget<ExportPage>(find.byType(ExportPage))
        .location;
    expect(Uri.parse(location).queryParameters['content'], 'supporting');
  });

  appTest('historical revision stays read only without file management', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'history-panel',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: exactPanel('history-panel'),
        ),
      ),
    );
    f.container
        .read(routerProvider)
        .go('/supporting/$meId/history-panel?revision=1');
    await settle(tester);

    expect(find.text('Revision 1'), findsOneWidget);
    final edit = tester.widget<StitchButton>(
      find.widgetWithText(StitchButton, 'Edit'),
    );
    final voidButton = tester.widget<VitalButton>(
      find.widgetWithText(VitalButton, 'Void'),
    );
    expect(edit.onPressed, isNull);
    expect(voidButton.onPressed, isNull);
    expect(find.text('File checksums'), findsNothing);
    expect(find.text('Files'), findsNothing);
  });

  appTest('copy places the recorded checksum on the clipboard', (tester) async {
    final f = await launch(tester);
    final saved = (await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'copy-panel',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: supporting.supportingUiPanel('copy-panel'),
        ),
      ),
    ))!;
    final file = (await runIo(
      tester,
      () => supporting.seedSupportingFile(f.store, saved),
    ))!;
    MethodCall? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    f.container.read(routerProvider).go('/supporting/$meId/copy-panel');
    await settle(tester);
    await tester.ensureVisible(
      find.byKey(ValueKey('screen-panel-copy-${file.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('screen-panel-copy-${file.id}')));
    await tester.pump();

    expect(copied?.arguments, {'text': file.inspection!.sha256});
    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('Checksum copied.'), findsOneWidget);
  });

  appTest('linked records resolve saved names and keep missing links blank', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'linked-item',
        name: 'Telmisartan 40mg',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    final event = (await runIo(
      tester,
      () => f.store.saveEvent(
        SaveEventCommand(
          commandId: 'linked-event',
          generation: f.store.generation,
          expectedRevision: null,
          expectedPersonRevision: 2,
          event: EventRecord(
            id: newCommandId(),
            personId: meId,
            name: 'Morning protocol course',
            eventType: 'Prescription course',
            zoneId: 'UTC',
            revision: 1,
          ),
        ),
      ),
    ))!;
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'linked-panel',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: linkedPanel(
            'linked-panel',
            itemId: item.id,
            eventId: event.id,
          ),
        ),
      ),
    );
    f.container.read(routerProvider).go('/supporting/$meId/linked-panel');
    await settle(tester);

    expect(find.text('Telmisartan 40mg'), findsOneWidget);
    expect(find.text('Morning protocol course'), findsOneWidget);
    expect(find.text('Substance'), findsOneWidget);
    expect(find.text('Event'), findsOneWidget);
    expect(find.text(item.id), findsNothing);
    expect(find.text(event.id), findsNothing);

    final linkedRow = find.byType(VitalCompactRow).first;
    expect(tester.widget<VitalCompactRow>(linkedRow).onPressed, isNotNull);
    await tester.ensureVisible(linkedRow);
    await tester.pumpAndSettle();
    await tester.tap(linkedRow);
    await tester.pumpAndSettle();
    expect(find.byType(ItemHistory), findsOneWidget);
  });

  appTest('missing linked names show an unavailable state without raw ids', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'gone-item',
        name: 'Removed substance name',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    final event = (await runIo(
      tester,
      () => f.store.saveEvent(
        SaveEventCommand(
          commandId: 'gone-event',
          generation: f.store.generation,
          expectedRevision: null,
          expectedPersonRevision: 2,
          event: EventRecord(
            id: newCommandId(),
            personId: meId,
            name: 'Removed event name',
            eventType: 'Prescription course',
            zoneId: 'UTC',
            revision: 1,
          ),
        ),
      ),
    ))!;
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'gone-panel',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: linkedPanel('gone-panel', itemId: item.id, eventId: event.id),
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => f.store),
        appLockProvider.overrideWith(supporting.SupportingOpenLock.new),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
        itemLookupProvider.overrideWith(
          (ref, id) => Stream<SubstanceItem?>.value(null),
        ),
        screenPanelEventProvider.overrideWith(
          (ref, id) => Stream<EventRecord?>.value(null),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    await settle(tester);
    container.read(routerProvider).go('/supporting/$meId/gone-panel');
    await settle(tester);

    expect(find.text('Linked record unavailable'), findsNWidgets(2));
    expect(find.text(item.id), findsNothing);
    expect(find.text(event.id), findsNothing);
    expect(find.text('Removed substance name'), findsNothing);
  });

  appTest('factual result filters reset paging and keep complete values', (
    tester,
  ) async {
    final f = await launch(tester);
    final results = [
      for (var i = 0; i < 30; i++)
        LabResultSnapshot(
          id: 'filter-result-$i',
          metricId: 'filter-metric-$i',
          markerName: 'Marker $i with full name',
          value: SupportingValue.numeric('$i'),
          unit: 'U/L',
          referenceRange: i < 25
              ? SourceReferenceRange(originalText: '0 - 100')
              : null,
        ),
    ];
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'filter-panel',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: supporting.panel('filter-panel', meId, results: results),
        ),
      ),
    );
    f.container.read(routerProvider).go('/supporting/$meId/filter-panel');
    await settle(tester);

    expect(find.text('All (30)'), findsOneWidget);
    expect(find.text('With range (25)'), findsOneWidget);
    expect(find.text('No range (5)'), findsOneWidget);
    expect(find.byType(ScreenPanelResultCard), findsNWidgets(25));

    await supporting.tap(tester, 'No range (5)');
    expect(find.byType(ScreenPanelResultCard), findsNWidgets(5));

    await supporting.tap(tester, 'All (30)');
    await supporting.tap(tester, 'Next');
    expect(find.byType(ScreenPanelResultCard), findsNWidgets(5));
    expect(find.text('Marker 29 with full name'), findsOneWidget);
    await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'shorten-filter-panel',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          expectedRevision: 1,
          panel: supporting.panel(
            'filter-panel',
            meId,
            results: results.take(2).toList(),
          ),
        ),
      ),
    );
    f.container.invalidate(supportingLookupProvider);
    await waitForText(tester, 'All (2)');
    expect(find.byType(ScreenPanelResultCard), findsNWidgets(2));
    expect(find.text('Marker 0 with full name'), findsOneWidget);
  });

  appTest('320 px at 200 percent keeps actions and checksums readable', (
    tester,
  ) async {
    final f = await launch(tester);
    final saved = (await runIo(
      tester,
      () => f.store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'narrow-panel',
          generation: f.store.generation,
          expectedPersonRevision: 2,
          panel: exactPanel('narrow-panel'),
        ),
      ),
    ))!;
    await runIo(tester, () => supporting.seedSupportingFile(f.store, saved));
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 760),
            textScaler: TextScaler.linear(2),
          ),
          child: VitalApp(),
        ),
      ),
    );
    await settle(tester);
    f.container.read(routerProvider).go('/supporting/$meId/narrow-panel');
    await settle(tester);
    expect(tester.takeException(), isNull);

    final files = find.text('File checksums');
    await tester.ensureVisible(files);
    await tester.pumpAndSettle();
    expect(files, findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
