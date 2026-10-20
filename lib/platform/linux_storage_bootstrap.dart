import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'storage_bootstrap.dart';

/// A small replaceable OS secret boundary; tests supply an isolated fake.
abstract interface class LinuxSecretStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// Uses the installed libsecret client, without a shell or secret arguments.
final class SecretToolStore implements LinuxSecretStore {
  const SecretToolStore({
    this.namespace = 'dev.truegrit.vital',
    this.timeout = const Duration(seconds: 15),
  });

  final String namespace;
  final Duration timeout;

  List<String> get _attributes => ['application', namespace, 'dataset', 'main'];

  Future<_CommandResult> _run(List<String> arguments, {String? input}) async {
    try {
      return await _command(
        '/usr/bin/secret-tool',
        arguments,
        input: input,
        timeout: timeout,
      );
    } catch (_) {
      _keyringUnavailable();
    }
  }

  @override
  Future<String?> read() async {
    // SearchItems returns only matching object paths, including locked items.
    // A cancelled unlock may otherwise look identical to an absent lookup.
    // Never enumerate the user's unrelated secrets or retrieve their values.
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(namespace)) {
      _keyringUnavailable();
    }
    _CommandResult metadata;
    try {
      metadata = await _command('/usr/bin/gdbus', [
        'call',
        '--session',
        '--dest',
        'org.freedesktop.secrets',
        '--object-path',
        '/org/freedesktop/secrets',
        '--method',
        'org.freedesktop.Secret.Service.SearchItems',
        "{'application': '$namespace', 'dataset': 'main'}",
      ], timeout: timeout);
    } catch (_) {
      _keyringUnavailable();
    }
    if (metadata.code != 0 || metadata.hasErrorOutput) _keyringUnavailable();
    final compact = metadata.output
        .replaceAll('@ao ', '')
        .replaceAll(RegExp(r'\s'), '');
    if (compact == '([],[])') return null;
    final paths = RegExp("'(/[^']*)'").allMatches(metadata.output).toList();
    if (paths.length > 1) _recovery();
    if (paths.length != 1) _keyringUnavailable();
    final result = await _run(['lookup', ..._attributes]);
    if (result.code != 0 || result.hasErrorOutput) _keyringUnavailable();
    final value = result.output.trim();
    if (value.isEmpty) _keyringUnavailable();
    return value;
  }

  @override
  Future<void> write(String value) async {
    // The bootstrap lock and immediately preceding read establish absence.
    // No replacement/clear operation is exposed by this boundary.
    final result = await _run([
      'store',
      '--label=True Grit Vital encrypted records',
      ..._attributes,
    ], input: value);
    if (result.code != 0 || result.hasErrorOutput) _keyringUnavailable();
  }
}

/// Linux local-test storage. The secret remains in the user's Secret Service.
/// No reset, replacement secret or plaintext database fallback is provided.
final class LinuxStorageBootstrap implements StorageBootstrap {
  LinuxStorageBootstrap({
    String? dataDirectory,
    LinuxSecretStore? secretStore,
    this.operationTimeout = const Duration(seconds: 20),
  }) : _directory = dataDirectory,
       _secrets = secretStore ?? const SecretToolStore();

  final String? _directory;
  final LinuxSecretStore _secrets;
  // Bounds lock acquisition and each OS helper. No timed-out mutation Future
  // continues after releasing the lock.
  final Duration operationTimeout;
  final Map<String, String> _prepared = {};

