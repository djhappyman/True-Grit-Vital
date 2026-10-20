import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/attachments/attachment_pages.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'attachment_ui_test.dart' show attachmentAppTest, fixture, openList;
import 'vital_app_test.dart' show runIo, settle;

/// Seeds protected ready files with explicit creation times so page order and
/// timestamp ties are deterministic rather than dependent on wall-clock time.
Future<Map<String, AttachmentRecord>> seedAttachmentList(
  RecordStore store,
  SubstanceItem item,
  int count, {
  String prefix = 'File',
  DateTime? base,
  DateTime Function(int index)? at,
}) async {
  final records = <String, AttachmentRecord>{};
  final moment = base ?? DateTime.utc(2026, 10, 20, 9);
  final bytes = Uint8List.fromList([0x20, 0x26]);
  final inspection = AttachmentInspection(
    mediaKind: AttachmentMediaKind.other,
    byteCount: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    mimeType: 'application/octet-stream',
  );
  final ownerRevision = (await store.profileById(meId))!.revision;
  for (var index = 0; index < count; index++) {
    final id = index.toString().padLeft(2, '0');
    final createdAt = at?.call(index) ?? moment.add(Duration(seconds: index));
    final job = AttachmentJob(
      id: 'job-$prefix-$id',
      generation: store.generation,
      personId: meId,
      expectedPersonRevision: ownerRevision,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      targetRevision: item.revision,
      attachmentId: 'attachment-$prefix-$id',
      versionId: 'version-$prefix-$id',
      name: '$prefix $id',
      createdAt: createdAt,
    );
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin-$prefix-$id', job: job),
    );
    await store.appendAttachmentChunk(
      commandId: 'chunk-$prefix-$id',
      jobId: job.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    records[id] = await store.publishAttachment(
      commandId: 'publish-$prefix-$id',
      jobId: job.id,
      generation: store.generation,
      inspection: inspection,
    );
  }
  return records;
}

List<AttachmentRecord> newestFirst(Iterable<AttachmentRecord> records) {
  final ordered = records.toList()
    ..sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  return ordered;
}

