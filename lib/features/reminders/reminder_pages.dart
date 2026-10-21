import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';
import '../../ui/stitch_ui.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/device_zone.dart';
import '../../app/reminders.dart';
import 'reminder_health_panel.dart';
import '../../app/settings_toggle_row.dart';
import '../../app/storage.dart';
import '../../app/vital_app.dart' show routerProvider;
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../plans/daily_feed.dart';
import '../plans/interval_review.dart';
import '../plans/interval_editor.dart';
import '../plans/plan_providers.dart';
import '../plans/plan_form.dart' show expectationLabel;
import '../profiles/profile_pages.dart'
    show profilesProvider, personLabel, ownerLabel;
import '../recording/record_pages.dart';
import '../events/event_pages.dart' show eventLookupProvider;

/// The host stays mounted through lock. Only its unlocked child exposes the
/// pending banner; navigation always pushes a separately owned captured form.
class ReminderHost extends ConsumerStatefulWidget {
  const ReminderHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<ReminderHost> createState() => _ReminderHostState();
}

class _ReminderHostState extends ConsumerState<ReminderHost> {
  final _opened = <String>{};
  late final GoRouter _router;
  bool _routeRefreshQueued = false;
  String get _path => _router.routerDelegate.currentConfiguration.isEmpty
      ? ''
      : _router.routerDelegate.state.uri.path;
  @override
  void initState() {
    super.initState();
    _router = ref.read(routerProvider);
    _router.routerDelegate.addListener(routeChanged);
  }

  void routeChanged() {
    if (_routeRefreshQueued) return;
    _routeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeRefreshQueued = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(routeChanged);
    super.dispose();
  }

  void open(PendingReminderAction pending) {
    _opened.add(pending.envelopeId);
    final location =
        '/reminders/action/${Uri.encodeComponent(pending.envelopeId)}';
    if (_path == location ||
        !ref
            .read(remindersProvider)
            .pending
            .any((p) => p.envelopeId == pending.envelopeId)) {
      return;
    }
    ref.read(routerProvider).push(location);
  }

