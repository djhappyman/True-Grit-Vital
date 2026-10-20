import '../test/fixtures/single_user.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

import 'stock_flow_test.dart' as ui;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Run only through the protected device snapshot harness. All records below
  // are synthetic and use the real Android encrypted storage bootstrap.
  testWidgets(
    'selected and monthly calendar plans retain adult Taken on encrypted reopen',
    (tester) async {
      const bootstrap = AndroidStorageBootstrap();
      final location = await bootstrap.prepare();
      final store = await RecordStore.open(
        path: location.path,
        key: location.key,
        isNew: location.isNew,
      );
      addTearDown(store.close);
      await bootstrap.activate(location);
      final me = (await store.profileById(meId))!;
      if (!me.adultConfirmed) {
        await store.editProfile(
          commandId: newCommandId(),
          personId: meId,
          expectedRevision: me.revision,
          name: me.name,
          adultConfirmed: true,
        );
      }
      final adult = await store.configureOwnProfile(
        commandId: newCommandId(),
        name: 'Synthetic calendar adult',
        adultConfirmed: true,
      );
      final today = CivilDate.fromDateTime(DateTime.now().toUtc());
      final ids = <String>[];
      for (final (name, calendar) in <(String, CalendarPattern)>[
        (
          'Synthetic selected weekdays',
          SelectedWeekdays([today.calendarValue.weekday]),
        ),
        (
          'Synthetic monthly nominal',
          EveryNMonths(
            anchorMonth: today,
            interval: 1,
            selector: DayOfMonth(
              today.day,
              missingDatePolicy: MissingDatePolicy.lastValid,
            ),
          ),
        ),
      ]) {
        final item = await store.createItem(
          commandId: newCommandId(),
          personId: adult.id,
          expectedPersonRevision: adult.revision,
          name: name,
          form: 'Tablet',
          unit: 'mg',
          type: 'Medicine',
        );
        ids.add(item.id);
        await store.saveDailyPlan(
          commandId: newCommandId(),
          expectedPersonRevision: adult.revision,
          expectedGeneration: store.generation,
          plan: DailyPlanVersion(
            personId: adult.id,
            itemId: item.id,
            planId: newCommandId(),
            versionId: newCommandId(),
            start: today,
            calendar: calendar,
            timing: DailyCount(
              1,
              PlannedAmount(
                quantity: ExactQuantity.parse('0.125'),
                enteredText: '0.12500',
                unit: 'mg',
              ),
            ),
            zoneBasis: FixedHome('UTC'),
          ),
        );
      }
      await store.saveBrowsingScope(FeedScope.person(adult.id));
      final providers = ProviderContainer(
        overrides: [storeLoaderProvider.overrideWithValue(() async => store)],
      );
      addTearDown(providers.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: providers,
          child: const VitalApp(),
        ),
      );
      await ui.waitFor(tester, find.text('Synthetic selected weekdays'));
      expect(find.textContaining('Synthetic calendar adult'), findsWidgets);
      expect(find.textContaining('0.12500 mg'), findsWidgets);
      await ui.tap(
        tester,
        find.bySemanticsLabel(
          RegExp(r'^Taken: .*Synthetic selected weekdays,'),
        ),
      );
      await ui.waitFor(tester, find.text('1 recorded, 0 skipped, 1 planned'));
      final remaining = find.bySemanticsLabel(
        RegExp(r'^Taken: .*Synthetic monthly nominal,'),
      );
      await ui.tap(tester, remaining);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if ((await store.records(personId: adult.id))
                .where((r) => ids.contains(r.itemId))
                .length ==
            2) {
          break;
        }
      }
      final reopened = await RecordStore.open(
        path: location.path,
        key: location.key,
        isNew: false,
      );
      try {
        final records = (await reopened.records(personId: adult.id))
            .where((r) => ids.contains(r.itemId))
            .toList();
        expect(records.length, 2);
        expect(
          records.every(
            (r) => r.personId == adult.id && r.originalEntry == '0.12500',
          ),
          true,
        );
        final rows = await reopened.dailyRows(
          from: today,
          toExclusive: today.addDays(1),
          observedZone: 'UTC',
        );
        expect(
          rows.rows
              .where((r) => ids.contains(r.expectation.itemId))
              .every((r) => r.takenCount == 1),
          true,
        );
        final plans = await reopened.dailyPlans(
          scope: FeedScope.person(adult.id),
        );
        expect(plans.any((p) => p.plan.calendar is SelectedWeekdays), true);
        expect(plans.any((p) => p.plan.calendar is EveryNMonths), true);
      } finally {
        await reopened.close();
      }
    },
  );
}
