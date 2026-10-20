import 'package:true_grit_vital/ui/vital_ui.dart';

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/reminders/reminder_pages.dart';
import 'package:true_grit_vital/features/profiles/profile_pages.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart'
    show DoseForm;
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/platform/reminders.dart';

import '../private_drafts_ui_test.dart' show FakeAuth;
import '../vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;

class UiGateway implements ReminderGateway {
  ReminderClockSample clock = ReminderClockSample(
    utcMilliseconds: DateTime.now().toUtc().millisecondsSinceEpoch,
    elapsedMilliseconds: 3600000,
    bootId: 'b1',
  );
  int permissions = 0;
  bool allowed = true;
  @override
  Future<ReminderCapabilities> capabilities() async => ReminderCapabilities(
    supported: true,
    notificationPermission: allowed,
    appEnabled: true,
    channelEnabled: true,
    exactAlarm: true,
    protectedStorageAvailable: true,
    bootIdentityAvailable: true,
    fingerprint: 'test-adapter',
  );
  @override
  Future<ReminderClockSample> sampleClock() async => clock;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<NativeReminderAction?> getInitialAction() async => null;
  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async => NativeReminderSnapshot(
    accepted: true,
    epoch: epoch,
    sequence: sequence,
    receipts: [
      for (final d in desired)
        NativeReminderReceipt(
          requestToken: d.requestToken,
          state: allowed
              ? NativeReminderState.accepted
              : NativeReminderState.failed,
          reason: allowed ? null : 'permission',
        ),
      for (final t in obsoleteTokens)
        NativeReminderReceipt(
          requestToken: t,
          state: NativeReminderState.cancelled,
        ),
    ],
    fingerprint: 'test-adapter',
  );
  @override
  Future<bool> requestNotifications() async {
    permissions++;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<
  ({
    RecordStore store,
    ProviderContainer container,
    PendingReminderAction? action,
  })
>
launch(
  WidgetTester tester, {
  bool unsupported = false,
  ReminderActionKind? action,
}) async {
  final dir = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-reminder-ui-'),
  ))!;
  final store = (await runIo(tester, () async {
    final store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    await store.editProfile(
      commandId: 'adult',
      personId: meId,
      expectedRevision: 1,
      name: 'Ada',
      adultConfirmed: true,
    );
    await store.saveBrowsingScope(const FeedScope.everyone());
    return store;
  }))!;
  PendingReminderAction? pending;
  if (action != null) {
    pending = await runIo(tester, () async {
      final item = await store.createItem(
        commandId: 'item',
        expectedPersonRevision: 2,
        name: 'Original substance',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      final date = CivilDate.fromDateTime(DateTime.now().toUtc());
      await store.saveDailyPlan(
        commandId: 'plan',
        expectedPersonRevision: 2,
        expectedGeneration: store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          itemId: item.id,
          planId: 'p1',
          versionId: 'v1',
          start: date,
          zoneBasis: const FollowingLocal(),
          timing: DailySlots([
            DailySlot(
              id: 'am',
              time: WallTime(12, 0),
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1.25'),
                unit: 'mg',
              ),
              reminderEnabled: false,
            ),
          ]),
        ),
      );
      await store.setPlanReminders(
        commandId: 'enable',
        planId: 'p1',
        personId: meId,
        expectedPlanRevision: 1,
        expectedPersonRevision: 2,
        enabled: true,
      );
      final row = (await store.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'Europe/London',
      )).rows.single;
      return store.createReminderAction(
        target: await store.reminderTarget(row, observedZone: 'Europe/London'),
        action: action,
        observedZone: 'Europe/London',
      );
    });
  }
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() async => store),
      appAuthGatewayProvider.overrideWithValue(FakeAuth()),
      reminderGatewayProvider.overrideWithValue(
        unsupported ? const UnsupportedReminders() : UiGateway(),
      ),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await runIo(tester, store.close);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
  container
      .read(routerProvider)
      .go(
        pending == null
            ? '/reminders'
            : '/reminders/action/${pending.envelopeId}',
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  await waitForText(tester, pending == null ? 'Reminders' : 'Person: Ada');
  return (store: store, container: container, action: pending);
}

