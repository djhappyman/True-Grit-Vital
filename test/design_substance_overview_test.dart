import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' show ImperativeRouteMatch;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/plan_providers.dart';
import 'package:true_grit_vital/features/substances/substance_overview.dart';
import 'package:true_grit_vital/platform/device_zone.dart'
    show DeviceZoneObservation;
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

/// Widget-level coverage for the substance overview route. The store fixture
/// is direct, so store mutations only need the launch set-up profile revision.
const fixtureRevision = 2;

/// Tap a shared command button identified by its visible label. The section
/// header owns the label inside a VitalButton, so a plain text finder could
/// mis-route to title or dock elements.
Future<void> tapButton(WidgetTester tester, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  final target = find
      .ancestor(of: find.text(text), matching: find.byType(VitalButton))
      .last;
  for (
    var attempt = 0;
    attempt < 3 && target.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    await tester.ensureVisible(target);
    await settle(tester);
  }
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await settle(tester);
}

/// Wait for a rendered result rather than assuming a fixed number of IO turns.
/// Fragments support the schedule vocabulary whose lines carry live values.
Future<void> waitForTextContaining(WidgetTester tester, String fragment) async {
  final elapsed = Stopwatch()..start();
  while (find.textContaining(fragment).evaluate().isEmpty) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw TestFailure('Expected rendered fragment did not appear: $fragment');
    }
    await runIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
}

/// Direct fixture launcher for the overview route. Mirrors the collection
/// launcher's store setup so a test can choose the observed device zone and
/// replace the shared next-plan feed without touching the shared helpers.
Future<({RecordStore store, ProviderContainer container})> launchOverview(
  WidgetTester tester, {
  DeviceZoneObservation? zone,
  bool fakeNextFeed = false,
  List<SavedDailyPlan> Function()? fixturePlans,
}) async {
  final dir = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-substance-overview-'),
  ))!;
  final store = (await runIo(tester, () async {
    final opened = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    await opened.editProfile(
      commandId: 'setup',
      personId: meId,
      expectedRevision: 1,
      name: 'Main Adult',
      adultConfirmed: true,
    );
    await opened.saveBrowsingScope(const FeedScope.me());
    return opened;
  }))!;
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() async => store),
      appAuthGatewayProvider.overrideWithValue(FakeAuth()),
      observedDeviceZoneProvider.overrideWith(
        (ref) =>
            Stream.value(zone ?? DeviceZoneObservation.fromId('Europe/London')),
      ),
      // Reproduction hook for the bounded shared next-plan feed.
      if (fakeNextFeed)
        nextDailyPlansProvider.overrideWith((ref, scope) async* {
          yield DailyPlanNextRows(rows: const [], complete: false);
        }),
      // Reproduction hook for a saved-plan list beyond one store routine; the
      // store keeps one plan row per item, so the 51-entry cut is unreachable
      // through real saves.
      if (fixturePlans != null)
        overviewPlansProvider.overrideWith((ref, query) async* {
          await ref.watch(recordStoreProvider.future);
          yield fixturePlans();
        }),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await runIo(tester, store.close);
    await dir.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  return (store: store, container: container);
}

Future<void> section(WidgetTester tester, String label) async {
  await waitForText(tester, 'Record');
  await settle(tester);
  final target = find.descendant(
    of: find.byType(VitalSegments<int>),
    matching: find.text(label),
  );
  await tester.tap(target.first);
  await settle(tester);
}

