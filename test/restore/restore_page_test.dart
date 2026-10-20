import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/restore.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import '../vital_app_test.dart' show settle, tap;

final class FakeRestoreGateway implements RestoreGateway {
  @override
  bool supported = true;
  @override
  int currentSchemaVersion = 21;

  Object? validationError;
  Completer<RestoreArchive>? validationGate;
  bool failActivation = false;
  bool remindersInvalidated = true;
  int chooseCalls = 0, validateCalls = 0, prepareCalls = 0, activateCalls = 0;
  int discardArchiveCalls = 0, discardPickCalls = 0, refreshCalls = 0;
  late RestorePick pick;
  late RestoreArchive archive;

  @override
  Future<RestorePick?> chooseArchive() async {
    chooseCalls++;
    return pick;
  }

  @override
  Future<void> discardPick(RestorePick pick) async {
    discardPickCalls++;
  }

  @override
  Future<RestoreArchive> validateArchive({
    required RestorePick pick,
    required String password,
    required BackupCancellationToken token,
    void Function(RestoreProgress progress)? onProgress,
  }) async {
    validateCalls++;
    final error = validationError;
    if (error != null) throw error;
    onProgress?.call(
      const RestoreProgress(stage: RestoreProgressStage.checking, fraction: 1),
    );
    if (validationGate != null) return validationGate!.future;
    return archive;
  }

  @override
  Future<void> discardArchive(RestoreArchive archive) async {
    discardArchiveCalls++;
  }

  @override
  Future<RestorePreparedDatabase> prepare(RestoreArchive archive) async {
    prepareCalls++;
    return RestorePreparedDatabase(
      path: archive.databasePath,
      previousGeneration: 'aaaaaaaaaaaaaaaa',
      generation: 'bbbbbbbbbbbbbbbb',
      previousNamespace: 'cccccccccccccccc',
      reminderNamespace: 'dddddddddddddddd',
      schemaVersion: 21,
      peopleCount: archive.inventory.peopleCount,
      recordCount: archive.inventory.recordCount,
      itemCount: archive.inventory.itemCount,
      supportingCount: archive.inventory.supportingCount,
      attachmentCount: archive.inventory.attachmentCount,
    );
  }

