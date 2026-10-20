import 'fixtures/single_user.dart';

import 'package:true_grit_vital/ui/vital_ui.dart';

import 'dart:async';

import 'package:true_grit_vital/features/plans/daily_feed.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/app/app_lock.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'vital_app_test.dart' show appTest, settle, runIo;

// This isolated clock-choice test formats saved instants without opening storage.
class FixedClockDisplayPreferences extends DisplayPreferencesController {
  @override
  DisplayPreferences build() =>
      const DisplayPreferences(timeFormat: TimeFormat.h24);
}

Future<void> tap(WidgetTester tester, String text) async {
  tester.testTextInput.hide();
  await settle(tester);
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
  await settle(tester);
}

class PlanTestZone implements DeviceZoneGateway {
  @override
  Future<DeviceZoneObservation> read() async =>
      DeviceZoneObservation.fromId('Europe/London');
  @override
  Stream<void> get changes => const Stream.empty();
}

Future<({RecordStore store, ProviderContainer container, SubstanceItem item})>
launchPlan(
  WidgetTester tester, {
  String person = meId,
  Stream<DeviceZoneObservation>? observations,
}) async {
  final dir = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-plan-ui-'),
  ))!;
  final store = (await runIo(tester, () async {
    final s = await RecordStore.open(
      path: '${dir.path}/records.db',
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
  if (person != meId) {
    person = (await runIo(
      tester,
      () => store.configureOwnProfile(
        commandId: 'other',
        name: 'Other Adult',
        adultConfirmed: true,
      ),
    ))!.id;
  }
  person = meId;
  final owner = (await runIo(tester, () => store.profileById(person)))!;
  final item = (await runIo(
    tester,
    () => store.createItem(
      commandId: 'item',
      personId: person,
      expectedPersonRevision: owner.revision,
      name: 'Full synthetic substance name',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    ),
  ))!;
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() async => store),
      appAuthGatewayProvider.overrideWithValue(FakeAuth()),
      observedDeviceZoneProvider.overrideWith(
        (ref) =>
            observations ??
            Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  container.read(routerProvider).push('/schedule/${item.id}');
  await settle(tester);
  return (store: store, container: container, item: item);
}

void main() {
  appTest(
    'daily count preview save Taken Skip Undo keep exact amount and captured owner',
    (tester) async {
      final f = await launchPlan(tester);
      await tester.enterText(find.byType(TextField).at(0), '2');
      await tester.enterText(find.byType(TextField).at(1), '1.00');
      await tap(tester, 'Preview');
      expect(
        find.textContaining('2 planned, 1.00 mg each, untimed'),
        findsWidgets,
      );
      await tap(tester, 'Save');
      await settle(tester);
      expect(find.text('0 recorded, 0 skipped, 2 planned'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('Upcoming'), findsNothing);
      expect(find.text('Recorded'), findsOneWidget);
      final plannedRowState = tester.state(find.byType(DailyRowCard).first);
      expect(
        find.text(
          'Next planned date: ${CivilDate.fromDateTime(DateTime.now())}',
        ),
        findsOneWidget,
      );
      await tap(tester, 'Taken');
      expect(find.text('1 recorded, 0 skipped, 2 planned'), findsOneWidget);
      await tap(tester, 'Skip');
      expect(find.text('1 recorded, 1 skipped, 2 planned'), findsOneWidget);
      expect(
        tester.state(find.byType(DailyRowCard).first),
        same(plannedRowState),
      );
      // Undo is offered on the stable planned row, separately from actual history.
      final undo = find.text('Undo').first;
      await tester.ensureVisible(undo);
      await tester.tap(undo);
      await settle(tester);
      expect(find.textContaining('1 skipped, 2 planned'), findsNothing);
      final rows = (await runIo(tester, () => f.store.records()))!;
      expect(rows.single.enteredAmount, '1.00');
      expect(rows.single.personId, meId);
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'several stable slots preserve independently entered amounts through version edits',
    (tester) async {
      final f = await launchPlan(tester);
      await tap(tester, 'Chosen times');
      await tester.enterText(find.byType(TextField).at(0), '08:15');
      await tester.enterText(find.byType(TextField).at(1), '0.50');
      await tap(tester, 'Add');
      await tester.enterText(find.byType(TextField).at(2), '21:45');
      await tester.enterText(find.byType(TextField).at(3), '1.2500');
      await tap(tester, 'Preview');
      expect(find.textContaining('08:15: 0.50 mg'), findsWidgets);
      expect(find.textContaining('21:45: 1.2500 mg'), findsWidgets);
      await tap(tester, 'Save');
      final initial = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single;
      final ids = (initial.plan.timing as DailySlots).slots
          .map((s) => s.id)
          .toList();
      f.container
          .read(routerProvider)
          .push('/schedule/${f.item.id}?plan=${initial.plan.planId}');
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(1), '0.75');
      final tomorrow = CivilDate.fromDateTime(DateTime.now())
          .addDays(1)
          .toString();
      await tester.enterText(find.byType(TextField).at(4), tomorrow);
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      final versions = (await runIo(
        tester,
        () => f.store.dailyPlanVersions(initial.plan.planId, personId: meId),
      ))!;
      expect(versions.length, 2);
      expect(
        (versions.last.plan.timing as DailySlots).slots.map((s) => s.id),
        ids,
      );
      expect(
        (versions.first.plan.timing as DailySlots)
            .slots
            .first
            .amount
            .enteredText,
        '0.50',
      );
      expect(
        (versions.last.plan.timing as DailySlots)
            .slots
            .first
            .amount
            .enteredText,
        '0.75',
      );
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'as needed has no expectations and optional home zone remains explicit',
    (tester) async {
      final f = await launchPlan(tester);
      await tap(tester, 'As needed');
      await tap(tester, 'Home zone');
      await tester.enterText(find.byType(TextField).last, 'Europe/London');
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      expect(find.text('As needed'), findsOneWidget);
      expect(find.text('Taken'), findsNothing);
      final plan = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single.plan;
      expect(plan.zoneBasis, isA<FixedHome>());
      expect(plan.timing, isA<AsNeeded>());
      final rows = (await runIo(
        tester,
        () => f.store.todayDailyRows(
          now: DateTime.now().toUtc(),
          observedZone: 'Europe/London',
        ),
      ))!;
      expect(rows.rows, isEmpty);
      expect(rows.complete, true);
    },
  );
  appTest('ordinary plan draft restores exact fields and private owner', (
    tester,
  ) async {
    final f = await launchPlan(tester);
    await tester.enterText(find.byType(TextField).at(0), '3');
    await tester.enterText(find.byType(TextField).at(1), '0.250000');
    await settle(tester);
    final drafts = (await runIo(tester, f.store.drafts))!;
    expect(drafts.single.kind, DraftKind.dailyPlan);
    expect(drafts.single.fields['amount'], '0.250000');
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    await tap(tester, 'Resume');
    expect(
      (tester.widget<TextField>(find.byType(TextField).at(1))).controller!.text,
      '0.250000',
    );
    await tap(tester, 'Preview');
    await tap(tester, 'Save');
    expect((await runIo(tester, f.store.drafts))!, isEmpty);
  });
  appTest('your plan stays available despite a legacy saved feed choice', (
    tester,
  ) async {
    final f = await launchPlan(tester, person: 'other');
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.enterText(find.byType(TextField).at(1), '0.1250');
    await tap(tester, 'Preview');
    await tap(tester, 'Save');
    expect(find.text('Taken'), findsWidgets);
    await runIo(
      tester,
      () => f.store.saveBrowsingScope(const FeedScope.everyone()),
    );
    await settle(tester);
    await settle(tester);
    expect(find.textContaining('Other Adult'), findsWidgets);
    await tap(tester, 'Taken');
    final records = (await runIo(
      tester,
      () => f.store.records(scope: const FeedScope.everyone()),
    ))!;
    expect(records.single.personId, f.item.personId);
    expect(records.single.source, RecordSource.selfReported);
    expect(
      (await runIo(
        tester,
        () => f.store.records(scope: const FeedScope.me()),
      ))!,
      hasLength(1),
    );
  });
  appTest(
    'plan draft stays covered while locked and restores its exact amount',
    (tester) async {
      final f = await launchPlan(tester);
      await tester.enterText(find.byType(TextField).at(0), '2');
      await tester.enterText(find.byType(TextField).at(1), '0.010000');
      await settle(tester);
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      await settle(tester);
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      expect(find.text('0.010000'), findsNothing);
      expect(f.store.writesSuspended, true);
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).unlock(),
      );
      await settle(tester);
      expect(
        (tester.widget<TextField>(find.byType(TextField).at(1)))
            .controller!
            .text,
        '0.010000',
      );
      expect(
        (await runIo(tester, f.store.drafts))!.single.fields['amount'],
        '0.010000',
      );
    },
  );
  appTest(
    'preview exposes a repeated clock and unsupported date without choosing a time',
    (tester) async {
      await launchPlan(tester);
      await tap(tester, 'Chosen times');
      await tester.enterText(find.byType(TextField).at(0), '01:30');
      await tester.enterText(find.byType(TextField).at(1), '1');
      await tester.enterText(find.byType(TextField).at(2), '2026-10-25');
      await tap(tester, 'Preview');
      expect(find.textContaining('This local time occurs twice'), findsWidgets);
      expect(
        find.text('Earlier'),
        findsNothing,
      ); // Review choices happen on the captured occurrence.
      await tester.enterText(find.byType(TextField).at(2), '2090-10-25');
      await tap(tester, 'Preview');
      expect(find.textContaining('cannot be calculated'), findsWidgets);
      expect(find.text('No next planned date within this plan.'), findsNothing);
    },
  );
  appTest('plan form keeps full values at narrow width and double text', (
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
    await launchPlan(tester);
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.enterText(find.byType(TextField).at(1), '0.125000');
    await tap(tester, 'Preview');
    await tap(tester, 'Save');
    expect(find.textContaining('0.125000 mg'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'replacement clock candidates clear as soon as the entered time changes',
    (tester) async {
      final plan = DailyPlanVersion(
        personId: meId,
        planId: 'p',
        itemId: 'i',
        versionId: 'v',
        start: CivilDate(2026, 10, 25),
        timing: DailySlots([
          DailySlot(
            id: 's',
            time: WallTime(1, 30),
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              unit: 'mg',
            ),
            reminderEnabled: false,
          ),
        ]),
        zoneBasis: FixedHome('Europe/London'),
      );
      final row = DailyResolver()
          .resolveDate(plan, plan.start, observedZone: 'Europe/London')
          .single;
      final choices = <ClockDecision>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            displayPreferencesProvider.overrideWith(
              FixedClockDisplayPreferences.new,
            ),
          ],
          child: ShadcnApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', 'GB')],
            home: Scaffold(
              child: ClockReplacement(
                expectation: row,
                enabled: true,
                onChoice: choices.add,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '01:30');
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(find.text('Earlier'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(choices, isEmpty);
      await tester.enterText(find.byType(TextField), '02:30');
      await tester.pump();
      expect(find.text('Earlier'), findsNothing);
      expect(find.text('Later'), findsNothing);
      expect(choices, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  appTest(
    'saved home zone stays actionable when the observed device zone is unavailable',
    (tester) async {
      await launchPlan(
        tester,
        observations: Stream.value(const DeviceZoneObservation.unavailable()),
      );
      await tester.enterText(find.byType(TextField).at(0), '1');
      await tester.enterText(find.byType(TextField).at(1), '1.00');
      await tap(tester, 'Home zone');
      await tester.enterText(find.byType(TextField).last, 'Europe/London');
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      expect(find.text('Taken'), findsOneWidget);
      expect(find.textContaining('untimed in Europe/London'), findsOneWidget);
      expect(
        find.text(
          'Next planned date: ${CivilDate.fromDateTime(DateTime.now())}',
        ),
        findsOneWidget,
      );
    },
  );
  appTest(
    'local zone changes invalidate the preview while keeping entered values',
    (tester) async {
      final observations = StreamController<DeviceZoneObservation>.broadcast();
      addTearDown(observations.close);
      await launchPlan(tester, observations: observations.stream);
      observations.add(DeviceZoneObservation.fromId('Europe/London'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(0), '2');
      await tester.enterText(find.byType(TextField).at(1), '0.2500');
      await tap(tester, 'Preview');
      expect(
        tester
            .widget<VitalButton>(find.widgetWithText(VitalButton, 'Save'))
            .onPressed,
        isNotNull,
      );
      observations.add(DeviceZoneObservation.fromId('America/New_York'));
      await settle(tester);
      expect(
        tester
            .widget<VitalButton>(find.widgetWithText(VitalButton, 'Save'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '0.2500',
      );
    },
  );
}
