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
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/schedule_screen.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

const captureDirectory = String.fromEnvironment('VITAL_SCHEDULE_CAPTURES');

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (captureDirectory.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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

DailySlots _slots() => DailySlots([
  DailySlot(
    id: newCommandId(),
    time: WallTime(8, 0),
    amount: PlannedAmount(
      quantity: ExactQuantity.parse('1'),
      unit: 'mg',
      enteredText: '1',
    ),
    reminderEnabled: true,
  ),
  DailySlot(
    id: newCommandId(),
    time: WallTime(20, 0),
    amount: PlannedAmount(
      quantity: ExactQuantity.parse('1'),
      unit: 'mg',
      enteredText: '1',
    ),
    reminderEnabled: false,
  ),
]);

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
    appTest('schedule renders loaded light and dark composition', (
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
        () => f.store.createItem(
          commandId: newCommandId(),
          expectedPersonRevision: 2,
          name: 'Telmisartan',
          form: 'Tablet',
          unit: 'mg',
          type: 'Medicine',
        ),
      ))!;
      final saved = (await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: newCommandId(),
          expectedPersonRevision: 2,
          expectedGeneration: f.store.generation,
          plan: DailyPlanVersion(
            personId: meId,
            planId: newCommandId(),
            itemId: item.id,
            versionId: newCommandId(),
            start: CivilDate.fromDateTime(DateTime.now()),
            timing: _slots(),
            zoneBasis: const FollowingLocal(),
            calendar: const EveryDay(),
          ),
        ),
      ))!;
      f.container.read(appearanceProvider.notifier).setMode(theme);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: key, child: const VitalApp()),
        ),
      );
      await settle(tester);
      f.container
          .read(routerProvider)
          .go('/schedule/${item.id}?plan=${saved.plan.planId}');
      await waitForText(tester, 'RECURRENCE');
      expect(find.text('Telmisartan'), findsOneWidget);
      expect(find.byType(ScheduleChoiceChip), findsNWidgets(8));
      await capture(tester, key, '${theme.name}-schedule');
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
      await capture(tester, key, '${theme.name}-schedule-full');
      expect(tester.takeException(), isNull);
    });
  }
}
