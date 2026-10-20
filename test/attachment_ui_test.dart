import 'package:true_grit_vital/ui/vital_ui.dart';

import 'fixtures/single_user.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/attachments.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/attachments.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'attachments/attachment_pdf_test.dart' show syntheticPdf;
import 'attachments/protected_file_probe_test.dart' show png;
import 'daily_plan_ui_test.dart' show tap;
import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart' show appTest, runIo, settle, waitForText;

class FixtureFileGateway implements AttachmentGateway {
  FixtureFileGateway(
    this.source, {
    this.shareEnabled = false,
    this.saveEnabled = true,
  });
  Uint8List source;
  String name = 'Original.png';
  bool shareEnabled, saveEnabled, cancelled = false, recover = false;
  int? advertisedBytes;
  Completer<AttachmentSelection?>? pending;
  final picked = <String>[], finished = <String>[];
  Uint8List? saved;
  AttachmentSelection selection(String jobId) => AttachmentSelection(
    jobId: jobId,
    name: name,
    byteCount: advertisedBytes ?? source.length,
    openRead: () => Stream.value(source),
  );
  @override
  AttachmentCapabilities get capabilities => AttachmentCapabilities(
    pickFile: true,
    photo: true,
    camera: false,
    share: shareEnabled,
    save: saveEnabled,
  );
  @override
  Future<AttachmentSelection?> pickFile({required String jobId}) async {
    picked.add(jobId);
    if (pending != null) return await pending!.future;
    return cancelled ? null : selection(jobId);
  }

  @override
  Future<AttachmentSelection?> pickPhoto({
    required String jobId,
    bool camera = false,
  }) => pickFile(jobId: jobId);
  @override
  Future<AttachmentSelection?> recoverSelection({
    required String jobId,
  }) async => recover ? selection(jobId) : null;
  @override
  Future<void> finishSelection(String jobId) async {
    finished.add(jobId);
  }

  @override
  Future<bool> save({
    required String name,
    required String mime,
    required Uint8List bytes,
  }) async {
    saved = Uint8List.fromList(bytes);
    return !cancelled;
  }
}

class FixtureHandoff implements AttachmentHandoffGateway {
  final chunks = <String, BytesBuilder>{}, expiries = <String, DateTime>{};
  final offered = <String>{};
  Future<void> Function()? onShare;
  int shares = 0;
  @override
  Future<void> begin({
    required String id,
    required String name,
    required String mime,
    required DateTime expiresAt,
  }) async {
    chunks[id] = BytesBuilder(copy: true);
    expiries[id] = expiresAt;
  }

  @override
  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  }) async {
    expect(chunks[id]!.length, offset);
    chunks[id]!.add(bytes);
    return offset + bytes.length;
  }

  @override
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) async {
    expect(chunks[id]!.length, byteCount);
  }

  @override
  Future<bool> share(String id) async {
    offered.add(id);
    shares++;
    await onShare?.call();
    return true;
  }

  @override
  Future<bool> cancel(String id) async {
    if (offered.contains(id)) return false;
    chunks.remove(id);
    return true;
  }

  @override
  Future<List<String>> cleanup() async => [];
}

Future<AttachmentRecord> seedFile(
  RecordStore store,
  SubstanceItem item,
  Uint8List bytes, {
  String name = 'Original.png',
  AttachmentTargetKind kind = AttachmentTargetKind.item,
  String? target,
  int revision = 1,
}) async {
  final job = AttachmentJob(
    id: newCommandId(),
    generation: store.generation,
    personId: item.personId,
    expectedPersonRevision: (await store.profileById(item.personId))!.revision,
    targetKind: kind,
    targetId: target ?? item.id,
    targetRevision: kind == AttachmentTargetKind.item
        ? item.revision
        : revision,
    attachmentId: newCommandId(),
    versionId: newCommandId(),
    name: name,
    createdAt: DateTime.now().toUtc(),
  );
  await store.beginAttachment(
    BeginAttachmentCommand(commandId: newCommandId(), job: job),
  );
  final inspection = await defaultAttachmentMediaDecoder().inspect(bytes);
  var offset = 0;
  await for (final chunk in boundedAttachmentChunks(Stream.value(bytes))) {
    await store.appendAttachmentChunk(
      commandId: newCommandId(),
      jobId: job.id,
      generation: job.generation,
      offset: offset,
      bytes: chunk,
    );
    offset += chunk.length;
  }
  return store.publishAttachment(
    commandId: newCommandId(),
    jobId: job.id,
    generation: job.generation,
    inspection: inspection,
    name: name,
  );
}

