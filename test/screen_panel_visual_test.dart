import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';

import 'supporting_ui_test.dart' as supporting;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

const panelSnapshots = String.fromEnvironment('SCREEN_PANEL_SNAPSHOTS');

Future<void> saveCapture(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$panelSnapshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

LabPanelSnapshot priorVisualPanel() => LabPanelSnapshot(
  id: SupportingRecordId(id: 'visual-prior', personId: meId),
  title: 'Prior source panel',
  collectionDate: SupportingDate.day(CivilDate(2026, 9, 14)),
  reportDate: SupportingDate.day(CivilDate(2026, 9, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryName: 'Source laboratory',
    methodText: 'Immunoassay',
    specimenText: 'Serum',
  ),
  results: [
    LabResultSnapshot(
      id: 'visual-prior-result-1',
      metricId: 'visual-metric-1',
      markerName: 'Apolipoprotein B',
      originalMarkerText: 'Apolipoprotein B (ApoB)',
      value: SupportingValue.numeric('60'),
      unit: 'mg/dL',
    ),
  ],
);

LabPanelSnapshot visualPanel(
  String id, {
  required String itemId,
  required String eventId,
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: 'Comprehensive metabolic and lipid panel',
  collectionDate: SupportingDate.day(CivilDate(2026, 10, 14)),
  reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryName: 'Source laboratory',
    methodText: 'Immunoassay',
    specimenText: 'Serum',
  ),
  results: [
    LabResultSnapshot(
      id: 'visual-result-1',
      metricId: 'visual-metric-1',
      markerName: 'Apolipoprotein B',
      originalMarkerText: 'Apolipoprotein B (ApoB)',
      value: SupportingValue.numeric('68'),
      unit: 'mg/dL',
      referenceRange: SourceReferenceRange(originalText: '< 90 mg/dL'),
      sourceFlag: 'H',
    ),
    LabResultSnapshot(
      id: 'visual-result-2',
      metricId: 'visual-metric-2',
      markerName: '25-Hydroxyvitamin D',
      originalMarkerText: '25-Hydroxyvitamin D',
      value: SupportingValue.numeric('58.4'),
      unit: 'ng/mL',
      referenceRange: SourceReferenceRange(originalText: '30 - 100'),
    ),
    LabResultSnapshot(
      id: 'visual-result-3',
      metricId: 'visual-metric-3',
      markerName: 'Fasting insulin',
      value: SupportingValue.missing(),
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
  setUpAll(() async {
    await (FontLoader('StitchSans')
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Bold.ttf')))
        .load();
    final loader = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await loader.load();
    await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
          rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
        ))
        .load();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('panel detail ${mode.name} capture', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final f = await launch(tester);
      final owner = (await runIo(tester, () => f.store.profileById(meId)))!;
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          expectedPersonRevision: owner.revision,
          commandId: 'visual-item',
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
            commandId: 'visual-event',
            generation: f.store.generation,
            expectedRevision: null,
            expectedPersonRevision: 2,
            event: EventRecord(
              id: newCommandId(),
              personId: meId,
              name: 'Morning prescription course',
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
            commandId: 'visual-prior',
            generation: f.store.generation,
            expectedPersonRevision: 2,
            panel: priorVisualPanel(),
          ),
        ),
      );
      final saved = (await runIo(
        tester,
        () => f.store.saveLabPanel(
          SaveLabPanelCommand(
            commandId: 'visual-panel',
            generation: f.store.generation,
            expectedPersonRevision: 2,
            panel: visualPanel(
              'visual-panel',
              itemId: item.id,
              eventId: event.id,
            ),
          ),
        ),
      ))!;
      await runIo(tester, () => supporting.seedSupportingFile(f.store, saved));
      f.container.read(appearanceProvider.notifier).setMode(mode);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      f.container.read(routerProvider).go('/supporting/$meId/visual-panel');
      await settle(tester);
      await waitForText(tester, 'Comprehensive metabolic and lipid panel');
      await waitForText(tester, 'Telmisartan 40mg');
      expect(find.byType(SupportingDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (panelSnapshots.isNotEmpty) {
        await saveCapture(tester, boundaryKey, '${mode.name}-panel-detail');
        final vertical = find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView && w.scrollDirection == Axis.vertical,
        );
        final scroll = find
            .descendant(of: vertical.first, matching: find.byType(Scrollable))
            .first;
        final extent = tester
            .state<ScrollableState>(scroll)
            .position
            .maxScrollExtent;
        final size = tester.view.physicalSize;
        tester.view.physicalSize = Size(
          size.width,
          size.height + extent.ceil() + 32,
        );
        await settle(tester);
        await saveCapture(
          tester,
          boundaryKey,
          '${mode.name}-panel-detail-full',
        );
        tester.view.physicalSize = size;
        await settle(tester);
        expect(tester.takeException(), isNull);
        if (mode == ThemeMode.light) {
          tester.view.physicalSize = const Size(320, 740);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: f.container,
              child: RepaintBoundary(
                key: boundaryKey,
                child: MediaQuery(
                  data: MediaQueryData.fromView(tester.view)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: const VitalApp(),
                ),
              ),
            ),
          );
          await settle(tester);
          f.container.read(routerProvider).go('/supporting/$meId/visual-panel');
          await settle(tester);
          await waitForText(tester, 'Comprehensive metabolic and lipid panel');
          expect(tester.takeException(), isNull);
          await saveCapture(
            tester,
            boundaryKey,
            'light-panel-detail-narrow-2x',
          );
          final narrowVertical = find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.vertical,
          );
          final narrowScroll = find
              .descendant(
                of: narrowVertical.first,
                matching: find.byType(Scrollable),
              )
              .first;
          final narrowExtent = tester
              .state<ScrollableState>(narrowScroll)
              .position
              .maxScrollExtent;
          final narrowSize = tester.view.physicalSize;
          tester.view.physicalSize = Size(
            narrowSize.width,
            narrowSize.height + narrowExtent.ceil() + 32,
          );
          await settle(tester);
          await saveCapture(
            tester,
            boundaryKey,
            'light-panel-detail-narrow-2x-full',
          );
          tester.view.physicalSize = narrowSize;
          await settle(tester);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
