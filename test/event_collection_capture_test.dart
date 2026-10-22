import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';

import 'screen_events_support.dart';
import 'vital_app_test.dart' show appTest, launch, settle, tap, waitForText;

const captureDirectory = String.fromEnvironment(
  'VITAL_EVENT_COLLECTION_CAPTURE',
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

Future<GlobalKey> openEvents(WidgetTester tester, ThemeMode theme) async {
  final f = await launch(tester, todayClock: screenEventsNow);
  await seedScreenEvents(tester, f.store);
  f.container.read(appearanceProvider.notifier).setMode(theme);
  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: f.container,
      child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
    ),
  );
  await settle(tester);
  f.container.read(routerProvider).go('/events');
  await settle(tester);
  await waitForText(tester, 'Autumn Immunity & Recovery Cycle');
  return boundaryKey;
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

  for (final theme in [ThemeMode.dark, ThemeMode.light]) {
    appTest('Event collection overview renders in ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final boundaryKey = await openEvents(tester, theme);
      await waitForText(tester, '2 active · 1 upcoming · 1 completed');
      await waitForText(
        tester,
        'Counts and filters cover every saved event, not only this page.',
      );
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '${theme.name}-events-overview');

      await tap(tester, 'Review (0)');
      await waitForText(tester, 'No events match this filter.');
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '${theme.name}-events-review-empty');
    });
  }

  appTest('Event collection overview stays readable at 320px and double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final boundaryKey = await openEvents(tester, ThemeMode.dark);
    await waitForText(tester, '2 active · 1 upcoming · 1 completed');
    expect(tester.takeException(), isNull);
    await capture(
      tester,
      boundaryKey,
      'dark-events-overview-narrow-double-text',
    );
    // The horizontal status row stays reachable at this size; Clear is the
    // recovery action once the chosen status has no events.
    await tap(tester, 'Review (0)');
    await waitForText(tester, 'No events match this filter.');
    await Scrollable.ensureVisible(
      tester.element(find.text('No events match this filter.')),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await capture(
      tester,
      boundaryKey,
      'dark-events-review-empty-narrow-double-text',
    );
  });
}