Future<
  ({
    RecordStore store,
    ProviderContainer container,
    SubstanceItem item,
    FixtureFileGateway gateway,
    FixtureHandoff handoff,
  })
>
fixture(
  WidgetTester tester, {
  FixtureFileGateway? gateway,
  Future<void> Function(RecordStore, SubstanceItem)? prepare,
  bool reopen = false,
}) async {
  final directory = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-file-ui-'),
  ))!;
  final key = List.generate(32, (i) => i + 1),
      path = '${directory.path}/files.sqlite';
  var store = (await runIo(
    tester,
    () => RecordStore.open(path: path, key: key, isNew: true),
  ))!;
  final item = (await runIo(tester, () async {
    await store.editProfile(
      commandId: newCommandId(),
      personId: meId,
      expectedRevision: 1,
      name: 'Main Adult',
      adultConfirmed: true,
    );
    await store.saveBrowsingScope(const FeedScope.me());
    return store.createItem(
      commandId: newCommandId(),
      personId: meId,
      expectedPersonRevision: 2,
      name: 'Synthetic file item',
      form: 'Tablet',
      unit: 'count',
      type: 'Test',
    );
  }))!;
  if (prepare != null) await runIo(tester, () => prepare(store, item));
  if (reopen) {
    await runIo(tester, store.close);
    store = (await runIo(
      tester,
      () => RecordStore.open(path: path, key: key, isNew: false),
    ))!;
  }
  final files =
      gateway ?? FixtureFileGateway((await runIo(tester, () => png(8, 8)))!);
  final handoff = FixtureHandoff();
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() async => store),
      appAuthGatewayProvider.overrideWithValue(FakeAuth()),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      attachmentGatewayProvider.overrideWithValue(files),
      attachmentHandoffProvider.overrideWithValue(handoff),
    ],
  );
  activeContainer = container;
  addTearDown(() async {
    container.dispose();
    await runIo(tester, store.close);
    await runIo(tester, () => directory.delete(recursive: true));
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  return (
    store: store,
    container: container,
    item: item,
    gateway: files,
    handoff: handoff,
  );
}

Finder field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);
Future<void> openList(
  WidgetTester tester,
  ProviderContainer container,
  SubstanceItem item,
) async {
  container.read(routerProvider).go('/files/${item.personId}/item/${item.id}');
  await settle(tester);
}

ProviderContainer? activeContainer;

void attachmentAppTest(String name, Future<void> Function(WidgetTester) body) {
  appTest(name, (tester) async {
    try {
      await body(tester);
    } finally {
      // The attachment controller keeps a cleanup timer alive. Dispose the
      // external container inside the test body so the widget-test harness
      // does not report that timer as a leak after the tree is removed.
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      activeContainer?.dispose();
      activeContainer = null;
    }
  });
}

