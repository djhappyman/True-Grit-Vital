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

  appTest('settings sections expose every real destination', (tester) async {
    await launch(tester);
    await tap(tester, 'Settings');
    await waitForText(tester, 'On this device');
    for (final name in [
      'Profile',
      'Appearance',
      'Reminders',
      'Help',
      'Licences',
    ]) {
      expect(find.text(name), findsWidgets);
    }
    await tester.tap(segment('Privacy'));
    await settle(tester);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Your name and report details.'), findsNothing);
    await tester.tap(segment('Data'));
    await settle(tester);
    for (final name in ['Reports', 'Exports', 'Backup', 'Restore']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.byType(SettingsPreviewRow), findsNothing);
  });

  appTest('settings invents no metrics and advertises no unfinished feature', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, 'Settings');
    for (final group in ['General', 'Privacy', 'Data']) {
      await tester.tap(segment(group));
      await settle(tester);
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
        'Automatic backups',
        'FHIR export',
      ]) {
        expect(find.textContaining(claim), findsNothing, reason: claim);
      }
      expect(find.byType(SettingsPreviewRow), findsNothing);
    }
  });

  appTest('settings pages preserve one group with swipe and tab alternatives', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, 'Settings');
    await tester.tap(segment('Privacy'));
    await settle(tester);
    expect(find.text('Recent local error codes.'), findsOneWidget);
    await tester.tap(segment('Data'));
    await settle(tester);
    expect(find.text('Review your substance reports.'), findsOneWidget);
    expect(find.text('Recent local error codes.'), findsNothing);
    await tester.tap(segment('General'));
    await settle(tester);
    expect(find.text('Your name and report details.'), findsOneWidget);
    expect(find.text('Review your substance reports.'), findsNothing);
    expect(find.text('All'), findsNothing);
  });

  appTest('settings rows still open their real capability routes', (
    tester,
  ) async {
    final f = await launch(tester);
    for (final (group, label, path) in [
      ('General', 'Profile', '/profile'),
      ('Privacy', 'Privacy', '/settings/privacy'),
      ('Privacy', 'Diagnostics', '/settings/diagnostics'),
      ('General', 'Help', '/settings/help'),
      ('General', 'Licences', '/settings/licences'),
      ('Data', 'Reports', '/reports'),
      ('Data', 'Exports', '/exports'),
      ('Data', 'Backup', '/backup'),
      ('Data', 'Restore', '/restore'),
      ('General', 'Reminders', '/reminders'),
      ('General', 'Appearance', '/appearance'),
    ]) {
      f.container.read(routerProvider).go('/settings');
      await settle(tester);
      await tester.tap(segment(group));
      await settle(tester);
      final row = find.widgetWithText(SettingsNavigationRow, label);
      await tester.ensureVisible(row);
      await settle(tester);
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Button)).last,
      );
      await settle(tester);
      expect(await pathOf(tester, f.container), path, reason: label);
    }
  });

  appTest('settings peer pages fit narrow double text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester);
    await tap(tester, 'Settings');
    for (final width in [320.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 740);
      for (final group in ['General', 'Privacy', 'Data']) {
        await tester.tap(segment(group));
        await settle(tester);
        expect(tester.takeException(), isNull);
      }
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
