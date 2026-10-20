import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/artifact_transfer.dart';

/// Pure-Dart bounded staging for non-Android hosts.
///
/// Staged files live outside the encrypted dataset directory, in a private
/// per-user directory. They are transient copies of an already completed
/// artifact, never user originals. Android uses the native protected store
/// instead; both expose the same begin/append/publish/cancel lifecycle.
final class ArtifactFileStore {
  ArtifactFileStore({
    this.rootOverride,
    DateTime Function()? clock,
    this.maxBytes = ArtifactLimits.maxBytes,
    this.maxRetained = ArtifactLimits.maxRetained,
    this.executableDirectory = '/usr/bin',
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final Directory? rootOverride;
  final DateTime Function() _clock;
  final int maxBytes, maxRetained;
  final String executableDirectory;

  Directory get root => rootOverride ?? defaultRoot();

  static Directory defaultRoot() {
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    final base = runtime != null && runtime.startsWith('/')
        ? runtime
        : Directory.systemTemp.path;
    final user = (Platform.environment['USER'] ?? 'local').replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    return Directory('$base/vital-artifacts-$user');
  }

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
    if (byteCount < 1 || byteCount > maxBytes) {
      throw const ArtifactFailure('artifact_transfer_input');
    }
    final now = _clock();
    artifactExpiry(now, expiresAt);
    await _guard(() async {
      await _ensureRoot();
      await cleanup(preserve: id);
      if (await _metaFile(id).exists() || await _partFile(id).exists()) {
        throw const ArtifactFailure('artifact_transfer_conflict');
      }
      final retained = await _metas();
      if (retained.length >= maxRetained) {
        throw const ArtifactFailure('artifact_transfer_capacity');
      }
      await _writeMeta(
        _Entry(
          id: id,
          name: name,
          mimeType: mimeType,
          byteCount: byteCount,
          expiresAt: expiresAt,
        ),
      );
      final part = _partFile(id);
      await part.writeAsBytes(const <int>[], flush: true);
      await _harden(part.path, '0600');
      await _sync(root.path);
    });
  }

  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  }) async {
    artifactIdentity(id);
    if (bytes.isEmpty || bytes.length > ArtifactLimits.chunkBytes) {
      throw const ArtifactFailure('artifact_transfer_input');
    }
    return _guard(() async {
      final entry = await _live(id);
      if (entry.ready) {
        throw const ArtifactFailure('artifact_transfer_conflict');
      }
      if (offset < 0 ||
          offset + bytes.length > entry.byteCount ||
          offset + bytes.length > maxBytes) {
        throw const ArtifactFailure('artifact_transfer_input');
      }
      final part = _partFile(id);
      if (await _type(part.path) != FileSystemEntityType.file) {
        throw const ArtifactFailure('artifact_transfer_incomplete');
      }
      final length = await part.length();
      if (offset != length) {
        if (offset > length || offset + bytes.length > length) {
          throw const ArtifactFailure('artifact_transfer_conflict');
        }
        final prior = await part
            .openRead(offset, offset + bytes.length)
            .fold(<int>[], (all, chunk) => all..addAll(chunk));
        if (prior.length != bytes.length || !_equal(prior, bytes)) {
          throw const ArtifactFailure('artifact_transfer_conflict');
        }
        return length;
      }
      final output = await part.open(mode: FileMode.append);
      try {
        await output.writeFrom(bytes);
        await output.flush();
      } finally {
        await output.close();
      }
      return length + bytes.length;
    });
  }

  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) async {
    artifactIdentity(id);
    artifactDigest(sha256);
    await _guard(() async {
      final entry = await _live(id);
      if (entry.ready) {
        final readable = await _readable(entry);
        if (entry.sha256 != sha256 || await readable.length() != byteCount) {
          throw const ArtifactFailure('artifact_transfer_conflict');
        }
        return;
      }
      if (byteCount != entry.byteCount) {
        throw const ArtifactFailure('artifact_transfer_input');
      }
      final part = _partFile(id);
      if (await _type(part.path) != FileSystemEntityType.file ||
          await part.length() != byteCount) {
        throw const ArtifactFailure('artifact_transfer_incomplete');
      }
      final actual = await _digest(part);
      if (actual != sha256) {
        throw const ArtifactFailure('artifact_transfer_integrity');
      }
      await part.rename(_binFile(id).path);
      await _harden(_binFile(id).path, '0600');
      await _sync(root.path);
      await _writeMeta(entry.copy(ready: true, sha256: sha256));
    });
  }

  Future<File> readable(String id) async {
    artifactIdentity(id);
    return _guard(() async {
      final entry = await _live(id);
      return _readable(entry);
    });
  }

  /// The staged name and media type are the store's, never a caller override.
  Future<({String name, String mimeType, int byteCount})> describe(
    String id,
  ) async {
    artifactIdentity(id);
    return _guard(() async {
      final entry = await _live(id);
      final file = await _readable(entry);
      return (
        name: entry.name,
        mimeType: entry.mimeType,
        byteCount: await file.length(),
      );
    });
  }

  Future<bool> cancel(String id) async {
    artifactIdentity(id);
    return _guard(() async {
      final meta = _metaFile(id);
      if (!await meta.exists()) return true;
      final entry = await _tryRead(id);
      if (entry == null) {
        await _remove(id);
        return true;
      }
      // A receiver may already hold a grant for an offered artifact.
      if (entry.offered && entry.expiresAt.isAfter(_clock())) return false;
      await _remove(id);
      return true;
    });
  }

  Future<List<String>> cleanup({
    String? preserve,
    bool includeOffered = false,
  }) async {
    if (preserve != null) artifactIdentity(preserve);
    return _guard(() async {
      if (await _type(root.path) != FileSystemEntityType.directory) {
        return const <String>[];
      }
      final entries = await root.list(followLinks: false).take(65).toList();
      if (entries.length > 64) {
        throw const ArtifactFailure('artifact_transfer_storage');
      }
      final removed = <String>{};
      final known = <String>{};
      for (final entity in entries) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!name.endsWith('.meta')) continue;
        final id = name.substring(0, name.length - 5);
        if (!_identityPattern.hasMatch(id)) {
          await _deleteEntity(entity.path, removed, id);
          continue;
        }
        known.add(id);
        final entry = await _tryRead(id);
        final now = _clock();
        if (entry == null ||
            !entry.expiresAt.isAfter(now) ||
            (!entry.ready && id != preserve) ||
            (entry.ready &&
                id != preserve &&
                (includeOffered || !entry.offered))) {
          await _remove(id);
          removed.add(id);
        }
      }
      for (final entity in entries) {
        final name = entity.path.split(Platform.pathSeparator).last;
        final match = _suffixPattern.firstMatch(name);
        if (match == null) continue;
        final id = match.group(1)!;
        if (known.contains(id) || !_identityPattern.hasMatch(id)) continue;
        if (await _type(entity.path) == FileSystemEntityType.file) {
          await _deleteEntity(entity.path, removed, id);
        }
      }
      if (removed.isNotEmpty) await _sync(root.path);
      return removed.toList()..sort();
    });
  }

  Future<void> _writeMeta(_Entry entry) async {
    final next = File('${root.path}/${entry.id}.next');
    await next.writeAsString(jsonEncode(entry.toJson()), flush: true);
    await _harden(next.path, '0600');
    await next.rename(_metaFile(entry.id).path);
    await _sync(root.path);
  }

  Future<_Entry> _live(String id) async {
    final entry = await _read(id);
    if (!entry.expiresAt.isAfter(_clock())) {
      await _remove(id);
      throw const ArtifactFailure('artifact_transfer_expired');
    }
    return entry;
  }

  Future<_Entry> _read(String id) async {
    final entry = await _tryRead(id);
    if (entry == null) {
      throw const ArtifactFailure('artifact_transfer_missing');
    }
    return entry;
  }

  Future<_Entry?> _tryRead(String id) async {
    final file = _metaFile(id);
    final type = await _type(file.path);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file || await file.length() > 4096) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      final entry = _Entry.fromJson(decoded);
      if (entry.id != id) return null;
      artifactNeutralName(entry.name);
      artifactMimeType(entry.mimeType);
      if (entry.byteCount < 1 || entry.byteCount > maxBytes) return null;
      if (!entry.expiresAt.isUtc) return null;
      if (entry.ready) artifactDigest(entry.sha256);
      return entry;
    } on ArtifactFailure {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<File> _readable(_Entry entry) async {
    if (!entry.ready) {
      throw const ArtifactFailure('artifact_transfer_incomplete');
    }
    final bin = _binFile(entry.id);
    if (await _type(bin.path) != FileSystemEntityType.file ||
        await bin.length() != entry.byteCount) {
      throw const ArtifactFailure('artifact_transfer_incomplete');
    }
    return bin;
  }

  Future<void> _remove(String id) async {
    for (final file in [
      _partFile(id),
      _binFile(id),
      File('${root.path}/$id.next'),
      _metaFile(id),
    ]) {
      if (await _type(file.path) == FileSystemEntityType.file) {
        await file.delete();
      }
    }
    await _sync(root.path);
  }

  Future<void> _deleteEntity(
    String path,
    Set<String> removed,
    String id,
  ) async {
    if (await _type(path) != FileSystemEntityType.file) return;
    await File(path).delete();
    if (_identityPattern.hasMatch(id)) removed.add(id);
  }

  Future<List<String>> _metas() async {
    final result = <String>[];
    await for (final entity in root.list(followLinks: false).take(65)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.endsWith('.meta')) {
        result.add(name.substring(0, name.length - 5));
      }
      if (result.length > maxRetained) break;
    }
    return result;
  }

  Future<void> _ensureRoot() async {
    final type = await _type(root.path);
    if (type == FileSystemEntityType.notFound) {
      await _command(executableDirectory, 'install', [
        '-d',
        '-m',
        '0700',
        '--',
        root.path,
      ]);
    } else if (type != FileSystemEntityType.directory) {
      throw const ArtifactFailure('artifact_transfer_storage');
    }
    if (await _type(root.path) != FileSystemEntityType.directory) {
      throw const ArtifactFailure('artifact_transfer_storage');
    }
    await _harden(root.path, '0700');
    final parent = root.parent;
    if (await _type(parent.path) == FileSystemEntityType.directory) {
      await _sync(parent.path);
    }
  }

  Future<void> _harden(String path, String mode) =>
      _command(executableDirectory, 'chmod', [mode, '--', path]);

  Future<void> _sync(String path) =>
      _command(executableDirectory, 'sync', ['--', path]);

  Future<void> _command(
    String directory,
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(
        '$directory/$executable',
        arguments,
        runInShell: false,
      );
      if (result.exitCode != 0) {
        throw const ArtifactFailure('artifact_transfer_storage');
      }
    } on ArtifactFailure {
      rethrow;
    } on ProcessException {
      throw const ArtifactFailure('artifact_transfer_storage');
    }
  }

  Future<FileSystemEntityType> _type(String path) =>
      FileSystemEntity.type(path, followLinks: false);

  Future<String> _digest(File file) async {
    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.value!.toString();
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ArtifactFailure {
      rethrow;
    } catch (_) {
      throw const ArtifactFailure('artifact_transfer_storage');
    }
  }

  File _metaFile(String id) => File('${root.path}/$id.meta');
  File _partFile(String id) => File('${root.path}/$id.part');
  File _binFile(String id) => File('${root.path}/$id.bin');
}