  void openEvent(PendingEventEndReview pending) {
    _opened.add(pending.envelopeId);
    if (ref.read(appLockProvider).locked) return;
    ref
        .read(routerProvider)
        .push(
          '/event/${pending.eventId}/review?envelope=${Uri.encodeComponent(pending.envelopeId)}',
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remindersProvider),
        lock = ref.watch(appLockProvider);
    final t = AppLocalizations.of(context);
    final pending = state.pending.firstOrNull;
    final eventPending = state.eventPending.firstOrNull;
    final path = _path;
    if (pending != null &&
        path ==
            '/reminders/action/${Uri.encodeComponent(pending.envelopeId)}') {
      _opened.add(pending.envelopeId);
    }
    final unlocked = lock.ready && !lock.locked;
    if (unlocked &&
        pending != null &&
        eventPending == null &&
        !_opened.contains(pending.envelopeId) &&
        const [
          '/today',
          '/substances',
          '/events',
          '/history',
          '/appearance',
          '/reminders',
        ].contains(path)) {
      _opened.add(pending.envelopeId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !ref.read(appLockProvider).locked &&
            const [
              '/today',
              '/substances',
              '/events',
              '/history',
              '/appearance',
              '/reminders',
            ].contains(_path)) {
          open(pending);
        }
      });
    }
    if (unlocked &&
        eventPending != null &&
        !_opened.contains(eventPending.envelopeId) &&
        const [
          '/today',
          '/substances',
          '/events',
          '/history',
          '/appearance',
          '/reminders',
        ].contains(path)) {
      _opened.add(eventPending.envelopeId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ref.read(appLockProvider).locked) {
          openEvent(eventPending);
        }
      });
    }
    return Column(
      children: [
        if (unlocked && eventPending != null && !path.startsWith('/event/'))
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(t.eventEndReview),
                  VitalButton.secondary(
                    onPressed: () => openEvent(eventPending),
                    child: Text(t.review),
                  ),
                ],
              ),
            ),
          ),
        if (unlocked &&
            pending != null &&
            !path.startsWith('/reminders/action/'))
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(liveRegion: true, child: Text(t.reminderPending)),
                  VitalButton.secondary(
                    onPressed: () => open(pending),
                    child: Text(t.review),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        state = ref.watch(remindersProvider);
    final control = ref.read(remindersProvider.notifier), report = state.report;
    final c = report.capabilities;
    final profiles =
        ref.watch(profilesProvider).value ?? const <AdultProfile>[];
    String scopeLabel(String scope) {
      if (scope == 'everyone') return t.reminders;
      if (scope.startsWith('event:')) {
        final event = ref.watch(eventLookupProvider(scope.substring(6))).value;
        return event == null
            ? t.events
            : t.reminderScope(
                personLabel(t, profiles, event.personId),
                event.name,
              );
      }
      if (scope.startsWith('person:')) {
        final id = scope.substring(7);
        return personLabel(t, profiles, id);
      }
      if (scope.startsWith('plan:')) {
        final plan = ref
            .watch(scopePlansProvider(const FeedScope.everyone()))
            .value
            ?.where((p) => p.plan.planId == scope.substring(5))
            .firstOrNull
            ?.plan;
        if (plan != null) {
          final item = ref.watch(itemLookupProvider(plan.itemId)).value;
          return t.reminderScope(
            personLabel(t, profiles, plan.personId),
            item?.name ?? t.substances,
          );
        }
      }
      return t.schedule;
    }

    return EntryPage(
      children: [
        Heading(t.reminders),
        Text(t.reminderHelp),
        const SizedBox(height: 16),
        Text(t.reminderGeneric),
        Text(t.reminderDetailedUnavailable),
        const SizedBox(height: 16),
        if (c == null)
          Text(t.loadingRecords)
        else if (!c.supported)
          Text(t.reminderUnsupported)
        else ...[
          if (!c.protectedStorageAvailable) Text(t.reminderProtected),
          if (!c.notificationPermission) ...[
            Text(t.reminderPermission),
            VitalButton.secondary(
              onPressed: state.busy
                  ? null
                  : () => control.permission((g) => g.requestNotifications()),
              child: Text(t.reminderAllow),
            ),
          ],
          if (!c.appEnabled ||
              !c.channelEnabled ||
              !c.notificationPermission) ...[
            Text(t.reminderBlocked),
            VitalButton.secondary(
              onPressed: state.busy
                  ? null
                  : () =>
                        control.permission((g) => g.openNotificationSettings()),
              child: Text(t.reminderSettings),
            ),
          ],
          if (!c.exactAlarm) ...[
            Text(t.reminderExact),
            VitalButton.secondary(
              onPressed: state.busy
                  ? null
                  : () => control.permission((g) => g.openExactAlarmSettings()),
              child: Text(t.reminderSettings),
            ),
          ],
          if (!c.bootIdentityAvailable) Text(t.reminderClock),
          const SizedBox(height: 16),
          if (report.failed || state.actionFailed)
            Semantics(liveRegion: true, child: Text(t.reminderAttention)),
          ReminderHealthPanel(scopeLabel: scopeLabel, showBlockers: false),
          for (final excluded
              in report.projection?.exclusions ??
                  const <ReminderExclusion>[]) ...[
            const SizedBox(height: 12),
            Text(scopeLabel(excluded.scope)),
            Text(switch (excluded.reason) {
              'disabled' => t.reminderDisabled,
              'untimed' => t.reminderUntimed,
              'no_occurrences' => t.reminderNoOccurrences,
              'clock_review' => t.reminderClockReview,
              'elapsed_clock_recovery' => t.intervalClockHelp,
              'capacity' => t.reminderStateCapacity,
              'event_end_due' => t.eventDueReview,
              'work_limit' => t.reminderWorkLimit,
              _ => t.reminderIncomplete,
            }),
            Text(t.reminderExcludedCount(excluded.count)),
            if (excluded.reason == 'elapsed_clock_recovery')
              VitalButton.secondary(
                onPressed: () => context.go('/today'),
                child: Text(t.review),
              ),
          ],
          for (final d
              in report.projection?.attention ?? const <DesiredReminder>[]) ...[
            const SizedBox(height: 12),
            Text(
              t.reminderActionContext(
                ownerLabel(ref, t, d.target.row.expectation.identity.personId),
                d.target.row.itemName,
                d.target.row.expectation.amount.enteredText,
                d.target.row.expectation.amount.unit,
              ),
            ),
            Text(t.reminderRepairReason(reminderStateLabel(t, d.repairState))),
            if (d.repairState == ReminderRepairState.interrupted)
              Text(t.reminderInterrupted),
            DailySnoozeButton(row: d.target.row, refreshForReview: true),
          ],
        ],
        const SizedBox(height: 16),
        VitalButton.secondary(
          onPressed: state.busy ? null : control.retry,
          child: Text(t.retry),
        ),
        for (final event in <String, EventEndReminder>{
          for (final e in [
            ...?report.projection?.eventEnds,
            ...?report.projection?.eventEndAttention,
          ])
            e.requestToken: e,
        }.values) ...[
          const SizedBox(height: 16),
          Heading(t.eventEndReview),
          Text(
            ref.watch(eventLookupProvider(event.eventId)).value?.name ??
                t.events,
          ),
          Text(t.profileOwner(ownerLabel(ref, t, event.personId))),
          Text(
            t.eventReviewTime(displayStamp(context, ref, event.projectedUtc)),
          ),
          Text(
            t.reminderRepairReason(reminderStateLabel(t, event.repairState)),
          ),
          VitalButton.secondary(
            onPressed: () => context.push('/event/${event.eventId}/review'),
            child: Text(t.review),
          ),
        ],
        for (final pending in state.eventPending) ...[
          const SizedBox(height: 12),
          Text(t.eventEndReview),
          Text(t.profileOwner(ownerLabel(ref, t, pending.personId))),
          VitalButton.secondary(
            onPressed: () => context.push(
              '/event/${pending.eventId}/review?envelope=${Uri.encodeComponent(pending.envelopeId)}',
            ),
            child: Text(t.review),
          ),
        ],
        for (final pending in state.pending) ...[
          const SizedBox(height: 12),
          Text(
            t.reminderActionContext(
              ownerLabel(
                ref,
                t,
                pending.target.row.expectation.identity.personId,
              ),
              pending.target.row.itemName,
              pending.target.row.expectation.amount.enteredText,
              pending.target.row.expectation.amount.unit,
            ),
          ),
          VitalButton.secondary(
            onPressed: () => context.push(
              '/reminders/action/${Uri.encodeComponent(pending.envelopeId)}',
            ),
            child: Text(t.review),
          ),
        ],
      ],
    );
  }
}

