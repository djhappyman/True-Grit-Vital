import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/attachments.dart';
import 'attachment_handoff.dart';
import 'attachment_media.dart';
import 'attachment_pdf.dart';

import 'package:file_picker/file_picker.dart';

export 'attachment_handoff.dart';
export 'attachment_media.dart';

final class AttachmentCapabilities {
  const AttachmentCapabilities({
    required this.pickFile,
    required this.photo,
    required this.camera,
    required this.share,
    required this.save,
  });
  final bool pickFile, photo, camera, share, save;
}

abstract interface class AttachmentPickerRecoveryGateway {
  Future<String?> pendingJobId();
}

abstract interface class AttachmentGateway {
  AttachmentCapabilities get capabilities;
  Future<AttachmentSelection?> pickFile({required String jobId});
  Future<AttachmentSelection?> pickPhoto({
    required String jobId,
    bool camera = false,
  });
  Future<AttachmentSelection?> recoverSelection({required String jobId});
  Future<void> finishSelection(String jobId);
  Future<bool> save({
    required String name,
    required String mime,
    required Uint8List bytes,
  });
}

/// No original copy or file name/URI is persisted by the Android picker adapter.
final class AndroidAttachmentGateway
    implements AttachmentGateway, AttachmentPickerRecoveryGateway {
  const AndroidAttachmentGateway();
  static const channel = MethodChannel('true_grit_vital/attachment_picker');
  @override
  AttachmentCapabilities get capabilities => const AttachmentCapabilities(
    pickFile: true,
    photo: true,
    camera: false,
    share: true,
    save: false,
  );
  Future<T?> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw AttachmentFailure(e.code);
    } on MissingPluginException {
      throw const AttachmentFailure('attachment_picker_unavailable');
    }
  }

  Future<AttachmentSelection?> _selection(
    String method,
    String id, {
    bool photo = false,
  }) async {
    attachmentIdentity(id);
    final result = await _call<Map<Object?, Object?>>(method, {
      'jobId': id,
      'photoOnly': photo,
    });
    if (result == null) return null;
    if (result['jobId'] != id) {
      throw const AttachmentFailure('attachment_picker_context');
    }
    if (result['state'] == 'cancelled' || result['state'] == 'pending') {
      return null;
    }
    if (result['state'] != 'selected' ||
        result['name'] is! String ||
        result['byteCount'] is! int) {
      throw const AttachmentFailure('attachment_picker_context');
    }
    final size = result['byteCount']! as int;
    if (size > AttachmentLimits.maxInputBytes) {
      throw const AttachmentFailure('attachment_byte_limit');
    }
    return AttachmentSelection(
      jobId: id,
      name: result['name']! as String,
      byteCount: size,
      openRead: () => _read(id),
    );
  }

  Stream<List<int>> _read(String id) async* {
    var offset = 0;
    while (true) {
      final chunk = await _call<Uint8List>('read', {
        'jobId': id,
        'offset': offset,
      });
      if (chunk == null) break;
      if (chunk.isEmpty ||
          chunk.length > AttachmentLimits.chunkBytes ||
          chunk.length > AttachmentLimits.maxInputBytes - offset) {
        throw const AttachmentFailure('attachment_byte_limit');
      }
      offset += chunk.length;
      yield chunk;
    }
  }

  @override
  Future<String?> pendingJobId() => _call<String>('pending', const {});
  @override
  Future<AttachmentSelection?> pickFile({required String jobId}) =>
      _selection('pick', jobId);
  @override
  Future<AttachmentSelection?> pickPhoto({
    required String jobId,
    bool camera = false,
  }) {
    if (camera) throw const AttachmentFailure('attachment_camera_unavailable');
    return _selection('pick', jobId, photo: true);
  }

  @override
  Future<AttachmentSelection?> recoverSelection({required String jobId}) =>
      _selection('recover', jobId);
  @override
  Future<void> finishSelection(String jobId) async {
    attachmentIdentity(jobId);
    await _call<void>('finish', {'jobId': jobId});
  }

  @override
  Future<bool> save({
    required String name,
    required String mime,
    required Uint8List bytes,
  }) => Future.error(const AttachmentFailure('attachment_save_unavailable'));
}

