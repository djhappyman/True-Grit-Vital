// Synthetic encrypted process-death fixture. Runner owns its temporary directory.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final dir = args[0], mode = args[1];
  final store = await RecordStore.open(
    path: '$dir/attachment.db',
    key: List.generate(32, (i) => i + 1),
    isNew: mode == 'init',
  );
  final input = File('$dir/input.json'),
      pinFile = File('$dir/pin.json'),
      source = File('$dir/source-original');
  final bytes = Uint8List.fromList(
    List.generate(AttachmentLimits.chunkBytes + 1024, (i) => i % 251),
  );
  final inspection = AttachmentInspection(
    mediaKind: AttachmentMediaKind.other,
    byteCount: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    mimeType: 'application/octet-stream',
  );
  if (mode == 'init') {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic attachment process',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
    input.writeAsStringSync(
      jsonEncode(
        AttachmentJob(
          id: 'job',
          generation: store.generation,
          personId: meId,
          expectedPersonRevision: 1,
          targetKind: AttachmentTargetKind.item,
          targetId: item.id,
          targetRevision: 1,
          attachmentId: 'attachment',
          versionId: 'version',
          name: 'Synthetic original',
          createdAt: DateTime.utc(2026, 10, 19),
        ).toJson(),
      ),
    );
    source.writeAsBytesSync(bytes);
  } else {
    final job = AttachmentJob.fromJson(
      Map<String, Object?>.from(jsonDecode(input.readAsStringSync()) as Map),
    );
    Future<void> begin({bool fail = false}) async {
      await store.beginAttachment(
        BeginAttachmentCommand(commandId: 'begin', job: job),
        beforeCommit: fail
            ? () async {
                exit(81);
              }
            : null,
      );
    }

    Future<void> chunk(int offset, {bool fail = false}) async {
      await store.appendAttachmentChunk(
        commandId: 'chunk-$offset',
        jobId: job.id,
        generation: job.generation,
        offset: offset,
        bytes: Uint8List.fromList(
          bytes.sublist(
            offset,
            offset == 0 ? AttachmentLimits.chunkBytes : bytes.length,
          ),
        ),
        beforeCommit: fail
            ? () async {
                exit(82);
              }
            : null,
      );
    }

    Future<AttachmentRecord> publish({bool fail = false}) async =>
        store.publishAttachment(
          commandId: 'publish',
          jobId: job.id,
          generation: job.generation,
          inspection: inspection,
          beforeCommit: fail
              ? () async {
                  exit(85);
                }
              : null,
        );
    Future<void> checkBytes(AttachmentPin pin) async {
      final digest = await sha256.bind(store.readAttachmentPin(pin)).first;
      if (digest.toString() != inspection.sha256) {
        throw StateError('original_changed');
      }
    }

    if (mode == 'begin-before') {
      await begin(fail: true);
    } else if (mode == 'begin') {
      await begin();
    } else if (mode == 'chunk-before') {
      await chunk(0, fail: true);
    } else if (mode == 'mid') {
      await chunk(0);
      exit(83);
    } else if (mode == 'complete-before') {
      await chunk(0);
      await chunk(AttachmentLimits.chunkBytes);
      exit(84);
    } else if (mode == 'publish-before') {
      await publish(fail: true);
    } else if (mode == 'publish-after') {
      await publish();
      exit(86);
    } else if (mode == 'verify-empty') {
      if (await store.attachmentJob(job.id) != null ||
          (await store.attachments(personId: meId)).isNotEmpty) {
        throw StateError('partial_begin');
      }
    } else if (mode.startsWith('verify-stage-')) {
      final expected = mode == 'verify-stage-empty'
          ? 0
          : mode == 'verify-stage-partial'
          ? AttachmentLimits.chunkBytes
          : bytes.length;
      if ((await store.attachmentJob(job.id))?.receivedBytes != expected ||
          (await store.attachments(personId: meId)).isNotEmpty) {
        throw StateError('partial_publication');
      }
    } else if (mode == 'verify-ready') {
      final a = await publish();
      final pin = await store.pinAttachment(
        id: a.id,
        generation: job.generation,
        expectedRevision: 1,
      );
      await checkBytes(pin);
      await store.releaseAttachmentPin(pin);
      if ((await store.attachments(personId: meId)).length != 1) {
        throw StateError('duplicate_original');
      }
    } else if (mode == 'delete-before' ||
        mode == 'delete-mid' ||
        mode == 'delete-after') {
      final a = await publish();
      if (mode == 'delete-mid') {
        final pin = await store.pinAttachment(
          id: a.id,
          generation: job.generation,
          expectedRevision: 1,
          sessionId: 'interrupted-view',
        );
        pinFile.writeAsStringSync(jsonEncode(pin.toJson()));
      }
      await store.deleteAttachment(
        commandId: 'delete',
        attachment: a,
        expectedPersonRevision: 1,
        beforeCommit: mode == 'delete-before'
            ? () async {
                exit(87);
              }
            : null,
      );
      exit(mode == 'delete-mid' ? 88 : 89);
    } else if (mode == 'verify-pinned-delete') {
      if ((await store.attachments(personId: meId)).isNotEmpty) {
        throw StateError('association_not_hidden');
      }
      final pin = AttachmentPin.fromJson(
        Map<String, Object?>.from(
          jsonDecode(pinFile.readAsStringSync()) as Map,
        ),
      );
      await checkBytes(pin);
      await store.releaseAttachmentPin(pin);
      if (await store.attachmentJob(job.id) != null) {
        throw StateError('pinned_delete_not_reclaimed');
      }
    } else if (mode == 'verify-gone') {
      if ((await store.attachments(personId: meId)).isNotEmpty ||
          await store.attachmentJob(job.id) != null) {
        throw StateError('partial_delete');
      }
    } else {
      throw ArgumentError('mode');
    }
    if (sha256.convert(source.readAsBytesSync()).toString() !=
        inspection.sha256) {
      throw StateError('selected_original_deleted_or_changed');
    }
  }
  await store.close();
  stdout.writeln('PASS attachment $mode');
}