String reminderStateLabel(AppLocalizations t, ReminderRepairState state) =>
    switch (state) {
      ReminderRepairState.pending => t.reminderStatePending,
      ReminderRepairState.prepared => t.reminderStatePrepared,
      ReminderRepairState.consumed => t.reminderStateConsumed,
      ReminderRepairState.cancelled => t.reminderStateCancelled,
      ReminderRepairState.postUncertain => t.reminderStatePostUncertain,
      ReminderRepairState.failed => t.reminderStateFailed,
      ReminderRepairState.unknown => t.reminderStateUnknown,
      ReminderRepairState.capacity => t.reminderStateCapacity,
      ReminderRepairState.interrupted => t.reminderSnoozeInterrupted,
      ReminderRepairState.expired => t.reminderStateExpired,
      ReminderRepairState.review => t.reminderStateReview,
    };

class DailySnoozeButton extends ConsumerStatefulWidget {
  const DailySnoozeButton({
    super.key,
    required this.row,
    this.refreshForReview = false,
    this.stitch = false,
    this.onUnavailable,
  });
  final DailyRow row;
  final bool refreshForReview;
  final bool stitch;
  final VoidCallback? onUnavailable;
  @override
  ConsumerState<DailySnoozeButton> createState() => _DailySnoozeButtonState();
}

