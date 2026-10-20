import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../domain/backup/backup.dart';

/// Runs password KDF and streaming AEAD work away from the UI isolate.
/// Cancellation is cooperative first, then the worker is terminated so an
/// incomplete file cannot survive as a reported result.
final class BackupWorker {
  const BackupWorker();

  Future<BackupArchiveSummary> create({
    required File snapshot,
    required File output,
    required String password,
    required BackupHeader header,
    required List<int> datasetKey,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) async {
    final result = await _run(
      {
        'operation': 'create',
        'snapshot': snapshot.path,
        'output': output.path,
        'password': password,
        'header': header.toJson(),
        'datasetKey': datasetKey,
      },
      token: token,
      cleanupOnCancel: output,
      onProgress: onProgress,
    );
    return BackupArchiveSummary(
      header: BackupHeader.fromJson(
        Map<String, Object?>.from(result['header']! as Map),
      ),
      bytes: result['archiveBytes']! as int,
    );
  }

  Future<BackupDecryptResult> decrypt({
    required File archive,
    required File output,
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) async {
    final result = await _run(
      {
        'operation': 'decrypt',
        'archive': archive.path,
        'output': output.path,
        'password': password,
      },
      token: token,
      cleanupOnCancel: output,
      onProgress: onProgress,
    );
    return BackupDecryptResult(
      header: BackupHeader.fromJson(
        Map<String, Object?>.from(result['header']! as Map),
      ),
      snapshotBytes: result['snapshotBytes']! as int,
      snapshotSha256: result['snapshotSha256']! as String,
      datasetKey: (result['datasetKey']! as List<Object?>).cast<int>(),
      archiveBytes: result['archiveBytes']! as int,
    );
  }

  Future<Map<String, Object?>> _run(
    Map<String, Object?> request, {
    required BackupCancellationToken token,
    required File cleanupOnCancel,
    void Function(BackupProgress)? onProgress,
  }) async {
    token.throwIfCancelled();
    final replies = ReceivePort();
    final control = ReceivePort();
    final exits = ReceivePort();
    final errors = ReceivePort();
    final completer = Completer<Map<String, Object?>>();
    Isolate? isolate;
    Timer? stopTimer;
    SendPort? controlPort;

    void finishError(Object error, [StackTrace? stack]) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    }

    void stopWorker({bool deleteOutput = true}) {
      isolate?.kill(priority: Isolate.immediate);
      if (deleteOutput) {
        unawaited(_deleteQuietly(cleanupOnCancel));
      }
    }

    void complete(Map<String, Object?> value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    final subscription = replies.listen((message) {
      final data = Map<String, Object?>.from(message as Map);
      switch (data['type']) {
        case 'progress':
          onProgress?.call(
            BackupProgress(
              stage: BackupStage.values.byName(data['stage']! as String),
              completedBytes: data['completed']! as int,
              totalBytes: data['total']! as int,
            ),
          );
        case 'done':
          stopTimer?.cancel();
          complete(Map<String, Object?>.from(data['result']! as Map));
        case 'cancelled':
          stopTimer?.cancel();
          finishError(const BackupFailure('backup_cancelled'));
        case 'error':
          stopTimer?.cancel();
          finishError(BackupFailure(data['code']! as String));
      }
    });
    final exitSubscription = exits.listen((_) {
      if (!completer.isCompleted) {
        finishError(const BackupFailure('backup_failed'));
      }
    });
    final errorSubscription = errors.listen((message) {
      if (!completer.isCompleted) {
        finishError(const BackupFailure('backup_failed'));
      }
    });
    void cancelListener() {
      controlPort?.send('cancel');
      stopTimer?.cancel();
      stopTimer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          stopWorker();
          finishError(const BackupFailure('backup_cancelled'));
        }
      });
    }

    token.addListener(cancelListener);

    try {
      isolate = await Isolate.spawn<Map<String, Object?>>(
        _workerMain,
        {...request, 'replies': replies.sendPort, 'control': control.sendPort},
        onExit: exits.sendPort,
        onError: errors.sendPort,
        debugName: 'vital-backup-worker',
      );
      final port = await control.first.timeout(const Duration(seconds: 10));
      controlPort = port as SendPort;
      if (token.isCancelled) cancelListener();
      return await completer.future;
    } finally {
      token.removeListener(cancelListener);
      stopTimer?.cancel();
      await subscription.cancel();
      await exitSubscription.cancel();
      await errorSubscription.cancel();
      replies.close();
      control.close();
      exits.close();
      errors.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Startup cleanup retries known staging names.
  }
}

void _workerMain(Map<String, Object?> request) {
  final replies = request['replies']! as SendPort;
  final control = ReceivePort();
  (request['control']! as SendPort).send(control.sendPort);
  var cancelled = false;
  control.listen((message) {
    if (message == 'cancel') cancelled = true;
  });
  void progress(BackupStage stage, int completed, int total) {
    replies.send({
      'type': 'progress',
      'stage': stage.name,
      'completed': completed,
      'total': total,
    });
  }

  Future<void> run() async {
    try {
      final operation = request['operation']! as String;
      if (operation == 'create') {
        final header = BackupHeader.fromJson(
          Map<String, Object?>.from(request['header']! as Map),
        );
        final summary = await createBackupArchive(
          snapshot: File(request['snapshot']! as String),
          output: File(request['output']! as String),
          password: request['password']! as String,
          header: header,
          datasetKey: (request['datasetKey']! as List<Object?>).cast<int>(),
          isCancelled: () => cancelled,
          onProgress: (completed, total) =>
              progress(BackupStage.encrypt, completed, total),
        );
        replies.send({
          'type': 'done',
          'result': {
            'header': summary.header.toJson(),
            'archiveBytes': summary.bytes,
          },
        });
      } else if (operation == 'decrypt') {
        final result = await decryptBackupArchive(
          archive: File(request['archive']! as String),
          output: File(request['output']! as String),
          password: request['password']! as String,
          isCancelled: () => cancelled,
          onProgress: (completed, total) =>
              progress(BackupStage.verify, completed, total),
        );
        replies.send({
          'type': 'done',
          'result': {
            'header': result.header.toJson(),
            'snapshotBytes': result.snapshotBytes,
            'snapshotSha256': result.snapshotSha256,
            'datasetKey': result.datasetKey,
            'archiveBytes': result.archiveBytes,
          },
        });
      } else {
        throw const BackupFailure('backup_failed');
      }
    } on BackupFailure catch (error) {
      replies.send({
        'type': error.code == 'backup_cancelled' ? 'cancelled' : 'error',
        'code': error.code,
      });
    } on FileSystemException catch (error) {
      replies.send({
        'type': 'error',
        'code': error.osError?.errorCode == 28
            ? 'backup_no_space'
            : 'backup_failed',
      });
    } catch (_) {
      replies.send({'type': 'error', 'code': 'backup_failed'});
    } finally {
      control.close();
    }
  }

  unawaited(run());
}
