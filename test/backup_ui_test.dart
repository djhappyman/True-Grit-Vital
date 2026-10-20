import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/backup.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';
import 'package:true_grit_vital/features/backup/backup_pages.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';

class _Unlocked extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

final class _FakeOperations implements BackupOperations {
  _FakeOperations({
    required this.creation,
    this.supported = true,
    this.gate,
    this.ignoreCancellation = false,
  });

  final BackupCreation creation;
  bool supported;
  final bool ignoreCancellation;
  BackupFailure? saveFailure;
  Completer<BackupCreation>? gate;
  int creates = 0, saves = 0, discards = 0;

  @override
  bool get destinationSupported => supported;

  @override
  Future<BackupCreation> createBackup({
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) async {
    creates++;
    onProgress?.call(const BackupProgress(stage: BackupStage.snapshot));
    token.addListener(() {
      if (ignoreCancellation) return;
      final pending = gate;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(const BackupFailure('backup_cancelled'));
      }
    });
    if (gate != null) return gate!.future;
    return creation;
  }

  @override
  Future<void> discard(BackupCreation creation) async => discards++;

  @override
  Future<BackupSaveStatus> save(BackupCreation creation) async {
    saves++;
    if (saveFailure != null) throw saveFailure!;
    return BackupSaveStatus.saved;
  }

  @override
  Future<StagedBackup> validateArchive({
    required File archive,
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) async => throw UnsupportedError('not used by this widget test');

  @override
  Future<void> cleanupAbandoned() async {}
}

void main() {
  late Directory directory;
  late File archive;
  late BackupCreation creation;
  final inventory = BackupInventory(
    generation: 'generation_ui',
    schemaVersion: 21,
    people: const [
      BackupPerson(id: 'me', name: 'Me', archived: false),
      BackupPerson(id: 'other', name: 'Synthetic adult', archived: false),
    ],
    peopleCount: 2,
    recordCount: 4,
    itemCount: 2,
    supportingCount: 1,
    attachmentCount: 3,
    attachmentBytes: 4096,
    attachmentSha256: 'a' * 64,
    earliestRecord: DateTime.utc(2026, 1, 1),
    latestRecord: DateTime.utc(2026, 10, 20),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-backup-ui-');
    archive = File(
      '${directory.path}/backup-20261020-120000-abcd1234.vitalbackup',
    );
    await archive.writeAsBytes(Uint8List(64));
    final bytes = await archive.length();
    creation = BackupCreation(
      archive: archive,
      fileName: archive.uri.pathSegments.last,
      byteCount: bytes,
      sha256: 'b' * 64,
      createdAt: DateTime.utc(2026, 10, 20, 12),
      inventory: inventory,
      summary: inventory.summaryFor(bytes, 'b' * 64),
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Widget app(BackupOperations operations) => ProviderScope(
    overrides: [
      backupOperationsProvider.overrideWithValue(operations),
      appLockProvider.overrideWith(_Unlocked.new),
    ],
    child: ShadcnApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB')],
      home: const BackupPage(),
    ),
  );

  Finder field(String name) => find.descendant(
    of: find.byKey(ValueKey(name)),
    matching: find.byType(TextField),
  );

  testWidgets('unsupported save is stated and blocks creation', (tester) async {
    final operations = _FakeOperations(creation: creation, supported: false);
    await tester.pumpWidget(app(operations));
    await tester.pumpAndSettle();
    expect(find.text('Cannot save'), findsOneWidget);
    expect(
      find.text('Saving backup files is unavailable on this device.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('backup-create')), findsNothing);
  });

  testWidgets('password requirements are checked before any work', (
    tester,
  ) async {
    final operations = _FakeOperations(creation: creation);
    await tester.pumpWidget(app(operations));
    await tester.pumpAndSettle();
    await tester.enterText(field('backup-password'), 'short');
    await tester.enterText(field('backup-confirm'), 'short');
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await tester.pump();
    expect(find.text('Use at least 12 characters.'), findsWidgets);
    expect(operations.creates, 0);

    await tester.enterText(field('backup-password'), 'a long enough password');
    await tester.enterText(field('backup-confirm'), 'a different password');
    await tester.ensureVisible(find.byKey(const ValueKey('backup-create')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(operations.creates, 0);
  });

  testWidgets('a complete backup can be saved', (tester) async {
    final operations = _FakeOperations(creation: creation);
    await tester.pumpWidget(app(operations));
    await tester.pumpAndSettle();
    await tester.enterText(field('backup-password'), 'a long enough password');
    await tester.enterText(field('backup-confirm'), 'a long enough password');
    await tester.ensureVisible(find.byKey(const ValueKey('backup-create')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await tester.pumpAndSettle();
    expect(find.text('Backup ready'), findsOneWidget);
    expect(find.text('Includes 2 adults and 3 files.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('backup-save')));
    await tester.pumpAndSettle();
    expect(operations.saves, 1);
    expect(find.text('Backup saved'), findsOneWidget);
    expect(
      find.textContaining('backup-20261020-120000-abcd1234.vitalbackup'),
      findsOneWidget,
    );
  });

  testWidgets('a failed save keeps the backup available to retry', (
    tester,
  ) async {
    final operations = _FakeOperations(creation: creation)
      ..saveFailure = const BackupFailure('backup_save_failed');
    await tester.pumpWidget(app(operations));
    await tester.pumpAndSettle();
    await tester.enterText(field('backup-password'), 'a long enough password');
    await tester.enterText(field('backup-confirm'), 'a long enough password');
    await tester.ensureVisible(find.byKey(const ValueKey('backup-create')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('backup-save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('backup-save')));
    await tester.pump();
    expect(find.text('Not saved'), findsOneWidget);
    expect(
      find.text('The backup file is still here. Try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('backup-save')), findsOneWidget);
    operations.saveFailure = null;
    await tester.tap(find.byKey(const ValueKey('backup-save')));
    await tester.pumpAndSettle();
    expect(find.text('Backup saved'), findsOneWidget);
  });

  test('a late success after Cancel is discarded instead of offered', () async {
    final gate = Completer<BackupCreation>();
    final operations = _FakeOperations(
      creation: creation,
      gate: gate,
      ignoreCancellation: true,
    );
    final container = ProviderContainer(
      overrides: [
        backupOperationsProvider.overrideWithValue(operations),
        appLockProvider.overrideWith(_Unlocked.new),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(backupProvider.notifier);
    final pending = controller.create(
      password: 'a long enough password',
      confirmation: 'a long enough password',
    );
    controller.cancel();
    gate.complete(creation);
    await pending;
    expect(container.read(backupProvider).phase, BackupPhase.cancelled);
    expect(container.read(backupProvider).creation, isNull);
    expect(operations.discards, 1);
  });

  testWidgets('cancellation is announced without a saved archive', (
    tester,
  ) async {
    final gate = Completer<BackupCreation>();
    final operations = _FakeOperations(creation: creation, gate: gate);
    await tester.pumpWidget(app(operations));
    await tester.pumpAndSettle();
    await tester.enterText(field('backup-password'), 'a long enough password');
    await tester.enterText(field('backup-confirm'), 'a long enough password');
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await tester.pump();
    expect(find.text('Preparing records'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('backup-cancel')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('backup-cancel')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Backup cancelled'), findsOneWidget);
    expect(find.text('No backup was created.'), findsOneWidget);
  });

  testWidgets('the setup remains readable at large text on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final operations = _FakeOperations(creation: creation);
    await tester.pumpWidget(app(operations));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Create backup'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-create')), findsOneWidget);
  });
}
