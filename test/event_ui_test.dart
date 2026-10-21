import 'fixtures/single_user.dart';

import 'dart:convert';

import 'package:true_grit_vital/ui/vital_ui.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart';
import 'package:true_grit_vital/platform/reminders.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/events/event_pages.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'stock_ui_test.dart' show item;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;
import 'daily_plan_ui_test.dart' show tap;

Finder field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);
Future<void> enter(WidgetTester tester, String label, String value) async {
  if (field(label).evaluate().isEmpty &&
      find.text('Details').evaluate().isNotEmpty) {
    await tap(tester, 'Details');
  }
  await waitForText(tester, label);
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), value);
  await settle(tester);
}

Future<EventRecord> seedEvent(
  RecordStore store,
  SubstanceItem substance, {
  String id = 'event',
  DateTime? from,
  List<EventMembership>? members,
}) async {
  final e = EventRecord(
    id: id,
    personId: substance.personId,
    name: 'Synthetic course $id',
    eventType: 'prescription',
    zoneId: 'Europe/London',
    revision: 1,
    plannedStart: EventDate.day(CivilDate(2026, 10, 1)),
    plannedEnd: EventDate.day(CivilDate(2026, 10, 25)),
    memberships:
        members ??
        [
          EventMembership(
            id: 'member-$id',
            itemId: substance.id,
            personId: substance.personId,
            effectiveFrom: from ?? DateTime.utc(2026, 10, 10),
            revision: 1,
          ),
        ],
  );
  final command = SaveEventCommand(
    commandId: newCommandId(),
    generation: store.generation,
    expectedRevision: null,
    expectedPersonRevision: (await store.profileById(substance.personId))!
        .revision,
    event: e,
  );
  return store.saveEvent(
    command,
    membershipReview: await store.previewEventMembership(command),
  );
}

Future<SavedDailyPlan> seedPlan(
  RecordStore store,
  SubstanceItem substance,
) async {
  final plan = DailyPlanVersion(
    personId: substance.personId,
    itemId: substance.id,
    planId: 'plan-${substance.id}',
    versionId: 'version-${substance.id}',
    start: CivilDate(2026, 10, 1),
    zoneBasis: FixedHome('Europe/London'),
    timing: DailyCount(
      1,
      PlannedAmount(quantity: ExactQuantity.parse('1'), unit: substance.unit),
    ),
  );
  return store.saveDailyPlan(
    commandId: newCommandId(),
    plan: plan,
    expectedPersonRevision: (await store.profileById(substance.personId))!
        .revision,
    expectedGeneration: store.generation,
  );
}

class EventDiagnosticsController extends ReminderController {
  EventDiagnosticsController(this.projection);
  final ReminderProjection projection;
  @override
  ReminderState build() => ReminderState(
    report: ReminderRepairReport(
      capabilities: const ReminderCapabilities(
        supported: true,
        notificationPermission: true,
        appEnabled: true,
        channelEnabled: true,
        exactAlarm: true,
        protectedStorageAvailable: true,
        bootIdentityAvailable: true,
        fingerprint: 'event-test',
      ),
      projection: projection,
    ),
  );
}

