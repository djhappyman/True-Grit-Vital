import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  final bytes = Uint8List.fromList('Synthetic page original'.codeUnits);
  final base = DateTime.utc(2026, 10, 20, 9);

  AttachmentInspection inspection() => AttachmentInspection(
    mediaKind: AttachmentMediaKind.other,
    byteCount: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    mimeType: 'application/octet-stream',
  );

  Future<AttachmentRecord> saved(String id, DateTime createdAt) async {
    final job = AttachmentJob(
      id: 'job-$id',
      generation: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      targetRevision: 1,
      attachmentId: 'attachment-$id',
      versionId: 'version-$id',
      name: 'Source $id',
      createdAt: createdAt,
    );
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin-$id', job: job),
    );
    await store.appendAttachmentChunk(
      commandId: 'chunk-$id',
      jobId: job.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    return store.publishAttachment(
      commandId: 'publish-$id',
      jobId: job.id,
      generation: store.generation,
      inspection: inspection(),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-attachment-page-');
    store = await RecordStore.open(
      path: '${dir.path}/attachment.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic source',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  // Newest first by created_at DESC, then id ASC. b, c and d share a timestamp.
  Future<Map<String, AttachmentRecord>> seedOrdered() async {
    final records = <String, AttachmentRecord>{};
    records['a'] = await saved('a', base.add(const Duration(seconds: 10)));
    records['b'] = await saved('b', base.add(const Duration(seconds: 20)));
    records['c'] = await saved('c', base.add(const Duration(seconds: 20)));
    records['d'] = await saved('d', base.add(const Duration(seconds: 20)));
    records['e'] = await saved('e', base.add(const Duration(seconds: 5)));
    records['f'] = await saved('f', base);
    return records;
  }

  test(
    'fixed-size keyset pages keep order and tied timestamps stable',
    () async {
      await seedOrdered();

      final first = await store.attachmentPage(
        personId: meId,
        targetKind: AttachmentTargetKind.item,
        targetId: item.id,
        limit: 2,
      );
      expect(first.records.map((r) => r.name), ['Source b', 'Source c']);
      expect(first.records, hasLength(2));
      expect(first.hasMore, isTrue);
      final cursor = first.nextCursor!;
      expect(cursor.generation, store.generation);
      expect(cursor.personId, meId);
      expect(cursor.targetKind, AttachmentTargetKind.item);
      expect(cursor.targetId, item.id);
      expect(cursor.id, first.records.last.id);
      expect(
        cursor.createdAtMicros,
        first.records.last.createdAt.microsecondsSinceEpoch,
      );

      final second = await store.attachmentPage(
        personId: meId,
        targetKind: AttachmentTargetKind.item,
        targetId: item.id,
        limit: 2,
        cursor: cursor,
      );
      // The tie continues by id rather than restarting or skipping d.
      expect(second.records.map((r) => r.name), ['Source d', 'Source a']);

      final third = await store.attachmentPage(
        personId: meId,
        targetKind: AttachmentTargetKind.item,
        targetId: item.id,
        limit: 2,
        cursor: second.nextCursor,
      );
      expect(third.records.map((r) => r.name), ['Source e', 'Source f']);
      expect(third.hasMore, isFalse);
      expect(third.nextCursor, isNull);

      final paged = [...first.records, ...second.records, ...third.records];
      expect(paged, hasLength(6));
      expect(paged.map((r) => r.id).toSet(), hasLength(6));
      // The older offset API keeps its existing order for other callers.
      expect(
        (await store.attachments(
          personId: meId,
          targetKind: AttachmentTargetKind.item,
          targetId: item.id,
        )).map((r) => r.id),
        paged.map((r) => r.id),
      );
    },
  );

  test(
    'renaming or deleting a row before the cursor keeps older rows',
    () async {
      final records = await seedOrdered();
      final first = await store.attachmentPage(
        personId: meId,
        targetKind: AttachmentTargetKind.item,
        targetId: item.id,
        limit: 2,
      );
      final cursor = first.nextCursor!;
      final owner = (await store.profileById(meId))!;

      // Both mutations precede the cursor. An offset window would now skip d.
      final renamed = await store.renameAttachment(
        commandId: 'rename-b',
        attachment: records['b']!,
        expectedPersonRevision: owner.revision,
        name: 'Renamed b',
      );
      await store.deleteAttachment(
        commandId: 'delete-b',
        attachment: renamed,
        expectedPersonRevision: owner.revision,
      );

      final second = await store.attachmentPage(
        personId: meId,
        targetKind: AttachmentTargetKind.item,
        targetId: item.id,
        limit: 2,
        cursor: cursor,
      );
      expect(second.records.map((r) => r.name), ['Source d', 'Source a']);
      final third = await store.attachmentPage(
        personId: meId,
        targetKind: AttachmentTargetKind.item,
        targetId: item.id,
        limit: 2,
        cursor: second.nextCursor,
      );
      expect(third.records.map((r) => r.name), ['Source e', 'Source f']);
    },
  );

  test('a file inserted newer than the cursor waits for a refresh', () async {
    await seedOrdered();
    final first = await store.attachmentPage(
      personId: meId,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      limit: 2,
    );
    final cursor = first.nextCursor!;

    await saved('z', base.add(const Duration(seconds: 30)));

    final second = await store.attachmentPage(
      personId: meId,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      limit: 3,
      cursor: cursor,
    );
    // The new row neither repeats c nor appears before the cursor.
    expect(second.records.map((r) => r.name), [
      'Source d',
      'Source a',
      'Source e',
    ]);
    final refreshed = await store.attachmentPage(
      personId: meId,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      limit: 3,
    );
    expect(refreshed.records.first.name, 'Source z');
  });

  test('a cursor cannot continue a different scope or generation', () async {
    await seedOrdered();
    final first = await store.attachmentPage(
      personId: meId,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      limit: 2,
    );
    final cursor = first.nextCursor!;

    Future<void> rejects(AttachmentPageCursor candidate, String code) =>
        expectLater(
          store.attachmentPage(
            personId: meId,
            targetKind: AttachmentTargetKind.item,
            targetId: item.id,
            cursor: candidate,
          ),
          throwsA(
            isA<CommandConflict>().having((error) => error.code, 'code', code),
          ),
        );

    await rejects(
      AttachmentPageCursor(
        generation: cursor.generation,
        personId: 'another_adult',
        targetKind: cursor.targetKind,
        targetId: cursor.targetId,
        createdAtMicros: cursor.createdAtMicros,
        id: cursor.id,
      ),
      'attachment_cursor',
    );
    await rejects(
      AttachmentPageCursor(
        generation: cursor.generation,
        personId: cursor.personId,
        targetKind: AttachmentTargetKind.record,
        targetId: cursor.targetId,
        createdAtMicros: cursor.createdAtMicros,
        id: cursor.id,
      ),
      'attachment_cursor',
    );
    await rejects(
      AttachmentPageCursor(
        generation: cursor.generation,
        personId: cursor.personId,
        targetKind: cursor.targetKind,
        targetId: 'another_item',
        createdAtMicros: cursor.createdAtMicros,
        id: cursor.id,
      ),
      'attachment_cursor',
    );
    await rejects(
      AttachmentPageCursor(
        generation: 'replaced-generation',
        personId: cursor.personId,
        targetKind: cursor.targetKind,
        targetId: cursor.targetId,
        createdAtMicros: cursor.createdAtMicros,
        id: cursor.id,
      ),
      'generation',
    );

    final continued = await store.attachmentPage(
      personId: meId,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      limit: 2,
      cursor: cursor,
    );
    expect(continued.records.map((r) => r.name), ['Source d', 'Source a']);
  });

  test('page bounds reject a non-positive limit', () async {
    expect(
      () => store.attachmentPage(personId: meId, limit: 0),
      throwsA(isA<RangeError>()),
    );
  });
}