class _DailySnoozeButtonState extends ConsumerState<DailySnoozeButton> {
  bool busy = false, failed = false;
  Future<void> start() async {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final store = await ref.read(recordStoreProvider.future),
          zone = ref.read(observedDeviceZoneProvider).value?.zoneId;
      var row = widget.row;
      if (widget.refreshForReview) {
        final identity = row.expectation.identity;
        final rows = await store.dailyRows(
          scope: FeedScope.person(identity.personId),
          from: identity.originalDate,
          toExclusive: identity.originalDate.addDays(1),
          observedZone: zone,
        );
        row = rows.rows.firstWhere((r) => r.expectation.identity == identity);
      }
      final target = await store.reminderTarget(row, observedZone: zone);
      final pending = await store.createReminderAction(
        target: target,
        action: ReminderActionKind.snooze,
        observedZone: zone,
      );
      if (mounted) {
        context.push(
          '/reminders/action/${Uri.encodeComponent(pending.envelopeId)}',
        );
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final enabled =
        ref
            .watch(
              _planReminderProvider(widget.row.expectation.identity.planId),
            )
            .value ==
        true;
    if (!enabled) {
      if (widget.onUnavailable != null) {
        return StitchButton(
          quiet: true,
          compact: true,
          icon: LucideIcons.alarmClock,
          onPressed: widget.onUnavailable,
          child: Text(t.snooze),
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlanCommand(
          row: widget.row,
          label: t.snooze,
          stitch: widget.stitch,
          onPressed: busy || widget.row.isResolved ? null : start,
        ),
        if (failed) Semantics(liveRegion: true, child: Text(t.reminderChanged)),
      ],
    );
  }
}

final _planReminderProvider = StreamProvider.autoDispose.family<bool, String>(
  retry: (_, _) => null,
  (ref, id) async* {
    final store = await ref.watch(recordStoreProvider.future);
    yield await store.planRemindersEnabled(id);
    await for (final _ in store.watchReminderChanges()) {
      yield await store.planRemindersEnabled(id);
    }
  },
);

class PlanReminderControl extends ConsumerStatefulWidget {
  const PlanReminderControl({super.key, required this.saved});
  final SavedDailyPlan saved;
  @override
  ConsumerState<PlanReminderControl> createState() =>
      _PlanReminderControlState();
}

class _PlanReminderControlState extends ConsumerState<PlanReminderControl> {
  bool busy = false, failed = false;
  Future<void> change(bool enabled) async {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      final p = widget.saved.plan;
      final owner = (await store.profiles())
          .where((v) => v.id == p.personId)
          .first;
      await store.setPlanReminders(
        commandId: newCommandId(),
        planId: p.planId,
        personId: p.personId,
        expectedPlanRevision: widget.saved.revision,
        expectedPersonRevision: owner.revision,
        enabled: enabled,
      );
      ref.invalidate(_planReminderProvider(p.planId));
      ref.read(remindersProvider.notifier).refresh();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), p = widget.saved.plan;
    final enabled = ref.watch(_planReminderProvider(p.planId));
    final capable =
        ref.watch(remindersProvider).report.capabilities?.supported == true;
    final owner = ownerLabel(ref, t, p.personId);
    bool hasTimes(DailyPlanVersion p) =>
        p.timing is DailySlots ||
        p.timing is ElapsedInterval ||
        p.timing is DailyWindows ||
        p.timing is MixedDailyCount;
    final phases = ref
        .watch(phaseDetailsProvider((plan: p.planId, person: p.personId)))
        .value;
    final timed = phases?.phases.any(hasTimes) ?? hasTimes(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsToggleRow(
          label: t.reminders,
          description: !timed
              ? t.reminderUntimed
              : !capable
              ? t.reminderUnsupported
              : t.reminderPlanHelp(owner),
          value: enabled.value ?? false,
          enabled:
              !busy &&
              enabled.hasValue &&
              ((timed && capable) || enabled.value == true),
          onChanged: change,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
        ),
        if (ref
                .watch(remindersProvider)
                .report
                .projection
                ?.exclusions
                .any(
                  (e) =>
                      e.scope == 'plan:${p.planId}' &&
                      e.reason == 'elapsed_clock_recovery',
                ) ==
            true)
          IntervalClockRecovery(saved: widget.saved),
        if (failed || enabled.hasError)
          Semantics(liveRegion: true, child: Text(t.saveFailure)),
        VitalButton.secondary(
          onPressed: () => context.push('/reminders'),
          child: Text(t.review),
        ),
      ],
    );
  }
}

