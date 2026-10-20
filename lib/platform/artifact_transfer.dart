import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../domain/artifact_transfer.dart';
import 'artifact_transfer_files.dart';

export 'artifact_transfer_files.dart';

/// A small capability-aware boundary for generated artifacts.
///
/// The artifact is always staged and verified before [save] or [share] is
/// offered to the receiver. Feature code supplies a completed stream, not a
/// whole-file buffer assumption.
abstract interface class ArtifactTransferGateway {
  ArtifactCapabilities get capabilities;
  Future<void> begin({
    required String id,
    required String name,
    required String mimeType,
    required int byteCount,
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
  Future<bool> save({
    required String id,
    required String name,
    required String mimeType,
  });
  Future<bool> share({
    required String id,
    required String name,
    required String mimeType,
  });
  Future<bool> cancel(String id);
  Future<List<String>> cleanup({String? preserve, bool includeOffered = false});
}

/// Uses the protected no-backup staging store and a real OS handoff.
final class AndroidArtifactTransfer implements ArtifactTransferGateway {
  const AndroidArtifactTransfer();
  static const channel = MethodChannel('true_grit_vital/artifact_transfer');

  @override
  ArtifactCapabilities get capabilities =>
      const ArtifactCapabilities(save: true, share: true);

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw ArtifactFailure(error.code);
    } on MissingPluginException {
      throw const ArtifactFailure('artifact_transfer_unavailable');
    }
  }

  @override
  Future<void> begin({
    required String id,
    required String name,
    required String mimeType,
    required int byteCount,
    required DateTime expiresAt,
  }) async {
    artifactIdentity(id);
    artifactNeutralName(name);
    artifactMimeType(mimeType);
    if (byteCount < 1 || byteCount > ArtifactLimits.maxBytes) {
      throw const ArtifactFailure('artifact_transfer_input');
    }
    await _call<void>('begin', {
      'id': id,
      'name': name,
      'mime': mimeType,
      'bytes': byteCount,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  }) async {
    artifactIdentity(id);
    if (bytes.isEmpty ||
        bytes.length > ArtifactLimits.chunkBytes ||
        offset < 0 ||
        offset + bytes.length > ArtifactLimits.maxBytes) {
      throw const ArtifactFailure('artifact_transfer_input');
    }
    final next = await _call<int>('append', {
      'id': id,
      'offset': offset,
      'bytes': bytes,
    });
    if (next == null || next < offset + bytes.length) {
      throw const ArtifactFailure('artifact_transfer_incomplete');
    }
    return next;
  }

  @override
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) async {
    artifactIdentity(id);
    artifactDigest(sha256);
    await _call<void>('publish', {
      'id': id,
      'bytes': byteCount,
      'sha256': sha256,
    });
  }

  @override
  Future<bool> save({
    required String id,
    required String name,
    required String mimeType,
  }) async {
    artifactIdentity(id);
    artifactNeutralName(name);
    artifactMimeType(mimeType);
    return (await _call<bool>('save', {
          'id': id,
          'name': name,
          'mime': mimeType,
        })) ??
        false;
  }

  @override
  Future<bool> share({
    required String id,
    required String name,
    required String mimeType,
  }) async {
    artifactIdentity(id);
    artifactNeutralName(name);
    artifactMimeType(mimeType);
    return (await _call<bool>('share', {
          'id': id,
          'name': name,
          'mime': mimeType,
        })) ??
        false;
  }

  @override
  Future<bool> cancel(String id) async {
    artifactIdentity(id);
    try {
      return (await _call<bool>('cancel', {'id': id})) ?? false;
    } on ArtifactFailure catch (error) {
      // An absent staged artifact already satisfies cancellation.
      if (error.code == 'artifact_transfer_missing') return true;
      rethrow;
    }
  }

  @override
  Future<List<String>> cleanup({
    String? preserve,
    bool includeOffered = false,
  }) async {
    if (preserve != null) artifactIdentity(preserve);
    final removed = await _call<List<Object?>>('cleanup', {
      'preserve': preserve,
      'includeOffered': includeOffered,
    });
    return (removed ?? const <Object?>[]).cast<String>();
  }
}

