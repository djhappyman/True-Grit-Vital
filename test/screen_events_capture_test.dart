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

import 'screen_events_support.dart';
import 'vital_app_test.dart' show appTest, launch, settle, waitForText;

const captureDirectory = String.fromEnvironment('VITAL_SCREEN_EVENTS_CAPTURE');

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

  for (final theme in [ThemeMode.dark, ThemeMode.light]) {
    appTest('Events reference renders with real fonts in ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
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
      await waitForText(tester, 'Telmisartan');
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '${theme.name}-events');
      if (captureDirectory.isNotEmpty) {
        final content =
            tester
                .getSize(find.byKey(const ValueKey('stitch-scroll-content')))
                .height +
            40;
        final viewport = tester
            .getSize(
              find
                  .byWidgetPredicate(
                    (w) =>
                        w is SingleChildScrollView &&
                        w.scrollDirection == Axis.vertical,
                  )
                  .first,
            )
            .height;
        tester.view.physicalSize = Size(
          390,
          (844 + math.max(0, content - viewport)).ceilToDouble(),
        );
        await settle(tester);
        await capture(tester, boundaryKey, '${theme.name}-events-full');
        tester.view.physicalSize = const Size(390, 844);
        await settle(tester);
      }
      f.container.read(routerProvider).go('/event/b-autumn');
      await settle(tester);
      await waitForText(tester, 'Autumn Immunity & Recovery Cycle');
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '${theme.name}-event-detail');
      if (captureDirectory.isNotEmpty) {
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find
                    .byWidgetPredicate(
                      (w) =>
                          w is SingleChildScrollView &&
                          w.scrollDirection == Axis.vertical,
                    )
                    .first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final viewport = scrollable.position.viewportDimension;
        final content = viewport + scrollable.position.maxScrollExtent;
        tester.view.physicalSize = Size(
          390,
          (844 + math.max(0, content - viewport)).ceilToDouble(),
        );
        await settle(tester);
        await capture(tester, boundaryKey, '${theme.name}-event-detail-full');
        tester.view.physicalSize = const Size(390, 844);
        await settle(tester);
      }
      if (theme == ThemeMode.dark) {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.view.physicalSize = const Size(320, 740);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        f.container.read(routerProvider).go('/events');
        await settle(tester);
        await waitForText(tester, 'Autumn Immunity & Recovery Cycle');
        expect(tester.takeException(), isNull);
        await capture(tester, boundaryKey, 'dark-events-narrow-double-text');
      }
    });
  }
}