class ReminderActionPage extends ConsumerStatefulWidget {
  const ReminderActionPage({super.key, required this.envelopeId});
  final String envelopeId;
  @override
  ConsumerState<ReminderActionPage> createState() => _ReminderActionPageState();
}

class _ReminderActionPageState extends ConsumerState<ReminderActionPage> {
  final custom = TextEditingController();
  final customFocus = FocusNode();
  PendingReminderAction? pending;
  bool loaded = false,
      busy = false,
      stale = false,
      saved = false,
      intervalReviewNeeded = false;
  String? error;
  int? selected;
  bool _changingChoice = false;
  String _lastControllerText = '';
  Future<void> _draftWrites = Future.value();
  void persistChoice({int? minutes, String? text, bool preset = false}) {
    final id = widget.envelopeId;
    final store = ref.read(recordStoreProvider.future);
    _draftWrites = _draftWrites
        .then((_) async {
          await (await store).updateReminderAction(
            id,
            delayMinutes: preset ? minutes : null,
            clearDelayMinutes: !preset,
            delayText: preset ? null : text,
            clearDelayText: preset,
          );
        })
        .catchError((Object _) {
          if (mounted) {
            setState(() => error = AppLocalizations.of(context).saveFailure);
          }
        });
  }

  @override
  void initState() {
    super.initState();
    custom.addListener(customChanged);
    customFocus.addListener(customFocused);
    scheduleMicrotask(load);
  }

  void customFocused() {
    if (!mounted ||
        !customFocus.hasFocus ||
        busy ||
        stale ||
        pending == null ||
        pending!.submitted) {
      return;
    }
    setState(() => selected = null);
    persistChoice(text: custom.text);
  }

  void customChanged() {
    final text = custom.text;
    if (text == _lastControllerText) return;
    _lastControllerText = text;
    if (!mounted ||
        !loaded ||
        busy ||
        stale ||
        _changingChoice ||
        pending == null ||
        pending!.submitted) {
      return;
    }
    setState(() => selected = null);
    persistChoice(text: text);
  }

