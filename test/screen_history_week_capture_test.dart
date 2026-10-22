import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart' show StitchButton;

import 'history_mobile_ui_test.dart' show historyItem, historyRecord, today;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

const captureDirectory = String.fromEnvironment('VITAL_HISTORY_WEEK_CAPTURE');

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

Future<void> skipDay(
  RecordStore store,
  SubstanceItem item,
  CivilDate day,
) async {
  await store.saveDailyPlan(
    commandId: newCommandId(),
    plan: DailyPlanVersion(
      personId: meId,
      planId: 'week-plan-$day',
      itemId: item.id,
      versionId: 'v1',
      start: day,
      timing: DailyCount(
        1,
        PlannedAmount(
          quantity: ExactQuantity.parse('1'),
          enteredText: '1',
          unit: 'mg',
        ),
      ),
      zoneBasis: FixedHome('Europe/London'),
    ),
    expectedPersonRevision: 2,
    expectedGeneration: store.generation,
  );
  final rows = await store.dailyRows(
    from: day,
    toExclusive: day.addDays(1),
    observedZone: 'Europe/London',
  );
  await store.actDaily(
    commandId: newCommandId(),
    row: rows.rows.single,
    kind: DailyActionKind.skip,
  );
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
    appTest('History selected week renders with real fonts in ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final f = await launch(tester);
      final item = (await runIo(
        tester,
        () => historyItem(f.store, 'Synthetic week medicine'),
      ))!;
      final day = today();
      await runIo(tester, () async {
        for (var i = 0; i < 3; i++) {
          await historyRecord(f.store, item, day);
        }
        await historyRecord(f.store, item, day.addDays(-1), amount: '2');
        final voided = await historyRecord(
          f.store,
          item,
          day.addDays(-2),
          amount: '1.5',
        );
        await f.store.voidRecord(
          commandId: newCommandId(),
          recordId: voided.id,
          expectedRevision: 1,
          expectedPersonRevision: 2,
        );
        await skipDay(f.store, item, day.addDays(-3));
      });
      f.container.read(appearanceProvider.notifier).setMode(theme);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      await waitForText(tester, 'Selected week');
      await waitForText(tester, 'Synthetic week medicine');
      final summary = find.byKey(const ValueKey('history-week-summary'));
      await tester.ensureVisible(summary);
      await settle(tester);
      expect(summary, findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, boundaryKey, '${theme.name}-history-week');

      if (theme == ThemeMode.dark) {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.view.physicalSize = const Size(320, 740);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await settle(tester);
        final dateHeading = find.descendant(
          of: find.byType(HistoryPage),
          matching: find.textContaining(
            RegExp(
              r'^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), ',
            ),
          ),
        );
        final todayAction = find.descendant(
          of: find.byType(HistoryPage),
          matching: find.widgetWithText(StitchButton, 'Today'),
        );
        expect(
          tester.getRect(todayAction).top,
          greaterThanOrEqualTo(tester.getRect(dateHeading).bottom),
        );
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(HistoryPage),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      widget.axisDirection == AxisDirection.down,
                ),
              )
              .first,
        );
        final content =
            scrollable.position.viewportDimension +
            scrollable.position.maxScrollExtent;
        tester.view.physicalSize = Size(320, (content + 40).ceilToDouble());
        await settle(tester);
        await tester.ensureVisible(summary);
        await settle(tester);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          boundaryKey,
          'dark-history-week-narrow-double-text',
        );
      }
    });
  }
}
