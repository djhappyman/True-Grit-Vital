import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Credentials for one local encrypted dataset. Never include this in logs.
final class StorageLocation {
  StorageLocation({
    required this.path,
    required List<int> key,
    required this.isNew,
  }) : key = List<int>.unmodifiable(key) {
    if (path.isEmpty || key.length != 32 || key.any((b) => b < 0 || b > 255)) {
      throw ArgumentError('Invalid storage credentials');
    }
  }

  final String path;
  final List<int> key;
  final bool isNew;
}

/// Technical code only; presentation supplies reviewed recovery wording.
final class StorageBootstrapException implements Exception {
  const StorageBootstrapException(this.code);
  final String code;
  @override
  String toString() => 'StorageBootstrapException($code)';
}

abstract interface class StorageBootstrap {
  Future<StorageLocation> prepare();

  /// Call only after the encrypted database has opened and validated.
  Future<void> activate(StorageLocation location);
}

/// Android is the only currently implemented production key-storage platform.
/// Host tests inject a [StorageBootstrap] with explicit synthetic credentials.
final class AndroidStorageBootstrap implements StorageBootstrap {
  const AndroidStorageBootstrap();
  static const _channel = MethodChannel('dev.truegrit.vital/storage');

  void _requireAndroid() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const StorageBootstrapException('unsupported_host');
    }
  }

  @override
  Future<StorageLocation> prepare() async {
    _requireAndroid();
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('prepare');
      final path = result?['path'];
      final key = result?['key'];
      final isNew = result?['isNew'];
      if (path is! String ||
          key is! Uint8List ||
          isNew is! bool ||
          path.isEmpty ||
          key.length != 32) {
        throw const StorageBootstrapException('invalid_native_response');
      }
      return StorageLocation(path: path, key: key, isNew: isNew);
    } on PlatformException catch (error) {
      throw StorageBootstrapException(error.code);
    } on MissingPluginException {
      throw const StorageBootstrapException('unsupported_host');
    }
  }

  @override
  Future<void> activate(StorageLocation location) async {
    _requireAndroid();
    try {
      await _channel.invokeMethod<void>('activate', {'path': location.path});
    } on PlatformException catch (error) {
      throw StorageBootstrapException(error.code);
    } on MissingPluginException {
      throw const StorageBootstrapException('unsupported_host');
    }
  }
}
