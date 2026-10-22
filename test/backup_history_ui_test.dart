import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/backup.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/features/backup/backup_pages.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'app_lock_controller_test.dart' show ControlledAuth;
import 'data/backup_history_store_test.dart' show receipt;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'settings_vault_ui_test.dart' show capture;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

void main() {
  setUpAll(loadFonts);
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('backup receipts distinguish checked from saved in ${mode.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester, auth: ControlledAuth());
      await runIo(tester, () async {
        await f.store.recordBackupReceipt(
          receipt(f.store.generation, 1, saved: true),
        );
        await f.store.recordBackupReceipt(receipt(f.store.generation, 2));
      });
      final key = GlobalKey();
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: key, child: const VitalApp()),
        ),
      );
      f.container.read(routerProvider).go('/backup');
      await waitForText(tester, 'Last save');
      final disclosure = find.byKey(
        const ValueKey('backup-history-disclosure'),
      );
      await tester.ensureVisible(disclosure);
      await settle(tester);
      expect(find.textContaining('Save confirmed:'), findsWidgets);
      await tester.tap(
        find.descendant(of: disclosure, matching: find.byType(Button)).first,
      );
      await settle(tester);
      expect(find.textContaining('Archive checked:'), findsNWidgets(2));
      expect(find.textContaining('No save confirmation.'), findsOneWidget);
      expect(find.textContaining('Recorded doses: 3.'), findsNWidgets(2));
      expect(find.textContaining('can be restored now.'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Archive checked:').first);
      await settle(tester);
      await capture(tester, key, '${mode.name}-backup-history');
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await settle(tester);
      expect(
        find.textContaining('Archive checked:'),
        findsNWidgets(2),
        reason: 'Receipt disclosure survives width, text scale and reduced-motion changes',
      );
      await tester.ensureVisible(find.textContaining('Archive checked:').first);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await capture(tester, key, '${mode.name}-backup-history-narrow');
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      expect(find.byType(BackupHistoryPanel).hitTestable(), findsNothing);
      expect(
        find.textContaining('Save confirmed:').hitTestable(),
        findsNothing,
      );
    });
  }

  appTest('history error offers retry without implying no saved backups', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(
      tester,
      () => f.store.writeSetting(BackupHistory.settingKey, 'invalid'),
    );
    f.container.read(routerProvider).go('/backup');
    await waitForText(
      tester,
      'Backup history could not be loaded. Retry to check it.',
    );
    expect(
      find.text('No confirmed save in the retained history.'),
      findsNothing,
    );
    await runIo(
      tester,
      () => f.store.writeSetting(
        BackupHistory.settingKey,
        BackupHistory.encode([receipt(f.store.generation, 1, saved: true)]),
      ),
    );
    f.container.invalidate(backupHistoryProvider);
    await waitForText(tester, 'Last save');
    expect(find.textContaining('Save confirmed:'), findsOneWidget);
  });
}