  @override
  void dispose() {
    custom.dispose();
    customFocus.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final store = await ref.read(recordStoreProvider.future);
      final p = (await store.pendingReminderActions())
          .where((p) => p.envelopeId == widget.envelopeId)
          .firstOrNull;
      if (!mounted) return;
      pending = p;
      if (p != null) {
        if (p.delayText != null) {
          custom.text = p.delayText!;
        } else if (const [5, 10, 15, 30, 60].contains(p.delayMinutes)) {
          selected = p.delayMinutes;
        } else if (p.delayMinutes != null) {
          custom.text = '${p.delayMinutes}';
        }
        if (!p.submitted) {
          try {
            await store.validateReminderTarget(
              p.target,
              observedZone: ref.read(observedDeviceZoneProvider).value?.zoneId,
            );
          } catch (_) {
            stale = true;
          }
        }
      }
    } catch (_) {
      if (mounted) error = AppLocalizations.of(context).saveFailure;
    }
    if (mounted) setState(() => loaded = true);
  }

  Future<void> choose(int? minutes) async {
    if (busy || pending == null || pending!.submitted) return;
    customFocus.unfocus();
    setState(() {
      selected = minutes;
      if (minutes != null) {
        _changingChoice = true;
        custom.clear();
        _changingChoice = false;
      }
    });
    if (minutes != null) {
      persistChoice(minutes: minutes, preset: true);
      await _draftWrites;
    }
  }

  Future<void> submit() async {
    final p = pending;
    if (p == null || busy || stale) return;
    final lock = ref.read(appLockProvider);
    if (!lock.ready || lock.locked || lock.busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await _draftWrites;
      final store = await ref.read(recordStoreProvider.future);
      final zone = ref.read(observedDeviceZoneProvider).value?.zoneId;
      if (!p.submitted) {
        if (p.action == ReminderActionKind.snooze) {
          final minutes = selected ?? int.tryParse(custom.text.trim());
          if (minutes == null ||
              minutes <= 0 ||
              !RegExp(
                r'^\d+$',
              ).hasMatch(selected == null ? custom.text.trim() : '$selected')) {
            throw const FormatException('delay');
          }
          // Save samples once, after selection and authentication. The encrypted
          // submission is immutable before any domain command is attempted.
          final sample = await ref.read(reminderGatewayProvider).sampleClock();
          await store.updateReminderAction(
            p.envelopeId,
            delayMinutes: minutes,
            delayText: selected == null ? custom.text.trim() : null,
            clearDelayText: selected != null,
            sample: sample,
            observedZone: zone,
            submit: true,
          );
        } else {
          final intervalSample =
              p.action == ReminderActionKind.taken &&
                  p.target.row.expectation.identity.intervalSegmentId != null
              ? await ref.read(reminderGatewayProvider).sampleClock()
              : null;
          await store.updateReminderAction(
            p.envelopeId,
            sample: intervalSample,
            actualAt: p.action == ReminderActionKind.taken
                ? intervalSample?.utc ?? DateTime.now().toUtc()
                : null,
            observedZone: zone,
            submit: true,
          );
        }
      }
      final captured = (await store.pendingReminderActions()).firstWhere(
        (v) => v.envelopeId == p.envelopeId,
      );
      if (mounted) pending = captured;
      if (captured.action == ReminderActionKind.snooze) {
        await store.snoozeReminder(
          SnoozeCommand(
            commandId: captured.commandId,
            target: captured.target,
            delayMinutes: captured.delayMinutes!,
            sample: captured.sample!,
            observedZone: captured.observedZone,
          ),
          currentObservedZone: zone,
        );
      } else if (captured.action != ReminderActionKind.open) {
        await store.actDaily(
          commandId: captured.commandId,
          row: captured.target.row,
          reminderTarget: captured.target,
          reminderObservedZone: zone,
          kind: captured.action == ReminderActionKind.taken
              ? DailyActionKind.taken
              : DailyActionKind.skip,
          actualAt: captured.actualAt,
          intervalClockSample: captured.sample,
        );
      }
      await store.acknowledgeReminderAction(captured.envelopeId);
      ref.read(remindersProvider.notifier).completePending(captured.envelopeId);
      if (mounted) setState(() => saved = true);
    } catch (e) {
      if (mounted) {
        if (e is FormatException) customFocus.requestFocus();
        setState(() {
          if (e is CommandConflict && e.code != 'app_locked') stale = true;
          intervalReviewNeeded =
              e is CommandConflict && e.code == 'interval_actual_review';
          error = intervalReviewNeeded
              ? AppLocalizations.of(context).intervalEarlierReview
              : e is FormatException
              ? AppLocalizations.of(context).reminderCustomHelp
              : e is CommandConflict && e.code != 'app_locked'
              ? AppLocalizations.of(context).reminderChanged
              : AppLocalizations.of(context).saveFailure;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> recordEarlier() async {
    final p = pending;
    if (p == null || busy || !intervalReviewNeeded) return;
    setState(() => busy = true);
    try {
      await (await ref.read(recordStoreProvider.future))
          .acknowledgeReminderAction(p.envelopeId);
      ref.read(remindersProvider.notifier).completePending(p.envelopeId);
      if (mounted) context.push('/record/${p.target.row.expectation.itemId}');
    } catch (_) {
      if (mounted) {
        setState(() => error = AppLocalizations.of(context).saveFailure);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    if (busy || pending?.submitted == true) return;
    try {
      await _draftWrites;
      await (await ref.read(recordStoreProvider.future))
          .acknowledgeReminderAction(widget.envelopeId);
      ref.read(remindersProvider.notifier).completePending(widget.envelopeId);
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/reminders');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = AppLocalizations.of(context).saveFailure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), p = pending;
    if (!loaded) return EntryPage(children: [Text(t.loadingRecords)]);
    if (p == null) {
      return EntryPage(
        children: [Heading(t.reminders), Text(error ?? t.reminderUnavailable)],
      );
    }
    final snooze = p.action == ReminderActionKind.snooze;
    final canSnooze =
        ref
            .watch(remindersProvider)
            .report
            .capabilities
            ?.bootIdentityAvailable ==
        true;
    return EntryPage(
      children: [
        Heading(snooze ? t.snooze : t.reminders),
        Text(
          t.profileOwner(
            ownerLabel(ref, t, p.target.row.expectation.identity.personId),
          ),
        ),
        Text(p.target.row.itemName),
        Text(expectationLabel(context, ref, t, p.target.row.expectation)),
        if (p.action == ReminderActionKind.taken &&
            p.target.row.expectation.identity.sourceActualId != null)
          Text(t.intervalTakenHelp),
        if (p.action == ReminderActionKind.open && !stale && !saved)
          DailyRowCard(row: p.target.row, reminderTarget: p.target),
        if (saved) ...[
          Semantics(
            liveRegion: true,
            child: Text(snooze ? t.reminderSaved : t.saved),
          ),
          if (p.action == ReminderActionKind.taken &&
              p.target.row.expectation.identity.sourceActualId != null)
            ref
                .watch(itemPlansProvider(p.target.row.expectation.itemId))
                .when(
                  loading: () => Text(t.loadingRecords),
                  error: (_, _) => LoadFailure(
                    onRetry: () => ref.invalidate(
                      itemPlansProvider(p.target.row.expectation.itemId),
                    ),
                  ),
                  data: (plans) {
                    final plan = plans
                        .where(
                          (s) =>
                              s.plan.planId ==
                              p.target.row.expectation.identity.planId,
                        )
                        .firstOrNull
                        ?.plan;
                    if (plan == null) return Text(t.planNextReview);
                    final zone = plan.zoneBasis is FixedHome
                        ? (plan.zoneBasis as FixedHome).zoneId
                        : ref.watch(observedDeviceZoneProvider).value?.zoneId;
                    return zone == null
                        ? Text(t.planZoneUnavailable)
                        : IntervalPlanPreview(plan: plan, observedZone: zone);
                  },
                ),
          VitalButton.secondary(
            onPressed: () => context.push('/reminders'),
            child: Text(t.review),
          ),
        ] else ...[
          if (stale && !intervalReviewNeeded) Text(t.reminderChanged),
          if (intervalReviewNeeded)
            VitalButton.secondary(
              onPressed: busy ? null : recordEarlier,
              child: Text(t.record),
            ),
          if (p.submitted) Text(t.reminderSubmitted),
          if (snooze) ...[
            const SizedBox(height: 16),
            Text(t.reminderSnoozeHelp),
            Text(t.reminderDelay),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in const [5, 10, 15, 30, 60])
                  Semantics(
                    selected: selected == minutes,
                    child: VitalButton.secondary(
                      multiline: true,
                      onPressed: busy || stale || p.submitted
                          ? null
                          : () => choose(minutes),
                      child: Text(t.reminderMinutes(minutes)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(t.reminderCustom),
            Semantics(
              label: t.reminderCustom,
              child: TextField(
                controller: custom,
                focusNode: customFocus,
                enabled: !busy && !stale && !p.submitted,
                keyboardType: TextInputType.number,
              ),
            ),
            Semantics(
              liveRegion: error == t.reminderCustomHelp,
              child: Text(t.reminderCustomHelp),
            ),
            if (!canSnooze) Text(t.reminderClock),
          ],
          if (error != null && error != t.reminderCustomHelp)
            Semantics(liveRegion: true, child: Text(error!)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (!stale)
                VitalButton(
                  onPressed: busy || (snooze && !canSnooze && !p.submitted)
                      ? null
                      : submit,
                  child: Text(
                    p.submitted
                        ? t.retry
                        : snooze
                        ? t.save
                        : p.action == ReminderActionKind.taken
                        ? t.taken
                        : p.action == ReminderActionKind.skip
                        ? t.skip
                        : t.reminderDone,
                  ),
                ),
              if (!p.submitted)
                VitalButton.secondary(
                  onPressed: busy ? null : cancel,
                  child: Text(t.cancel),
                ),
              if (stale)
                VitalButton.secondary(
                  onPressed: () => context.push(
                    '/schedule/${p.target.row.expectation.itemId}?plan=${p.target.row.expectation.identity.planId}',
                  ),
                  child: Text(t.review),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