final class UnsupportedAttachmentGateway implements AttachmentGateway {
  const UnsupportedAttachmentGateway();
  @override
  AttachmentCapabilities get capabilities => const AttachmentCapabilities(
    pickFile: false,
    photo: false,
    camera: false,
    share: false,
    save: false,
  );
  Never _fail() =>
      throw const AttachmentFailure('attachment_picker_unavailable');
  @override
  Future<AttachmentSelection?> pickFile({required String jobId}) async =>
      _fail();
  @override
  Future<AttachmentSelection?> pickPhoto({
    required String jobId,
    bool camera = false,
  }) async => _fail();
  @override
  Future<AttachmentSelection?> recoverSelection({
    required String jobId,
  }) async => _fail();
  @override
  Future<void> finishSelection(String jobId) async => _fail();
  @override
  Future<bool> save({
    required String name,
    required String mime,
    required Uint8List bytes,
  }) async => _fail();
}

AttachmentGateway defaultAttachmentGateway({String? dialogTitle}) =>
    Platform.isAndroid
    ? const AndroidAttachmentGateway()
    : Platform.isLinux
    ? LinuxAttachmentGateway(dialogTitle: dialogTitle)
    : const UnsupportedAttachmentGateway();

AttachmentHandoffGateway defaultAttachmentHandoffGateway() => Platform.isAndroid
    ? const AndroidAttachmentHandoff()
    : const UnsupportedAttachmentHandoff();
AttachmentMediaDecoder defaultAttachmentMediaDecoder() =>
    const AttachmentMediaDecoder(pdf: PdfrxAttachmentDecoder());

/// The audited Linux portal returns the original file URI without copying it.
final class LinuxAttachmentGateway implements AttachmentGateway {
  const LinuxAttachmentGateway({this.dialogTitle});
  final String? dialogTitle;
  @override
  AttachmentCapabilities get capabilities => const AttachmentCapabilities(
    pickFile: true,
    photo: true,
    camera: false,
    share: false,
    save: true,
  );
  Future<AttachmentSelection?> _pick(String jobId, bool photo) async {
    attachmentIdentity(jobId);
    try {
      final selected = await FilePicker.pickFile(
        type: photo ? FileType.image : FileType.any,
        dialogTitle: dialogTitle,
      );
      if (selected == null) return null;
      if (selected.uri.scheme != 'file') {
        throw const AttachmentFailure('attachment_picker_source_unavailable');
      }
      final length = await selected.length();
      if (length == null || length > AttachmentLimits.maxInputBytes) {
        throw const AttachmentFailure('attachment_byte_limit');
      }
      return AttachmentSelection(
        jobId: jobId,
        name: selected.name,
        byteCount: length,
        openRead: selected.readAsByteStream,
      );
    } on AttachmentFailure {
      rethrow;
    } catch (_) {
      throw const AttachmentFailure('attachment_picker_unavailable');
    }
  }

  @override
  Future<AttachmentSelection?> pickFile({required String jobId}) =>
      _pick(jobId, false);
  @override
  Future<AttachmentSelection?> pickPhoto({
    required String jobId,
    bool camera = false,
  }) {
    if (camera) throw const AttachmentFailure('attachment_camera_unavailable');
    return _pick(jobId, true);
  }

  @override
  Future<AttachmentSelection?> recoverSelection({required String jobId}) async {
    attachmentIdentity(jobId);
    // The original remains in its chosen location; the fixed job can be retried.
    return null;
  }

  @override
  Future<void> finishSelection(String jobId) async {
    attachmentIdentity(jobId);
  }

  @override
  Future<bool> save({
    required String name,
    required String mime,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > AttachmentLimits.maxInputBytes) {
      throw const AttachmentFailure('attachment_byte_limit');
    }
    try {
      return await FilePicker.saveFile(
            fileName: name,
            bytes: bytes,
            mimeType: mime,
            dialogTitle: dialogTitle,
          ) !=
          null;
    } catch (_) {
      throw const AttachmentFailure('attachment_save_unavailable');
    }
  }
}
