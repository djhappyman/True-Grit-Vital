import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/attachments.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/attachments/attachment_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/platform/attachment_media.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart' show appTest, runIo, settle;

class _UnlockedLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

class _LockedLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: true);
}

/// Records the exact protected bytes the viewer hands to the admitted PDF
/// renderer, so a matching name is never mistaken for matching content.
class _CapturingPdfDecoder implements AttachmentPdfDecoder {
  final captured = <Uint8List>[];

  @override
  Future<int> pageCount(Uint8List bytes) async => 1;

  @override
  Future<ui.Image> render(
    Uint8List bytes, {
    required int page,
    required int maxEdge,
  }) async {
    captured.add(Uint8List.fromList(bytes));
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 2, 2),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(2, 2);
    } finally {
      picture.dispose();
    }
  }
}

AttachmentInspection _pdfInspection(Uint8List bytes) => AttachmentInspection(
  mediaKind: AttachmentMediaKind.pdf,
  byteCount: bytes.length,
  sha256: sha256.convert(bytes).toString(),
  mimeType: 'application/pdf',
  pageCount: 1,
);

Uint8List _pdfBytes(String marker) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n$marker\n'));

AttachmentRecord _record({
  AttachmentTargetKind targetKind = AttachmentTargetKind.item,
  String personId = meId,
  int revision = 4,
  String versionId = 'version',
  AttachmentState state = AttachmentState.ready,
}) => AttachmentRecord(
  id: 'source',
  generation: 'generation',
  personId: personId,
  targetKind: targetKind,
  targetId: 'target',
  targetRevision: 2,
  revision: revision,
  versionId: versionId,
  name: 'Saved source.pdf',
  state: state,
  createdAt: DateTime.utc(2026, 10, 20),
  inspection: state == AttachmentState.ready
      ? _pdfInspection(_pdfBytes('x'))
      : null,
);

