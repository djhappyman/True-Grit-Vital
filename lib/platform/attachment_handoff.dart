import 'package:flutter/services.dart';

import '../domain/attachments.dart';

abstract interface class AttachmentHandoffGateway {
  Future<void> begin({
    required String id,
    required String name,
    required String mime,
    required DateTime expiresAt,
  });
  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  });
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  });
  Future<bool> share(String id);
  Future<bool> cancel(String id);
  Future<List<String>> cleanup();
}

final class AndroidAttachmentHandoff implements AttachmentHandoffGateway {
  const AndroidAttachmentHandoff();
  static const channel = MethodChannel('true_grit_vital/attachment_handoff');
  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw AttachmentFailure(e.code);
    } on MissingPluginException {
      throw const AttachmentFailure('attachment_handoff_unavailable');
    }
  }

  @override
  Future<void> begin({
    required String id,
    required String name,
    required String mime,
    required DateTime expiresAt,
  }) async {
    attachmentIdentity(id);
    await _call<void>('begin', {
      'id': id,
      'name': name,
      'mime': mime,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  }) async {
    attachmentIdentity(id);
    if (bytes.isEmpty ||
        bytes.length > AttachmentLimits.chunkBytes ||
        offset < 0 ||
        offset + bytes.length > AttachmentLimits.maxInputBytes) {
      throw const AttachmentFailure('attachment_byte_limit');
    }
    return (await _call<int>('append', {
      'id': id,
      'offset': offset,
      'bytes': bytes,
    }))!;
  }

  @override
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) async {
    attachmentIdentity(id);
    await _call<void>('publish', {
      'id': id,
      'bytes': byteCount,
      'sha256': sha256,
    });
  }

  @override
  Future<bool> share(String id) async {
    attachmentIdentity(id);
    return (await _call<bool>('share', {'id': id})) ?? false;
  }

  @override
  Future<bool> cancel(String id) async {
    attachmentIdentity(id);
    try {
      return (await _call<bool>('cancel', {'id': id})) ?? false;
    } on AttachmentFailure catch (error) {
      // Older native hosts report absence as an error. Absence already fulfils
      // cancellation, and must never pin a nonexistent external handoff.
      if (error.code == 'attachment_handoff_missing') return true;
      rethrow;
    }
  }

  @override
  Future<List<String>> cleanup() async =>
      (await _call<List<Object?>>('cleanup'))!.cast<String>();
}

final class UnsupportedAttachmentHandoff implements AttachmentHandoffGateway {
  const UnsupportedAttachmentHandoff();
  Never _fail() =>
      throw const AttachmentFailure('attachment_handoff_unavailable');
  @override
  Future<void> begin({
    required String id,
    required String name,
    required String mime,
    required DateTime expiresAt,
  }) async => _fail();
  @override
  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  }) async => _fail();
  @override
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) async => _fail();
  @override
  Future<bool> share(String id) async => _fail();
  @override
  Future<bool> cancel(String id) async => _fail();
  @override
  Future<List<String>> cleanup() async => const [];
}
