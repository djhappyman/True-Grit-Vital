// Separate-process restore activation fixture. Synthetic key, people and
// history only. Proves that process death at each activation boundary either
// keeps the previous dataset or completes the verified replacement, and that a
// wrong key leaves every recovery file in place.
import 'dart:convert';
import 'dart:io';

import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';
import 'package:true_grit_vital/restore/restore_activation.dart';

import 'fixtures/restore_fixture.dart';

Future<void> main(List<String> args) async {
  final directory = args[1];
  final mode = args[0];
  final dataPath = '$directory/data/records.sqlite';
  final expectedFile = File('$directory/expected.json');
  if (mode == 'init') {
    final crashPhase = args[2];
    await Directory('$directory/data').create(recursive: true);
    writeFixtureDatabase(dataPath);
    var live = await openFixtureStore(dataPath);
    final oldGeneration = live.generation;
    final oldNamespace = await live.restoreObjectNamespace();
    await live.close();
    final source = '$directory/source.sqlite';
    await File(dataPath).copy(source);
    live = await openFixtureStore(dataPath);
    final prepared = await live.prepareRestoredDatabase(
      stagedPath: source,
      rekeyTo: (_) async {},
    );
    await live.close();
    await expectedFile.writeAsString(
      jsonEncode({
        'old': oldGeneration,
        'new': prepared.generation,
        'oldNamespace': oldNamespace,
        'newNamespace': prepared.reminderNamespace,
      }),
      flush: true,
    );
    final activation = RestoreActivation(
      databasePath: dataPath,
      checkpoint: (phase) async {
        if (phase.name == crashPhase) exit(81);
      },
    );
    await activation.activate(
      preparedPath: prepared.path,
      previousGeneration: prepared.previousGeneration,
      newGeneration: prepared.generation,
      previousNamespace: prepared.previousNamespace ?? '',
      reminderNamespace: prepared.reminderNamespace,
      key: restoreTestKey,
      closeLive: () async {},
    );
    throw StateError('activation did not crash');
  }
  final expected =
      jsonDecode(await expectedFile.readAsString()) as Map<String, dynamic>;
  final activation = RestoreActivation(databasePath: dataPath);
  if (mode == 'wrong-key') {
    final before = Directory('${File(dataPath).parent.path}/restore')
        .listSync()
        .map((entry) => entry.path.split('/').last)
        .toSet();
    try {
      await activation.recoverInterrupted(key: List<int>.filled(32, 0));
      throw StateError('wrong key recovered');
    } on RestoreFailure catch (error) {
      if (error.code != RestoreCodes.recoveryRequired) rethrow;
    }
    final after = Directory('${File(dataPath).parent.path}/restore')
        .listSync()
        .map((entry) => entry.path.split('/').last)
        .toSet();
    if (!before.contains('journal.json') ||
        !after.contains('journal.json') ||
        !after.contains('previous.sqlite')) {
      throw StateError('wrong key did not preserve recovery files');
    }
    exit(0);
  }
  final recovery = await activation.recoverInterrupted(key: restoreTestKey);
  final expectOutcome = mode == 'old'
      ? RestoreRecoveryOutcome.cleaned
      : RestoreRecoveryOutcome.completed;
  if (recovery.outcome != expectOutcome) {
    throw StateError('outcome ${recovery.outcome} expected $expectOutcome');
  }
  final expectedGeneration = mode == 'old' ? expected['old'] : expected['new'];
  if (recovery.generation != expectedGeneration) {
    throw StateError('recovery generation ${recovery.generation}');
  }
  final store = await RecordStore.open(
    path: dataPath,
    key: restoreTestKey,
    isNew: false,
  );
  try {
    if (store.generation != expectedGeneration) {
      throw StateError('open generation ${store.generation}');
    }
    if (mode == 'new') {
      if ((await store.drafts()).isNotEmpty) {
        throw StateError('old draft survived');
      }
      final namespace = await store.restoreObjectNamespace();
      if (namespace != expected['newNamespace']) {
        throw StateError('reminder namespace not rebuilt');
      }
    }
  } finally {
    await store.close();
  }
  final restoreDirectory = Directory('${File(dataPath).parent.path}/restore');
  if (restoreDirectory.existsSync() && restoreDirectory.listSync().isNotEmpty) {
    throw StateError('restore files left behind');
  }
  exit(0);
}