  String get _path {
    final override = _directory;
    if (override != null) {
      if (!override.startsWith('/')) _unavailable();
      return override;
    }
    final xdg = Platform.environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.startsWith('/')) return '$xdg/true_grit_vital';
    final home = Platform.environment['HOME'];
    if (home == null || !home.startsWith('/')) _unavailable();
    return '$home/.local/share/true_grit_vital';
  }

  @override
  Future<StorageLocation> prepare() => _locked((directory) async {
    final entries = await directory.list(followLinks: false).take(10).toList();
    if (entries.length > 9) _recovery();
    final artifacts = entries.where(
      (entry) => entry.path.split('/').last != '.bootstrap.lock',
    );
    final stored = await _secrets.read();
    if (artifacts.isEmpty && stored == null) {
      final identity = _randomHex(16);
      final key = _randomHex(32);
      await _publish(directory, 'initializing', identity);
      final secret = jsonEncode({
        'version': 1,
        'dataset': identity,
        'key': key,
      });
      await _secrets.write(secret);
      // Verify the service committed exactly the intended secret before use.
      if (await _secrets.read() != secret) _recovery();
      _prepared[directory.path] = identity;
      return StorageLocation(
        path: '${directory.path}/records.sqlite',
        key: _decodeHex(key),
        isNew: true,
      );
    }
    final state = await _existing(directory, stored);
    _prepared[directory.path] = state.identity;
    return StorageLocation(
      path: '${directory.path}/records.sqlite',
      key: state.key,
      isNew: false,
    );
  });

  @override
  Future<void> activate(StorageLocation location) => _locked((directory) async {
    if (location.path != '${directory.path}/records.sqlite') _recovery();
    final state = await _existing(directory, await _secrets.read());
    if (_prepared[directory.path] != state.identity ||
        !_sameKey(location.key, state.key)) {
      _recovery();
    }
    final active = File('${directory.path}/active');
    if (!await active.exists()) {
      // The caller has validated the encrypted database. Persist its directory
      // entry before the ready marker, including any SQLite sidecars.
      await _sync(directory.path);
      await _publish(directory, 'active', state.identity);
    }
  });

  Future<({String identity, List<int> key})> _existing(
    Directory directory,
    String? secret,
  ) async {
    if (secret == null) _recovery();
    final entries = await directory.list(followLinks: false).take(10).toList();
    if (entries.length > 9) _recovery();
    const allowed = {
      '.bootstrap.lock',
      'initializing',
      'active',
      'records.sqlite',
      'records.sqlite-wal',
      'records.sqlite-shm',
      'records.sqlite-journal',
      'restore',
      'backup-staging',
    };
    for (final entry in entries) {
      final name = entry.path.split('/').last;
      final type = await FileSystemEntity.type(entry.path, followLinks: false);
      if ((name == 'restore' || name == 'backup-staging') &&
          type == FileSystemEntityType.directory) {
        // Restore staging/rollback lives in one private child directory. Its
        // files are journalled and verified by the restore engine.
        await _mode(entry.path, '0700');
        continue;
      }
      if (!allowed.contains(name) || type != FileSystemEntityType.file) {
        _recovery();
      }
      // SQLite creates sidecars inside a private directory. Harden every
      // observed dataset artifact before returning it to the caller.
      await _mode(entry.path, '0600');
    }
    final intent = File('${directory.path}/initializing');
    final database = File('${directory.path}/records.sqlite');
    if (!await intent.exists() ||
        !await database.exists() ||
        await database.length() < 512 ||
        await intent.length() != 32) {
      _recovery();
    }
    final identity = await intent.readAsString();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(identity)) _recovery();
    final active = File('${directory.path}/active');
    if (await active.exists() &&
        (await active.length() != 32 ||
            await active.readAsString() != identity)) {
      _recovery();
    }
    Object? decoded;
    try {
      if (secret.length > 512) _recovery();
      decoded = jsonDecode(secret);
    } on FormatException {
      _recovery();
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['dataset'] != identity ||
        decoded['key'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(decoded['key'] as String)) {
      _recovery();
    }
    return (identity: identity, key: _decodeHex(decoded['key'] as String));
  }

  Future<T> _locked<T>(Future<T> Function(Directory) body) async {
    if (!Platform.isLinux) {
      throw const StorageBootstrapException('unsupported_host');
    }
    Process? holder;
    try {
      final directory = Directory(_path);
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        _recovery();
      }
      // install creates the leaf with 0700 before any dataset content is stored.
      await _checked('/usr/bin/install', [
        '-d',
        '-m',
        '0700',
        '--',
        directory.path,
      ]);
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        _recovery();
      }
      await _sync(directory.parent.path);
      final lock = File('${directory.path}/.bootstrap.lock');
      final lockType = await FileSystemEntity.type(
        lock.path,
        followLinks: false,
      );
      if (lockType != FileSystemEntityType.notFound &&
          lockType != FileSystemEntityType.file) {
        _recovery();
      }
      await lock.create();
      await _mode(lock.path, '0600');
      final deadline = DateTime.now().add(operationTimeout);
      while (true) {
        holder = await Process.start('/usr/bin/flock', [
          '--exclusive',
          '--nonblock',
          '--no-fork',
          lock.path,
          '/usr/bin/cat',
        ], runInShell: false);
        // cat keeps the kernel lock for exactly the lifetime of this pipe.
        // A child process avoids POSIX per-process Dart File.lock semantics.
        holder.stderr.drain<void>();
        String? ready;
        try {
          holder.stdin.writeln('ready');
          await holder.stdin.flush();
          ready = await holder.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(operationTimeout);
        } on StateError {
          // Busy flock exits before cat can acknowledge.
        } on IOException {
          // Busy flock can also close stdin before the handshake write.
        }
        if (ready == 'ready') break;
        final code = await holder.exitCode.timeout(operationTimeout);
        try {
          await holder.stdin.close();
        } on IOException {
          // A rejected contender has already closed its end.
        }
        holder = null;
        if (code != 1 || DateTime.now().isAfter(deadline)) _unavailable();
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      return await body(directory);
    } on StorageBootstrapException {
      rethrow;
    } catch (_) {
      // Never propagate a process stderr, filesystem path, or secret value.
      _unavailable();
    } finally {
      if (holder != null) {
        holder.kill(ProcessSignal.sigkill);
        try {
          await holder.stdin.close();
        } on IOException {
          // Killing the helper closes its pipe as well.
        }
        await holder.exitCode;
      }
    }
  }

  Future<void> _publish(Directory directory, String name, String value) async {
    final target = File('${directory.path}/$name');
    final pending = File('${target.path}.pending');
    if (await target.exists() || await pending.exists()) _recovery();
    await pending.create(exclusive: true);
    await _mode(pending.path, '0600');
    await pending.writeAsString(value, flush: true);
    await pending.rename(target.path);
    await _sync(directory.path);
  }

  Future<void> _mode(String path, String mode) =>
      _checked('/usr/bin/chmod', [mode, '--', path]);
  Future<void> _sync(String path) => _checked('/usr/bin/sync', ['--', path]);
  Future<void> _checked(String executable, List<String> arguments) async {
    final result = await _command(
      executable,
      arguments,
      timeout: operationTimeout,
    );
    if (result.code != 0 || result.hasErrorOutput) _unavailable();
  }
}

