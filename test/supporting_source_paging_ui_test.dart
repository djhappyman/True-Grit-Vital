import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/supporting.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle;

class SourceOpenLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

AttachmentRecord sourceCandidate(String id, String name, String generation) =>
    AttachmentRecord(
      id: id,
      generation: generation,
      personId: meId,
      targetKind: AttachmentTargetKind.supporting,
      targetId: 'record',
      targetRevision: 1,
      revision: 1,
      versionId: 'version_$id',
      name: name,
      state: AttachmentState.ready,
      createdAt: DateTime.utc(2026, 10, 20),
      inspection: AttachmentInspection(
        mediaKind: AttachmentMediaKind.other,
        byteCount: 1,
        sha256: 'a' * 64,
        mimeType: 'application/octet-stream',
      ),
    );

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
    'an older saved file is reachable after fifty and selections survive',
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
      await runIo(tester, () async {
        final base = DateTime.utc(2026, 10, 20, 9);
        for (var i = 0; i < 51; i++) {
          await seedSourceFile(
            f.store,
            panel,
            'Source ${i.toString().padLeft(2, '0')}',
            base.add(Duration(seconds: i)),
          );
        }
      });

      f.container
          .read(routerProvider)
          .go('/supporting/$meId/source-panel/edit');
      await settle(tester);
      await tap(tester, 'Source');

      // The first page is bounded to the fifty newest files.
      expect(find.text('Source 50'), findsOneWidget);
      expect(find.text('Source 49'), findsOneWidget);
      expect(find.text('Source 00'), findsNothing);
      expect(find.text('More'), findsOneWidget);

      // A selection made before continuation stays captured.
      await attach(tester, 'Source 49');
      await tap(tester, 'More');
      expect(find.text('Source 00'), findsOneWidget);
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
      expect(find.text('Saved sources'), findsOneWidget);
    },
  );

  appTest('closing the source section discards its pending page', (
    tester,
  ) async {
    final f = await launch(tester);
    final pending = <Completer<SupportingSourcePage>>[];
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => f.store),
        appLockProvider.overrideWith(SourceOpenLock.new),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
        supportingSourceReaderProvider.overrideWithValue((request) {
          final result = Completer<SupportingSourcePage>();
          pending.add(result);
          return result.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    await settle(tester);
    container.read(routerProvider).go('/supporting/$meId/add-panel');
    await settle(tester);

    await tap(tester, 'Source');
    expect(pending, hasLength(1));
    expect(find.text('Opening records…'), findsWidgets);

    // Closing the section discards the page that is still in flight.
    await tap(tester, 'Source');
    pending.single.complete(
      SupportingSourcePage(
        records: [sourceCandidate('stale', 'Stale file', f.store.generation)],
        nextCursor: null,
        generation: f.store.generation,
      ),
    );
    await settle(tester);
    expect(find.text('Stale file'), findsNothing);

    await tap(tester, 'Source');
    expect(pending, hasLength(2));
    pending.last.complete(
      SupportingSourcePage(
        records: [sourceCandidate('fresh', 'Fresh file', f.store.generation)],
        nextCursor: null,
        generation: f.store.generation,
      ),
    );
    await settle(tester);
    expect(find.text('Fresh file'), findsOneWidget);
  });

  appTest('a page from a replaced generation is not offered', (tester) async {
    final f = await launch(tester);
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => f.store),
        appLockProvider.overrideWith(SourceOpenLock.new),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
        supportingSourceReaderProvider.overrideWithValue((request) {
          calls++;
          return Future.value(
            SupportingSourcePage(
              records: [
                sourceCandidate('replaced', 'Replaced file', 'replaced'),
              ],
              nextCursor: null,
              generation: 'replaced',
            ),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    await settle(tester);
    container.read(routerProvider).go('/supporting/$meId/add-panel');
    await settle(tester);

    await tap(tester, 'Source');
    await settle(tester);
    expect(find.text('Replaced file'), findsNothing);
    expect(
      find.text('Unable to load supporting records. Retry this view.'),
      findsOneWidget,
    );
    // The rejected page does not trigger an automatic retry loop.
    expect(calls, 1);
  });
}