  @override
  Future<RestoreActivationOutcome> activate({
    required RestoreArchive archive,
    required RestorePreparedDatabase prepared,
    void Function(RestoreProgress progress)? onProgress,
  }) async {
    activateCalls++;
    if (failActivation) throw const RestoreFailure(RestoreCodes.storage);
    return RestoreActivationOutcome(
      result: RestoreActivationResult(
        previousGeneration: prepared.previousGeneration,
        newGeneration: prepared.generation,
        previousNamespace: prepared.previousNamespace,
        reminderNamespace: prepared.reminderNamespace,
      ),
      remindersInvalidated: remindersInvalidated,
    );
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}

BackupHeader _header() => BackupHeader(
  createdAt: DateTime.utc(2026, 10, 20, 9, 30),
  schemaVersion: 21,
  generation: 'gggggggggggggggg',
  kdf: BackupKdfParameters(
    memoryKiB: 65536,
    iterations: 3,
    parallelism: 1,
    hashLength: 32,
    salt: Uint8List.fromList(List<int>.filled(16, 1)),
  ),
  cipher: BackupCipherParameters(
    chunkBytes: 262144,
    noncePrefix: Uint8List.fromList(List<int>.filled(16, 2)),
  ),
  snapshot: BackupSnapshotSummary(
    bytes: 1024,
    sha256: 'a' * 64,
    attachmentCount: 1,
    attachmentBytes: 100,
    attachmentSha256: 'b' * 64,
  ),
);

BackupInventory _inventory() => BackupInventory(
  generation: 'gggggggggggggggg',
  schemaVersion: 21,
  people: const [
    BackupPerson(id: 'me', name: 'Me', archived: false),
    BackupPerson(id: 'adult-two', name: 'Synthetic Adult', archived: true),
  ],
  peopleCount: 2,
  recordCount: 3,
  itemCount: 5,
  supportingCount: 3,
  attachmentCount: 1,
  attachmentBytes: 100,
  attachmentSha256: 'b' * 64,
  coverage: const [
    BackupPersonCoverage(
      person: BackupPerson(id: 'me', name: 'Me', archived: false),
      recordCount: 2,
      attachmentCount: 1,
      earliestRecord: null,
      latestRecord: null,
    ),
    BackupPersonCoverage(
      person: BackupPerson(
        id: 'adult-two',
        name: 'Synthetic Adult',
        archived: true,
      ),
      recordCount: 1,
      attachmentCount: 0,
      earliestRecord: null,
      latestRecord: null,
    ),
  ],
  earliestRecord: DateTime.utc(2026, 9, 1),
  latestRecord: DateTime.utc(2026, 10, 19),
);

Future<({ProviderContainer container, RecordStore store})> _launch(
  WidgetTester tester,
  FakeRestoreGateway gateway,
) async {
  final directory = await tester.runAsync(
    () => Directory.systemTemp.createTemp('vital-restore-widget-'),
  );
  final key = List.generate(32, (index) => index + 1);
  final path = '${directory!.path}/test.db';
  final store = (await tester.runAsync(
    () => RecordStore.open(path: path, key: key, isNew: true),
  ))!;
  await tester.runAsync(() async {
    final me = (await store.profileById(meId))!;
    await store.editProfile(
      commandId: 'fixture-adult',
      personId: meId,
      expectedRevision: me.revision,
      name: 'Me',
      adultConfirmed: true,
    );
    await store.saveBrowsingScope(const FeedScope.me());
  });
  final pickFile = File('${directory.path}/backup.vitalbackup');
  await tester.runAsync(() => pickFile.writeAsBytes([1, 2, 3], flush: true));
  gateway.pick = RestorePick(
    name: 'synthetic-backup.vitalbackup',
    file: pickFile,
    byteCount: 3,
  );
  gateway.archive = RestoreArchive(
    databasePath: '${directory.path}/staged.sqlite',
    header: _header(),
    inventory: _inventory(),
    archiveBytes: 4096,
    rekey: (_) async {},
    discard: () async {},
  );
  final container = ProviderContainer(
    overrides: [
      restoreGatewayProvider.overrideWithValue(gateway),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      storeLoaderProvider.overrideWithValue(() => Future.value(store)),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  container.read(routerProvider).push('/restore');
  await settle(tester);
  return (container: container, store: store);
}

void main() {
  testWidgets('a cancelled check cannot publish a late archive preview', (
    tester,
  ) async {
    final gateway = FakeRestoreGateway()
      ..validationGate = Completer<RestoreArchive>();
    final f = await _launch(tester, gateway);
    await tap(tester, 'Choose');
    final controller = f.container.read(restoreProvider.notifier);
    final pending = controller.check('synthetic password');
    await tester.pump();
    controller.cancelCheck();
    gateway.validationGate!.complete(gateway.archive);
    await pending;
    await tester.pump();
    expect(f.container.read(restoreProvider).preview, isNull);
    expect(f.container.read(restoreProvider).phase, RestorePhase.idle);
    expect(gateway.discardArchiveCalls, 1);
  });

  testWidgets('full replacement requires the confirmation checkbox', (
    tester,
  ) async {
    final gateway = FakeRestoreGateway();
    await _launch(tester, gateway);
    expect(find.text('No backup chosen'), findsOneWidget);
    await tap(tester, 'Choose');
    expect(find.text('synthetic-backup.vitalbackup'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'backup password');
    await tester.pump();
    await tap(tester, 'Check');
    expect(find.text('Backup contents'), findsOneWidget);
    expect(find.text('2 people'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Synthetic Adult (Archived)'), findsOneWidget);
    expect(find.text('3 records'), findsOneWidget);
    expect(find.text('2 records'), findsOneWidget);
    expect(find.text('1 record'), findsOneWidget);
    expect(find.text('1 attachment'), findsOneWidget);
    expect(find.textContaining('2026-09-01'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    // The Replace command must remain unavailable until the destructive
    // acknowledgement is explicitly checked.
    expect(
      tester
          .widget<VitalButton>(find.widgetWithText(VitalButton, 'Replace'))
          .onPressed,
      isNull,
    );
    final before = await tester.runAsync(() async => gateway.activateCalls);
    await tap(tester, 'Replace all records');
    expect(
      tester
          .widget<VitalButton>(find.widgetWithText(VitalButton, 'Replace'))
          .onPressed,
      isNotNull,
    );
    await tap(tester, 'Replace');
    expect(find.text('Restore complete'), findsOneWidget);
    expect(
      await tester.runAsync(() async => gateway.activateCalls),
      before! + 1,
    );
    expect(gateway.prepareCalls, 1);
    expect(
      find.textContaining('Old drafts and reminder actions'),
      findsOneWidget,
    );
  });

  testWidgets('wrong password keeps the chosen file and offers Retry', (
    tester,
  ) async {
    final gateway = FakeRestoreGateway()
      ..validationError = const BackupFailure('backup_wrong_password');
    await _launch(tester, gateway);
    await tap(tester, 'Choose');
    await tester.enterText(find.byType(TextField), 'wrong password');
    await tester.pump();
    await tap(tester, 'Check');
    expect(
      find.text(
        'That password does not open this backup. Check the password and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Restore failed'), findsOneWidget);
    await tap(tester, 'Retry');
    expect(find.text('synthetic-backup.vitalbackup'), findsOneWidget);
    expect(find.text('Check'), findsOneWidget);
  });

  testWidgets('activation failure is reported without a false completion', (
    tester,
  ) async {
    final gateway = FakeRestoreGateway()..failActivation = true;
    await _launch(tester, gateway);
    await tap(tester, 'Choose');
    await tester.enterText(find.byType(TextField), 'backup password');
    await tester.pump();
    await tap(tester, 'Check');
    await tap(tester, 'Replace all records');
    await tap(tester, 'Replace');
    expect(find.text('Restore failed'), findsOneWidget);
    expect(
      find.text(
        'There is not enough protected storage to replace these records. '
        'Free some space and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Restore complete'), findsNothing);
  });

  testWidgets('a reminder epoch failure is stated after a successful restore', (
    tester,
  ) async {
    final gateway = FakeRestoreGateway()..remindersInvalidated = false;
    await _launch(tester, gateway);
    await tap(tester, 'Choose');
    await tester.enterText(find.byType(TextField), 'backup password');
    await tester.pump();
    await tap(tester, 'Check');
    await tap(tester, 'Replace all records');
    await tap(tester, 'Replace');
    expect(find.text('Restore complete'), findsOneWidget);
    expect(
      find.text(
        'Records were restored. Reminder schedules could not be cleared. '
        'Check reminder settings after reopening Vital.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('unsupported host shows no working-looking control', (
    tester,
  ) async {
    final gateway = FakeRestoreGateway()..supported = false;
    await _launch(tester, gateway);
    expect(find.text('Restore unavailable'), findsOneWidget);
    expect(find.text('Choose'), findsNothing);
  });

  testWidgets('preview remains readable at large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = FakeRestoreGateway();
    await _launch(tester, gateway);
    await tap(tester, 'Choose');
    await tester.enterText(find.byType(TextField), 'backup password');
    await tester.pump();
    await tap(tester, 'Check');
    expect(find.text('Backup contents'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
