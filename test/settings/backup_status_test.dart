import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/backup.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/backup/backup_pages.dart';
import 'package:true_grit_vital/features/settings/settings_backup_status.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import '../screen_settings_hub_test.dart' show loadFonts;
import '../settings_vault_ui_test.dart' show VaultTestLock;
import '../vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const _savedKey = ValueKey('settings-backup-status-saved');
const _statusKey = ValueKey('settings-backup-status');

BackupReceipt _receipt(
  String generation,
  int id, {
  required DateTime verifiedAt,
  DateTime? savedAt,
}) => BackupReceipt(
  generation: generation,
  sha256: id.toRadixString(16).padLeft(64, '0'),
  byteCount: 4096,
  schemaVersion: currentRecordSchemaVersion,
  recordCount: 4,
  itemCount: 2,
  attachmentCount: 1,
  createdAt: verifiedAt.subtract(const Duration(minutes: 1)),
  verifiedAt: verifiedAt,
  savedAt: savedAt,
);

Future<void> _waitForKey(WidgetTester tester, Key key) async {
  for (var i = 0; i < 30 && find.byKey(key).evaluate().isEmpty; i++) {
    await settle(tester);
  }
  expect(find.byKey(key), findsOneWidget);
}

String _stamp(
  WidgetTester tester,
  ProviderContainer container,
  DateTime instant,
) {
  final context = tester.element(find.byType(SettingsBackupStatus));
  final preference = container.read(displayPreferencesProvider).timeFormat;
  final zone = container.read(displayZoneProvider);
  return displayFormatter(
    context,
    preference,
  ).format(DisplayTime().instant(instant, zone), includeOffset: true);
}

