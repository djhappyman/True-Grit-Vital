import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/daily_feed.dart';
import 'package:true_grit_vital/features/recording/quick_record_sheet.dart';
import 'package:true_grit_vital/features/substances/stitch_substance_card.dart';
import 'package:true_grit_vital/features/substances/substance_summary_providers.dart';

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captureDirectory = String.fromEnvironment('VITAL_STITCH_CAPTURES');
const zone = 'Europe/London';

Future<void> seedReference(WidgetTester tester, RecordStore store) async {
  final today = DisplayTime().instant(DateTime.now().toUtc(), zone).civilDate;
  final specs = [
    ('Telmisartan', 'Oral Tablet', '40', 'Prescription', WallTime(12, 30)),
    ('Vitamin D3 + K2', 'Softgel', '25', 'Supplement', WallTime(12, 30)),
    ('Omega-3 EPA/DHA', 'Marine Oil', '2000', 'Supplement', WallTime(12, 30)),
    (
      'Magnesium Glycinate',
      'Veggie Capsule',
      '400',
      'Supplement',
      WallTime(21, 0),
    ),
    ('Zinc Picolinate', 'Capsule', '22', 'Supplement', WallTime(8, 0)),
    ('Creatine Monohydrate', 'Powder', '5000', 'Supplement', WallTime(8, 0)),
    ('Ibuprofen', 'Coated Tablet', '200', 'As needed', null),
  ];
  await runIo(tester, () async {
    for (final (index, spec) in specs.indexed) {
      final (name, form, amount, type, time) = spec;
      final item = await store.createItem(
        commandId: 'stitch-item-$index',
        expectedPersonRevision: 2,
        name: name,
        form: form,
        unit: 'mg',
        type: type,
      );
      final timing = time == null
          ? const AsNeeded()
          : DailySlots([
              DailySlot(
                id: 'slot',
                time: time,
                amount: PlannedAmount(
                  quantity: ExactQuantity.parse(amount),
                  unit: 'mg',
                ),
                reminderEnabled: false,
              ),
            ]);
      await store.saveDailyPlan(
        commandId: 'stitch-plan-$index',
        expectedPersonRevision: 2,
        expectedGeneration: store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'stitch-plan-$index',
          itemId: item.id,
          versionId: 'stitch-version-$index',
          start: today.addDays(-1),
          timing: timing,
          zoneBasis: FixedHome(zone),
        ),
      );
      await store.createStockContainer(
        commandId: 'stitch-stock-$index',
        personId: meId,
        expectedPersonRevision: 2,
        expectedGeneration: store.generation,
        itemId: item.id,
        label: '$name supply',
        unit: 'mg',
        strength: LabelledStrength(ingredientId: item.id, label: '$amount mg'),
        opening: ExactAmount.parseEntry(
          ['120', '1350', '76000', '8800', '990', '50000', '3600'][index],
        ),
        lowThreshold: index == 0 ? ExactAmount.parseEntry('160') : null,
        refillEnabled: index == 0,
      );
    }
    final rows = await store.dailyRows(
      scope: const FeedScope.me(),
      from: today,
      toExclusive: today.addDays(1),
      observedZone: zone,
    );
    for (final row in rows.rows.where(
      (r) => ['Zinc Picolinate', 'Creatine Monohydrate'].contains(r.itemName),
    )) {
      await store.actDaily(
        commandId: 'stitch-record-${row.itemName}',
        row: row,
        kind: DailyActionKind.taken,
        actualAt: DailyResolver().clock
            .candidates(today, WallTime(7, 45), zone)
            .first,
      );
    }
  });
  await settle(tester);
}

