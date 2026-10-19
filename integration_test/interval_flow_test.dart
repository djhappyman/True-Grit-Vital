import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';
import 'package:true_grit_vital/platform/reminders.dart';

import 'stock_flow_test.dart' as ui;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Root runs this fixture only through the protected Android snapshot harness.
  testWidgets(
    'fixed and actual intervals review correction and encrypted reopen',
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
      final adult = await store.createProfile(
        commandId: newCommandId(),
        name: 'Synthetic interval adult',
        adultConfirmed: true,
      );
      final clock = await const AndroidReminders().sampleClock();
      final now = clock.utc;
      final today = CivilDate.fromDateTime(now);
      final items = <SubstanceItem>[];
      for (final mode in IntervalMode.values) {
        final item = await store.createItem(
          commandId: newCommandId(),
          personId: adult.id,
          expectedPersonRevision: adult.revision,
          name: mode == IntervalMode.fixedPlanned
              ? 'Synthetic fixed interval'
              : 'Synthetic actual interval',
          form: 'Tablet',
          unit: 'mg',
          type: 'Medicine',
        );
        items.add(item);
        await store.saveDailyPlan(
          commandId: newCommandId(),
          expectedPersonRevision: adult.revision,
          expectedGeneration: store.generation,
          intervalClockSample: clock,
          plan: DailyPlanVersion(
            personId: adult.id,
            itemId: item.id,
            planId: newCommandId(),
            versionId: newCommandId(),
            start: today,
            zoneBasis: FixedHome('UTC'),
            timing: ElapsedInterval(
              segmentId: newCommandId(),
              duration: ExactElapsed.parseHours('6'),
              mode: mode,
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1.25'),
                enteredText: '1.2500',
                unit: 'mg',
              ),
              plannedAnchor: mode == IntervalMode.fixedPlanned
                  ? now.subtract(const Duration(hours: 1))
                  : null,
            ),
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
      await ui.waitFor(tester, find.text('Synthetic fixed interval'));
      expect(find.text('No qualifying dose'), findsWidgets);
      final actualItem = items.last;
      final source = await store.record(
        commandId: newCommandId(),
        itemId: actualItem.id,
        personId: adult.id,
        amount: '1.2500',
        actualAt: now.subtract(const Duration(minutes: 30)),
      );
      final saved = (await store.dailyPlans(itemId: actualItem.id)).single;
      expect(
        await store.intervalSources(
          planId: saved.plan.planId,
          personId: adult.id,
        ),
        isEmpty,
      );
      providers.read(routerProvider).go('/history');
      await ui.waitFor(tester, find.byType(RecordCard));
      await ui.tap(tester, find.text('Review'));
      await ui.tap(tester, find.text('Select'));
      expect(find.textContaining('After:'), findsOneWidget);
      await ui.tap(tester, find.text('Cancel'));
      expect(
        await store.intervalSources(
          planId: saved.plan.planId,
          personId: adult.id,
        ),
        isEmpty,
      );
      await ui.tap(tester, find.text('Select'));
      await ui.tap(tester, find.text('Save'));
      await store.record(
        commandId: newCommandId(),
        itemId: actualItem.id,
        personId: adult.id,
        amount: '0.5',
        actualAt: now.subtract(const Duration(minutes: 10)),
      );
      expect(
        (await store.intervalSources(
          planId: saved.plan.planId,
          personId: adult.id,
        )).single.actualId,
        source.id,
      );
      providers
          .read(routerProvider)
          .push('/correct/${source.id}?person=${adult.id}');
      await ui.waitFor(tester, find.text('Correct use'));
      final time = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is LabelledInput && w.label == 'Actual time',
        ),
        matching: find.byType(TextField),
      );
      final shifted = source.actualAt.toLocal().subtract(
        const Duration(minutes: 10),
      );
      await ui.reveal(tester, time);
      await tester.enterText(
        time,
        '${shifted.hour.toString().padLeft(2, '0')}:${shifted.minute.toString().padLeft(2, '0')}',
      );
      await ui.tap(tester, find.text('Save'));
      expect(find.textContaining('Before:'), findsOneWidget);
      expect(find.textContaining('After:'), findsOneWidget);
      await ui.tap(tester, find.text('Save'));
      await ui.waitFor(tester, find.byType(RecordCard));
      final reopened = await RecordStore.open(
        path: location.path,
        key: location.key,
        isNew: false,
      );
      try {
        final restored = await reopened.intervalSources(
          planId: saved.plan.planId,
          personId: adult.id,
        );
        expect(restored.single.revision, source.revision + 1);
        expect(restored.single.personId, adult.id);
        expect(
          (await reopened.dailyPlans(itemId: items.first.id))
              .single
              .plan
              .timing,
          isA<ElapsedInterval>(),
        );
      } finally {
        await reopened.close();
      }
    },
  );
}