void main() {
  setUpAll(() {
    if (Platform.isLinux) {
      Pdfrx.pdfiumModulePath = File('build/native_assets/linux/libpdfium.so')
          .absolute
          .path;
    }
  });
  attachmentAppTest(
    'file picker captures adult and item before selection and ignores later feed scope',
    (tester) async {
      final source = (await runIo(tester, () => png(8, 8)))!,
          gateway = FixtureFileGateway(source)
            ..pending = Completer<AttachmentSelection?>();
      final f = await fixture(tester, gateway: gateway);
      await openList(tester, f.container, f.item);
      await tap(tester, 'Choose');
      final job = (await runIo(tester, f.store.pendingAttachmentJobs))!.single;
      expect(job.personId, meId);
      expect(job.targetId, f.item.id);
      final other = (await runIo(
        tester,
        () => f.store.createProfile(
          commandId: newCommandId(),
          name: 'Other adult',
          adultConfirmed: true,
        ),
      ))!;
      await runIo(
        tester,
        () => f.store.saveBrowsingScope(FeedScope.person(other.id)),
      );
      gateway.pending!.complete(gateway.selection(job.id));
      await waitForText(tester, 'File added to this record.');
      final saved = (await runIo(
        tester,
        () => f.store.attachments(personId: meId),
      ))!.single;
      expect(saved.targetId, f.item.id);
      expect(
        await runIo(tester, () => f.store.attachments(personId: other.id)),
        isEmpty,
      );
      expect(source, gateway.source);
      expect(gateway.finished, contains(job.id));
    },
  );
  attachmentAppTest(
    'cancelled selection publishes no attachment and keeps the selected source',
    (tester) async {
      final f = await fixture(tester);
      f.gateway.cancelled = true;
      await openList(tester, f.container, f.item);
      await tap(tester, 'Choose');
      await waitForText(
        tester,
        'Selection cancelled. The original is unchanged.',
      );
      expect(
        await runIo(tester, () => f.store.attachments(personId: meId)),
        isEmpty,
      );
      expect(await runIo(tester, f.store.pendingAttachmentJobs), isEmpty);
    },
  );
  attachmentAppTest(
    'reopened picker job resumes only its original adult while Me is visible',
    (tester) async {
      final source = (await runIo(tester, () => png(8, 8)))!,
          gateway = FixtureFileGateway(source)..recover = true;
      late SubstanceItem original;
      final f = await fixture(
        tester,
        gateway: gateway,
        reopen: true,
        prepare: (store, _) async {
          final owner = await store.configureOwnProfile(
            commandId: newCommandId(),
            name: 'Recovered adult',
            adultConfirmed: true,
          );
          original = await store.createItem(
            commandId: newCommandId(),
            personId: owner.id,
            expectedPersonRevision: owner.revision,
            name: 'Recovered source',
            form: 'Tablet',
            unit: 'count',
            type: 'Test',
          );
          final job = AttachmentJob(
            id: newCommandId(),
            generation: store.generation,
            personId: owner.id,
            expectedPersonRevision: owner.revision,
            targetKind: AttachmentTargetKind.item,
            targetId: original.id,
            targetRevision: original.revision,
            attachmentId: newCommandId(),
            versionId: newCommandId(),
            name: 'Waiting original',
            createdAt: DateTime.now().toUtc(),
          );
          await store.beginAttachment(
            BeginAttachmentCommand(commandId: newCommandId(), job: job),
          );
        },
      );
      await settle(tester);
      expect(
        (await runIo(
          tester,
          () => f.store.attachments(personId: original.personId),
        ))!.single.targetId,
        original.id,
      );
      expect(
        await runIo(tester, () => f.store.attachments(personId: meId)),
        hasLength(1),
      );
      expect(
        await runIo(tester, f.store.readBrowsingScope),
        const FeedScope.me(),
      );
    },
  );
  attachmentAppTest(
    'changed dose revision rejects picker publication and remains cancellable',
    (tester) async {
      final f = await fixture(tester);
      f.gateway.pending = Completer<AttachmentSelection?>();
      final actual = (await runIo(
        tester,
        () => f.store.record(
          commandId: newCommandId(),
          itemId: f.item.id,
          personId: meId,
          expectedPersonRevision: 2,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 19, 12),
        ),
      ))!;
      f.container.read(routerProvider).go('/files/me/record/${actual.id}');
      await settle(tester);
      await tap(tester, 'Choose');
      final job = (await runIo(tester, f.store.pendingAttachmentJobs))!.single;
      await runIo(
        tester,
        () => f.store.correct(
          commandId: newCommandId(),
          recordId: actual.id,
          expectedRevision: actual.revision,
          personId: meId,
          expectedPersonRevision: 2,
          amount: '2',
          actualAt: actual.actualAt,
        ),
      );
      f.gateway.pending!.complete(f.gateway.selection(job.id));
      await waitForText(
        tester,
        'This file’s record changed or is unavailable. Return to its original record and review it.',
      );
      expect(
        await runIo(tester, () => f.store.attachments(personId: meId)),
        isEmpty,
      );
      await tap(tester, 'Cancel');
      expect(await runIo(tester, f.store.pendingAttachmentJobs), isEmpty);
      expect(
        (await runIo(
          tester,
          () => f.store.recordById(actual.id, personId: meId),
        ))!.revision,
        2,
      );
    },
  );
  attachmentAppTest(
    'bounded image preview clears on lock and reloads only after unlock',
    (tester) async {
      final f = await fixture(tester),
          source = (await runIo(tester, () => png(2048, 1024)))!;
      final file = (await runIo(
        tester,
        () => seedFile(f.store, f.item, source),
      ))!;
      f.container.read(routerProvider).go('/attachment/${file.id}');
      await waitForText(tester, 'Page 1 of 1');
      await settle(tester);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(image.width, lessThanOrEqualTo(1600));
      expect(
        image.width * image.height * 4,
        lessThanOrEqualTo(AttachmentLimits.maxPreviewBytes),
      );
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.inactive);
      await settle(tester);
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.resumed);
      await tap(tester, 'Unlock');
      await settle(tester);
      expect(find.byType(RawImage), findsOneWidget);
      expect(
        (await runIo(
          tester,
          () => f.store.attachmentById(file.id),
        ))!.inspection!.byteCount,
        source.length,
      );
    },
  );
  attachmentAppTest(
    'real PDF original renders bounded pages with working page controls',
    (tester) async {
      final f = await fixture(tester),
          source = syntheticPdf(3, width: 40000, height: 40000);
      final file = (await runIo(
        tester,
        () => seedFile(f.store, f.item, source, name: 'Original.pdf'),
      ))!;
      f.container.read(routerProvider).go('/attachment/${file.id}');
      await waitForText(tester, 'Page 1 of 3');
      await settle(tester);
      expect(find.byType(RawImage), findsOneWidget);
      await tap(tester, 'Next');
      await waitForText(tester, 'Page 2 of 3');
      await settle(tester);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(
        image.width * image.height * 4,
        lessThanOrEqualTo(AttachmentLimits.maxPreviewBytes),
      );
      await tap(tester, 'Previous');
      await waitForText(tester, 'Page 1 of 3');
    },
  );
  attachmentAppTest(
    'rename retains invalid raw input through lock then restores focus to Rename',
    (tester) async {
      final f = await fixture(tester),
          source = (await runIo(tester, () => png(8, 8)))!;
      final file = (await runIo(
        tester,
        () => seedFile(f.store, f.item, source),
      ))!;
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(routerProvider).go('/attachment/${file.id}/rename');
      await settle(tester);
      await tester.enterText(field('File name'), '');
      await tap(tester, 'Save');
      expect(
        find.text('Enter a file name with 1 to 255 characters.'),
        findsWidgets,
      );
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.inactive);
      await settle(tester);
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.resumed);
      await tap(tester, 'Unlock');
      expect(tester.widget<TextField>(field('File name')).controller!.text, '');
      await tester.enterText(field('File name'), 'Readable original');
      await tap(tester, 'Save');
      await waitForText(tester, 'Original file');
      await settle(tester);
      expect(
        (await runIo(tester, () => f.store.attachmentById(file.id)))!.name,
        'Readable original',
      );
      final rename = tester.widget<VitalButton>(
        find.widgetWithText(VitalButton, 'Rename'),
      );
      expect(rename.focusNode!.hasFocus, true);
      expect(
        (await runIo(tester, () => f.store.attachmentById(file.id)))!.versionId,
        file.versionId,
      );
    },
  );
  attachmentAppTest(
    'delete cancellation returns focus and deletion returns to the original file list',
    (tester) async {
      final f = await fixture(tester),
          source = (await runIo(tester, () => png(8, 8)))!;
      final file = (await runIo(
        tester,
        () => seedFile(f.store, f.item, source),
      ))!;
      f.container.read(routerProvider).go('/attachment/${file.id}');
      await settle(tester);
      await tap(tester, 'Delete');
      expect(find.text('Delete from record'), findsOneWidget);
      expect(
        find.textContaining(
          'Vital removes its protected copy after any open preview or share releases it.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Your source file and shared copies stay unchanged.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('when open uses finish'), findsNothing);
      await tap(tester, 'Cancel');
      final delete = tester.widget<VitalButton>(
        find.widgetWithText(VitalButton, 'Delete'),
      );
      expect(delete.focusNode!.hasFocus, true);
      expect(
        await runIo(tester, () => f.store.attachmentById(file.id)),
        isNotNull,
      );
      await tap(tester, 'Delete');
      await tap(tester, 'Delete');
      await waitForText(
        tester,
        'No files attached. Choose a file or an existing photo to add one.',
      );
      expect(
        await runIo(tester, () => f.store.attachmentById(file.id)),
        isNull,
      );
      expect(
        f.container.read(routerProvider).routerDelegate.state.uri.path,
        '/files/me/item/${f.item.id}',
      );
    },
  );
  attachmentAppTest(
    'stale delete confirmation refuses the changed file and a retry deletes the current one',
    (tester) async {
      final f = await fixture(tester),
          source = (await runIo(tester, () => png(8, 8)))!;
      final file = (await runIo(
        tester,
        () => seedFile(f.store, f.item, source),
      ))!;
      f.container.read(routerProvider).go('/attachment/${file.id}');
      await settle(tester);
      await tap(tester, 'Delete');
      expect(find.text('Delete from record'), findsOneWidget);
      // The file is renamed while the confirmation is open, so the confirmed
      // attempt is now stale and must refuse to delete the changed record.
      await runIo(
        tester,
        () => f.store.renameAttachment(
          commandId: newCommandId(),
          attachment: file,
          expectedPersonRevision: 2,
          name: 'Renamed.png',
        ),
      );
      await tap(tester, 'Delete');
      await waitForText(
        tester,
        'This file’s record changed or is unavailable. Return to its original record and review it.',
      );
      expect(
        (await runIo(tester, () => f.store.attachmentById(file.id)))!.name,
        'Renamed.png',
      );
      // Retrying reviews the current revision, so the delete can finish.
      await tap(tester, 'Delete');
      await tap(tester, 'Delete');
      await waitForText(
        tester,
        'No files attached. Choose a file or an existing photo to add one.',
      );
      expect(
        await runIo(tester, () => f.store.attachmentById(file.id)),
        isNull,
      );
    },
  );
  attachmentAppTest(
    'share retains a named original handoff after lock and never changes its bytes',
    (tester) async {
      final f = await fixture(tester);
      f.gateway.shareEnabled = true;
      final source = (await runIo(tester, () => png(8, 8)))!,
          file = (await runIo(
            tester,
            () => seedFile(f.store, f.item, source),
          ))!;
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.handoff.onShare = () async {
        f.container
            .read(appLockProvider.notifier)
            .lifecycle(AppLifecycleState.inactive);
      };
      f.container.read(routerProvider).go('/attachment/${file.id}');
      await settle(tester);
      await tap(tester, 'Share');
      expect(find.textContaining('Main Adult'), findsWidgets);
      await tap(tester, 'Share');
      expect(f.handoff.shares, 1);
      expect(f.handoff.chunks.values.single.toBytes(), source);
      expect(f.handoff.offered.length, 1);
      expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.resumed);
      await tap(tester, 'Unlock');
      await waitForText(
        tester,
        'Share opened. The prepared original stays available for up to 24 hours.',
      );
      expect(f.handoff.chunks.values.single.toBytes(), source);
      expect(
        await runIo(tester, () => f.store.attachmentById(file.id)),
        isNotNull,
      );
    },
  );
  attachmentAppTest(
    'save uses unchanged bytes and malformed input leaves an actionable waiting job',
    (tester) async {
      final f = await fixture(tester),
          source = (await runIo(tester, () => png(8, 8)))!;
      final file = (await runIo(
        tester,
        () => seedFile(f.store, f.item, source),
      ))!;
      f.container.read(routerProvider).go('/attachment/${file.id}');
      await settle(tester);
      await tap(tester, 'Save');
      await tap(tester, 'Save');
      await waitForText(tester, 'Copy saved to the location you chose.');
      expect(f.gateway.saved, source);
      f.gateway.source = Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      await openList(tester, f.container, f.item);
      await tap(tester, 'Choose');
      await waitForText(
        tester,
        'This image cannot be previewed. Choose a complete image with at most 16 million pixels and one frame. Your source is unchanged.',
      );
      expect(
        (await runIo(
          tester,
          () => f.store.attachments(personId: meId),
        ))!.length,
        1,
      );
      expect((await runIo(tester, f.store.pendingAttachmentJobs))!.length, 1);
      await tap(tester, 'Cancel');
      expect(await runIo(tester, f.store.pendingAttachmentJobs), isEmpty);
    },
  );

  attachmentAppTest('voided dose explains why files cannot be added', (
    tester,
  ) async {
    final f = await fixture(tester);
    final actual = (await runIo(
      tester,
      () => f.store.record(
        commandId: newCommandId(),
        itemId: f.item.id,
        personId: meId,
        expectedPersonRevision: 2,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 19, 12),
      ),
    ))!;
    await runIo(
      tester,
      () => f.store.voidRecord(
        commandId: newCommandId(),
        recordId: actual.id,
        expectedRevision: actual.revision,
        expectedPersonRevision: 2,
      ),
    );
    f.container.read(routerProvider).go('/files/me/record/${actual.id}');
    await settle(tester);
    expect(
      find.text('This dose is voided. Files cannot be added to it.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<VitalButton>(find.widgetWithText(VitalButton, 'Choose'))
          .onPressed,
      isNull,
    );
  });
  attachmentAppTest(
    'share-only platform names Share and does not promise Save',
    (tester) async {
      final source = (await runIo(tester, () => png(8, 8)))!;
      final f = await fixture(
        tester,
        gateway: FixtureFileGateway(
          source,
          shareEnabled: true,
          saveEnabled: false,
        ),
      );
      final image = (await runIo(
        tester,
        () => seedFile(f.store, f.item, source),
      ))!;
      final notes = (await runIo(
        tester,
        () => seedFile(
          f.store,
          f.item,
          Uint8List.fromList(utf8.encode('plain notes')),
          name: 'Notes.txt',
        ),
      ))!;
      f.container.read(routerProvider).go('/attachment/${image.id}');
      await waitForText(tester, 'Page 1 of 1');
      expect(
        find.text(
          'This preview is scaled for display. Sharing uses the unchanged original.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Saving uses'), findsNothing);
      expect(find.textContaining('share or save'), findsNothing);
      expect(find.widgetWithText(VitalButton, 'Share'), findsOneWidget);
      expect(find.widgetWithText(VitalButton, 'Save'), findsNothing);
      f.container.read(routerProvider).go('/attachment/${notes.id}');
      await settle(tester);
      expect(
        find.text(
          'This file type has no preview. You can share the unchanged original.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('save the unchanged original'), findsNothing);
      expect(find.textContaining('share or save'), findsNothing);
    },
  );
  attachmentAppTest(
    'save-only platform names Save and does not promise Share',
    (tester) async {
      final f = await fixture(tester);
      final image = (await runIo(
        tester,
        () async => seedFile(f.store, f.item, await png(8, 8)),
      ))!;
      final notes = (await runIo(
        tester,
        () => seedFile(
          f.store,
          f.item,
          Uint8List.fromList(utf8.encode('plain notes')),
          name: 'Notes.txt',
        ),
      ))!;
      f.container.read(routerProvider).go('/attachment/${image.id}');
      await waitForText(tester, 'Page 1 of 1');
      expect(
        find.text(
          'This preview is scaled for display. Saving uses the unchanged original.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Sharing uses'), findsNothing);
      expect(find.textContaining('share or save'), findsNothing);
      expect(find.widgetWithText(VitalButton, 'Share'), findsNothing);
      expect(find.widgetWithText(VitalButton, 'Save'), findsOneWidget);
      f.container.read(routerProvider).go('/attachment/${notes.id}');
      await settle(tester);
      expect(
        find.text(
          'This file type has no preview. You can save the unchanged original.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('share the unchanged original'), findsNothing);
      expect(find.textContaining('share or save'), findsNothing);
    },
  );
  for (final width in [320.0, 1200.0]) {
    attachmentAppTest(
      'shared file UI width $width works at double text without overflow',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final f = await fixture(tester);
        await openList(tester, f.container, f.item);
        await tap(tester, 'Choose');
        await waitForText(tester, 'File added to this record.');
        await tap(tester, 'Open');
        await waitForText(tester, 'Original file');
        await tap(tester, 'Rename');
        await tester.enterText(
          field('File name'),
          'Long synthetic original name for layout',
        );
        await tap(tester, 'Save');
        await waitForText(tester, 'Original file');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