void main() {
  setUpAll(loadFonts);

  appTest('latest confirmed save uses save time, not list or check order', (
    tester,
  ) async {
    final f = await launch(tester);
    final generation = f.store.generation;
    final olderSave = _receipt(
      generation,
      1,
      savedAt: DateTime.utc(2026, 10, 20, 8, 30),
      verifiedAt: DateTime.utc(2026, 10, 22, 23, 50),
    );
    final verifiedOnly = _receipt(
      generation,
      2,
      verifiedAt: DateTime.utc(2026, 10, 22, 23, 55),
    );
    final laterSave = _receipt(
      generation,
      3,
      savedAt: DateTime.utc(2026, 10, 21, 9, 5),
      verifiedAt: DateTime.utc(2026, 10, 21, 9, 6),
    );
    await runIo(
      tester,
      () => f.store.writeSetting(
        BackupHistory.settingKey,
        BackupHistory.encode([olderSave, verifiedOnly, laterSave]),
      ),
    );
    f.container.read(routerProvider).go('/settings?group=data');
    await waitForText(tester, 'Backup status');
    await _waitForKey(tester, _savedKey);
    final rendered = tester.widget<Text>(find.byKey(_savedKey)).data;
    expect(
      rendered,
      'Last save: ${_stamp(tester, f.container, laterSave.savedAt!)}',
    );
    expect(
      rendered,
      isNot(contains(_stamp(tester, f.container, olderSave.savedAt!))),
    );
    expect(find.textContaining('Archive checked'), findsNothing);
    expect(f.container.read(backupProvider).phase, BackupPhase.idle);
    expect(find.byType(TextField), findsNothing);
  });

  appTest('a confirmed save refreshes the compact status', (tester) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/settings?group=data');
    await waitForText(tester, 'No confirmed save.');
    final saved = _receipt(
      f.store.generation,
      9,
      savedAt: DateTime.utc(2026, 10, 22, 15, 45),
      verifiedAt: DateTime.utc(2026, 10, 22, 15, 44),
    );
    await runIo(tester, () => f.store.recordBackupReceipt(saved));
    await _waitForKey(tester, _savedKey);
    expect(
      tester.widget<Text>(find.byKey(_savedKey)).data,
      'Last save: ${_stamp(tester, f.container, saved.savedAt!)}',
    );
  });

  appTest('verified-only receipts show a plain empty state', (tester) async {
    final f = await launch(tester);
    await runIo(
      tester,
      () => f.store.writeSetting(
        BackupHistory.settingKey,
        BackupHistory.encode([
          _receipt(
            f.store.generation,
            4,
            verifiedAt: DateTime.utc(2026, 10, 22, 13),
          ),
        ]),
      ),
    );
    f.container.read(routerProvider).go('/settings?group=data');
    await waitForText(tester, 'No confirmed save.');
    expect(find.byKey(_savedKey), findsNothing);
    expect(find.textContaining('Last save'), findsNothing);
    expect(find.text('Backup'), findsOneWidget);
  });

  appTest('history error offers Retry and never implies a saved backup', (
    tester,
  ) async {
    final f = await launch(tester);
    final saved = _receipt(
      f.store.generation,
      5,
      savedAt: DateTime.utc(2026, 10, 22, 11),
      verifiedAt: DateTime.utc(2026, 10, 22, 10, 59),
    );
    var reads = 0;
    final scoped = ProviderContainer(
      parent: f.container,
      overrides: [
        backupHistoryProvider.overrideWith((ref) {
          reads++;
          return reads == 1
              ? Stream<List<BackupReceipt>>.error(
                  StateError('synthetic history read'),
                )
              : Stream.value([saved]);
        }),
      ],
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scoped, child: const VitalApp()),
    );
    scoped.read(routerProvider).go('/settings?group=data');
    await waitForText(tester, 'Backup status could not be loaded.');
    expect(find.text('No confirmed save.'), findsNothing);
    expect(find.byKey(_savedKey), findsNothing);
    await tap(tester, 'Retry');
    await _waitForKey(tester, _savedKey);
    expect(find.text('Backup status could not be loaded.'), findsNothing);
    expect(reads, 2);
  });

  appTest('old-generation receipts are ignored and the summary hides on lock', (
    tester,
  ) async {
    final f = await launch(tester);
    final current = _receipt(
      f.store.generation,
      6,
      savedAt: DateTime.utc(2026, 10, 22, 10),
      verifiedAt: DateTime.utc(2026, 10, 22, 9, 59),
    );
    final old = _receipt(
      'previous_generation',
      7,
      savedAt: DateTime.utc(2026, 10, 23, 10),
      verifiedAt: DateTime.utc(2026, 10, 23, 9, 59),
    );
    await runIo(
      tester,
      () => f.store.writeSetting(
        BackupHistory.settingKey,
        BackupHistory.encode([old, current]),
      ),
    );
    final scoped = ProviderContainer(
      parent: f.container,
      overrides: [appLockProvider.overrideWith(VaultTestLock.new)],
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scoped, child: const VitalApp()),
    );
    scoped.read(routerProvider).go('/settings?group=data');
    await waitForText(tester, 'Backup status');
    await _waitForKey(tester, _savedKey);
    expect(
      tester.widget<Text>(find.byKey(_savedKey)).data,
      'Last save: ${_stamp(tester, scoped, current.savedAt!)}',
    );
    expect(find.byKey(_statusKey), findsOneWidget);
    (scoped.read(appLockProvider.notifier) as VaultTestLock).hide();
    await settle(tester);
    expect(find.text('Backup status'), findsNothing);
    expect(find.byKey(_statusKey), findsNothing);
    expect(find.byKey(_savedKey), findsNothing);
  });

  appTest('Backup command opens the existing workflow and Back returns', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/settings?group=data');
    await waitForText(tester, 'Backup status');
    await tap(tester, 'Backup');
    expect(find.byType(BackupPage), findsOneWidget);
    await tap(tester, 'Back');
    await waitForText(tester, 'Backup status');
    expect(
      f.container.read(routerProvider).state.uri.toString(),
      '/settings?group=data',
    );
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('backup status fits 320px and double text in ${mode.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      await runIo(
        tester,
        () => f.store.writeSetting(
          BackupHistory.settingKey,
          BackupHistory.encode([
            _receipt(
              f.store.generation,
              8,
              savedAt: DateTime.utc(2026, 10, 22, 21, 30),
              verifiedAt: DateTime.utc(2026, 10, 22, 21, 29),
            ),
          ]),
        ),
      );
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await settle(tester);
      f.container.read(routerProvider).go('/settings?group=data');
      await waitForText(tester, 'Backup status');
      await _waitForKey(tester, _savedKey);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settle(tester);
      final card = find.byKey(_statusKey);
      await tester.ensureVisible(card);
      await settle(tester);
      expect(tester.takeException(), isNull);
      final command = find.descendant(
        of: card,
        matching: find.byType(VitalButton),
      );
      expect(command, findsOneWidget);
      expect(tester.getSize(command).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(card).width, lessThanOrEqualTo(288));
    });
  }
  appTest('capture backup status inside Settings Data', (tester) async {
    const output = String.fromEnvironment('VITAL_BACKUP_STATUS_CAPTURES');
    if (output.isEmpty) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await launch(tester);
    await runIo(
      tester,
      () => f.store.recordBackupReceipt(
        _receipt(
          f.store.generation,
          12,
          verifiedAt: DateTime.utc(2026, 10, 22, 12),
          savedAt: DateTime.utc(2026, 10, 22, 12, 1),
        ),
      ),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: RepaintBoundary(key: key, child: const VitalApp()),
      ),
    );
    f.container.read(routerProvider).go('/settings?group=data');
    await _waitForKey(tester, _savedKey);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await settle(tester);
      await tester.ensureVisible(find.byType(SettingsBackupStatus));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$output/${mode.name}-backup-status.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
