import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Size;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/privacy.dart';
import 'package:true_grit_vital/domain/privacy/diagnostics.dart';
import 'package:true_grit_vital/domain/privacy/settings_capabilities.dart';
import 'package:true_grit_vital/features/settings/settings_widgets.dart';

import '../vital_app_test.dart' show appTest, launch, runIo, tap;

const _mit = 'MIT License\n\nPermission is hereby granted.';

Future<String> _syntheticLicences(String asset) async => switch (asset) {
  applicationLicenceAsset => _mit,
  adoptedNoticesAsset =>
    '===== alpha 1.0: LICENSE =====\nMIT text for alpha\n'
        '===== beta 2.0: NOTICE =====\nApache text for beta\n',
  _ => throw StateError('unexpected_asset'),
};

void main() {
  appTest('Settings is the shell inventory for implemented sections only', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, 'Settings');
    expect(find.text('Appearance, privacy, records and help.'), findsOneWidget);
    for (final label in [
      'Profile',
      'Privacy',
      'Appearance',
      'Reminders',
      'Diagnostics',
      'Help',
      'Licences',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    for (final label in ['Reports', 'Exports', 'Backup', 'Restore']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  appTest('settings survives narrow large text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester);
    await tap(tester, 'Settings');
    expect(find.text('Appearance, privacy, records and help.'), findsOneWidget);
    await tester.ensureVisible(find.text('Licences'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tap(tester, 'Privacy');
    expect(find.text('Privacy'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  appTest('dependent data rows appear only with a real configured route', (
    tester,
  ) async {
    await launch(
      tester,
      settingsCapabilities: const SettingsCapabilities(
        reportsPath: '/reports',
        exportsPath: '/exports',
        backupPath: '/backup',
        restorePath: '/restore',
      ),
    );
    await tap(tester, 'Settings');
    for (final label in ['Reports', 'Exports', 'Backup', 'Restore']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  appTest('display persistence failure is surfaced with a route back', (
    tester,
  ) async {
    await launch(
      tester,
      appearanceWriter: (_) async =>
          throw StateError('synthetic_write_failure'),
    );
    await tap(tester, 'Settings');
    expect(
      find.text(
        'Some display changes were not saved. Try again in Appearance.',
      ),
      findsNothing,
    );
    await tap(tester, 'Appearance');
    await tap(tester, 'Light');
    await tap(tester, 'Back');
    expect(
      find.text(
        'Some display changes were not saved. Try again in Appearance.',
      ),
      findsOneWidget,
    );
  });

  appTest('Help explains recovery, privacy and catalogue source limits', (
    tester,
  ) async {
    await launch(tester, licenceLoader: _syntheticLicences);
    await tap(tester, 'Settings');
    await tap(tester, 'Help');
    expect(
      find.text(
        'If Vital cannot open your records, it never starts an empty replacement. Unlock your device and retry.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Vital has no accounts, ads or analytics. Your records stay here unless you save or share a copy.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Anyone who can unlock Vital on this device can see your records.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('No catalogue is installed. Custom items are still available.'),
      findsOneWidget,
    );
    expect(
      find.text('Copies you share are outside Vital’s control.'),
      findsOneWidget,
    );
  });

  appTest('bundled notices open readable licence text', (tester) async {
    await launch(tester, licenceLoader: _syntheticLicences);
    await tap(tester, 'Settings');
    await tap(tester, 'Licences');
    expect(find.text('alpha 1.0: LICENSE'), findsOneWidget);
    expect(find.text('beta 2.0: NOTICE'), findsOneWidget);
    await tap(tester, 'alpha 1.0: LICENSE');
    expect(find.text('MIT text for alpha'), findsOneWidget);
    await tap(tester, 'Back');
    await tap(tester, 'Vital licence');
    expect(
      find.textContaining('Permission is hereby granted.'),
      findsOneWidget,
    );
  });

  appTest('diagnostics list, clear and clear failure are truthful', (
    tester,
  ) async {
    final f = await launch(tester);
    await tap(tester, 'Settings');
    await tap(tester, 'Diagnostics');
    expect(find.text('No recent issues.'), findsOneWidget);

    final log = await runIo(
      tester,
      () => f.container.read(diagnosticLogProvider.future),
    );
    await runIo(
      tester,
      () => log!.record(
        DiagnosticCode.profileDelete,
        platform: DiagnosticPlatform.linux,
        at: DateTime.utc(2026, 10, 20, 12),
      ),
    );
    f.container.invalidate(diagnosticEventsProvider);
    await tap(tester, 'Back');
    await tap(tester, 'Diagnostics');
    expect(find.text('Delete failed'), findsOneWidget);
    expect(
      find.text(
        'Nothing is sent automatically. This build has no diagnostic uploader.',
      ),
      findsOneWidget,
    );

    await tap(tester, 'Clear');
    expect(find.text('Diagnostics cleared.'), findsOneWidget);
    expect(find.text('No recent issues.'), findsOneWidget);

    await runIo(tester, () async {
      await log!.record(
        DiagnosticCode.dataLoad,
        platform: DiagnosticPlatform.linux,
      );
      f.store.suspendWrites(true);
    });
    f.container.invalidate(diagnosticEventsProvider);
    await tap(tester, 'Back');
    await tap(tester, 'Diagnostics');
    await tap(tester, 'Clear');
    expect(find.text('Not cleared. Try again.'), findsOneWidget);
    await runIo(tester, () async => f.store.suspendWrites(false));
  });

  testWidgets('settings navigation row is one accessible command', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var activations = 0;
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: SettingsNavigationRow(
            label: 'Privacy',
            description: 'Archive, delete or review copies.',
            onPressed: () => activations++,
          ),
        ),
      ),
    );
    final target = find.bySemanticsLabel('Privacy');
    expect(target, findsOneWidget);
    final node = tester.getSemantics(target);
    expect(node.getSemanticsData().flagsCollection.isButton, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 1);
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        nodeId: node.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(activations, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(activations, 3);
    semantics.dispose();
  });
}
