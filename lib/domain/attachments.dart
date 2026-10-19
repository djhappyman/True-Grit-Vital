import 'dart:typed_data';

/// Limits apply independently. Originals are retained without display resampling.
abstract final class AttachmentLimits {
  static const maxInputBytes = 16 * 1024 * 1024;
  static const chunkBytes = 64 * 1024;
  static const maxDecodedPixels = 16000000;
  static const maxDisplayEdge = 1600;
  static const maxPdfPages = 100;
  static const maxConcurrentJobs = 1;
  static const maxPreviewBytes = 8 * 1024 * 1024;
  static const maxFrames = 1;
  static const handoffLifetime = Duration(hours: 24);
}

enum AttachmentTargetKind { item, record, supporting }

enum AttachmentState { staging, ready, deleting }

enum AttachmentMediaKind { image, pdf, other }

enum AttachmentJobState {
  awaitingPicker,
  importing,
  ready,
  cancelled,
  interrupted,
}

enum AttachmentPickerKind { file, photo, camera }

final class AttachmentFailure implements Exception {
  const AttachmentFailure(this.code);
  final String code;
  @override
  String toString() => 'AttachmentFailure($code)';
}

void attachmentIdentity(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw const AttachmentFailure('attachment_identity');
  }
}

final class AttachmentInspection {
  AttachmentInspection({
    required this.mediaKind,
    required this.byteCount,
    required this.sha256,
    required this.mimeType,
    this.width,
    this.height,
    this.pageCount,
    this.frameCount,
  }) {
    if (byteCount < 1 ||
        byteCount > AttachmentLimits.maxInputBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        mimeType.length > 128) {
      throw const AttachmentFailure('attachment_input');
    }
    if (mediaKind == AttachmentMediaKind.image &&
        (width == null ||
            height == null ||
            width! < 1 ||
            height! < 1 ||
            width! * height! > AttachmentLimits.maxDecodedPixels ||
            frameCount != 1)) {
      throw const AttachmentFailure('attachment_image_limit');
    }
    if (mediaKind == AttachmentMediaKind.pdf &&
        (pageCount == null ||
            pageCount! < 1 ||
            pageCount! > AttachmentLimits.maxPdfPages)) {
      throw const AttachmentFailure('attachment_page_limit');
    }
  }
  final AttachmentMediaKind mediaKind;
  final int byteCount;
  final String sha256, mimeType;
  final int? width, height, pageCount, frameCount;
  Map<String, Object?> toJson() => {
    'mediaKind': mediaKind.name,
    'byteCount': byteCount,
    'sha256': sha256,
    'mimeType': mimeType,
    'width': width,
    'height': height,
    'pageCount': pageCount,
    'frameCount': frameCount,
  };
  factory AttachmentInspection.fromJson(Map<String, Object?> j) =>
      AttachmentInspection(
        mediaKind: AttachmentMediaKind.values.byName(j['mediaKind']! as String),
        byteCount: j['byteCount']! as int,
        sha256: j['sha256']! as String,
        mimeType: j['mimeType']! as String,
        width: j['width'] as int?,
        height: j['height'] as int?,
        pageCount: j['pageCount'] as int?,
        frameCount: j['frameCount'] as int?,
      );
}

/// A target is captured before leaving the app and never follows the visible feed.
final class AttachmentJob {
  AttachmentJob({
    required this.id,
    required this.generation,
    required this.personId,
    required this.expectedPersonRevision,
    required this.targetKind,
    required this.targetId,
    required this.targetRevision,
    required this.attachmentId,
    required this.versionId,
    required this.name,
    required this.createdAt,
    this.pickerKind = AttachmentPickerKind.file,
    this.state = AttachmentJobState.awaitingPicker,
    this.receivedBytes = 0,
  }) {
    for (final v in [
      id,
      generation,
      personId,
      targetId,
      attachmentId,
      versionId,
    ]) {
      attachmentIdentity(v);
    }
    if (expectedPersonRevision < 1 ||
        targetRevision < 1 ||
        name.trim().isEmpty ||
        name.length > 255 ||
        !createdAt.isUtc ||
        receivedBytes < 0 ||
        receivedBytes > AttachmentLimits.maxInputBytes) {
      throw const AttachmentFailure('attachment_job');
    }
  }
  final String id,
      generation,
      personId,
      targetId,
      attachmentId,
      versionId,
      name;
  final int expectedPersonRevision, targetRevision, receivedBytes;
  final AttachmentTargetKind targetKind;
  final AttachmentPickerKind pickerKind;
  final AttachmentJobState state;
  final DateTime createdAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'generation': generation,
    'personId': personId,
    'expectedPersonRevision': expectedPersonRevision,
    'targetKind': targetKind.name,
    'targetId': targetId,
    'targetRevision': targetRevision,
    'attachmentId': attachmentId,
    'versionId': versionId,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'pickerKind': pickerKind.name,
    'state': state.name,
    'receivedBytes': receivedBytes,
  };
  factory AttachmentJob.fromJson(Map<String, Object?> j) => AttachmentJob(
    id: j['id']! as String,
    generation: j['generation']! as String,
    personId: j['personId']! as String,
    expectedPersonRevision: j['expectedPersonRevision']! as int,
    targetKind: AttachmentTargetKind.values.byName(j['targetKind']! as String),
    targetId: j['targetId']! as String,
    targetRevision: j['targetRevision']! as int,
    attachmentId: j['attachmentId']! as String,
    versionId: j['versionId']! as String,
    name: j['name']! as String,
    createdAt: DateTime.parse(j['createdAt']! as String),
    pickerKind: AttachmentPickerKind.values.byName(j['pickerKind']! as String),
    state: AttachmentJobState.values.byName(j['state']! as String),
    receivedBytes: j['receivedBytes']! as int,
  );
}