typedef ArtifactSaveDialog = Future<bool> Function({
  required String name,
  required String mimeType,
  required Uint8List bytes,
});

/// Local desktop staging with a real portal save dialog.
final class FileArtifactTransfer implements ArtifactTransferGateway {
  FileArtifactTransfer({
    ArtifactFileStore? store,
    Directory? root,
    DateTime Function()? clock,
    this.saveDialog,
    this.maxSaveBytes = 64 * 1024 * 1024,
  }) : _store = store ?? ArtifactFileStore(rootOverride: root, clock: clock);

  final ArtifactFileStore _store;
  final ArtifactSaveDialog? saveDialog;
  final int maxSaveBytes;

  @override
  ArtifactCapabilities get capabilities =>
      ArtifactCapabilities(save: true, share: false, maxBytes: maxSaveBytes);

  @override
  Future<void> begin({
    required String id,
    required String name,
    required String mimeType,
    required int byteCount,
    required DateTime expiresAt,
  }) => _store.begin(
    id: id,
    name: name,
    mimeType: mimeType,
    byteCount: byteCount,
    expiresAt: expiresAt,
  );

  @override
  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  }) => _store.append(id: id, offset: offset, bytes: bytes);

  @override
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) => _store.publish(id: id, byteCount: byteCount, sha256: sha256);

  @override
  Future<bool> save({
    required String id,
    required String name,
    required String mimeType,
  }) async {
    artifactIdentity(id);
    artifactNeutralName(name);
    artifactMimeType(mimeType);
    final metadata = await _store.describe(id);
    if (metadata.name != name || metadata.mimeType != mimeType) {
      throw const ArtifactFailure('artifact_transfer_conflict');
    }
    if (metadata.byteCount > maxSaveBytes) {
      throw const ArtifactFailure('artifact_transfer_save_limit');
    }
    final file = await _store.readable(id);
    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
      if (bytes.length > maxSaveBytes) {
        throw const ArtifactFailure('artifact_transfer_save_limit');
      }
      return await (saveDialog ?? _portalSave)(
        name: name,
        mimeType: mimeType,
        bytes: bytes,
      );
    } on ArtifactFailure {
      rethrow;
    } catch (_) {
      throw const ArtifactFailure('artifact_transfer_save_unavailable');
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<bool> share({
    required String id,
    required String name,
    required String mimeType,
  }) async {
    throw const ArtifactFailure('artifact_transfer_share_unavailable');
  }

  @override
  Future<bool> cancel(String id) => _store.cancel(id);

  @override
  Future<List<String>> cleanup({
    String? preserve,
    bool includeOffered = false,
  }) => _store.cleanup(preserve: preserve, includeOffered: includeOffered);

  static Future<bool> _portalSave({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    try {
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: mimeType,
      );
      return saved != null;
    } catch (_) {
      throw const ArtifactFailure('artifact_transfer_save_unavailable');
    }
  }
}

/// No staging store or OS handoff exists on this host.
final class UnsupportedArtifactTransfer implements ArtifactTransferGateway {
  const UnsupportedArtifactTransfer();

  @override
  ArtifactCapabilities get capabilities =>
      const ArtifactCapabilities(save: false, share: false);

  Never _fail() => throw const ArtifactFailure('artifact_transfer_unavailable');

  @override
  Future<void> begin({
    required String id,
    required String name,
    required String mimeType,
    required int byteCount,
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
  Future<bool> save({
    required String id,
    required String name,
    required String mimeType,
  }) async => _fail();

  @override
  Future<bool> share({
    required String id,
    required String name,
    required String mimeType,
  }) async => _fail();

  @override
  Future<bool> cancel(String id) async => _fail();

  @override
  Future<List<String>> cleanup({
    String? preserve,
    bool includeOffered = false,
  }) async => const [];
}

ArtifactTransferGateway defaultArtifactTransferGateway({String? scope}) {
  if (Platform.isAndroid) return const AndroidArtifactTransfer();
  if (Platform.isLinux) {
    final root = scope == null
        ? null
        : Directory(
            '${ArtifactFileStore.defaultRoot().path}-${sha256.convert(utf8.encode(scope))}',
          );
    return FileArtifactTransfer(root: root);
  }
  return const UnsupportedArtifactTransfer();
}
