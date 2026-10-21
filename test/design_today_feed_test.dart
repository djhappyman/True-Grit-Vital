import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/daily_feed.dart';
import 'package:true_grit_vital/features/plans/today_hero.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart' show appTest, runIo, settle, waitForText;

const _zone = 'Europe/London';

Future<(RecordStore, ProviderContainer, SubstanceItem)> launchToday(
  WidgetTester tester, {
  required List<DailyTiming> timings,
  required DateTime Function() todayNow,
}) async {
  final items = <SubstanceItem>[];
  final directory = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-today-'),
  ))!;
  final store = (await runIo(tester, () async {
    final s = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    await s.editProfile(
      commandId: 'setup',
      personId: meId,
      expectedRevision: 1,
      name: 'Main Adult',
      adultConfirmed: true,
    );
    await s.saveBrowsingScope(const FeedScope.me());
    return s;
  }))!;
  // Several covered days keep today's envelope full at every real run time.
  final day = DisplayTime().instant(DateTime.now().toUtc(), _zone).civilDate;
  final from = day.addDays(-2), until = day.addDays(3);
  for (final (index, timing) in timings.indexed) {
    final revision = (await runIo(
      tester,
      () => store.profileById(meId),
    ))!.revision;
    final planItem = (await runIo(
      tester,
      () => store.createItem(
        commandId: 'item-$index',
        personId: meId,
        expectedPersonRevision: revision,
        name: 'Synthetic full substance name $index',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    items.add(planItem);
    await runIo(
      tester,
      () => store.saveDailyPlan(
        commandId: 'plan-$index',
        plan: DailyPlanVersion(
          personId: meId,
          planId: newCommandId(),
          itemId: planItem.id,
          versionId: newCommandId(),
          start: from,
          endExclusive: until,
          timing: timing,
          zoneBasis: FixedHome(_zone),
        ),
        expectedPersonRevision: revision,
        expectedGeneration: store.generation,
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() async => store),
      appAuthGatewayProvider.overrideWithValue(FakeAuth()),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId(_zone)),
      ),
      todayNowProvider.overrideWithValue(todayNow),
      artifactTransferGatewayProvider.overrideWithValue(
        const UnsupportedArtifactTransfer(),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  container.read(routerProvider).go('/today');
  await settle(tester);
  return (store, container, items.first);
}

PlannedAmount _oneMg() => PlannedAmount(
  quantity: ExactQuantity.parse('1'),
  enteredText: '1',
  unit: 'mg',
);

Future<void> tap(WidgetTester tester, String text) =>
    tapFinder(tester, find.text(text).last);

Future<void> tapFinder(WidgetTester tester, Finder target) async {
  await settle(tester);
  for (var attempt = 0; attempt < 3; attempt++) {
    await tester.ensureVisible(target);
    await settle(tester);
    if (target.hitTestable().evaluate().isNotEmpty) break;
  }
  await tester.tap(target);
  await settle(tester);
}

void main() {
  appTest(
    'count plans keep taken and skipped separate with truthful day sums',
    (tester) async {
      final (store, container, item) = await launchToday(
        tester,
        timings: [DailyCount(2, _oneMg())],
        todayNow: () => DateTime.now().toUtc(),
      );
      expect(find.text('Today’s sequence'), findsOneWidget);
      expect(find.text('0 of 2 doses recorded, 0 skipped.'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      // A pending untimed expectation never offers a countdown or guess.
      expect(find.text('Anytime'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('Upcoming'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DailyRowCard &&
              w.presentation == DailyCardPresentation.timeline,
        ),
        findsOneWidget,
      );
      final rowState = tester.state(
        find
            .byWidgetPredicate(
              (w) =>
                  w is DailyRowCard &&
                  w.presentation == DailyCardPresentation.timeline,
            )
            .first,
      );
      await tap(tester, 'Taken');
      await waitForText(tester, '1 recorded, 0 skipped, 2 planned');
      expect(find.text('1 of 2 doses recorded, 0 skipped.'), findsOneWidget);
      // The planned row keeps its element identity across recording.
      expect(
        tester.state(
          find
              .byWidgetPredicate(
                (w) =>
                    w is DailyRowCard &&
                    w.presentation == DailyCardPresentation.timeline,
              )
              .first,
        ),
        same(rowState),
      );
      await tap(tester, 'Skip');
      await waitForText(tester, '1 recorded, 1 skipped, 2 planned');
      expect(find.text('1 of 2 doses recorded, 1 skipped.'), findsOneWidget);
      // Skips resolve an expectation; the hero stops advertising pending work.
      expect(find.text('The next dose has no expected time.'), findsNothing);
      expect(find.text('2 remaining'), findsNothing);
      final undoButton = find
          .descendant(
            of: find.byType(DailyRowCard),
            matching: find.text('Undo'),
          )
          .last;
      await tapFinder(tester, undoButton);
      await settle(tester);
      await waitForText(tester, '1 recorded, 0 skipped, 2 planned');
      final records = (await runIo(tester, () => store.records()))!;
      expect(records, hasLength(1));
      expect(records.single.enteredAmount, '1');
      expect(records.single.itemId, item.id);
      expect(records.single.personId, meId);
    },
  );

  appTest('slot plans group under the expected wall time with a countdown', (
    tester,
  ) async {
    // Fake the hero clock on the real shown date: 09:00 London against a
    // planned 09:30 slot keeps the countdown honest at any real run time.
    final shownDate = DisplayTime()
        .instant(DateTime.now().toUtc(), _zone)
        .civilDate;
    final fakedNow = DailyResolver().clock
        .candidates(shownDate, WallTime(9, 0), _zone)
        .first
        .add(const Duration(milliseconds: 500));
    final (store, container, item) = await launchToday(
      tester,
      timings: [
        DailySlots([
          DailySlot(
            id: 'morning',
            time: WallTime(9, 30),
            amount: _oneMg(),
            reminderEnabled: false,
          ),
        ]),
      ],
      todayNow: () => fakedNow,
    );
    expect(find.text('Today’s sequence'), findsOneWidget);
    expect(find.text('0 of 1 doses recorded, 0 skipped.'), findsOneWidget);
    // The group title uses the plan zone's shown wall time. The full app keeps
    // the 12/24-hour system preference, so both renderings stay valid here.
    final group =
        find.text('9:30 AM').evaluate().isNotEmpty ||
        find.text('09:30').evaluate().isNotEmpty;
    expect(group, isTrue);
    expect(find.text('Synthetic full substance name 0'), findsWidgets);
    expect(find.text('Next dose in 30 minutes.'), findsOneWidget);
    expect(find.text('Due'), findsNothing);
    expect(find.text('Upcoming'), findsNothing);
    // Recording resolves the slot row inside its group.
    await tap(tester, 'Taken');
    await settle(tester);
    await waitForText(tester, '1 of 1 doses recorded, 0 skipped.');
    final plans = (await runIo(
      tester,
      () => store.dailyPlans(itemId: item.id),
    ))!;
    expect(plans, hasLength(1));
  });

  appTest('as needed plans show entry points without planned-dose claims', (
    tester,
  ) async {
    await launchToday(
      tester,
      timings: [const AsNeeded()],
      todayNow: () => DateTime.now().toUtc(),
    );
    expect(find.text('No doses are planned today.'), findsOneWidget);
    // No scheduled rows and no plan-completion framing for a PRN-only day.
    expect(find.text('Due'), findsNothing);
    expect(find.byType(DailyRowCard), findsNothing);
    expect(find.text('As needed'), findsOneWidget);
    expect(find.text('Synthetic full substance name 0'), findsOneWidget);
    final chip = find.text('Synthetic full substance name 0');
    await tester.ensureVisible(chip);
    await settle(tester);
    await tester.tap(chip);
    await settle(tester);
    expect(find.byType(TextField), findsWidgets);
  });

  appTest(
    'compact day rows surface quick actions and hold management behind Details',
    (tester) async {
      await launchToday(
        tester,
        timings: [DailyCount(2, _oneMg())],
        todayNow: () => DateTime.now().toUtc(),
      );
      final card = find.byWidgetPredicate(
        (w) =>
            w is DailyRowCard && w.presentation == DailyCardPresentation.hero,
      );
      expect(card, findsOneWidget);
      // The compact reference row keeps the logging pair and the stock source
      // reachable immediately; advanced management stays disclosed.
      expect(
        find.descendant(of: card, matching: find.text('Taken')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Skip')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Source')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Undo')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Extra')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Edit')),
        findsNothing,
      );
      await tester.tap(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Details',
          ),
        ),
      );
      await settle(tester);
      expect(
        find.descendant(of: card, matching: find.text('Extra')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Edit')),
        findsOneWidget,
      );
      // Recording still works directly from the undetailed card.
      await tap(tester, 'Taken');
      await waitForText(tester, '1 recorded, 0 skipped, 2 planned');
      expect(
        find.descendant(of: card, matching: find.text('Undo')),
        findsOneWidget,
      );
      expect(find.textContaining('1 of 2 doses recorded'), findsOneWidget);
    },
  );

  appTest('narrow large-text Today keeps hero, groups and actions reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await launchToday(
      tester,
      timings: [
        DailySlots([
          DailySlot(
            id: 'morning',
            time: WallTime(9, 30),
            amount: _oneMg(),
            reminderEnabled: false,
          ),
        ]),
        DailyCount(2, _oneMg()),
      ],
      todayNow: () => DateTime.now().toUtc(),
    );
    expect(find.text('Today’s sequence'), findsOneWidget);
    expect(find.text('0 of 3 doses recorded, 0 skipped.'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is DailyRowCard &&
            w.presentation == DailyCardPresentation.timeline,
      ),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });
}