void main() {
  appTest('overview section jumps scroll the one canonical page', (
    tester,
  ) async {
    final f = await launchOverview(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: newCommandId(),
        expectedPersonRevision: fixtureRevision,
        name: 'Section jump item',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    final router = f.container.read(routerProvider);
    router.go('/substance/${item.id}');
    await settle(tester);
    await waitForText(tester, 'Section jump item');
    await section(tester, 'History');
    expect(router.routerDelegate.state.uri.path, '/substance/${item.id}');
    expect(find.byType(SubstanceOverviewPage), findsOneWidget);
    await section(tester, 'Overview');
    expect(find.text('Section jump item'), findsOneWidget);
  });

  appTest(
    'overview joins record, schedule, stock, history and context routes',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () async {
        final created = await f.store.createItem(
          expectedPersonRevision: fixtureRevision,
          commandId: 'overview-item',
          name: 'Synthetic overview substance',
          form: 'Tablet',
          unit: 'mg',
          type: 'Medicine',
        );
        await f.store.record(
          expectedPersonRevision: fixtureRevision,
          commandId: 'overview-one',
          itemId: created.id,
          amount: '1',
          actualAt: DateTime(2026, 10, 20, 8),
        );
        await f.store.record(
          expectedPersonRevision: fixtureRevision,
          commandId: 'overview-two',
          itemId: created.id,
          amount: '2',
          actualAt: DateTime(2026, 10, 20, 19),
        );
        await f.store.saveDailyPlan(
          commandId: 'overview-plan',
          expectedPersonRevision: fixtureRevision,
          expectedGeneration: f.store.generation,
          plan: DailyPlanVersion(
            personId: meId,
            planId: 'overview-plan',
            itemId: created.id,
            versionId: 'overview-v1',
            start: CivilDate(2026, 2, 1),
            // One timed slot keeps the plan's daily pattern on a chosen time.
            timing: DailySlots([
              DailySlot(
                id: 'morning',
                time: WallTime(8, 0),
                amount: PlannedAmount(
                  quantity: ExactQuantity.parse('1'),
                  unit: 'mg',
                ),
                reminderEnabled: false,
              ),
            ]),
            zoneBasis: const FollowingLocal(),
          ),
        );
        await f.store.createStockContainer(
          commandId: 'overview-stock',
          expectedPersonRevision: fixtureRevision,
          expectedGeneration: f.store.generation,
          personId: meId,
          itemId: created.id,
          label: 'Synthetic original container',
          unit: 'mg',
          strength: LabelledStrength(
            ingredientId: created.id,
            label: 'Not known',
          ),
          opening: ExactAmount(BigInt.from(12), BigInt.one),
        );
        return created;
      }))!;
      f.container.read(routerProvider).push('/substance/${item.id}');
      await settle(tester);
      await waitForText(tester, 'Synthetic overview substance');
      expect(find.text('Synthetic overview substance'), findsOneWidget);
      expect(find.textContaining('Tablet'), findsWidgets);
      expect(find.text('Record'), findsOneWidget);
      // The schedule study emits through this overview's own store stream.
      await section(tester, 'Schedule');
      await waitForTextContaining(tester, 'Chosen time');
      expect(find.textContaining('Chosen time'), findsOneWidget);
      await waitForTextContaining(tester, 'Starts');
      expect(find.textContaining('Starts'), findsOneWidget);
      await section(tester, 'Stock');
      await waitForText(tester, 'Synthetic original container');
      expect(find.text('12 mg'), findsOneWidget);
      expect(find.text('Synthetic original container'), findsOneWidget);
      await section(tester, 'History');
      expect(find.text('1 mg'), findsOneWidget);
      expect(find.text('2 mg'), findsOneWidget);
      expect(find.textContaining('Actual:'), findsAtLeastNWidgets(2));
      expect(find.text('No plan yet'), findsNothing);
      await tester.ensureVisible(
        find.descendant(
          of: find.byKey(const ValueKey('overview-history-review')),
          matching: find.byType(VitalButton),
        ),
      );
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('overview-history-review')),
          matching: find.byType(VitalButton),
        ),
      );
      await settle(tester);
      final config = f.container
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration;
      expect(config.last.route.path, '/item/:id');
      await tapButton(tester, 'Back');
      expect(find.byType(SubstanceOverviewPage), findsOneWidget);
      await tapButton(tester, 'Record');
      expect(find.text('Record dose'), findsOneWidget);
    },
  );

  appTest('missing substance resolves truthfully instead of actions', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(routerProvider).push('/substance/missing-target');
    await settle(tester);
    await waitForText(
      tester,
      'This substance is unavailable. Return to Substances.',
    );
    expect(find.text('Record'), findsNothing);
    await tapButton(tester, 'Back');
    expect(find.byType(SubstanceOverviewPage), findsNothing);
    await tap(tester, 'Substances');
    expect(find.byType(VitalEmptyState), findsOneWidget);
  });

  appTest('paused plan states its expectation instead of a next dose', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () async {
      final created = await f.store.createItem(
        expectedPersonRevision: fixtureRevision,
        commandId: 'paused-item',
        name: 'Synthetic paused substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      await f.store.saveDailyPlan(
        commandId: 'paused-plan',
        expectedPersonRevision: fixtureRevision,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'paused-plan',
          itemId: created.id,
          versionId: 'paused-v1',
          start: CivilDate(2026, 2, 1),
          timing: DailyCount(
            1,
            PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
          ),
          zoneBasis: const FollowingLocal(),
          pauses: [
            PlanPause(
              start: DateTime.now().toUtc().subtract(const Duration(days: 1)),
            ),
          ],
        ),
      );
      return created;
    }))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await settle(tester);
    await section(tester, 'Schedule');
    await settle(tester);
    await waitForText(tester, 'Paused');
    expect(find.text('Paused'), findsOneWidget);
    expect(find.textContaining('No next planned date'), findsNothing);
    expect(find.textContaining('Planned once a day'), findsOneWidget);
  });

  appTest('recent records stay bounded and name the full history', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () async {
      final created = await f.store.createItem(
        expectedPersonRevision: fixtureRevision,
        commandId: 'bounded-item',
        name: 'Synthetic bounded substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      for (var i = 1; i <= 21; i++) {
        await f.store.record(
          expectedPersonRevision: fixtureRevision,
          commandId: 'bounded-$i',
          itemId: created.id,
          amount: '$i',
          actualAt: DateTime(2026, 10, 20, 12).subtract(Duration(minutes: i)),
        );
      }
      return created;
    }))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await settle(tester);
    await section(tester, 'History');
    await settle(tester);
    await waitForText(tester, 'Older records stay in the full history.');
    expect(find.textContaining('Actual:'), findsNWidgets(20));
    expect(
      find.text('Older records stay in the full history.'),
      findsOneWidget,
    );
  });

  appTest('back from overview keeps the originating list state', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: fixtureRevision,
        commandId: 'origin-item',
        name: 'Synthetic originating substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    f.container.read(routerProvider).go('/substances');
    await settle(tester);
    await waitForText(tester, 'Synthetic originating substance');
    f.container.read(routerProvider).push('/substance/${item.id}');
    await settle(tester);
    await waitForText(tester, 'Record');
    await tapButton(tester, 'Back');
    expect(find.byType(SubstanceOverviewPage), findsNothing);
    await waitForText(tester, 'Synthetic originating substance');
    expect(find.text('Synthetic originating substance'), findsOneWidget);
  });

  appTest('overview holds narrow and large text in light and dark', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester);
    final item = (await runIo(tester, () async {
      final created = await f.store.createItem(
        expectedPersonRevision: fixtureRevision,
        commandId: 'narrow-item',
        name: 'Long synthetic substance name with full details',
        form: 'Extended synthetic form label',
        unit: 'count',
        type: 'Supplement',
      );
      await f.store.record(
        expectedPersonRevision: fixtureRevision,
        commandId: 'narrow-record',
        itemId: created.id,
        amount: '1',
        actualAt: DateTime(2026, 10, 20, 8),
      );
      await f.store.saveDailyPlan(
        commandId: 'narrow-plan',
        expectedPersonRevision: fixtureRevision,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'narrow-plan',
          itemId: created.id,
          versionId: 'narrow-v1',
          start: CivilDate(2026, 2, 1),
          timing: DailyCount(
            2,
            PlannedAmount(quantity: ExactQuantity.parse('0.5'), unit: 'count'),
          ),
          zoneBasis: const FollowingLocal(),
        ),
      );
      return created;
    }))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await settle(tester);
    await waitForText(
      tester,
      'Long synthetic substance name with full details',
    );
    expect(find.textContaining('No plan yet'), findsNothing);
    f.container.read(appearanceProvider.notifier).setMode(ThemeMode.dark);
    await settle(tester);
    expect(find.text('Record'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('following plans name an unobserved zone instead of implying UTC', (
    tester,
  ) async {
    final f = await launchOverview(
      tester,
      zone: const DeviceZoneObservation.unavailable(),
    );
    final item = (await runIo(tester, () async {
      final created = await f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'zone-item',
        name: 'Synthetic unobserved substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      await f.store.saveDailyPlan(
        commandId: 'zone-plan',
        expectedPersonRevision: 2,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'zone-plan',
          itemId: created.id,
          versionId: 'zone-v1',
          start: CivilDate(2026, 2, 1),
          timing: DailySlots([
            DailySlot(
              id: 'morning',
              time: WallTime(8, 0),
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1'),
                unit: 'mg',
              ),
              reminderEnabled: false,
            ),
          ]),
          zoneBasis: const FollowingLocal(),
        ),
      );
      return created;
    }))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await settle(tester);
    await section(tester, 'Schedule');
    await waitForTextContaining(tester, 'Observed zone:');
    expect(find.text('Observed zone: Unknown'), findsOneWidget);
    // The observed-wording change must not hide the plan's own content.
    expect(find.textContaining('Chosen time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('following plans carry the actually observed zone onwards', (
    tester,
  ) async {
    final f = await launchOverview(tester);
    final item = (await runIo(tester, () async {
      final created = await f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'zone-ok-item',
        name: 'Synthetic observed substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      await f.store.saveDailyPlan(
        commandId: 'zone-ok-plan',
        expectedPersonRevision: 2,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'zone-ok-plan',
          itemId: created.id,
          versionId: 'zone-ok-v1',
          start: CivilDate(2026, 2, 1),
          timing: DailySlots([
            DailySlot(
              id: 'morning',
              time: WallTime(8, 0),
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1'),
                unit: 'mg',
              ),
              reminderEnabled: false,
            ),
          ]),
          zoneBasis: const FollowingLocal(),
        ),
      );
      return created;
    }))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await settle(tester);
    await section(tester, 'Schedule');
    await waitForText(tester, 'Observed zone: Europe/London');
    // An explicitly stored home zone keeps its own stored name.
    expect(find.textContaining('Observed zone'), findsOneWidget);
  });

  appTest(
    'a locally stored home zone shows its explicit zone despite no device zone',
    (tester) async {
      final f = await launchOverview(
        tester,
        zone: const DeviceZoneObservation.unavailable(),
      );
      final item = (await runIo(tester, () async {
        final created = await f.store.createItem(
          expectedPersonRevision: 2,
          commandId: 'home-zone-item',
          name: 'Synthetic home zone substance',
          form: 'Tablet',
          unit: 'mg',
          type: 'Medicine',
        );
        await f.store.saveDailyPlan(
          commandId: 'home-zone-plan',
          expectedPersonRevision: 2,
          expectedGeneration: f.store.generation,
          plan: DailyPlanVersion(
            personId: meId,
            planId: 'home-zone-plan',
            itemId: created.id,
            versionId: 'home-zone-v1',
            start: CivilDate(2026, 2, 1),
            timing: DailyCount(
              1,
              PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
            ),
            zoneBasis: FixedHome('Europe/London'),
          ),
        );
        return created;
      }))!;
      f.container.read(routerProvider).push('/substance/${item.id}');
      await section(tester, 'Schedule');
      await waitForText(tester, 'Observed zone: Europe/London');
      expect(find.text('Observed zone: Unknown'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('saved plan list stays bounded and names its working editor', (
    tester,
  ) async {
    final f = await launchOverview(
      tester,
      fixturePlans: () => [
        for (var i = 1; i <= 51; i++)
          SavedDailyPlan(
            plan: DailyPlanVersion(
              personId: meId,
              planId: 'fixture-plan-$i',
              itemId: 'fixture-item',
              versionId: 'fixture-plan-$i-v1',
              start: CivilDate(2026, 2, 1),
              timing: DailyCount(
                1,
                PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
              ),
              zoneBasis: const FollowingLocal(),
            ),
            revision: 1,
          ),
      ],
    );
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'bound-item',
        name: 'Synthetic bounded plans substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await settle(tester);
    await section(tester, 'Schedule');
    await waitForText(
      tester,
      'This summary shows the first plans. Open Schedule to review the rest.',
    );
    expect(
      find.text(
        'This summary shows the first plans. Open Schedule to review the rest.',
      ),
      findsOneWidget,
    );
    final shownEdits = <String>{};
    for (final button in tester.widgetList<VitalButton>(
      find.byType(VitalButton),
    )) {
      final key = button.key;
      if (key is ValueKey<String> && key.value.startsWith('overview-plan-')) {
        shownEdits.add(key.value);
      }
    }
    expect(shownEdits, hasLength(50));
    expect(tester.takeException(), isNull);
  });

  appTest('plan editing targets the displayed plan identity', (tester) async {
    final f = await launchOverview(tester);
    final item = (await runIo(tester, () async {
      final created = await f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'single-plan-item',
        name: 'Synthetic two plans substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      await f.store.saveDailyPlan(
        commandId: 'single-second-plan',
        expectedPersonRevision: 2,
        expectedPlanRevision: null,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'single-second-plan',
          itemId: created.id,
          versionId: 'single-second-plan-v1',
          start: CivilDate(2026, 2, 1),
          timing: DailySlots([
            DailySlot(
              id: 'second-slot',
              time: WallTime(15, 0),
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1'),
                unit: 'mg',
              ),
              reminderEnabled: false,
            ),
          ]),
          zoneBasis: const FollowingLocal(),
        ),
      );
      return created;
    }))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await settle(tester);
    await section(tester, 'Schedule');
    await waitForTextContaining(tester, 'Chosen time');
    await waitForTextContaining(tester, 'Starts');
    final edit = tester.widget<VitalButton>(
      find.byKey(const ValueKey('overview-plan-edit-single-second-plan')),
    );
    expect(edit.onPressed, isNotNull);
    final editKey = find.byKey(
      const ValueKey('overview-plan-edit-single-second-plan'),
    );
    await tester.ensureVisible(editKey.last);
    await settle(tester);
    await tester.tap(editKey.last);
    await settle(tester);
    final config = f.container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration;
    final pushed = config.last as ImperativeRouteMatch;
    expect(pushed.route.path, '/schedule/:id');
    expect(pushed.matches.uri.queryParameters['plan'], 'single-second-plan');
    expect(tester.takeException(), isNull);
  });

  appTest(
    'a plan outside the bounded next-dose feed is named rather than denied',
    (tester) async {
      final f = await launchOverview(tester, fakeNextFeed: true);
      final item = (await runIo(tester, () async {
        final created = await f.store.createItem(
          expectedPersonRevision: 2,
          commandId: 'missing-next-item',
          name: 'Synthetic bounded feed substance',
          form: 'Tablet',
          unit: 'mg',
          type: 'Medicine',
        );
        await f.store.saveDailyPlan(
          commandId: 'missing-next-plan',
          expectedPersonRevision: 2,
          expectedGeneration: f.store.generation,
          plan: DailyPlanVersion(
            personId: meId,
            planId: 'missing-next-plan',
            itemId: created.id,
            versionId: 'missing-next-v1',
            start: CivilDate(2026, 2, 1),
            timing: DailyCount(
              1,
              PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
            ),
            zoneBasis: const FollowingLocal(),
          ),
        );
        return created;
      }))!;
      f.container.read(routerProvider).push('/substance/${item.id}');
      await section(tester, 'Schedule');
      await waitForText(
        tester,
        'This plan is not in the bounded next-dose summary. Open Schedule to review it.',
      );
      expect(
        find.textContaining('No next planned date'),
        findsNothing,
        reason: 'A feed limitation cannot be written as a schedule outcome.',
      );
      expect(find.text('Synthetic bounded feed substance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('linked events beyond the summary cut point to a working Events', (
    tester,
  ) async {
    final f = await launchOverview(tester);
    final item = (await runIo(tester, () async {
      var revision = 2;
      final created = await f.store.createItem(
        expectedPersonRevision: revision,
        commandId: 'events-item',
        name: 'Synthetic event substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      for (var i = 1; i <= 21; i++) {
        revision = (await f.store.profileById(meId))!.revision;
        final event = EventRecord(
          id: 'overview-event-$i',
          personId: meId,
          name: 'Synthetic course $i',
          eventType: 'prescription',
          zoneId: 'Europe/London',
          revision: 1,
          plannedStart: EventDate.day(CivilDate(2026, 10, 1)),
          plannedEnd: EventDate.day(CivilDate(2026, 10, 25)),
          memberships: [
            EventMembership(
              id: 'overview-member-$i',
              itemId: created.id,
              personId: meId,
              effectiveFrom: DateTime.utc(2026, 10, 10),
              revision: 1,
            ),
          ],
        );
        final command = SaveEventCommand(
          commandId: 'overview-event-command-$i',
          generation: f.store.generation,
          expectedRevision: null,
          expectedPersonRevision: revision,
          event: event,
        );
        await f.store.saveEvent(
          command,
          membershipReview: await f.store.previewEventMembership(command),
        );
      }
      return created;
    }))!;
    // The real arrival path: the dock destination is the navigation base, the
    // overview is pushed on top of it.
    f.container.read(routerProvider).go('/substances');
    await settle(tester);
    f.container.read(routerProvider).push('/substance/${item.id}');
    await waitForTextContaining(tester, 'first events');
    expect(
      find.text(
        'This summary shows the first events. Open Events to review them all.',
      ),
      findsOneWidget,
    );
    // Twenty-one matches stay inside the reachable page, so the warning here
    // is the matches cut, not a full event page.
    expect(find.textContaining('Synthetic course '), findsNWidgets(20));
    final events = find.byKey(const ValueKey('overview-events-review'));
    await tester.ensureVisible(events.last);
    await settle(tester);
    await tester.tap(events.last);
    await settle(tester);
    final config = f.container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration;
    expect(config.last.route.path, '/events');
    expect(tester.takeException(), isNull);
  });

  appTest('saved plan edits refresh the mounted overview', (tester) async {
    final f = await launchOverview(tester);
    final item = (await runIo(tester, () async {
      final created = await f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'live-item',
        name: 'Synthetic live substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      await f.store.saveDailyPlan(
        commandId: 'live-plan',
        expectedPersonRevision: 2,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'live-plan',
          itemId: created.id,
          versionId: 'live-v1',
          start: CivilDate(2026, 2, 1),
          timing: DailyCount(
            1,
            PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
          ),
          zoneBasis: const FollowingLocal(),
        ),
      );
      return created;
    }))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await settle(tester);
    await section(tester, 'Schedule');
    await waitForTextContaining(tester, 'Planned once a day');
    expect(find.text('Paused'), findsNothing);
    // A plain store mutation, with no provider invalidation from the page.
    final revision = await runIo(tester, () async {
      final fresh = (await f.store.profileById(meId))!;
      await f.store.saveDailyPlan(
        commandId: 'live-plan-pause',
        expectedPersonRevision: fresh.revision,
        expectedPlanRevision: 1,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'live-plan',
          itemId: item.id,
          versionId: 'live-v2',
          start: CivilDate(2026, 2, 1),
          timing: DailyCount(
            1,
            PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
          ),
          zoneBasis: const FollowingLocal(),
          pauses: [
            PlanPause(
              start: DateTime.now().toUtc().subtract(const Duration(days: 1)),
            ),
          ],
        ),
      );
      return fresh.revision;
    });
    expect(revision, greaterThan(0));
    await settle(tester);
    await waitForText(tester, 'Paused');
    expect(find.text('Paused'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('overview quick actions open combine and stock for this item', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: fixtureRevision,
        commandId: 'quick-item',
        name: 'Synthetic quick action substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await waitForText(tester, item.name);
    await waitForText(tester, 'Record');
    await tap(tester, 'More');
    await settle(tester);
    await tap(tester, 'Combine');
    await settle(tester);
    var config = f.container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration;
    expect(config.last.route.path, '/combined/:person');
    expect(
      (config.last as ImperativeRouteMatch).matches.uri.queryParameters['item'],
      item.id,
    );
    f.container.read(routerProvider).pop();
    await waitForText(tester, item.name);
    await waitForText(tester, 'Record');
    await tap(tester, 'More');
    await settle(tester);
    await tap(tester, 'Stock');
    await settle(tester);
    config = f.container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration;
    expect(config.last.route.path, '/stock/:person');
    expect(
      (config.last as ImperativeRouteMatch).matches.uri.queryParameters['item'],
      item.id,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('overview names an exact low balance and opens stock', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () async {
      final created = await f.store.createItem(
        expectedPersonRevision: fixtureRevision,
        commandId: 'low-item',
        name: 'Synthetic low stock substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
      await f.store.createStockContainer(
        commandId: 'low-stock',
        expectedPersonRevision: fixtureRevision,
        expectedGeneration: f.store.generation,
        personId: meId,
        itemId: created.id,
        label: 'Synthetic low container',
        unit: 'mg',
        strength: LabelledStrength(
          ingredientId: created.id,
          label: 'Not known',
        ),
        opening: ExactAmount(BigInt.from(3), BigInt.one),
        lowThreshold: ExactAmount(BigInt.from(5), BigInt.one),
      );
      return created;
    }))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await waitForText(tester, 'Low stock');
    // The alert heading and the container badge both name the real state.
    expect(find.text('Low stock'), findsWidgets);
    expect(find.text('Synthetic low container · 3 mg'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('overview-stock-alert-review')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('overview-stock-alert-review')));
    await settle(tester);
    final config = f.container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration;
    expect(config.last.route.path, '/stock/:person');
    expect(
      (config.last as ImperativeRouteMatch).matches.uri.queryParameters['item'],
      item.id,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('overview stacks hero actions at 320 and pairs them at 430', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: fixtureRevision,
        commandId: 'responsive-item',
        name: 'Synthetic responsive substance with a complete name',
        form: 'Extended tablet form',
        unit: 'count',
        type: 'Supplement',
      ),
    ))!;
    f.container.read(routerProvider).push('/substance/${item.id}');
    await waitForText(
      tester,
      'Synthetic responsive substance with a complete name',
    );
    for (final width in [320.0, 430.0]) {
      tester.view.physicalSize = Size(width, 740);
      await settle(tester);
      expect(find.text('Overview'), findsOneWidget);
      await tap(tester, 'More');
      expect(find.text('Combine'), findsOneWidget);
      expect(find.text('Stock').hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await settle(tester);
      expect(tester.takeException(), isNull);
    }
  });
}