void main() {
  group('attachment list keyset pages', () {
    late Directory dir;
    late RecordStore store;
    late SubstanceItem item;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vital-attachment-list-');
      store = await RecordStore.open(
        path: '${dir.path}/attachment-list.db',
        key: List.generate(32, (index) => index + 1),
        isNew: true,
      );
      item = await store.createItem(
        commandId: 'item',
        name: 'Synthetic file item',
        form: 'tablet',
        unit: 'count',
        type: 'medicine',
      );
    });

    tearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });

    test('55 files with ties keep the older tail reachable after a preceding '
        'rename, delete and newer insert', () async {
      // Seven files share each second, including the tie across the 50-row
      // page boundary, so continuation must use `id` as its second key.
      final records = await seedAttachmentList(
        store,
        item,
        55,
        at: (index) =>
            DateTime.utc(2026, 10, 20, 9).add(Duration(seconds: index ~/ 7)),
      );
      final expected = newestFirst(records.values);
      expect(expected, hasLength(55));
      expect(expected[49].createdAt, expected[50].createdAt);

      Future<AttachmentPage> readPage(AttachmentPageCursor? cursor) =>
          store.attachmentPage(
            personId: meId,
            targetKind: AttachmentTargetKind.item,
            targetId: item.id,
            limit: attachmentListPageSize,
            cursor: cursor,
          );

      final first = await readPage(null);
      expect(
        first.records.map((record) => record.id),
        expected.take(attachmentListPageSize).map((record) => record.id),
      );
      expect(first.hasMore, isTrue);
      final cursor = first.nextCursor!;

      // Mutate only rows before the captured cursor: rename then delete the
      // newest file and insert a newer one. An offset window would now shift
      // by one and skip the surviving row that follows the old boundary.
      final owner = (await store.profileById(meId))!;
      final renamed = await store.renameAttachment(
        commandId: 'rename-head',
        attachment: expected.first,
        expectedPersonRevision: owner.revision,
        name: 'Renamed head',
      );
      await store.deleteAttachment(
        commandId: 'delete-head',
        attachment: renamed,
        expectedPersonRevision: owner.revision,
      );

      // The old offset window now skips the surviving row that shifted into
      // the gap; the captured keyset cursor still starts at that row.
      final offsetTail = await store.attachments(
        personId: meId,
        targetKind: AttachmentTargetKind.item,
        targetId: item.id,
        limit: attachmentListPageSize,
        offset: attachmentListPageSize,
      );
      expect(
        offsetTail.map((record) => record.id),
        expected.skip(attachmentListPageSize + 1).map((record) => record.id),
      );
      final cursorAfterDelete = await readPage(cursor);
      expect(
        cursorAfterDelete.records.map((record) => record.id),
        expected.skip(attachmentListPageSize).map((record) => record.id),
      );

      await seedAttachmentList(
        store,
        item,
        1,
        prefix: 'New',
        at: (_) => DateTime.utc(2026, 10, 20, 10),
      );

      final second = await readPage(cursor);
      final tail = expected.skip(attachmentListPageSize).toList();
      expect(
        second.records.map((record) => record.id),
        tail.map((record) => record.id),
      );
      expect(second.hasMore, isFalse);
      expect(
        second.records.where((record) => record.name == 'New 00'),
        isEmpty,
      );

      final survivingFirstPage = {
        for (final record in first.records)
          if (record.id != renamed.id) record.id,
      };
      final secondIds = second.records.map((record) => record.id).toSet();
      expect(survivingFirstPage.intersection(secondIds), isEmpty);
      // The 49 surviving first-page rows plus the 5 older rows reach every
      // original survivor exactly once. The newer insert waits for refresh.
      expect(survivingFirstPage, hasLength(49));
      expect(secondIds, hasLength(5));
      expect(second.records.last.name, expected.last.name);

      // A deliberate head refresh shows the new file and the remaining
      // order, while the captured cursor above still reached the old tail.
      final refreshed = await readPage(null);
      expect(refreshed.records.first.name, 'New 00');
      expect(
        refreshed.records.map((record) => record.name),
        isNot(contains('Renamed head')),
      );
      expect(refreshed.hasMore, isTrue);
    });
  });

  attachmentAppTest(
    'list navigation keeps its cursor chain through a viewer return and '
    'shows the whole tail once',
    (tester) async {
      final fixtureData = await fixture(
        tester,
        prepare: (store, item) => seedAttachmentList(store, item, 60),
      );
      await openList(tester, fixtureData.container, fixtureData.item);

      List<String> visibleNames() => [
        for (final tile in tester.widgetList<AttachmentTile>(
          find.byType(AttachmentTile),
        ))
          tile.attachment.name,
      ];
      Future<void> press(String label) async {
        final button = find.widgetWithText(VitalButton, label);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await settle(tester);
      }

      final firstPage = visibleNames();
      expect(firstPage, hasLength(attachmentListPageSize));
      expect(firstPage.first, 'File 59');
      expect(firstPage.last, 'File 10');
      expect(find.widgetWithText(VitalButton, 'Previous'), findsNothing);
      expect(find.widgetWithText(VitalButton, 'Next'), findsOneWidget);
      final preceding = tester
          .widgetList<AttachmentTile>(find.byType(AttachmentTile))
          .firstWhere((tile) => tile.attachment.name == 'File 59')
          .attachment;

      await press('Next');
      expect(visibleNames(), [
        'File 09',
        'File 08',
        'File 07',
        'File 06',
        'File 05',
        'File 04',
        'File 03',
        'File 02',
        'File 01',
        'File 00',
      ]);
      expect(find.widgetWithText(VitalButton, 'Previous'), findsOneWidget);
      expect(find.widgetWithText(VitalButton, 'Next'), findsNothing);

      // Opening a file and returning must land on the same page rather than
      // restarting at the head or replaying the last server window.
      await tester.tap(find.widgetWithText(VitalButton, 'Open').first);
      await settle(tester);
      expect(find.text('File 09'), findsWidgets);
      await press('Back');
      expect(visibleNames().first, 'File 09');

      // Deleting a row from the previous page while this page is visible is
      // the concrete offset defect: an offset would shift and skip File 09.
      final owner = (await runIo(
        tester,
        () => fixtureData.store.profileById(meId),
      ))!;
      await runIo(
        tester,
        () => fixtureData.store.deleteAttachment(
          commandId: newCommandId(),
          attachment: preceding,
          expectedPersonRevision: owner.revision,
        ),
      );
      await settle(tester);
      expect(visibleNames().first, 'File 09');
      expect(visibleNames(), hasLength(10));

      // A newer insert also waits for the head page; it cannot renumber this
      // page's continuation or duplicate a visible row.
      await runIo(
        tester,
        () => seedAttachmentList(
          fixtureData.store,
          fixtureData.item,
          1,
          prefix: 'New',
          at: (_) => DateTime.utc(2026, 10, 21),
        ),
      );
      await settle(tester);
      expect(visibleNames().first, 'File 09');
      expect(visibleNames(), hasLength(10));

      await press('Previous');
      final refreshedFirstPage = visibleNames();
      expect(refreshedFirstPage, hasLength(attachmentListPageSize));
      expect(refreshedFirstPage.first, 'New 00');
      expect(refreshedFirstPage, isNot(contains('File 59')));
      expect(find.widgetWithText(VitalButton, 'Next'), findsOneWidget);

      await press('Next');
      final lastPage = visibleNames();
      final combined = [...refreshedFirstPage, ...lastPage];
      expect(combined, hasLength(60));
      expect(combined.toSet(), hasLength(60));
      expect(combined, contains('File 09'));
      expect(combined, contains('File 00'));
      expect(combined, contains('New 00'));
    },
  );
}