final class AttachmentRecord {
  AttachmentRecord({
    required this.id,
    required this.generation,
    required this.personId,
    required this.targetKind,
    required this.targetId,
    required this.targetRevision,
    required this.revision,
    required this.versionId,
    required this.name,
    required this.state,
    required this.createdAt,
    this.inspection,
  }) {
    for (final v in [id, generation, personId, targetId, versionId]) {
      attachmentIdentity(v);
    }
    if (revision < 1 ||
        targetRevision < 1 ||
        name.trim().isEmpty ||
        name.length > 255 ||
        !createdAt.isUtc ||
        state == AttachmentState.ready && inspection == null) {
      throw const AttachmentFailure('attachment_record');
    }
  }
  final String id, generation, personId, targetId, versionId, name;
  final AttachmentTargetKind targetKind;
  final int targetRevision, revision;
  final AttachmentState state;
  final DateTime createdAt;
  final AttachmentInspection? inspection;
  Map<String, Object?> toJson() => {
    'id': id,
    'generation': generation,
    'personId': personId,
    'targetKind': targetKind.name,
    'targetId': targetId,
    'targetRevision': targetRevision,
    'revision': revision,
    'versionId': versionId,
    'name': name,
    'state': state.name,
    'createdAt': createdAt.toIso8601String(),
    'inspection': inspection?.toJson(),
  };
  factory AttachmentRecord.fromJson(Map<String, Object?> j) => AttachmentRecord(
    id: j['id']! as String,
    generation: j['generation']! as String,
    personId: j['personId']! as String,
    targetKind: AttachmentTargetKind.values.byName(j['targetKind']! as String),
    targetId: j['targetId']! as String,
    targetRevision: j['targetRevision']! as int,
    revision: j['revision']! as int,
    versionId: j['versionId']! as String,
    name: j['name']! as String,
    state: AttachmentState.values.byName(j['state']! as String),
    createdAt: DateTime.parse(j['createdAt']! as String),
    inspection: j['inspection'] == null
        ? null
        : AttachmentInspection.fromJson(
            Map<String, Object?>.from(j['inspection']! as Map),
          ),
  );
}

final class AttachmentPin {
  const AttachmentPin({
    required this.id,
    required this.attachment,
    this.sessionId = 'default',
    this.purpose = 'preview',
    this.expiresAt,
  });
  final String id;
  final AttachmentRecord attachment;
  final String sessionId, purpose;
  final DateTime? expiresAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'attachment': attachment.toJson(),
    'sessionId': sessionId,
    'purpose': purpose,
    'expiresAt': expiresAt?.toIso8601String(),
  };
  factory AttachmentPin.fromJson(Map<String, Object?> j) => AttachmentPin(
    id: j['id']! as String,
    attachment: AttachmentRecord.fromJson(
      Map<String, Object?>.from(j['attachment']! as Map),
    ),
    sessionId: j['sessionId']! as String,
    purpose: j['purpose']! as String,
    expiresAt: j['expiresAt'] == null
        ? null
        : DateTime.parse(j['expiresAt']! as String),
  );
  String get generation => attachment.generation;
  String get versionId => attachment.versionId;
}

final class BeginAttachmentCommand {
  const BeginAttachmentCommand({required this.commandId, required this.job});
  final String commandId;
  final AttachmentJob job;
}

/// Original source is read-only. Cancelling an import never deletes the source.
final class AttachmentSelection {
  const AttachmentSelection({
    required this.jobId,
    required this.name,
    required this.byteCount,
    required this.openRead,
    this.dispose,
  });
  final String jobId, name;
  final int byteCount;
  final Stream<List<int>> Function() openRead;

  /// Only an adapter-owned picker cache copy, never the user's chosen original.
  final Future<void> Function()? dispose;
}

/// Bounds arbitrary stream chunks without whole-original aggregation.
Stream<Uint8List> boundedAttachmentChunks(Stream<List<int>> source) async* {
  var count = 0;
  await for (final bytes in source) {
    if (bytes.length > AttachmentLimits.maxInputBytes - count) {
      throw const AttachmentFailure('attachment_byte_limit');
    }
    count += bytes.length;
    for (
      var offset = 0;
      offset < bytes.length;
      offset += AttachmentLimits.chunkBytes
    ) {
      final end = (offset + AttachmentLimits.chunkBytes).clamp(0, bytes.length);
      yield Uint8List.fromList(bytes.sublist(offset, end));
    }
  }
  if (count == 0) throw const AttachmentFailure('attachment_empty');
}