void main() {
  appTest(
    'unsupported settings stay readable at narrow large text and never prompt',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await launch(tester, unsupported: true);
      expect(
        find.text(
          'Alerts are not available on this platform. Plans and records stay available.',
        ),
        findsOneWidget,
      );
      expect(find.text('Allow'), findsNothing);
      expect(find.text('Settings'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'S04 snooze has no hidden choice and samples accepted Save, no clinical write',
    (tester) async {
      final fixture = await launch(tester, action: ReminderActionKind.snooze);
      expect(
        find.text('Person: Ada'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(find.text('Original substance'), findsOneWidget);
      await tap(tester, 'Save');
      expect(
        (await runIo(
          tester,
          () => fixture.store.pendingReminderActions(),
        ))!.single.submitted,
        false,
      );
      await tap(tester, '15 minutes');
      final gateway =
          fixture.container.read(reminderGatewayProvider) as UiGateway;
      gateway.clock = ReminderClockSample(
        utcMilliseconds: gateway.clock.utcMilliseconds + 1200000,
        elapsedMilliseconds: 4800000,
        bootId: 'b1',
      );
      await tap(tester, 'Save');
      await waitForText(
        tester,
        'Snooze saved. Check reminder health to see whether the alert is prepared.',
      );
      expect(
        find.text(
          'Snooze saved. Check reminder health to see whether the alert is prepared.',
        ),
        findsOneWidget,
      );
      final projection = (await runIo(
        tester,
        () => fixture.store.prepareReminders(
          now: gateway.clock.utc,
          observedZone: 'Europe/London',
          clockSample: gateway.clock,
          adapterFingerprint: 'test-adapter',
        ),
      ))!;
      final snooze = projection.desired
          .where((d) => d.kind == ReminderKind.snooze)
          .single;
      expect(snooze.deadlineMilliseconds, 5700000);
      expect(snooze.target.row.expectation.identity.personId, meId);
      expect((await runIo(tester, () => fixture.store.records()))!, isEmpty);
    },
  );
  appTest(
    'Taken confirms original owner and replay creates one administration',
    (tester) async {
      final fixture = await launch(tester, action: ReminderActionKind.taken);
      expect(
        find.text('Person: Ada'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect((await runIo(tester, () => fixture.store.records()))!, isEmpty);
      await tap(tester, 'Taken');
      await waitForText(tester, 'Saved');
      expect(find.text('Saved'), findsOneWidget);
      final records = (await runIo(tester, () => fixture.store.records()))!;
      expect(records, hasLength(1));
      expect(records.single.personId, meId);
      expect(records.single.amount.scaled, 1250000);
      expect(
        (await runIo(tester, () => fixture.store.pendingReminderActions()))!,
        isEmpty,
      );
    },
  );
  appTest(
    'rapid custom edit then preset Save freezes the final deliberate choice',
    (tester) async {
      final fixture = await launch(tester, action: ReminderActionKind.snooze);
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, '37');
      await tester.enterText(field, '38');
      await tester.ensureVisible(find.text('5 minutes'));
      await tester.tap(find.text('5 minutes'));
      await tester.pump();
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      final saveButton = find.ancestor(
        of: find.text('Save'),
        matching: find.byType(VitalButton),
      );
      expect(tester.widget<VitalButton>(saveButton).onPressed, isNotNull);
      expect(saveButton.hitTestable(), findsOneWidget);
      await tester.tap(saveButton);
      try {
        await waitForText(
          tester,
          'Snooze saved. Check reminder health to see whether the alert is prepared.',
        );
      } catch (_) {
        final p = (await runIo(
          tester,
          () => fixture.store.pendingReminderActions(),
        ))!.single;
        final dynamic form = tester.state(find.byType(ReminderActionPage));
        final lock = fixture.container.read(appLockProvider);
        fail(
          'Displayed: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ')}; pending delay=${p.delayMinutes}, raw=${p.delayText}, submitted=${p.submitted}; selected=${form.selected}, busy=${form.busy}, stale=${form.stale}; lock ready=${lock.ready} locked=${lock.locked} busy=${lock.busy}',
        );
      }
      final gateway =
          fixture.container.read(reminderGatewayProvider) as UiGateway;
      final projection = (await runIo(
        tester,
        () => fixture.store.prepareReminders(
          now: gateway.clock.utc,
          observedZone: 'Europe/London',
          clockSample: gateway.clock,
          adapterFingerprint: 'test-adapter',
        ),
      ))!;
      expect(
        projection.desired
            .where((d) => d.kind == ReminderKind.snooze)
            .single
            .delayMinutes,
        5,
      );
      expect((await runIo(tester, () => fixture.store.records()))!, isEmpty);
    },
  );
  appTest('custom raw entry survives reopening without submitting', (
    tester,
  ) async {
    final fixture = await launch(tester, action: ReminderActionKind.snooze);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '007x');
    await settle(tester);
    final captured = (await runIo(
      tester,
      () => fixture.store.pendingReminderActions(),
    ))!.single;
    expect(captured.delayText, '007x');
    expect(captured.submitted, false);
    fixture.container.read(routerProvider).go('/today');
    await settle(tester);
    fixture.container
        .read(routerProvider)
        .push('/reminders/action/${fixture.action!.envelopeId}');
    await waitForText(tester, 'Snooze');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '007x',
    );
    await tap(tester, '5 minutes');
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '7');
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);
    var empty = (await runIo(
      tester,
      () => fixture.store.pendingReminderActions(),
    ))!.single;
    final checkpointStop = DateTime.now().add(const Duration(seconds: 5));
    while (empty.delayText != '' || empty.delayMinutes != null) {
      if (DateTime.now().isAfter(checkpointStop)) {
        final dynamic form = tester.state(find.byType(ReminderActionPage));
        fail(
          'Empty custom checkpoint did not settle: delay=${empty.delayMinutes}, raw=${empty.delayText}; selected=${form.selected}; text=${tester.widget<TextField>(find.byType(TextField)).controller!.text}',
        );
      }
      await settle(tester);
      empty = (await runIo(
        tester,
        () => fixture.store.pendingReminderActions(),
      ))!.single;
    }
    expect(empty.delayText, '');
    expect(empty.delayMinutes, isNull);
    fixture.container.read(routerProvider).go('/today');
    await settle(tester);
    fixture.container
        .read(routerProvider)
        .push('/reminders/action/${fixture.action!.envelopeId}');
    final fieldStop = DateTime.now().add(const Duration(seconds: 10));
    while (find.byType(TextField).evaluate().isEmpty) {
      if (DateTime.now().isAfter(fieldStop)) {
        fail('Reopened custom field did not render');
      }
      await settle(tester);
    }
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await tap(tester, 'Save');
    expect(
      (await runIo(
        tester,
        () => fixture.store.pendingReminderActions(),
      ))!.single.submitted,
      false,
    );
    expect((await runIo(tester, () => fixture.store.records()))!, isEmpty);
  });

  appTest('permission observation never prompts and explicit Allow requests once', (
    tester,
  ) async {
    final fixture = await launch(tester, action: ReminderActionKind.snooze);
    await tap(tester, 'Cancel');
    await tap(tester, 'Retry');
    final preparedStop = DateTime.now().add(const Duration(seconds: 10));
    while (fixture.container
            .read(remindersProvider)
            .report
            .projection
            ?.coverage
            .any((c) => c.preparedThrough != null) !=
        true) {
      if (DateTime.now().isAfter(preparedStop)) {
        final r = fixture.container.read(remindersProvider).report;
        fail(
          'Initial prepared evidence did not settle: revision=${r.revision}, seq=${r.projection?.sequence}, desired=${r.projection?.desired.map((d) => '${d.repairState}/${d.reason}').join(',')}, coverage=${r.projection?.coverage.map((c) => '${c.scope}/${c.reason}').join(',')}, failed=${r.failed}',
        );
      }
      await settle(tester);
    }
    while (fixture.container.read(remindersProvider).busy) {
      if (DateTime.now().isAfter(preparedStop)) {
        fail('Initial repair remained busy');
      }
      await settle(tester);
    }
    final gateway =
        fixture.container.read(reminderGatewayProvider) as UiGateway;
    gateway.allowed = false;
    fixture.container.read(remindersProvider.notifier).refresh();
    expect(fixture.container.read(remindersProvider).report.projection, isNull);
    try {
      await waitForText(tester, 'Allow');
    } catch (_) {
      final report = fixture.container.read(remindersProvider).report;
      fail(
        'Route=${fixture.container.read(routerProvider).routeInformationProvider.value.uri}; report permission=${report.capabilities?.notificationPermission}; profiles=${fixture.container.read(profilesProvider)}; lock=${fixture.container.read(appLockProvider).locked}; displayed=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ')}',
      );
    }

    expect(gateway.permissions, 0);
    await tap(tester, 'Retry');
    final retryStop = DateTime.now().add(const Duration(seconds: 10));
    while (fixture.container.read(remindersProvider).busy) {
      if (DateTime.now().isAfter(retryStop)) {
        fail('Explicit repair remained busy');
      }
      await settle(tester);
    }
    expect(
      fixture.container
              .read(remindersProvider)
              .report
              .projection
              ?.coverage
              .any((c) => c.preparedThrough != null) ??
          false,
      false,
    );
    expect(gateway.permissions, 0);
    await tap(tester, 'Allow');
    expect(gateway.permissions, 1);
    await settle(tester);
    expect(gateway.permissions, 1);
    expect(find.text('Allow'), findsOneWidget);
  });
  appTest(
    'new pending action preserves an unrelated imperatively pushed form',
    (tester) async {
      final fixture = await launch(tester, action: ReminderActionKind.snooze);
      await tap(tester, 'Cancel');
      final router = fixture.container.read(routerProvider);
      router.go('/today');
      await settle(tester);
      final original = fixture.action!.target.row.expectation;
      router.push('/record/${original.itemId}');
      final stop = DateTime.now().add(const Duration(seconds: 10));
      while (find.byType(DoseForm).evaluate().isEmpty) {
        if (DateTime.now().isAfter(stop)) fail('Dose form did not render');
        await settle(tester);
      }
      await settle(tester);
      final formState = tester.state(find.byType(DoseForm));
      final fieldStop = DateTime.now().add(const Duration(seconds: 10));
      while (find.byType(TextField).evaluate().isEmpty) {
        if (DateTime.now().isAfter(fieldStop)) {
          fail('Dose entry fields did not render');
        }
        await settle(tester);
      }
      final textField = find.byType(TextField).first;
      await tester.ensureVisible(textField);
      await tester.enterText(textField, '2.5');
      final entered = tester.widget<TextField>(textField).controller!.text;
      await runIo(tester, () async {
        final rows = await fixture.store.dailyRows(
          from: original.identity.originalDate,
          toExclusive: original.identity.originalDate.addDays(1),
          observedZone: 'Europe/London',
        );
        final target = await fixture.store.reminderTarget(
          rows.rows.single,
          observedZone: 'Europe/London',
        );
        await fixture.store.createReminderAction(
          target: target,
          action: ReminderActionKind.snooze,
          observedZone: 'Europe/London',
        );
      });
      await runIo(
        tester,
        () => fixture.container.read(remindersProvider.notifier).capture(),
      );
      await settle(tester);
      expect(
        router.routerDelegate.state.uri.path,
        '/record/${original.itemId}',
      );
      expect(identical(tester.state(find.byType(DoseForm)), formState), true);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        entered,
      );
      expect(find.text('A reminder is awaiting review.'), findsOneWidget);
      await tap(tester, 'Review');
      final actionStop = DateTime.now().add(const Duration(seconds: 10));
      while (find.byType(ReminderActionPage).evaluate().isEmpty) {
        if (DateTime.now().isAfter(actionStop)) {
          fail('Explicit review did not route');
        }
        await settle(tester);
      }
      expect(
        identical(
          tester.state(find.byType(DoseForm, skipOffstage: false)),
          formState,
        ),
        true,
      );
      expect((await runIo(tester, () => fixture.store.records()))!, isEmpty);
    },
  );
  appTest('generic open action rejects Taken after reminder off and on', (
    tester,
  ) async {
    final fixture = await launch(tester, action: ReminderActionKind.open);
    await runIo(tester, () async {
      await fixture.store.setPlanReminders(
        commandId: 'off-open',
        planId: 'p1',
        personId: meId,
        expectedPlanRevision: 1,
        expectedPersonRevision: 2,
        enabled: false,
      );
      await fixture.store.setPlanReminders(
        commandId: 'on-open',
        planId: 'p1',
        personId: meId,
        expectedPlanRevision: 1,
        expectedPersonRevision: 2,
        enabled: true,
      );
    });
    await tap(tester, 'Taken');
    await settle(tester);
    expect((await runIo(tester, () => fixture.store.records()))!, isEmpty);
    expect(
      (await runIo(
        tester,
        () => fixture.store.pendingReminderActions(),
      ))!.single.envelopeId,
      fixture.action!.envelopeId,
    );
  });
}
