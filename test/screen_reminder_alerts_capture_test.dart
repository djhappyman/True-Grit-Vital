import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/reminder_gateway.dart';
import 'package:true_grit_vital/app/vital_app.dart';

import 'reminders/reminder_ui_test.dart' show UiGateway, launch;
import 'vital_app_test.dart' show appTest, settle, waitForText;

const captureDirectory = String.fromEnvironment(
  'VITAL_SCREEN_REMINDER_ALERTS_CAPTURE',
);

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  if (captureDirectory.isEmpty) return;
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
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
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('reminder alert options render with real fonts in ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final fixture = await launch(tester);
      final gateway =
          fixture.container.read(reminderGatewayProvider) as UiGateway;
      final appliedStop = DateTime.now().add(const Duration(seconds: 10));
      while (gateway.appliedAlerts.isEmpty) {
        if (DateTime.now().isAfter(appliedStop)) {
          fail('The alert adapter never received the initial choice');
        }
        await settle(tester);
      }
      fixture.container.read(appearanceProvider.notifier).setMode(theme);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      fixture.container.read(routerProvider).go('/reminders');
      await settle(tester);
      await waitForText(tester, 'Reminders');
      await tester.ensureVisible(find.text('Alert options'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '${theme.name}-reminder-alerts');
      if (theme == ThemeMode.dark) {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.view.physicalSize = const Size(320, 740);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await settle(tester);
        await tester.ensureVisible(find.text('Alert options'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          boundaryKey,
          'dark-reminder-alerts-narrow-double-text',
        );
      }
    });
  }
}
