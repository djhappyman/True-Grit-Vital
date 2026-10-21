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

import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

const captureDirectory = String.fromEnvironment('VITAL_UI_SNAPSHOTS');

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
      final file = File('$captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

SupportingProvenance _source(String laboratory) => SupportingProvenance(
  mode: SupportingProvenanceMode.manualTranscription,
  laboratoryId: 'lab-a',
  laboratoryName: laboratory,
  methodId: 'method-a',
  methodText: 'Method A',
  specimenId: 'specimen-a',
  specimenText: 'Serum',
);

LabResultSnapshot _value(
  String id,
  String metric,
  String name,
  String value,
  String unit, {
  SourceReferenceRange? range,
  String? flag,
}) => LabResultSnapshot(
  id: id,
  metricId: metric,
  markerName: name,
  value: SupportingValue.numeric(value),
  unit: unit,
  referenceRange: range,
  sourceFlag: flag,
);

Future<void> _savePanel(
  WidgetTester tester,
  RecordStore store, {
  required String id,
  required String title,
  required SupportingDate collection,
  required List<LabResultSnapshot> results,
  required String laboratory,
}) async {
  final owner = (await runIo(tester, () => store.profileById(meId)))!;
  await runIo(
    tester,
    () => store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: 'capture-$id',
        generation: store.generation,
        expectedPersonRevision: owner.revision,
        panel: LabPanelSnapshot(
          id: SupportingRecordId(id: id, personId: meId),
          title: title,
          collectionDate: collection,
          reportDate: collection,
          provenance: _source(laboratory),
          results: results,
        ),
      ),
    ),
  );
}

Future<void> seedLabs(WidgetTester tester, RecordStore store) async {
  await _savePanel(
    tester,
    store,
    id: 'earlier',
    title: 'Baseline hormone and nutrient panel',
    collection: SupportingDate.day(CivilDate(2026, 8, 15)),
    laboratory: 'Quest Diagnostics',
    results: [
      _value(
        'earlier-vitamin',
        'vitamin',
        'Vitamin D (25-OH)',
        '32.0',
        'ng/mL',
      ),
      _value('earlier-crp', 'crp', 'hs-CRP', '0.71', 'mg/L'),
    ],
  );
  await _savePanel(
    tester,
    store,
    id: 'recent',
    title: 'Comprehensive metabolic and lipid panel',
    collection: SupportingDate.day(CivilDate(2026, 10, 14)),
    laboratory: 'LabCorp Outpatient Diagnostics',
    results: [
      _value(
        'recent-vitamin',
        'vitamin',
        'Vitamin D (25-OH)',
        '58.4',
        'ng/mL',
        range: SourceReferenceRange(originalText: '40 to 70'),
      ),
      _value('recent-crp', 'crp', 'hs-CRP', '0.45', 'mg/L'),
    ],
  );
  final owner = (await runIo(tester, () => store.profileById(meId)))!;
  await runIo(
    tester,
    () => store.saveObservation(
      SaveObservationCommand(
        commandId: 'capture-observation',
        generation: store.generation,
        expectedPersonRevision: owner.revision,
        observation: ObservationSnapshot(
          id: SupportingRecordId(id: 'observation', personId: meId),
          title: 'Resting pulse observation',
          measuredDate: SupportingDate.day(CivilDate(2026, 10, 20)),
          provenance: _source('Home measurement'),
          components: [
            _value('observation-pulse', 'pulse', 'Resting pulse', '64', 'bpm'),
          ],
        ),
      ),
    ),
  );
  await _savePanel(
    tester,
    store,
    id: 'undated',
    title: 'Undated source record',
    collection: SupportingDate.unknown(),
    laboratory: 'Source laboratory',
    results: [_value('undated-crp', 'crp', 'hs-CRP', '0.60', 'mg/L')],
  );
}

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
    appTest('labs collection captures ${mode.name} with saved records', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final fixture = await launch(tester);
      await seedLabs(tester, fixture.store);
      fixture.container.read(appearanceProvider.notifier).setMode(mode);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      fixture.container.read(routerProvider).go('/supporting');
      await settle(tester);
      await waitForText(tester, 'Biomarkers & Labs');
      await waitForText(tester, '3 markers');
      expect(tester.takeException(), isNull);
      final scaffold = find.byType(Scaffold).last;
      final rect = tester.getRect(scaffold);
      expect(rect.top, greaterThanOrEqualTo(28));
      expect(rect.bottom, lessThanOrEqualTo(820));
      if (captureDirectory.isEmpty) return;
      await saveCapture(tester, boundaryKey, '${mode.name}-screen-labs');
      final vertical = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.vertical,
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
      await saveCapture(tester, boundaryKey, '${mode.name}-screen-labs-full');
      tester.view.physicalSize = size;
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