DateTime referenceNow() {
  final today = DisplayTime().instant(DateTime.now().toUtc(), zone).civilDate;
  return DailyResolver().clock
      .candidates(today, WallTime(11, 55), zone)
      .first
      .add(const Duration(milliseconds: 500));
}

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
    appTest(
      'Stitch screens have loaded records, real fonts and safe areas in ${theme.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
        addTearDown(tester.view.reset);
        final f = await launch(tester, todayClock: referenceNow);
        await seedReference(tester, f.store);
        f.container.read(appearanceProvider.notifier).setMode(theme);
        await runIo(
          tester,
          () => f.container
              .read(displayPreferencesProvider.notifier)
              .setTimeFormat(TimeFormat.h12),
        );
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
          ),
        );
        await settle(tester);
        for (final screen in ['today', 'substances']) {
          f.container.read(routerProvider).go('/$screen');
          await settle(tester);
          expect(tester.takeException(), isNull);
          if (screen == 'today') {
            expect(find.text('SCHEDULE'), findsOneWidget);
            final rows = tester.widgetList<DailyRowCard>(
              find.byType(DailyRowCard),
            );
            expect(rows, isNotEmpty);
            expect(
              rows.every(
                (row) => row.presentation == DailyCardPresentation.timeline,
              ),
              isTrue,
            );
            expect(
              rows.map((row) => row.row.itemName).toSet().length,
              rows.length,
            );
          } else {
            await waitForText(tester, 'Magnesium Glycinate');
            await runIo(tester, () async {
              for (final item in await f.store.items()) {
                final anchor = (personId: meId, itemId: item.id);
                await f.container.read(summaryPlansProvider(anchor).future);
                await f.container.read(summaryStockProvider(anchor).future);
              }
            });
            await settle(tester);
            expect(find.byType(StitchSubstanceCard), findsNWidgets(7));
            expect(find.text('All (7)'), findsOneWidget);
          }
          await capture(tester, boundaryKey, '${theme.name}-$screen');
          if (captureDirectory.isNotEmpty) {
            final content =
                tester
                    .getSize(
                      find.byKey(const ValueKey('stitch-scroll-content')),
                    )
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
            await capture(tester, boundaryKey, '${theme.name}-$screen-full');
            tester.view.physicalSize = const Size(390, 844);
            await settle(tester);
          }
        }
      },
    );
  }

  appTest(
    'Stitch timeline retains durable Taken and Undo, and opening quick entry saves no doses',
    (tester) async {
      final f = await launch(tester, todayClock: referenceNow);
      await seedReference(tester, f.store);
      final before = (await runIo(tester, () => f.store.records()))!.length;
      final pending = find
          .byWidgetPredicate(
            (w) =>
                w is DailyRowCard &&
                w.presentation == DailyCardPresentation.timeline &&
                !w.row.isResolved,
          )
          .first;
      final name = tester.widget<DailyRowCard>(pending).row.itemName;
      await tap(tester, name);
      final primary = find.descendant(
        of: pending,
        matching: find.widgetWithText(Button, 'Taken'),
      );
      expect(tester.widget<Button>(primary).onPressed, isNotNull);
      await tester.ensureVisible(primary);
      await settle(tester);
      await tester.tap(primary);
      await settle(tester);
      final recorded = (await runIo(tester, () => f.store.records()))!;
      expect(recorded.length, before + 1);
      final taken = recorded.singleWhere((r) => r.name == name && !r.isVoided);
      final row = find.byWidgetPredicate(
        (w) =>
            w is DailyRowCard &&
            w.presentation == DailyCardPresentation.timeline &&
            w.row.itemName == name,
      );
      final undo = find.descendant(
        of: row,
        matching: find.widgetWithText(Button, 'Undo'),
      );
      final wait = Stopwatch()..start();
      while (undo.evaluate().isEmpty &&
          wait.elapsed < const Duration(seconds: 10)) {
        await settle(tester);
      }
      await tester.ensureVisible(undo);
      await settle(tester);
      await tester.tap(undo);
      await settle(tester);
      var undone = (await runIo<UseRecord?>(
        tester,
        () => f.store.recordById(taken.id),
      ))!;
      final deadline = Stopwatch()..start();
      while (!undone.isVoided &&
          deadline.elapsed < const Duration(seconds: 8)) {
        await settle(tester);
        undone = (await runIo<UseRecord?>(
          tester,
          () => f.store.recordById(taken.id),
        ))!;
      }
      expect(
        undone.isVoided,
        isTrue,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .join(' | '),
      );
      expect(undone.id, taken.id);
      await tap(tester, 'Add');
      expect(find.byType(QuickRecordSheet), findsOneWidget);
      f.container.read(routerProvider).pop();
      await settle(tester);
      expect(
        (await runIo(
          tester,
          () => f.store.records(),
        ))!.where((r) => !r.isVoided).length,
        before,
      );
    },
  );

  appTest('Stitch screens preserve full names at 320px and double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester, todayClock: referenceNow);
    await seedReference(tester, f.store);
    expect(tester.takeException(), isNull);
    f.container.read(routerProvider).go('/substances');
    await settle(tester);
    await waitForText(tester, 'Magnesium Glycinate');
    expect(find.text('Magnesium Glycinate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