final _identityPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
final _suffixPattern = RegExp(r'^([A-Za-z0-9_-]{1,128})\.(?:part|bin|next)$');

bool _equal(List<int> first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

final class _Entry {
  const _Entry({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.byteCount,
    required this.expiresAt,
    this.ready = false,
    this.offered = false,
    this.sha256 = '',
  });

  factory _Entry.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) throw const FormatException();
    final ready = json['ready'];
    final offered = json['offered'];
    if (ready is! bool || offered is! bool) throw const FormatException();
    return _Entry(
      id: json['id']! as String,
      name: json['name']! as String,
      mimeType: json['mime']! as String,
      byteCount: json['bytes']! as int,
      expiresAt: DateTime.parse(json['expiresAt']! as String),
      ready: ready,
      offered: offered,
      sha256: json['sha256']! as String,
    );
  }

  final String id, name, mimeType, sha256;
  final int byteCount;
  final DateTime expiresAt;
  final bool ready, offered;

  _Entry copy({bool? ready, bool? offered, String? sha256}) => _Entry(
    id: id,
    name: name,
    mimeType: mimeType,
    byteCount: byteCount,
    expiresAt: expiresAt,
    ready: ready ?? this.ready,
    offered: offered ?? this.offered,
    sha256: sha256 ?? this.sha256,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'mime': mimeType,
    'bytes': byteCount,
    'expiresAt': expiresAt.toIso8601String(),
    'ready': ready,
    'offered': offered,
    'sha256': sha256,
  };
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
