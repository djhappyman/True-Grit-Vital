import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/features/settings/settings_pages.dart';
import 'package:true_grit_vital/features/settings/settings_widgets.dart';

import 'vital_app_test.dart' show appTest, launch, settle, tap, waitForText;

const captures = String.fromEnvironment('VITAL_SETTINGS_CAPTURES');

Future<void> loadFonts() async {
  await (FontLoader('StitchSans')
        ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Medium.ttf'))
        ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-SemiBold.ttf'))
        ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Bold.ttf')))
      .load();
  await (FontLoader('NotoSans')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
      .load();
  await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
        rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
      ))
      .load();
}

/// The hub filter sits above the cards, so its option is always the first
/// match for a group name that a card heading also uses.
Finder segment(String label) => find.text(label).first;

Future<String> pathOf(WidgetTester tester, ProviderContainer container) async =>
    container.read(routerProvider).state.uri.path;

void main() {
  setUpAll(loadFonts);

  appTest('settings hub keeps every real destination reachable by default', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, 'Settings');
    await waitForText(tester, 'On this device');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance, privacy, records and help.'), findsOneWidget);
    for (final label in [
      'Profile',
      'Appearance',
      'Reminders',
      'Help',
      'Licences',
      'Privacy',
      'Diagnostics',
      'Reports',
      'Exports',
      'Backup',
      'Restore',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Local storage'), findsOneWidget);
    expect(find.byType(SettingsPreviewRow), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  appTest('settings hub invents no cipher, size or version claim', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, 'Settings');
    await waitForText(tester, 'On this device');
    for (final claim in [
      'AES',
      'GCM',
      '4.2 MB',
      '2.4.1',
      '8904',
      'SQLite Ledger',
      'Zero cloud telemetry',
      'Bypass',
      'Person:',
    ]) {
      expect(find.textContaining(claim), findsNothing, reason: claim);
    }
    expect(
      find.text('Database size and record totals are not available yet.'),
      findsOneWidget,
    );
    expect(
      find.text('Not available yet. Create a backup when you need one.'),
      findsOneWidget,
    );
    expect(
      find.text('Not available yet. Use Exports for structured data.'),
      findsOneWidget,
    );
  });

  appTest('settings hub filter shows one group and restores every group', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, 'Settings');
    await waitForText(tester, 'On this device');

    await tester.tap(segment('Privacy'));
    await settle(tester);
    expect(find.text('Archive, delete or review copies.'), findsOneWidget);
    expect(find.text('Recent local error codes.'), findsOneWidget);
    expect(find.text('Your name and report details.'), findsNothing);
    expect(find.text('Review your substance reports.'), findsNothing);

    await tester.tap(segment('Data'));
    await settle(tester);
    expect(find.text('Review your substance reports.'), findsOneWidget);
    expect(find.text('Local storage'), findsOneWidget);
    expect(find.text('Recent local error codes.'), findsNothing);

    await tester.tap(segment('General'));
    await settle(tester);
    expect(find.text('Your name and report details.'), findsOneWidget);
    expect(find.text('Review your substance reports.'), findsNothing);

    await tester.tap(segment('All'));
    await settle(tester);
    for (final label in [
      'Your name and report details.',
      'Archive, delete or review copies.',
      'Review your substance reports.',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  appTest('settings previews are labelled, not switches or commands', (
    tester,
  ) async {
    final f = await launch(tester);
    await tap(tester, 'Settings');
    await waitForText(tester, 'On this device');
    expect(find.byType(Switch), findsNothing);
    for (final label in ['Automatic backups', 'FHIR export']) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(SettingsPreviewRow),
      );
      expect(row, findsOneWidget, reason: label);
      expect(
        find.descendant(of: row, matching: find.byType(Switch)),
        findsNothing,
        reason: label,
      );
      expect(
        find.descendant(of: row, matching: find.byType(Button)),
        findsNothing,
        reason: label,
      );
      expect(
        find.descendant(of: row, matching: find.text('Preview')),
        findsOneWidget,
        reason: label,
      );
    }
    final before = await pathOf(tester, f.container);
    await tester.ensureVisible(find.text('Automatic backups'));
    await settle(tester);
    await tester.tap(find.text('Automatic backups'));
    await settle(tester);
    expect(await pathOf(tester, f.container), before);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('settings rows still open their real capability routes', (
    tester,
  ) async {
    final f = await launch(tester);
    await tap(tester, 'Settings');
    await waitForText(tester, 'On this device');
    for (final (label, path) in [
      ('Profile', '/profile'),
      ('Privacy', '/settings/privacy'),
      ('Diagnostics', '/settings/diagnostics'),
      ('Help', '/settings/help'),
      ('Licences', '/settings/licences'),
      ('Reports', '/reports'),
      ('Exports', '/exports'),
      ('Backup', '/backup'),
      ('Restore', '/restore'),
      ('Reminders', '/reminders'),
      ('Appearance', '/appearance'),
    ]) {
      await tap(tester, label);
      expect(
        await pathOf(tester, f.container),
        path,
        reason: '$label should open $path',
      );
      f.container.read(routerProvider).go('/settings');
      await settle(tester);
      await waitForText(tester, 'On this device');
    }
    expect(tester.takeException(), isNull);
  });

  appTest('settings hub grows without clipping at narrow widths and 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester);
    await tap(tester, 'Settings');
    await waitForText(tester, 'On this device');
    for (final width in [320.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 740);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$width at double text');
      expect(find.text('On this device'), findsOneWidget);
      expect(find.text('Local storage'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('FHIR export'), 300);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$width at double text');
      expect(find.text('FHIR export').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Settings'), -300);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$width at double text');
    }
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('settings hub renders loaded ${theme.name} records safely', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      f.container.read(appearanceProvider.notifier).setMode(theme);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      f.container.read(routerProvider).go('/settings');
      await settle(tester);
      await waitForText(tester, 'On this device');
      expect(tester.takeException(), isNull);
      if (captures.isEmpty) return;
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captures/${theme.name}-settings.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final content = position.maxScrollExtent + position.viewportDimension;
      final viewport = position.viewportDimension;
      tester.view.physicalSize = Size(
        390,
        (844 + math.max(0, content - viewport)).ceilToDouble(),
      );
      await settle(tester);
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captures/${theme.name}-settings-full.png');
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      tester.view.physicalSize = const Size(320, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captures/${theme.name}-settings-narrow.png');
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    });
  }
}
