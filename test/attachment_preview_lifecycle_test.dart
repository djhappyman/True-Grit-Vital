import 'dart:async';
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
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/attachments/attachment_pages.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/platform/attachment_media.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart' show runIo, settle;

/// Stands in for the store-loader boundary. A restore swaps the store and
/// invalidates [recordStoreProvider] rather than mutating it in place.
class _StoreSlot {
  _StoreSlot(this.store);
  RecordStore store;
}

class _PreviewLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

/// Returns one distinct bounded image per synthetic source. A render can be
/// held open so a source change lands while the previous decode is still live.
class _FakePdfDecoder implements AttachmentPdfDecoder {
  _FakePdfDecoder({this.failPages = const {}});
  final Set<int> failPages;
  Completer<void>? gate;
  final renderStarted = Completer<void>();
  final rendered = <int>[];

  @override
  Future<int> pageCount(Uint8List bytes) async => 1;

  @override
  Future<ui.Image> render(
    Uint8List bytes, {
    required int page,
    required int maxEdge,
  }) async {
    if (!renderStarted.isCompleted) renderStarted.complete();
    if (gate != null) await gate!.future;
    if (failPages.contains(page)) {
      throw const AttachmentFailure('attachment_page_limit');
    }
    final side = _sourceSide(bytes);
    rendered.add(page);
    return _solidImage(side);
  }

  int _sourceSide(Uint8List bytes) =>
      utf8.decode(bytes, allowMalformed: true).contains('source-b') ? 3 : 2;
}

Future<ui.Image> _solidImage(int side) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(side, side);
  } finally {
    picture.dispose();
  }
}

Uint8List _pdf(String marker) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n$marker\n'));

AttachmentInspection _inspection(Uint8List bytes, int pages) =>
    AttachmentInspection(
      mediaKind: AttachmentMediaKind.pdf,
      byteCount: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      mimeType: 'application/pdf',
      pageCount: pages,
    );

Future<({RecordStore store, SubstanceItem item})> _openFixture(
  WidgetTester tester,
) async {
  final directory = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-preview-lifecycle-'),
  ))!;
  final store = (await runIo(
    tester,
    () => RecordStore.open(
      path: '${directory.path}/test.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    ),
  ))!;
  addTearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  await runIo(tester, () async {
    final me = (await store.profileById(meId))!;
    await store.editProfile(
      commandId: 'preview-adult-${store.generation}',
      personId: meId,
      expectedRevision: me.revision,
      name: 'Me',
      adultConfirmed: true,
    );
  });
  final item = (await runIo(
    tester,
    () => store.createItem(
      commandId: 'preview-item-${store.generation}',
      expectedPersonRevision: 2,
      name: 'Preview fixture',
      form: 'Tablet',
      unit: 'count',
      type: 'Medicine',
    ),
  ))!;
  return (store: store, item: item);
}

Future<AttachmentRecord> _seedPdf(
  WidgetTester tester,
  RecordStore store,
  SubstanceItem item, {
  required String id,
  required String version,
  required Uint8List bytes,
  required int pages,
}) async => (await runIo(tester, () async {
  final owner = (await store.profileById(meId))!;
  final jobId = '$id-job';
  final job = AttachmentJob(
    id: jobId,
    generation: store.generation,
    personId: meId,
    expectedPersonRevision: owner.revision,
    targetKind: AttachmentTargetKind.item,
    targetId: item.id,
    targetRevision: item.revision,
    attachmentId: id,
    versionId: version,
    name: 'Original.pdf',
    createdAt: DateTime.now().toUtc(),
  );
  await store.beginAttachment(
    BeginAttachmentCommand(commandId: '$id-begin', job: job),
  );
  await store.appendAttachmentChunk(
    commandId: '$id-chunk',
    jobId: jobId,
    generation: store.generation,
    offset: 0,
    bytes: bytes,
  );
  return store.publishAttachment(
    commandId: '$id-publish',
    jobId: jobId,
    generation: store.generation,
    inspection: _inspection(bytes, pages),
  );
}))!;