LabPanelSnapshot _panel({List<SupportingSourceReference> sources = const []}) =>
    LabPanelSnapshot(
      id: SupportingRecordId(id: 'source-panel', personId: meId),
      title: 'Source panel',
      collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
      reportDate: SupportingDate.day(CivilDate(2026, 10, 20)),
      provenance: SupportingProvenance(
        mode: SupportingProvenanceMode.manualTranscription,
        sourceReferences: sources,
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

Future<AttachmentRecord> _seedPdf(
  RecordStore store, {
  required AttachmentTargetKind targetKind,
  required String targetId,
  required int targetRevision,
  required String name,
  required String marker,
  required DateTime createdAt,
}) async {
  final bytes = _pdfBytes(marker);
  final owner = (await store.profileById(meId))!;
  final job = AttachmentJob(
    id: newCommandId(),
    generation: store.generation,
    personId: meId,
    expectedPersonRevision: owner.revision,
    targetKind: targetKind,
    targetId: targetId,
    targetRevision: targetRevision,
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
    inspection: _pdfInspection(bytes),
    name: name,
  );
}

Future<void> _tapText(
  WidgetTester tester,
  Finder finder, {
  bool last = false,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  final target = last ? finder.last : finder.first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await settle(tester);
}

Future<void> _attach(WidgetTester tester, String name) async {
  final target = find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.properties.label == 'Attach $name.',
  );
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await settle(tester);
}

Future<void> _saveAndWait(WidgetTester tester) async {
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

String _sourceRoute(AttachmentRecord file, {int? revision}) => Uri(
  path: '/supporting-source/$meId/${file.id}',
  queryParameters: {
    'revision': (revision ?? file.revision).toString(),
    'version': file.versionId,
  },
).toString();

void main() {
  group('saved source availability keeps the captured attachment identity', () {
    for (final kind in AttachmentTargetKind.values) {
      test('a ready $kind attachment can open as its saved source', () {
        expect(
          supportingSourceAvailability(
            attachment: _record(targetKind: kind),
            personId: meId,
            revision: 4,
            contentVersionId: 'version',
          ),
          SupportingSourceAvailability.available,
        );
      });
    }

    test('owner, readiness, revision and content version still decide', () {
      expect(
        supportingSourceAvailability(
          attachment: null,
          personId: meId,
          revision: 4,
          contentVersionId: 'version',
        ),
        SupportingSourceAvailability.unavailable,
      );
      expect(
        supportingSourceAvailability(
          attachment: _record(personId: 'another-person'),
          personId: meId,
          revision: 4,
          contentVersionId: 'version',
        ),
        SupportingSourceAvailability.unavailable,
      );
      for (final state in [AttachmentState.staging, AttachmentState.deleting]) {
        expect(
          supportingSourceAvailability(
            attachment: _record(state: state),
            personId: meId,
            revision: 4,
            contentVersionId: 'version',
          ),
          SupportingSourceAvailability.unavailable,
        );
      }
      expect(
        supportingSourceAvailability(
          attachment: _record(revision: 5),
          personId: meId,
          revision: 4,
          contentVersionId: 'version',
        ),
        SupportingSourceAvailability.changed,
      );
      expect(
        supportingSourceAvailability(
          attachment: _record(versionId: 'new-version'),
          personId: meId,
          revision: 4,
          contentVersionId: 'version',
        ),
        SupportingSourceAvailability.changed,
      );
    });
  });

  appTest(
    'an item or record attachment can be selected, saved and opened at the captured version',
    (tester) async {
      final directory = (await runIo(
        tester,
        () => Directory.systemTemp.createTemp('vital-source-targets-'),
      ))!;
      final store = (await runIo(
        tester,
        () => RecordStore.open(
          path: '${directory.path}/records.db',
          key: List.generate(32, (i) => i + 1),
          isNew: true,
        ),
      ))!;
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      final item = (await runIo(tester, () async {
        final me = (await store.profileById(meId))!;
        await store.editProfile(
          commandId: 'source-targets-adult',
          personId: meId,
          expectedRevision: me.revision,
          name: 'Me',
          adultConfirmed: true,
        );
        await store.saveBrowsingScope(const FeedScope.me());
        return store.createItem(
          commandId: 'source-targets-item',
          name: 'Synthetic item',
          form: 'Tablet',
          unit: 'count',
          type: 'Test',
          expectedPersonRevision: 2,
        );
      }))!;
      final record = (await runIo(
        tester,
        () => store.record(
          commandId: 'source-targets-record',
          itemId: item.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 19, 9),
          expectedPersonRevision: 2,
        ),
      ))!;
      final panel = (await runIo(
        tester,
        () => store.saveLabPanel(
          SaveLabPanelCommand(
            commandId: 'source-targets-panel',
            generation: store.generation,
            expectedPersonRevision: 2,
            panel: _panel(),
          ),
        ),
      ))!;
      final itemFile = (await runIo(
        tester,
        () => _seedPdf(
          store,
          targetKind: AttachmentTargetKind.item,
          targetId: item.id,
          targetRevision: item.revision,
          name: 'Item source.pdf',
          marker: 'item-attached original bytes',
          createdAt: DateTime.utc(2026, 10, 20, 9),
        ),
      ))!;
      final recordFile = (await runIo(
        tester,
        () => _seedPdf(
          store,
          targetKind: AttachmentTargetKind.record,
          targetId: record.id,
          targetRevision: record.revision,
          name: 'Record source.pdf',
          marker: 'record-attached original bytes',
          createdAt: DateTime.utc(2026, 10, 20, 9, 1),
        ),
      ))!;
      final pdf = _CapturingPdfDecoder();
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(_UnlockedLock.new),
          observedDeviceZoneProvider.overrideWith(
            (ref) =>
                Stream.value(DeviceZoneObservation.fromId('Europe/London')),
          ),
          attachmentMediaProvider.overrideWithValue(
            AttachmentMediaDecoder(pdf: pdf),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const VitalApp(),
        ),
      );
      await settle(tester);

      container
          .read(routerProvider)
          .go('/supporting/$meId/${panel.id.id}/edit');
      await settle(tester);
      await _tapText(tester, find.text('Source'));
      expect(find.text('Item source.pdf'), findsOneWidget);
      expect(find.text('Record source.pdf'), findsOneWidget);
      await _attach(tester, 'Item source.pdf');
      await _attach(tester, 'Record source.pdf');
      await _saveAndWait(tester);
      expect(find.byType(SupportingDetailPage), findsOneWidget);
      await _tapText(tester, find.text('Source details'));
      expect(find.text('Item source.pdf'), findsOneWidget);
      expect(find.text('Record source.pdf'), findsOneWidget);

      final saved = (await runIo(
        tester,
        () => store.supportingRecord(meId, panel.id.id),
      ))!;
      expect(
        saved.snapshot.provenance.sourceReferences.map((source) => source.id),
        [itemFile.id, recordFile.id],
      );
      expect(
        saved.snapshot.provenance.sourceReferences.map(
          (source) => source.contentVersionId,
        ),
        [itemFile.versionId, recordFile.versionId],
      );

      // The item-attached file still belongs to the item. Saving it as a
      // supporting source did not retarget, copy or relink the attachment.
      final currentItem = (await runIo(
        tester,
        () => store.attachmentById(itemFile.id),
      ))!;
      expect(currentItem.targetKind, AttachmentTargetKind.item);
      expect(currentItem.targetId, item.id);
      expect(currentItem.targetRevision, item.revision);
      expect(currentItem.versionId, itemFile.versionId);
      final currentRecord = (await runIo(
        tester,
        () => store.attachmentById(recordFile.id),
      ))!;
      expect(currentRecord.targetKind, AttachmentTargetKind.record);
      expect(currentRecord.targetId, record.id);
      expect(currentRecord.targetRevision, record.revision);

      await _tapText(tester, find.text('Open'));
      expect(find.byType(SupportingSourceViewerPage), findsOneWidget);
      expect(pdf.captured, hasLength(1));
      expect(
        utf8.decode(pdf.captured.single),
        '%PDF-1.7\nitem-attached original bytes\n',
      );
      final itemPreview = tester.widget<AttachmentPreviewSurface>(
        find.byType(AttachmentPreviewSurface),
      );
      expect(itemPreview.attachment.id, itemFile.id);
      expect(itemPreview.attachment.personId, meId);
      expect(itemPreview.attachment.revision, itemFile.revision);
      expect(itemPreview.attachment.versionId, itemFile.versionId);

      container.read(routerProvider).go('/supporting/$meId/${panel.id.id}');
      await settle(tester);
      await _tapText(tester, find.text('Source details'));
      await _tapText(tester, find.text('Open'), last: true);
      expect(find.byType(SupportingSourceViewerPage), findsOneWidget);
      expect(pdf.captured, hasLength(2));
      expect(
        utf8.decode(pdf.captured.last),
        '%PDF-1.7\nrecord-attached original bytes\n',
      );
      final recordPreview = tester.widget<AttachmentPreviewSurface>(
        find.byType(AttachmentPreviewSurface),
      );
      expect(recordPreview.attachment.id, recordFile.id);
      expect(recordPreview.attachment.versionId, recordFile.versionId);
    },
  );

  appTest(
    'a renamed or deleted item source stays changed or unavailable without substitute bytes',
    (tester) async {
      final directory = (await runIo(
        tester,
        () => Directory.systemTemp.createTemp('vital-source-targets-negative-'),
      ))!;
      final store = (await runIo(
        tester,
        () => RecordStore.open(
          path: '${directory.path}/records.db',
          key: List.generate(32, (i) => i + 1),
          isNew: true,
        ),
      ))!;
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      final data = (await runIo(tester, () async {
        final me = (await store.profileById(meId))!;
        await store.editProfile(
          commandId: 'source-targets-negative-adult',
          personId: meId,
          expectedRevision: me.revision,
          name: 'Me',
          adultConfirmed: true,
        );
        await store.saveBrowsingScope(const FeedScope.me());
        final item = await store.createItem(
          commandId: 'source-targets-negative-item',
          name: 'Synthetic item',
          form: 'Tablet',
          unit: 'count',
          type: 'Test',
          expectedPersonRevision: 2,
        );
        final panel = await store.saveLabPanel(
          SaveLabPanelCommand(
            commandId: 'source-targets-negative-panel',
            generation: store.generation,
            expectedPersonRevision: 2,
            panel: _panel(),
          ),
        );
        final file = await _seedPdf(
          store,
          targetKind: AttachmentTargetKind.item,
          targetId: item.id,
          targetRevision: item.revision,
          name: 'Original item source.pdf',
          marker: 'item-attached original bytes',
          createdAt: DateTime.utc(2026, 10, 20, 9),
        );
        return (item: item, panel: panel, file: file);
      }))!;
      await runIo(
        tester,
        () => store.saveLabPanel(
          SaveLabPanelCommand(
            commandId: 'source-targets-negative-save',
            generation: store.generation,
            expectedPersonRevision: 2,
            expectedRevision: data.panel.revision,
            panel: _panel(
              sources: [
                SupportingSourceReference(
                  id: data.file.id,
                  personId: meId,
                  version: data.file.revision,
                  kind: SupportingSourceKind.attachment,
                  originalText: data.file.name,
                  contentVersionId: data.file.versionId,
                ),
              ],
            ),
          ),
        ),
      );
      final pdf = _CapturingPdfDecoder();
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(_UnlockedLock.new),
          observedDeviceZoneProvider.overrideWith(
            (ref) =>
                Stream.value(DeviceZoneObservation.fromId('Europe/London')),
          ),
          attachmentMediaProvider.overrideWithValue(
            AttachmentMediaDecoder(pdf: pdf),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const VitalApp(),
        ),
      );
      await settle(tester);

      final renamed = (await runIo(
        tester,
        () => store.renameAttachment(
          commandId: 'source-targets-negative-rename',
          attachment: data.file,
          expectedPersonRevision: 2,
          name: 'Renamed current item source.pdf',
        ),
      ))!;
      container.read(routerProvider).go(_sourceRoute(data.file));
      await settle(tester);
      expect(
        find.text(
          'This saved source changed after it was saved. Its exact original is not available.',
        ),
        findsOneWidget,
      );
      expect(find.text('Renamed current item source.pdf'), findsNothing);
      expect(find.text('Original item source.pdf'), findsNothing);
      expect(find.byType(AttachmentPreviewSurface), findsNothing);
      expect(pdf.captured, isEmpty);

      await runIo(
        tester,
        () => store.deleteAttachment(
          commandId: 'source-targets-negative-delete',
          attachment: renamed,
          expectedPersonRevision: 2,
        ),
      );
      container.read(routerProvider).go(_sourceRoute(data.file));
      await settle(tester);
      expect(
        find.text(
          'This saved source is no longer available. The record keeps its saved source details.',
        ),
        findsOneWidget,
      );
      expect(find.text('Renamed current item source.pdf'), findsNothing);
      expect(find.byType(AttachmentPreviewSurface), findsNothing);
      expect(pdf.captured, isEmpty);
    },
  );

  testWidgets('locked app shows no item source identity or bytes', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [appLockProvider.overrideWith(_LockedLock.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadcnApp(
          theme: vitalTheme(Brightness.light),
          locale: const Locale('en', 'GB'),
          supportedLocales: const [Locale('en', 'GB')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const VitalComponentThemes(
            child: SupportingSourceViewerPage(
              personId: meId,
              attachmentId: 'item-source',
              revision: 1,
              contentVersionId: 'version',
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Unlock Vital to view supporting records.'),
      findsOneWidget,
    );
    expect(find.text('Original item source.pdf'), findsNothing);
    expect(find.byType(AttachmentPreviewSurface), findsNothing);
  });
}
