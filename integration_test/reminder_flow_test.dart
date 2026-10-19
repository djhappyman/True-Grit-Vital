import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/reminders.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

import 'stock_flow_test.dart' as ui;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Run separately from the isolated native epoch fixture, through the
  // snapshot harness with synthetic notification/exact-alarm grants.
  testWidgets(
    'elapsed product Snooze and Taken retain owner, components and identity',
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
      var me = (await store.profileById(meId))!;
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
        name: 'Synthetic reminder adult',
        adultConfirmed: true,
      );
      final item = await store.createItem(
        commandId: newCommandId(),
        personId: adult.id,
        expectedPersonRevision: adult.revision,
        name: 'Synthetic scoped reminder substance',
        form: 'Liquid',
        unit: 'ml',
        type: 'Medicine',
        productComponents: [
          ProductComponent(
            ingredientId: 'reminder-amber',
            name: 'Synthetic amber',
            concentrationText: '3',
          ),
          ProductComponent(
            ingredientId: 'reminder-blue',
            name: 'Synthetic blue',
            concentrationText: '7',
          ),
        ],
      );
      final initialClock = await const AndroidReminders().sampleClock();
      final due = initialClock.utc.add(const Duration(minutes: 10));
      final date = CivilDate(due.year, due.month, due.day);
      final planId = newCommandId();
      await store.saveDailyPlan(
        commandId: newCommandId(),
        expectedPersonRevision: adult.revision,
        expectedGeneration: store.generation,
        intervalClockSample: initialClock,
        plan: DailyPlanVersion(
          personId: adult.id,
          planId: planId,
          itemId: item.id,
          versionId: newCommandId(),
          start: date,
          timing: ElapsedInterval(
            segmentId: newCommandId(),
            duration: ExactElapsed.parseHours('24'),
            mode: IntervalMode.fixedPlanned,
            plannedAnchor: due,
            reminderEnabled: false,
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              enteredText: '1.000',
              unit: 'ml',
            ),
          ),
          zoneBasis: FixedHome('UTC'),
        ),
      );
      await store.setPlanReminders(
        commandId: newCommandId(),
        planId: planId,
        personId: adult.id,
        expectedPlanRevision: 1,
        expectedPersonRevision: adult.revision,
        enabled: true,
      );
      Future<DailyRow> row() async => (await store.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'Europe/London',
      )).rows.singleWhere((r) => r.expectation.identity.planId == planId);
      final original = await row();
      // The visible scope deliberately belongs to somebody else.
      await store.saveBrowsingScope(const FeedScope.me());
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
      await ui.waitFor(tester, find.text('Substances'));
      // Wait for the real reconciler to register this original adult's request.
      DesiredReminder? nativeRequest;
      for (var i = 0; i < 100 && nativeRequest == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final ready = providers
            .read(remindersProvider)
            .report
            .projection
            ?.desired
            .where(
              (d) =>
                  d.target.row.expectation.identity.planId == planId &&
                  d.repairState == ReminderRepairState.prepared,
            );
        if (ready != null && ready.isNotEmpty) nativeRequest = ready.first;
      }
      expect(nativeRequest, isNotNull);
      final actionRequest = nativeRequest!;
      expect(actionRequest.trigger, ReminderTrigger.elapsed);
      expect(actionRequest.sample!.bootId, initialClock.bootId);
      expect(
        actionRequest.deadlineMilliseconds - initialClock.elapsedMilliseconds,
        const Duration(minutes: 10).inMilliseconds,
      );
      expect(actionRequest.target.row.expectation.identity.intervalOrdinal, 0);
      debugPrint(
        'VITAL_REMINDER_ACTION:${jsonEncode({'epoch': actionRequest.namespace, 'requestToken': actionRequest.requestToken, 'actionToken': actionRequest.snoozeToken, 'action': 'snooze'})}',
      );
      // The protected harness delivers the actual Android Activity intent twice.
      // Native observation, encrypted capture and the coordinator must route it.
      await ui.waitFor(tester, find.text('5 minutes'));
      final pending = (await store.pendingReminderActions()).singleWhere(
        (p) =>
            p.target.row.expectation.identity.planId == planId &&
            p.action == ReminderActionKind.snooze,
      );
      expect(find.text('Synthetic scoped reminder substance'), findsWidgets);
      expect(find.textContaining('Synthetic reminder adult'), findsWidgets);
      for (
        var i = 0;
        i < 100 &&
            providers
                    .read(remindersProvider)
                    .report
                    .capabilities
                    ?.bootIdentityAvailable !=
                true;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        providers
            .read(remindersProvider)
            .report
            .capabilities
            ?.bootIdentityAvailable,
        true,
      );
      await ui.tap(tester, find.text('5 minutes'));
      await ui.tap(tester, find.text('Save'));
      await ui.waitFor(tester, find.textContaining('Snooze saved.'));
      expect(
        (await store.records(personId: adult.id))
            .where((r) => r.itemId == item.id),
        isEmpty,
      );
      final sample = await const AndroidReminders().sampleClock();
      final projection = await store.prepareReminders(
        now: DateTime.now().toUtc(),
        observedZone: 'Europe/London',
        clockSample: sample,
        adapterFingerprint:
            (await const AndroidReminders().capabilities()).fingerprint,
      );
      final snooze = projection.desired.singleWhere(
        (r) =>
            r.kind == ReminderKind.snooze &&
            r.target.row.expectation.identity.planId == planId,
      );
      expect(
        snooze.target.row.expectation.identity,
        original.expectation.identity,
      );
      expect(snooze.target.row.expectation.identity.personId, adult.id);
      expect(
        snooze.deadlineMilliseconds - snooze.sample!.elapsedMilliseconds,
        300000,
      );
      expect(snooze.delayMinutes, 5);
      final replay = await store.snoozeReminder(
        SnoozeCommand(
          commandId: pending.commandId,
          target: pending.target,
          delayMinutes: 5,
          sample: snooze.sample!,
          observedZone: 'Europe/London',
        ),
        currentObservedZone: 'Europe/London',
      );
      expect(replay.alreadyCommitted, true);
      expect(replay.desired.requestToken, snooze.requestToken);

      final fresh = await row();
      final taken = await store.createReminderAction(
        target: await store.reminderTarget(
          fresh,
          observedZone: 'Europe/London',
        ),
        action: ReminderActionKind.taken,
        observedZone: 'Europe/London',
      );
      providers
          .read(routerProvider)
          .push('/reminders/action/${taken.envelopeId}');
      await ui.waitFor(tester, find.text('Taken'));
      await ui.tap(tester, find.text('Taken'));
      await ui.waitFor(tester, find.text('Saved'));
      final actual = (await store.records(personId: adult.id))
          .singleWhere((r) => r.itemId == item.id);
      expect(actual.personId, adult.id);
      expect(actual.originalEntry, '1.000');
      expect(actual.product!.volume, ExactAmount.parseEntry('1'));
      expect(actual.product!.components.map((component) => component.amount), [
        ExactAmount.parseEntry('3'),
        ExactAmount.parseEntry('7'),
      ]);
      expect((await row()).takenCount, 1);
      expect(
        (await store.pendingReminderActions()).where(
          (p) => p.envelopeId == taken.envelopeId,
        ),
        isEmpty,
      );
      final reopened = await RecordStore.open(
        path: location.path,
        key: location.key,
        isNew: false,
      );
      try {
        final persisted = (await reopened.records(personId: adult.id))
            .where((r) => r.itemId == item.id)
            .toList();
        expect(persisted.length, 1);
        expect(persisted.single.personId, adult.id);
      } finally {
        await reopened.close();
      }
    },
  );
}
