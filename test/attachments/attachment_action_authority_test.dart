import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/attachments.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/attachments.dart';

import 'attachment_controller_test.dart'
    show FaultHandoff, InventoryGateway, RecoveryLock, seedFile, until;

class DelayedHandoff extends FaultHandoff {
  DelayedHandoff() : super(() => DateTime.now().toUtc());
  final publishing = Completer<void>(), resume = Completer<void>();
  int shares = 0;
  @override
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) async {
    publishing.complete();
    await resume.future;
  }

  @override
  Future<bool> share(String id) {
    shares++;
    return super.share(id);
  }
}

class DelayedSave extends InventoryGateway {
  final saving = Completer<void>(), resume = Completer<void>();
  Uint8List? passedBytes;
  int saves = 0;
  @override
  AttachmentCapabilities get capabilities => const AttachmentCapabilities(
    pickFile: false,
    photo: false,
    camera: false,
    share: false,
    save: true,
  );
  @override
  Future<bool> save({
    required String name,
    required String mime,
    required Uint8List bytes,
  }) async {
    saves++;
    passedBytes = bytes;
    saving.complete();
    await resume.future;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late RecordStore store;
  late AttachmentRecord file;
  late ProviderContainer container;
  late DelayedHandoff handoff;
  final key = List.generate(32, (i) => i + 1);

  int pinCount() {
    final db = sqlite3.open('${directory.path}/records.db');
    try {
      db.execute("PRAGMA cipher='chacha20'");
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute('PRAGMA key="x\'$hex\'"');
      return db.select('SELECT COUNT(*) n FROM attachment_pin').single['n']
          as int;
    } finally {
      db.close();
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'vital-action-authority-',
    );
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: true,
    );
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic original',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    );
    file = await seedFile(store, item, Uint8List.fromList([1, 2, 3]));
    handoff = DelayedHandoff();
    container = ProviderContainer(
      overrides: [
        recordStoreProvider.overrideWith((ref) async => store),
        appLockProvider.overrideWith(RecoveryLock.new),
        attachmentGatewayProvider.overrideWithValue(InventoryGateway()),
        attachmentHandoffProvider.overrideWithValue(handoff),
      ],
    );
    await container.read(recordStoreProvider.future);
    container.listen(attachmentsControllerProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await until(() => !container.read(attachmentsControllerProvider).busy);
  });
  tearDown(() async {
    container.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final interruption in [
    'lock cycle',
    'attachment revision',
    'owner revision',
    'target revision',
  ]) {
    test(
      'publish completion after $interruption cannot initiate sharing',
      () async {
        final controller = container.read(
          attachmentsControllerProvider.notifier,
        );
        final work = controller.handoff(file, save: false);
        await handoff.publishing.future;
        if (interruption == 'lock cycle') {
          final lock = container.read(appLockProvider.notifier) as RecoveryLock;
          lock.setLocked(true);
          lock.setLocked(false);
        } else if (interruption == 'attachment revision') {
          await store.renameAttachment(
            commandId: 'rename',
            attachment: file,
            expectedPersonRevision: 1,
            name: 'Changed original',
          );
        } else if (interruption == 'target revision') {
          await store.saveItemDetail(
            commandId: 'edit-target',
            itemId: file.targetId,
            instructions: '',
            notes: '',
            expectedRevision: null,
            name: 'Changed target',
            expectedItemRevision: 1,
          );
        } else {
          await store.editProfile(
            commandId: 'owner',
            personId: meId,
            expectedRevision: 1,
            name: 'Changed owner',
            adultConfirmed: true,
          );
        }
        handoff.resume.complete();
        await work;
        expect(handoff.shares, 0);
        expect(handoff.artifacts, isEmpty);
        expect(pinCount(), 0);
        expect(await store.attachmentById(file.id), isNotNull);
      },
    );
  }

  test('a departed route cancels only its unoffered handoff', () async {
    var onRoute = true;
    handoff.artifacts['unrelated-live'] = DateTime.now().toUtc().add(
      const Duration(minutes: 5),
    );
    handoff.offered.add('unrelated-live');
    final controller = container.read(attachmentsControllerProvider.notifier);
    final work = controller.handoff(
      file,
      save: false,
      isCurrent: () => onRoute,
    );
    await handoff.publishing.future;
    onRoute = false;
    handoff.resume.complete();
    await work;
    expect(handoff.shares, 0);
    expect(handoff.artifacts.keys, ['unrelated-live']);
    expect(pinCount(), 0);
  });

  test('dataset replacement cannot share a delayed old publication', () async {
    final oldStore = store;
    final controller = container.read(attachmentsControllerProvider.notifier);
    final work = controller.handoff(file, save: false);
    await handoff.publishing.future;
    final replacement = await RecordStore.open(
      path: '${directory.path}/replacement.db',
      key: key,
      isNew: true,
    );
    addTearDown(replacement.close);
    container.updateOverrides([
      recordStoreProvider.overrideWith((ref) async => replacement),
      appLockProvider.overrideWith(RecoveryLock.new),
      attachmentGatewayProvider.overrideWithValue(InventoryGateway()),
      attachmentHandoffProvider.overrideWithValue(handoff),
    ]);
    await container.read(recordStoreProvider.future);
    container.read(attachmentsControllerProvider);
    handoff.resume.complete();
    await work;
    expect(handoff.shares, 0);
    expect(handoff.artifacts, isEmpty);
    expect(pinCount(), 0);
    expect(await oldStore.attachmentById(file.id), isNotNull);
  });

  test(
    'double activation offers one captured handoff and retains its lease',
    () async {
      final controller = container.read(attachmentsControllerProvider.notifier);
      final work = controller.handoff(file, save: false);
      await handoff.publishing.future;
      await controller.handoff(file, save: false);
      handoff.resume.complete();
      await work;
      expect(handoff.shares, 1);
      expect(handoff.artifacts, hasLength(1));
      expect(pinCount(), 1);
      expect(await store.attachmentById(file.id), isNotNull);
    },
  );

  test(
    'rename rolls back revision and audit when authority expires after writes',
    () async {
      final controller = container.read(attachmentsControllerProvider.notifier);
      final access = controller.actionEpoch;
      final lock = container.read(appLockProvider.notifier) as RecoveryLock;
      var checks = 0;
      await expectLater(
        store.renameAttachment(
          commandId: 'expired-rename',
          attachment: file,
          expectedPersonRevision: 1,
          name: 'Must roll back',
          canCommit: () {
            checks++;
            if (checks == 3) {
              lock.setLocked(true);
              lock.setLocked(false);
            }
            return controller.actionCurrent(access);
          },
        ),
        throwsA(
          isA<CommandConflict>().having((e) => e.code, 'code', 'app_locked'),
        ),
      );
      expect(checks, 3);
      final unchanged = (await store.attachmentById(file.id))!;
      expect(unchanged.name, file.name);
      expect(unchanged.revision, file.revision);
      expect(await store.operationCommitted('expired-rename'), false);
      final retry = await store.renameAttachment(
        commandId: 'expired-rename',
        attachment: file,
        expectedPersonRevision: 1,
        name: 'Must roll back',
        canCommit: () => controller.actionCurrent(controller.actionEpoch),
      );
      expect(retry.revision, file.revision + 1);
      expect(await store.operationCommitted('expired-rename'), true);
    },
  );

  test('an initiated save keeps its factual result, wipes bytes and releases its pin', () async {
    final gateway = DelayedSave();
    container.updateOverrides([
      recordStoreProvider.overrideWith((ref) async => store),
      appLockProvider.overrideWith(RecoveryLock.new),
      attachmentGatewayProvider.overrideWithValue(gateway),
      attachmentHandoffProvider.overrideWithValue(handoff),
    ]);
    await container.read(recordStoreProvider.future);
    final controller = container.read(attachmentsControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await until(() => !container.read(attachmentsControllerProvider).busy);
    final work = controller.handoff(file, save: true);
    await gateway.saving.future;
    await controller.handoff(file, save: true);
    final lock = container.read(appLockProvider.notifier) as RecoveryLock;
    lock.setLocked(true);
    lock.setLocked(false);
    gateway.resume.complete();
    await work;
    expect(gateway.saves, 1);
    expect(gateway.passedBytes, everyElement(0));
    expect(pinCount(), 0);
    expect(container.read(attachmentsControllerProvider).notice, 'copySaved');
    expect(await store.attachmentById(file.id), isNotNull);
  });

  test(
    'a queued rename cannot regain authority after lock then unlock',
    () async {
      final blocker = await seedFile(
        store,
        (await store.itemById(file.targetId))!,
        Uint8List.fromList([4, 5]),
      );
      final entered = Completer<void>(), resume = Completer<void>();
      final blockingWrite = store.deleteAttachment(
        commandId: 'blocking-write',
        attachment: blocker,
        expectedPersonRevision: 1,
        beforeCommit: () async {
          entered.complete();
          await resume.future;
        },
      );
      await entered.future;
      final controller = container.read(attachmentsControllerProvider.notifier);
      final access = controller.actionEpoch;
      final queued = store.renameAttachment(
        commandId: 'queued-rename',
        attachment: file,
        expectedPersonRevision: 1,
        name: 'Expired queued change',
        canCommit: () => controller.actionCurrent(access),
      );
      final rejected = expectLater(
        queued,
        throwsA(
          isA<CommandConflict>().having((e) => e.code, 'code', 'app_locked'),
        ),
      );
      final lock = container.read(appLockProvider.notifier) as RecoveryLock;
      lock.setLocked(true);
      lock.setLocked(false);
      resume.complete();
      await blockingWrite;
      await rejected;
      final unchanged = (await store.attachmentById(file.id))!;
      expect(unchanged.name, file.name);
      expect(unchanged.revision, file.revision);
      expect(await store.operationCommitted('queued-rename'), false);
    },
  );
}
