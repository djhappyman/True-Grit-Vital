import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/app/exports.dart';
import 'package:true_grit_vital/app/backup.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';
import 'package:true_grit_vital/platform/linux_storage_bootstrap.dart';

/// Native Linux shell, real encrypted SQLite and real Secret Service. The
/// runner supplies a unique disposable namespace and directory; the production
/// dataset and staging directory are never used.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native boot, encrypted persistence, navigation and export', (
    tester,
  ) async {
    const directory = String.fromEnvironment('VITAL_BOOT_DIRECTORY');
    const namespace = String.fromEnvironment('VITAL_BOOT_NAMESPACE');
    if (!Platform.isLinux ||
        !directory.startsWith('/tmp/vital-linux-boot-') ||
        !namespace.startsWith('dev.truegrit.vital.smoke.')) {
      fail(
        'Use tool/release/run_linux_boot.py with an isolated test namespace',
      );
    }
    final bootstrap = LinuxStorageBootstrap(
      dataDirectory: '$directory/records',
      secretStore: const SecretToolStore(namespace: namespace),
    );
    final location = await bootstrap.prepare();
    var store = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: location.isNew,
    );
    await bootstrap.activate(location);
    final me = (await store.profileById(meId))!;
    await store.editProfile(
      commandId: 'native-boot-adult',
      personId: meId,
      expectedRevision: me.revision,
      name: 'Synthetic adult',
      adultConfirmed: true,
    );
    final item = await store.createItem(
      commandId: 'native-boot-item',
      personId: meId,
      expectedPersonRevision: me.revision + 1,
      name: 'Synthetic substance',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    );
    await store.record(
      commandId: 'native-boot-dose',
      itemId: item.id,
      amount: '1.25',
      actualAt: DateTime.now().toUtc(),
      expectedPersonRevision: me.revision + 1,
    );
    await store.saveBrowsingScope(const FeedScope.me());
    await store.close();
    final reopened = await bootstrap.prepare();
    expect(reopened.isNew, isFalse);
    store = await RecordStore.open(
      path: reopened.path,
      key: reopened.key,
      isNew: false,
    );
    await bootstrap.activate(reopened);
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => store),
        artifactTransferGatewayProvider.overrideWithValue(
          FileArtifactTransfer(root: Directory('$directory/artifacts')),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await store.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    Future<void> waitFor(Finder finder) async {
      for (var attempt = 0; attempt < 200; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('Native boot UI did not appear: $finder');
    }

    await waitFor(find.text('True Grit: Vital'));
    await waitFor(find.text('Synthetic substance'));
    await tester.tap(find.text('Substances').last);
    await waitFor(find.text('Synthetic substance'));
    container.read(routerProvider).push('/exports');
    await waitFor(find.text('Preview'));
    await tester.ensureVisible(find.text('Preview').last);
    await tester.tap(find.text('Preview').last);
    await waitFor(find.text('Review'));
    expect(
      container
          .read(exportControllerProvider('/exports'))
          .artifact!
          .preview
          .doseRecords,
      1,
    );
    container.read(routerProvider).go('/settings');
    await waitFor(find.text('Appearance, people, privacy and help.'));
    for (final label in ['Reports', 'Exports', 'Backup', 'Restore']) {
      expect(find.text(label), findsOneWidget);
    }
    container.read(routerProvider).go('/reports?person=me');
    await waitFor(find.text('Substance summary'));
    await tester.ensureVisible(find.text('Preview').last);
    await tester.tap(find.text('Preview').last);
    await waitFor(find.text('Report preview'));
    final report = container.read(reportControllerProvider).artifact!;
    expect(report.fontsEmbedded, isTrue);
    expect(report.pageCount, greaterThanOrEqualTo(1));
    expect(report.text, contains('1.25 mg'));

    container.read(routerProvider).go('/backup');
    await waitFor(find.byKey(const ValueKey('backup-password')));
    final passwordField = find.descendant(
      of: find.byKey(const ValueKey('backup-password')),
      matching: find.byType(TextField),
    );
    final confirmationField = find.descendant(
      of: find.byKey(const ValueKey('backup-confirm')),
      matching: find.byType(TextField),
    );
    await tester.enterText(passwordField, 'synthetic native backup phrase');
    await tester.enterText(confirmationField, 'synthetic native backup phrase');
    await tester.ensureVisible(find.byKey(const ValueKey('backup-create')));
    await tester.tap(find.byKey(const ValueKey('backup-create')));
    await waitFor(find.text('Backup ready'));
    final creation = container.read(backupProvider).creation!;
    expect(creation.inventory.peopleCount, 1);
    expect(creation.inventory.recordCount, 1);
    await tester.runAsync(
      () => container.read(backupProvider.notifier).discard(),
    );
    expect(await tester.runAsync(creation.archive.exists), isFalse);
    // The real bootstrap must admit staging on a subsequent launch.
    final afterBackup = await tester.runAsync(bootstrap.prepare);
    expect(afterBackup!.isNew, isFalse);
    expect(afterBackup.path, location.path);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
