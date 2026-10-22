import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/backup.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/domain/backup/backup_history.dart';
import 'package:true_grit_vital/features/backup/backup_pages.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'screen_settings_hub_test.dart' show loadFonts;
import 'settings_vault_ui_test.dart' show capture;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

BackupReceipt row(String generation, int id, {DateTime? save}) => BackupReceipt(
  generation: generation,
  sha256: id.toRadixString(16).padLeft(64, '0'),
  byteCount: 2048,
  schemaVersion: 26,
  recordCount: 3,
  itemCount: 2,
  attachmentCount: 1,
  createdAt: DateTime.utc(2026, 10, 20, 8),
  verifiedAt: DateTime.utc(2026, 10, 22, 8, id),
  savedAt: save,
);

Future<void> openHistory(WidgetTester tester) async {
  final disclosure = find.byKey(const ValueKey('backup-history-disclosure'));
  await tester.ensureVisible(disclosure);
  await settle(tester);
  await tester.tap(
    find.descendant(of: disclosure, matching: find.byType(Button)).first,
  );
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);
  test('latest confirmation ignores insertion and check times', () {
    final old = row('generation_test', 4, save: DateTime.utc(2026, 10, 20));
    final recent = row('generation_test', 1, save: DateTime.utc(2026, 10, 21));
    final checked = row('generation_test', 9);
    expect(latestConfirmedBackup([old, checked, recent]), same(recent));
    expect(latestConfirmedBackup([recent, checked, old]), same(recent));
    expect(latestConfirmedBackup([checked]), isNull);
    expect(latestConfirmedBackup([]), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('receipt filters preserve latest save and fit ${mode.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final f = await launch(tester);
      final old = row(f.store.generation, 4, save: DateTime.utc(2026, 10, 20));
      final recent = row(
        f.store.generation,
        1,
        save: DateTime.utc(2026, 10, 21),
      );
      final checked = row(f.store.generation, 9);
      await runIo(
        tester,
        () => f.store.writeSetting(
          BackupHistory.settingKey,
          BackupHistory.encode([old, checked, recent]),
        ),
      );
      f.container.read(appearanceProvider.notifier).setMode(mode);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: key, child: const VitalApp()),
        ),
      );
      f.container.read(routerProvider).go('/backup');
      await waitForText(tester, 'Last save');
      final latest = find.textContaining('Save confirmed:');
      final latestText = tester.widget<Text>(latest).data!;
      expect(latestText, contains('21 October 2026'));
      await openHistory(tester);
      expect(find.text('3 receipts'), findsOneWidget);
      expect(find.textContaining('Archive created:'), findsNWidgets(3));
      await tap(tester, 'Saved');
      expect(find.text('2 receipts'), findsOneWidget);
      expect(
        find.byKey(ValueKey('backup-receipt-${checked.sha256}')),
        findsNothing,
      );
      expect(find.text(latestText), findsNWidgets(2));
      await capture(tester, key, '${mode.name}-saved-receipts');
      tester.view.physicalSize = const Size(430, 844);
      await settle(tester);
      expect(tester.takeException(), isNull);
      // Keyboard invokes the same filter without changing backup state.
      final unconfirmed = find.widgetWithText(VitalButton, 'Unconfirmed');
      await tester.ensureVisible(unconfirmed);
      await settle(tester);
      final focus = Focus.of(
        tester.element(
          find.descendant(of: unconfirmed, matching: find.byType(Text)).first,
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('1 receipt'), findsOneWidget);
      expect(
        find.byKey(ValueKey('backup-receipt-${recent.sha256}')),
        findsNothing,
      );
      expect(find.text(latestText), findsOneWidget);
      expect(f.container.read(backupProvider).phase, BackupPhase.idle);
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await settle(tester);
      await tester.ensureVisible(find.text('1 receipt'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await capture(tester, key, '${mode.name}-unconfirmed-narrow');
      await tester.ensureVisible(find.text('Unconfirmed'));
      await settle(tester);
      await capture(tester, key, '${mode.name}-filters-narrow');
      // Updating the same receipt retains the filter and immediately removes it.
      await runIo(
        tester,
        () => f.store.writeSetting(
          BackupHistory.settingKey,
          BackupHistory.encode([old, recent]),
        ),
      );
      await waitForText(
        tester,
        'No receipts match. Choose All to see the retained history.',
      );
      await tap(tester, 'All');
      expect(find.text('2 receipts'), findsOneWidget);
    });
  }

  appTest('refresh and errors hide retained receipt details', (tester) async {
    final f = await launch(tester);
    final streams = <StreamController<List<BackupReceipt>>>[];
    final scoped = ProviderContainer(
      parent: f.container,
      overrides: [
        backupHistoryProvider.overrideWith((ref) {
          final stream = StreamController<List<BackupReceipt>>();
          streams.add(stream);
          ref.onDispose(stream.close);
          return stream.stream;
        }),
      ],
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scoped, child: const VitalApp()),
    );
    scoped.read(routerProvider).go('/backup');
    await waitForText(tester, 'Loading backup history.');
    final saved = row(f.store.generation, 1, save: DateTime.utc(2026, 10, 21));
    streams.last.add([saved]);
    await waitForText(tester, 'Last save');
    await openHistory(tester);
    expect(find.textContaining('SHA-256:'), findsOneWidget);
    scoped.invalidate(backupHistoryProvider);
    await settle(tester);
    expect(find.text('Loading backup history.'), findsOneWidget);
    expect(find.textContaining('SHA-256:'), findsNothing);
    expect(find.textContaining('Save confirmed:'), findsNothing);
    streams.last.addError(StateError('synthetic read failure'));
    await waitForText(
      tester,
      'Backup history could not be loaded. Retry to check it.',
    );
    expect(
      find.text('No confirmed save in the retained history.'),
      findsNothing,
    );
    await tap(tester, 'Retry');
    streams.last.add([saved]);
    await waitForText(tester, 'Last save');
    expect(find.byType(BackupHistoryPanel), findsOneWidget);
  });
}