String _randomHex(int length) {
  final random = Random.secure();
  return List.generate(
    length,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

List<int> _decodeHex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

bool _sameKey(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

Never _recovery() =>
    throw const StorageBootstrapException('storage_recovery_required');
Never _keyringUnavailable() =>
    throw const StorageBootstrapException('linux_keyring_unavailable');
Never _unavailable() =>
    throw const StorageBootstrapException('protected_storage_unavailable');

final class _CommandResult {
  const _CommandResult(this.code, this.output, this.hasErrorOutput);
  final int code;
  final String output;
  final bool hasErrorOutput;
}

Future<_CommandResult> _command(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  String? input,
}) async {
  Process? process;
  try {
    process = await Process.start(executable, arguments, runInShell: false);
    final running = process;
    final output = <int>[];
    var errorOutput = false;
    var overflow = false;
    final stdoutDone = running.stdout.listen((bytes) {
      if (output.length + bytes.length > 1024) {
        overflow = true;
        running.kill(ProcessSignal.sigkill);
      } else {
        output.addAll(bytes);
      }
    }).asFuture<void>();
    final stderrDone = running.stderr.listen((bytes) {
      if (bytes.isNotEmpty) errorOutput = true;
      // Discard errors instead of retaining potentially sensitive diagnostics.
    }).asFuture<void>();
    final completion = () async {
      if (input != null) running.stdin.write(input);
      await running.stdin.close();
      final code = await running.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      if (overflow) _unavailable();
      return _CommandResult(code, utf8.decode(output), errorOutput);
    }();
    return await completion.timeout(timeout);
  } on StorageBootstrapException {
    rethrow;
  } catch (_) {
    _unavailable();
  } finally {
    if (process != null) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }
}
