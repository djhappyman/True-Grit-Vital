import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle;

Future<void> tap(WidgetTester tester, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
  await settle(tester);
}

Future<void> saveAndWait(WidgetTester tester) async {
  final target = find.text('Save');
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  for (var i = 0; i < 300; i++) {
    await runIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byType(SupportingDetailPage).evaluate().isNotEmpty) break;
  }
  await settle(tester);
}

Future<void> attach(WidgetTester tester, String name) async {
  final target = find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.properties.label == 'Attach $name.',
  );
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
  await settle(tester);
}

LabPanelSnapshot sourcePanel() => LabPanelSnapshot(
  id: SupportingRecordId(id: 'source-panel', personId: meId),
  title: 'Source panel',
  collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
  reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
  ),
  results: [
    LabResultSnapshot(
      id: 'result-source-panel',
      metricId: 'metric',
      markerName: 'Marker',
      value: SupportingValue.numeric('2'),
      unit: 'mg/L',
    ),
  ],
);

Future<AttachmentRecord> seedSourceFile(
  RecordStore store,
  SupportingRevision panel,
  String name,
  DateTime createdAt,
) async {
  final bytes = Uint8List.fromList('Synthetic $name'.codeUnits);
  final job = AttachmentJob(
    id: newCommandId(),
    generation: store.generation,
    personId: meId,
    expectedPersonRevision: (await store.profileById(meId))!.revision,
    targetKind: AttachmentTargetKind.supporting,
    targetId: panel.id.id,
    targetRevision: panel.revision,
    attachmentId: newCommandId(),
    versionId: newCommandId(),
    name: name,
    createdAt: createdAt,
  );
  await store.beginAttachment(
    BeginAttachmentCommand(commandId: newCommandId(), job: job),
  );
  await store.appendAttachmentChunk(
    commandId: newCommandId(),
    jobId: job.id,
    generation: job.generation,
    offset: 0,
    bytes: bytes,
  );
  return store.publishAttachment(
    commandId: newCommandId(),
    jobId: job.id,
    generation: job.generation,
    inspection: AttachmentInspection(
      mediaKind: AttachmentMediaKind.other,
      byteCount: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      mimeType: 'application/octet-stream',
    ),
  );
}

void main() {
  appTest(
    'deleting or inserting before the cursor keeps the oldest file reachable',
    (tester) async {
      final f = await launch(tester);
      final owner = (await runIo(tester, () => f.store.profileById(meId)))!;
      final panel = (await runIo(
        tester,
        () => f.store.saveLabPanel(
          SaveLabPanelCommand(
            commandId: 'source-panel',
            generation: f.store.generation,
            expectedPersonRevision: owner.revision,
            panel: sourcePanel(),
          ),
        ),
      ))!;
      final seeded = <AttachmentRecord>[];
      const base = Duration(hours: 9);

      await runIo(tester, () async {
        for (var i = 0; i < 51; i++) {
          seeded.add(
            await seedSourceFile(
              f.store,
              panel,
              'Source ${i.toString().padLeft(2, '0')}',
              DateTime.utc(2026, 10, 20).add(base + Duration(seconds: i)),
            ),
          );
        }
      });

      f.container
          .read(routerProvider)
          .go('/supporting/$meId/source-panel/edit');
      await settle(tester);
      await tap(tester, 'Source');

      expect(find.text('Source 50'), findsOneWidget);
      expect(find.text('Source 49'), findsOneWidget);
      expect(find.text('Source 00'), findsNothing);
      expect(find.text('More'), findsOneWidget);

      // A selection made before continuation stays captured.
      await attach(tester, 'Source 49');

      await runIo(tester, () async {
        final current = (await f.store.profileById(meId))!;
        // Both changes would shift an offset window: the newest row is
        // deleted and a newer row arrives before the second page.
        await f.store.deleteAttachment(
          commandId: newCommandId(),
          attachment: seeded[50],
          expectedPersonRevision: current.revision,
        );
        await seedSourceFile(
          f.store,
          panel,
          'Source 99',
          DateTime.utc(2026, 10, 20).add(base + const Duration(seconds: 99)),
        );
      });

      await tap(tester, 'More');

      // Continuation is anchored to the captured sort keys, so the oldest
      // surviving file is still reachable and the new row waits.
      expect(find.text('Source 00'), findsOneWidget);
      expect(find.text('Source 99'), findsNothing);
      expect(find.text('More'), findsNothing);

      await attach(tester, 'Source 00');
      await saveAndWait(tester);

      expect(find.byType(SupportingDetailPage), findsOneWidget);
      final saved = (await runIo(
        tester,
        () => f.store.supportingRecord(meId, 'source-panel'),
      ))!;
      expect(
        saved.snapshot.provenance.sourceReferences.map(
          (source) => source.originalText,
        ),
        ['Source 49', 'Source 00'],
      );
    },
  );
}