Future<ProviderContainer> _pumpSurface(
  WidgetTester tester, {
  required RecordStore store,
  required ValueNotifier<AttachmentRecord> source,
  required AttachmentPdfDecoder pdf,
  _StoreSlot? slot,
}) async {
  final container = ProviderContainer(
    overrides: [
      appLockProvider.overrideWith(_PreviewLock.new),
      attachmentMediaProvider.overrideWithValue(
        AttachmentMediaDecoder(pdf: pdf),
      ),
      recordStoreProvider.overrideWith((ref) async => slot?.store ?? store),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
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
        home: VitalComponentThemes(
          child: Scaffold(
            child: SingleChildScrollView(
              child: ValueListenableBuilder<AttachmentRecord>(
                valueListenable: source,
                builder: (context, value, _) =>
                    AttachmentPreviewSurface(attachment: value),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return container;
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(VitalButton, label);
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await settle(tester);
}

double _zoomScale(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

int _imageSide(WidgetTester tester) =>
    tester.widget<RawImage>(find.byType(RawImage)).image!.width;

Finder get _previewFailure =>
    find.textContaining('Unable to show this preview');

void main() {
  testWidgets('a changed source clears an old failure, page and zoom', (
    tester,
  ) async {
    final f = await _openFixture(tester);
    final firstBytes = _pdf('source-a');
    final first = await _seedPdf(
      tester,
      f.store,
      f.item,
      id: 'preview-a',
      version: 'version-a',
      bytes: firstBytes,
      pages: 3,
    );
    final second = await _seedPdf(
      tester,
      f.store,
      f.item,
      id: 'preview-b',
      version: 'version-b',
      bytes: _pdf('source-b'),
      pages: 1,
    );
    final source = ValueNotifier(first);
    addTearDown(source.dispose);
    await _pumpSurface(
      tester,
      store: f.store,
      source: source,
      pdf: _FakePdfDecoder(failPages: {3}),
    );

    expect(find.text('Page 1 of 3'), findsOneWidget);
    await _tapButton(tester, 'Next');
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await _tapButton(tester, 'Zoom');
    expect(_zoomScale(tester), closeTo(1.5, 0.001));

    // The same immutable source may arrive as a fresh record instance. It must
    // keep the reader's page and zoom rather than resetting them.
    source.value = AttachmentRecord.fromJson({
      ...first.toJson(),
      'name': 'Same source, new label',
    });
    await tester.pump();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(_zoomScale(tester), closeTo(1.5, 0.001));

    await _tapButton(tester, 'Next');
    expect(find.text('Page 3 of 3'), findsOneWidget);
    expect(_previewFailure, findsOneWidget);

    source.value = second;
    await settle(tester);

    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(_previewFailure, findsNothing);
    expect(_imageSide(tester), 3);
    expect(_zoomScale(tester), closeTo(1, 0.001));
  });

  testWidgets('a source change during decode never restores the old source', (
    tester,
  ) async {
    final f = await _openFixture(tester);
    final first = await _seedPdf(
      tester,
      f.store,
      f.item,
      id: 'preview-a',
      version: 'version-a',
      bytes: _pdf('source-a'),
      pages: 1,
    );
    final second = await _seedPdf(
      tester,
      f.store,
      f.item,
      id: 'preview-b',
      version: 'version-b',
      bytes: _pdf('source-b'),
      pages: 1,
    );
    final pdf = _FakePdfDecoder()..gate = Completer<void>();
    final source = ValueNotifier(first);
    addTearDown(source.dispose);
    await _pumpSurface(tester, store: f.store, source: source, pdf: pdf);
    await _waitFor(tester, () => pdf.renderStarted.isCompleted);

    source.value = second;
    await tester.pump();
    // The new source reaches its own decode while the first decode is still
    // open. It must wait or retry, never bind the first result or stay failed.
    await settle(tester);
    pdf.gate!.complete();
    await settle(tester);

    expect(_previewFailure, findsNothing);
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(_imageSide(tester), 3);
  });

  testWidgets('a replaced store loads the same source from the current store', (
    tester,
  ) async {
    final firstStore = await _openFixture(tester);
    final secondStore = await _openFixture(tester);
    final first = await _seedPdf(
      tester,
      firstStore.store,
      firstStore.item,
      id: 'preview-shared',
      version: 'version-shared',
      bytes: _pdf('source-a'),
      pages: 1,
    );
    final second = await _seedPdf(
      tester,
      secondStore.store,
      secondStore.item,
      id: 'preview-shared',
      version: 'version-shared',
      bytes: _pdf('source-b'),
      pages: 1,
    );
    expect(second.generation, isNot(first.generation));
    expect(second.revision, first.revision);
    expect(second.versionId, first.versionId);

    final source = ValueNotifier(first);
    addTearDown(source.dispose);
    final slot = _StoreSlot(firstStore.store);
    final container = await _pumpSurface(
      tester,
      store: firstStore.store,
      source: source,
      pdf: _FakePdfDecoder(),
      slot: slot,
    );
    expect(_imageSide(tester), 2);

    slot.store = secondStore.store;
    container.invalidate(recordStoreProvider);
    source.value = second;
    await settle(tester);
    await settle(tester);

    expect(_previewFailure, findsNothing);
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    expect(_imageSide(tester), 3);
  });
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw TestFailure('Expected preview work did not start');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}