void main() {
  test('date parser keeps supplied precision and refuses missing zones and overflow', () {
    expect(
      parseEventDate('2021', partial: true)!.precision,
      EventDatePrecision.year,
    );
    expect(parseEventDate('2021-06', partial: true)!.value, '2021-06');
    expect(
      parseEventDate('Unknown', partial: true)!.precision,
      EventDatePrecision.unknown,
    );
    expect(parseEventDate(''), isNull);
    expect(() => parseEventDate('2026-02-30'), throwsA(anything));
    expect(() => parseEventDate('2026-02-30T12:00:00Z'), throwsA(anything));
    expect(() => parseEventDate('2026-10-19T12:00'), throwsA(anything));
    expect(() => parseEventDate('2026-10-19T12:00:99Z'), throwsA(anything));
    expect(
      () => parseEventDate('2026-10-19T12:00:00+01:99'),
      throwsA(anything),
    );
    expect(() => parseMembershipInstant('2026-10-19'), throwsA(anything));
    expect(
      parseMembershipInstant('2026-10-19T12:00:00+01:00'),
      DateTime.utc(2026, 10, 19, 11),
    );
  });
  appTest(
    'event creation retains fixed owner after browsing scope changes and separate bounds',
    (tester) async {
      final f = await launch(tester);
      final adult = (await runIo(
        tester,
        () => f.store.configureOwnProfile(
          commandId: newCommandId(),
          name: 'Another adult',
          adultConfirmed: true,
        ),
      ))!;
      await settle(tester);
      f.container.read(routerProvider).go('/event-create?person=${adult.id}');
      await settle(tester);
      await enter(tester, 'Event name', 'Named prescription');
      await enter(tester, 'Planned start', '2026-10-01');
      await enter(tester, 'Planned end', '2026-10-25');
      await enter(tester, 'Actual start', '2026-10-03');
      await runIo(
        tester,
        () => f.store.saveBrowsingScope(const FeedScope.me()),
      );
      await tap(tester, 'Review');
      await tap(tester, 'Save');
      await waitForText(tester, 'Named prescription');
      final e = (await runIo(tester, f.store.events))!.single;
      expect(e.personId, adult.id);
      expect(e.plannedStart!.value, '2026-10-01');
      expect(e.actualStart!.value, '2026-10-03');
      expect(e.completed, false);
      expect(await runIo(tester, f.store.records), isEmpty);
    },
  );
  appTest(
    'backdated membership preview can cancel then explicitly save historical inclusion',
    (tester) async {
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store)))!;
      final actual = (await runIo(
        tester,
        () => f.store.record(
          commandId: newCommandId(),
          itemId: i.id,
          expectedPersonRevision: 2,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 9, 12),
        ),
      ))!;
      await runIo(tester, () => seedEvent(f.store, i));
      f.container.read(routerProvider).go('/event/event/edit');
      await settle(tester);
      await enter(tester, 'Membership start', '2026-10-08T00:00:00Z');
      await tap(tester, 'Review');
      expect(find.text('Records included: 1'), findsOneWidget);
      expect(
        await runIo(tester, () => f.store.eventActuals(['event'])),
        isEmpty,
      );
      await tap(tester, 'Back');
      await tap(tester, 'Discard');
      expect(
        (await runIo(tester, () => f.store.eventById('event')))!.revision,
        1,
      );
      f.container.read(routerProvider).go('/event/event/edit');
      await settle(tester);
      await enter(tester, 'Membership start', '2026-10-08T00:00:00Z');
      await tap(tester, 'Review');
      await tap(tester, 'Save');
      await waitForText(tester, 'Event items');
      expect(
        (await runIo(tester, () => f.store.eventActuals(['event'])))!.single.id,
        actual.id,
      );
      expect(
        (await runIo(tester, () => f.store.history(actual.id)))!.length,
        1,
      );
      expect((await runIo(tester, f.store.records))!.length, 1);
    },
  );
  appTest(
    'overlap combined selection renders one actual and corrected time updates inclusion',
    (tester) async {
      final f = await launch(tester),
          i = (await runIo(tester, () => item(f.store)))!;
      final actual = (await runIo(
        tester,
        () => f.store.record(
          commandId: newCommandId(),
          itemId: i.id,
          expectedPersonRevision: 2,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 15, 12),
        ),
      ))!;
      await runIo(tester, () async {
        await seedEvent(f.store, i);
        await seedEvent(f.store, i, id: 'other');
      });
      f.container.read(routerProvider).go('/events');
      await settle(tester);
      await tap(tester, 'Select');
      await tap(tester, 'Select');
      expect(find.byType(RecordCard), findsOneWidget);
      await runIo(
        tester,
        () => f.store.correct(
          commandId: newCommandId(),
          recordId: actual.id,
          expectedRevision: actual.revision,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 9, 12),
          personId: meId,
          expectedPersonRevision: 2,
        ),
      );
      await settle(tester);
      expect(find.byType(RecordCard), findsNothing);
      expect((await runIo(tester, f.store.records))!.length, 1);
    },
  );
  appTest(
    'use periods preserve unknown and partial dates without changing plan or actual history',
    (tester) async {
      final f = await launch(tester),
          i = (await runIo(tester, () => item(f.store)))!;
      final p = (await runIo(tester, () => seedPlan(f.store, i)))!;
      f.container.read(routerProvider).go('/use/me/${i.id}/edit');
      await settle(tester);
      await enter(tester, 'Recorded start', 'Unknown');
      await tap(tester, 'Save');
      await waitForText(tester, 'Use history');
      var periods = (await runIo(
        tester,
        () => f.store.usePeriods(personId: meId, itemId: i.id),
      ))!;
      expect(periods.single.start.precision, EventDatePrecision.unknown);
      expect(periods.single.end, isNull);
      f.container
          .read(routerProvider)
          .go('/use/me/${i.id}/edit?period=${periods.single.id}');
      await settle(tester);
      await enter(tester, 'Recorded start', '2021-06');
      await enter(tester, 'Recorded end', '2022');
      await tap(tester, 'Save');
      await waitForText(tester, 'Use history');
      periods = (await runIo(
        tester,
        () => f.store.usePeriods(personId: meId, itemId: i.id),
      ))!;
      expect(periods.single.start.precision, EventDatePrecision.month);
      expect(periods.single.end!.precision, EventDatePrecision.year);
      expect(
        (await runIo(
          tester,
          () => f.store.dailyPlans(itemId: i.id),
        ))!.single.revision,
        p.revision,
      );
      expect(await runIo(tester, f.store.records), isEmpty);
    },
  );
  appTest(
    'dismiss leaves current plans and stock unchanged and item choices start empty',
    (tester) async {
      final f = await launch(tester),
          i = (await runIo(tester, () => item(f.store)))!;
      final p = (await runIo(tester, () => seedPlan(f.store, i)))!;
      await runIo(tester, () => seedEvent(f.store, i));
      f.container.read(routerProvider).go('/event/event/decision?item=${i.id}');
      await settle(tester);
      await waitForText(tester, 'Continue');
      final save = tester.widget<VitalButton>(
        find.widgetWithText(VitalButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      await settle(tester);
      expect(find.textContaining('Before:'), findsWidgets);
      await tap(tester, 'Continue');
      await tap(tester, 'Save');
      await waitForText(tester, 'Decision saved.');
      expect(
        (await runIo(
          tester,
          () => f.store.dailyPlans(itemId: i.id),
        ))!.single.revision,
        p.revision,
      );
      f.container.read(routerProvider).go('/event/event/decision');
      await settle(tester);
      await tap(tester, 'Dismiss');
      await waitForText(tester, 'Event items');
      expect(
        (await runIo(
          tester,
          () => f.store.eventById('event'),
        ))!.endReviewDismissed,
        true,
      );
      expect(
        (await runIo(
          tester,
          () => f.store.dailyPlans(itemId: i.id),
        ))!.single.revision,
        p.revision,
      );
      expect(await runIo(tester, f.store.records), isEmpty);
    },
  );
  appTest(
    'event invalid raw text survives lock with stable owner and operation',
    (tester) async {
      final f = await launch(tester, auth: FakeAuth());
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(routerProvider).go('/event-create?person=me');
      await settle(tester);
      await enter(tester, 'Event name', 'Private event');
      await enter(tester, 'Planned end', '2026-02-30');
      await tap(tester, 'Review');
      final before = (await runIo(tester, f.store.drafts))!.single;
      expect(before.fields['plannedEnd'], '2026-02-30');
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.resumed);
      await tap(tester, 'Unlock');
      expect(
        tester.widget<TextField>(field('Planned end')).controller!.text,
        '2026-02-30',
      );
      final after = (await runIo(tester, f.store.drafts))!.single;
      expect(after.operationId, before.operationId);
      expect(after.personId, meId);
      expect(jsonDecode(after.encode())['fields']['plannedEnd'], '2026-02-30');
    },
  );
  appTest(
    'explicit per-item stopping changes future plan eligibility after a reviewed next result',
    (tester) async {
      final f = await launch(tester),
          i = (await runIo(tester, () => item(f.store)))!;
      final plan = (await runIo(tester, () => seedPlan(f.store, i)))!;
      await runIo(tester, () => seedEvent(f.store, i));
      f.container.read(routerProvider).go('/event/event/decision?item=${i.id}');
      await waitForText(tester, 'Stop');
      await settle(tester);
      await tap(tester, 'Stop');
      expect(find.text('After: No current plan'), findsOneWidget);
      await tap(tester, 'Save');
      await waitForText(tester, 'Decision saved.');
      final current = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: i.id),
      ))!.single;
      expect(current.revision, plan.revision + 1);
      final phases = (await runIo(
        tester,
        () => f.store.phasePlan(planId: plan.plan.planId, personId: meId),
      ))!;
      expect(phases.end, isNotNull);
      expect(await runIo(tester, f.store.records), isEmpty);
    },
  );
  appTest('uncertain event save retries the frozen committed operation once', (
    tester,
  ) async {
    final f = await launch(tester);
    var writes = 0;
    final scoped = ProviderContainer(
      overrides: [
        // This container owns no store loader: the already opened fixture is
        // supplied through the parent and only the writer boundary is replaced.
        eventWriterProvider.overrideWithValue((command, review) async {
          writes++;
          await f.store.saveEvent(command, membershipReview: review);
          throw StateError('lost_response_after_commit');
        }),
      ],
      parent: f.container,
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scoped, child: const VitalApp()),
    );
    f.container.read(routerProvider).go('/event-create?person=me');
    await settle(tester);
    await enter(tester, 'Event name', 'Frozen retry');
    await tap(tester, 'Review');
    await tap(tester, 'Save');
    await waitForText(tester, 'Retry');
    expect((await runIo(tester, f.store.events))!.length, 1);
    await tap(tester, 'Retry');
    await waitForText(tester, 'Event items');
    expect(writes, 1);
    final event = (await runIo(tester, f.store.events))!.single;
    expect(
      (await runIo(tester, () => f.store.eventHistory(event.id)))!.length,
      1,
    );
  });
  appTest(
    'native event review stays private while locked and opens review without dose actions',
    (tester) async {
      final f = await launch(tester, auth: FakeAuth());
      final i = (await runIo(tester, () => item(f.store)))!;
      await runIo(tester, () async {
        await seedEvent(f.store, i);
        await f.container.read(appLockProvider.notifier).setEnabled(true);
        final projection = await f.store.prepareReminders(
          now: DateTime.utc(2026, 10, 19, 12),
          observedZone: 'Europe/London',
          clockSample: null,
          adapterFingerprint: 'event-widget',
        );
        final r = projection.eventEnds.single;
        await f.store.acknowledgeReminder(
          sequence: projection.sequence,
          generation: r.generation,
          requestToken: r.requestToken,
          intentRevision: r.eventRevision,
          receipt: ReminderReceipt.accepted,
          adapterFingerprint: 'event-widget',
        );
        expect(
          await f.store.captureEventEndAction(
            envelopeId: 'event-open',
            namespace: r.namespace,
            requestToken: r.requestToken,
            actionToken: r.requestToken,
            action: ReminderActionKind.open,
          ),
          true,
        );
        f.container
            .read(appLockProvider.notifier)
            .lifecycle(AppLifecycleState.inactive);
      });
      await settle(tester);
      expect(find.text('End review'), findsNothing);
      expect(find.text('Synthetic course event'), findsNothing);
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.resumed);
      await tap(tester, 'Unlock');
      await waitForText(tester, 'End review');
      expect(
        f.container.read(routerProvider).routerDelegate.state.uri.path,
        '/event/event/review',
      );
      expect(find.text('Taken'), findsNothing);
      expect(find.text('Snooze'), findsNothing);
      expect(await runIo(tester, f.store.records), isEmpty);
    },
  );
  appTest(
    'restored membership draft rehydrates its exact historical preview before Save',
    (tester) async {
      final f = await launch(tester),
          i = (await runIo(tester, () => item(f.store)))!;
      final actual = (await runIo(
        tester,
        () => f.store.record(
          commandId: newCommandId(),
          itemId: i.id,
          expectedPersonRevision: 2,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 9, 12),
        ),
      ))!;
      await runIo(tester, () => seedEvent(f.store, i));
      f.container.read(routerProvider).go('/event/event/edit');
      await settle(tester);
      await enter(tester, 'Membership start', '2026-10-08T00:00:00Z');
      await tap(tester, 'Review');
      expect(find.text('Records included: 1'), findsOneWidget);
      final draft = (await runIo(tester, f.store.drafts))!.single;
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      f.container.read(routerProvider).go(draft.route);
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump();
        expect(find.text('Records included: 0'), findsNothing);
      }
      await waitForText(tester, 'Records included: 1');
      expect(find.byType(RecordCard), findsOneWidget);
      expect(
        (await runIo(tester, f.store.drafts))!.single.operationId,
        draft.operationId,
      );
      await tap(tester, 'Save');
      await waitForText(tester, 'Event items');
      expect(
        (await runIo(tester, () => f.store.eventActuals(['event'])))!.single.id,
        actual.id,
      );
    },
  );
  test(
    'human references extend a shared prefix without exposing the full id',
    () {
      const first = 'abcdef000000000000000000000000000000000000000000',
          second = 'abcdef100000000000000000000000000000000000000000';
      expect(eventHumanReference(first, [first, second]), 'ABCDEF0');
      expect(eventHumanReference(second, [first, second]), 'ABCDEF1');
    },
  );
  appTest('same-name event items show useful details and membership uses its saved zone', (
    tester,
  ) async {
    final f = await launch(tester),
        first = (await runIo(
          tester,
          () => item(f.store, name: 'Shared source'),
        ))!;
    final second = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: 2,
        name: 'Shared source',
        form: 'liquid',
        unit: 'mg',
        type: 'Test',
      ),
    ))!;
    await runIo(
      tester,
      () => seedEvent(
        f.store,
        first,
        members: [
          for (final source in [first, second])
            EventMembership(
              id: newCommandId(),
              itemId: source.id,
              personId: meId,
              effectiveFrom: DateTime.utc(2026, 10, 10),
              revision: 1,
            ),
        ],
      ),
    );
    f.container.read(routerProvider).go('/event/event');
    await settle(tester);
    expect(
      find.text(
        'Item: Shared source · liquid · Test · mg · Entry ${eventHumanReference(first.id, [first.id, second.id])}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Item: Shared source · liquid · Test · mg · Entry ${eventHumanReference(second.id, [first.id, second.id])}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Membership: Saturday, 10 October 2026, 01:00, Europe/London (UTC+01:00) to Open (Europe/London).',
      ),
      findsNWidgets(2),
    );
    expect(find.textContaining(first.id), findsNothing);
    expect(find.textContaining(second.id), findsNothing);
    f.container.read(routerProvider).go('/event/event/edit');
    await settle(tester);
    expect(
      find.widgetWithText(
        VitalButton,
        'Item: Shared source · liquid · Test · mg · Entry ${eventHumanReference(first.id, [first.id, second.id])}',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(
        VitalButton,
        'Item: Shared source · liquid · Test · mg · Entry ${eventHumanReference(second.id, [first.id, second.id])}',
      ),
      findsOneWidget,
    );
    f.container.read(routerProvider).go('/event/event/review');
    await settle(tester);
    expect(
      find.text(
        'Item: Shared source · liquid · Test · mg · Entry ${eventHumanReference(first.id, [first.id, second.id])}',
      ),
      findsOneWidget,
    );
    expect(find.textContaining(first.id), findsNothing);
  });
  appTest('event reminder diagnostics name the affected event and adult', (
    tester,
  ) async {
    final f = await launch(tester);
    final owner = (await runIo(
      tester,
      () => f.store.configureOwnProfile(
        commandId: newCommandId(),
        name: 'Another adult',
        adultConfirmed: true,
      ),
    ))!;
    final i = (await runIo(tester, () => item(f.store, personId: owner.id)))!;
    await runIo(tester, () async {
      await seedEvent(f.store, i, id: 'first');
      await seedEvent(f.store, i, id: 'second');
    });
    final projection = ReminderProjection(
      generation: f.store.generation,
      namespace: 'test',
      sequence: 1,
      desired: [],
      obsoleteTokens: [],
      complete: false,
      coverage: [
        ReminderCoverage(
          scope: 'event:first',
          generation: f.store.generation,
          basis: 'Europe/London',
          adapterFingerprint: 'event-test',
          checkedAt: DateTime.utc(2026, 10, 19),
          complete: false,
        ),
      ],
      exclusions: [
        const ReminderExclusion(
          scope: 'event:first',
          reason: 'event_end_due',
          count: 1,
        ),
      ],
    );
    final scoped = ProviderContainer(
      parent: f.container,
      overrides: [
        remindersProvider.overrideWith(
          () => EventDiagnosticsController(projection),
        ),
      ],
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scoped, child: const VitalApp()),
    );
    f.container.read(routerProvider).go('/reminders');
    await settle(tester);
    expect(
      find.textContaining('Another adult: Synthetic course first'),
      findsWidgets,
    );
    expect(find.textContaining('Synthetic course second'), findsNothing);
    expect(
      find.text('This event has ended. Review which plans continue.'),
      findsOneWidget,
    );
  });
  appTest(
    'event zone and folded-boundary errors give repair steps and completion opens review',
    (tester) async {
      final f = await launch(tester);
      f.container.read(routerProvider).go('/event-create?person=me');
      await settle(tester);
      await enter(tester, 'Event name', 'Completed course');
      await enter(tester, 'Event zone', 'Europe/Lundon');
      await tap(tester, 'Review');
      await waitForText(
        tester,
        'Enter a valid IANA zone, such as Europe/London.',
      );
      expect(await runIo(tester, f.store.events), isEmpty);
      await enter(tester, 'Event zone', 'America/Havana');
      await enter(tester, 'Planned start', '2026-11-01');
      await tap(tester, 'Review');
      await waitForText(
        tester,
        'This date needs review. Enter an exact time with Z or an offset, check the event zone, then review again.',
      );
      await enter(tester, 'Event zone', 'Europe/London');
      await enter(tester, 'Planned start', '2026-10-01');
      await enter(tester, 'Planned end', '2026-10-25');
      await tap(tester, 'Completed');
      await tap(tester, 'Review');
      await tap(tester, 'Save');
      await waitForText(tester, 'End review');
      expect(
        f.container
            .read(routerProvider)
            .routerDelegate
            .state
            .uri
            .path
            .endsWith('/review'),
        true,
      );
      expect((await runIo(tester, f.store.events))!.single.completed, true);
      expect(await runIo(tester, f.store.records), isEmpty);
    },
  );
  for (final width in [320.0, 1200.0]) {
    appTest(
      'event form at width $width with double text keeps every field usable',
      (tester) async {
        tester.view.reset();
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final f = await launch(tester);
        f.container.read(routerProvider).go('/event-create?person=me');
        await settle(tester);
        await enter(
          tester,
          'Event name',
          'Long synthetic prescription name for layout',
        );
        await enter(tester, 'Planned end', '2026-10-25');
        await tap(tester, 'Review');
        await tap(tester, 'Save');
        await waitForText(tester, 'Event items');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
