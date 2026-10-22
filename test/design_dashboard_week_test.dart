import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/widgets.dart' show Semantics, ValueKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/today_hero.dart';
import 'package:true_grit_vital/features/plans/plan_providers.dart';
import 'package:true_grit_vital/features/recording/quick_record_sheet.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart' show appTest, runIo, settle;

const _zone = 'Europe/London';
final _today = CivilDate(2026, 10, 21);
final _now = DateTime.utc(2026, 10, 21, 12);

PlannedAmount _amount() => PlannedAmount(
  quantity: ExactQuantity.parse('1'),
  enteredText: '1',
  unit: 'mg',
);

typedef _Fixture = ({
  RecordStore store,
  ProviderContainer container,
  Map<String, String> itemIds,
});

Future<_Fixture> _launch(
  WidgetTester tester, {
  required List<
    ({String name, DailyTiming timing, CivilDate? start, CivilDate? end})
  >
  plans,
  List<String>? favourites,
}) async {
  final directory = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-dashboard-week-'),
  ))!;
  final store = (await runIo(tester, () async {
    final store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (index) => index + 1),
      isNew: true,
    );
    await store.editProfile(
      commandId: 'setup',
      personId: meId,
      expectedRevision: 1,
      name: 'Main Adult',
      adultConfirmed: true,
    );
    await store.saveBrowsingScope(const FeedScope.me());
    return store;
  }))!;
  final itemIds = <String, String>{};
  for (final (index, spec) in plans.indexed) {
    final revision = (await runIo(
      tester,
      () => store.profileById(meId),
    ))!.revision;
    final item = (await runIo(
      tester,
      () => store.createItem(
        commandId: 'item-$index',
        personId: meId,
        expectedPersonRevision: revision,
        name: spec.name,
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    itemIds[spec.name] = item.id;
    await runIo(
      tester,
      () => store.saveDailyPlan(
        commandId: 'plan-$index',
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'plan-$index',
          itemId: item.id,
          versionId: 'version-$index',
          start: spec.start ?? _today.addDays(-1),
          endExclusive: spec.end,
          timing: spec.timing,
          zoneBasis: FixedHome(_zone),
        ),
        expectedPersonRevision: revision,
        expectedGeneration: store.generation,
      ),
    );
  }
  if (favourites != null) {
    await runIo(
      tester,
      () => store.writeSetting(
        'dashboard_favourites',
        jsonEncode({'planIds': favourites}),
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
      todayNowProvider.overrideWithValue(() => _now),
      dailyFeedProvider.overrideWith(
        (ref, scope) => store.watchTodayDailyRows(
          scope: scope,
          now: _now,
          observedZone: _zone,
          maxPlans: 100,
          maxRows: 1000,
        ),
      ),
      artifactTransferGatewayProvider.overrideWithValue(
        const UnsupportedArtifactTransfer(),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    // Closing watched reads also needs the widget clock to keep moving.
    await runIo(tester, store.close);
    await directory.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  container.read(routerProvider).go('/today');
  await settle(tester);
  return (store: store, container: container, itemIds: itemIds);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
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
  appTest('selecting a date loads that day and never records a current dose', (
    tester,
  ) async {
    final fixture = await _launch(
      tester,
      plans: [
        (
          name: 'Yesterday only',
          timing: DailyCount(1, _amount()),
          start: _today.addDays(-1),
          end: _today,
        ),
        (
          name: 'Today only',
          timing: DailyCount(1, _amount()),
          start: _today,
          end: _today.addDays(1),
        ),
      ],
    );
    expect(find.text('Week summary'), findsNothing);
    expect(find.text('No set time'), findsOneWidget);
    expect(find.text('Today only'), findsWidgets);
    expect(find.text('Yesterday only'), findsNothing);
    expect(find.text('Taken'), findsWidgets);

    final yesterday = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.label?.contains('20 October 2026') ?? false),
    );
    await _tap(tester, yesterday.first);

    expect(find.text('Yesterday only'), findsWidgets);
    expect(find.text('Today only'), findsNothing);
    expect(find.text('No set time'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard-calendar-selection')),
      findsNothing,
    );
    // A browsed date has no one-tap current-time commands.
    expect(find.text('Taken'), findsNothing);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Snooze'), findsNothing);
    expect(find.text('Record'), findsWidgets);
    expect((await runIo(tester, fixture.store.records))!, isEmpty);

    await _tap(tester, find.text('Record').first);
    expect(
      fixture.container.read(routerProvider).routerDelegate.state.uri.path,
      '/unplanned',
    );
    expect(
      fixture.container.read(routerProvider).state.uri.queryParameters['day'],
      '2026-10-20',
    );
  });

  appTest(
    'unplanned medication chooses any existing medicine without favourites',
    (tester) async {
      final fixture = await _launch(
        tester,
        plans: [
          (
            name: 'Alpha PRN',
            timing: const AsNeeded(),
            start: _today.addDays(-5),
            end: null,
          ),
          (
            name: 'Beta PRN',
            timing: const AsNeeded(),
            start: _today.addDays(-5),
            end: null,
          ),
        ],
        favourites: ['plan-1', 'plan-0'],
      );
      expect(find.text('Configure'), findsNothing);
      expect(find.text('No unplanned medication today.'), findsOneWidget);
      await _tap(
        tester,
        find.descendant(
          of: find.byType(UnplannedMedication),
          matching: find.text('Add'),
        ),
      );
      expect(find.text('Beta PRN'), findsOneWidget);
      expect(find.text('Alpha PRN'), findsOneWidget);
      await _tap(tester, find.text('Alpha PRN'));
      final uri = fixture.container.read(routerProvider).state.uri;
      expect(uri.path, '/unplanned');
      expect(uri.queryParameters['item'], fixture.itemIds['Alpha PRN']);
      expect((await runIo(tester, fixture.store.records))!, isEmpty);
    },
  );

  appTest('planned doses share one timeline and unused dayparts stay hidden', (
    tester,
  ) async {
    DailySlots at(int hour) => DailySlots([
      DailySlot(
        id: 'slot',
        time: WallTime(hour, 0),
        amount: _amount(),
        reminderEnabled: false,
      ),
    ]);
    final f = await _launch(
      tester,
      plans: [
        (name: 'Morning medicine', timing: at(8), start: _today, end: null),
        (name: 'Evening medicine', timing: at(20), start: _today, end: null),
      ],
    );
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Afternoon'), findsNothing);
    expect(find.text('Evening'), findsOneWidget);
    expect(find.text('Morning medicine'), findsOneWidget);
    expect(find.text('Evening medicine'), findsOneWidget);
    final rows = (await runIo(
      tester,
      () => f.store.dailyRows(
        from: _today,
        toExclusive: _today.addDays(1),
        observedZone: _zone,
      ),
    ))!.rows;
    await runIo(
      tester,
      () => f.store.actDaily(
        commandId: 'take-morning',
        row: rows.first,
        kind: DailyActionKind.taken,
        actualAt: _now,
      ),
    );
    await settle(tester);
    expect(find.text('Morning medicine'), findsOneWidget);
    expect(find.text('Evening medicine'), findsOneWidget);
    expect(find.text('Recorded'), findsNothing);
    expect(
      (await runIo(
        tester,
        () => f.store.unplannedUses(
          from: DateTime.utc(2026, 10, 20, 23),
          before: DateTime.utc(2026, 10, 21, 23),
        ),
      ))!,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  appTest(
    'narrow large-text week browsing keeps the day and full names reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await _launch(
        tester,
        plans: [
          (
            name: 'Synthetic full substance name',
            timing: DailyCount(2, _amount()),
            start: _today,
            end: _today.addDays(1),
          ),
        ],
      );
      expect(find.text('Week summary'), findsNothing);
      expect(find.text('Synthetic full substance name'), findsWidgets);
      expect(find.text('Taken'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
