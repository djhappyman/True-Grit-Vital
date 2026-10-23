import '../../app/display_preferences.dart';
import '../../app/settings_toggle_row.dart';
import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'calendar_editor.dart';
import 'interval_clock.dart';
import 'interval_editor.dart';
import 'plan_form.dart';
import 'plan_providers.dart';

/// Raw entries are retained separately from validated calendar blocks.
class OnOffFormFields {
  bool enabled = false;
  final on = TextEditingController(),
      off = TextEditingController(),
      anchor = TextEditingController();
  List<TextEditingController> get controllers => [on, off, anchor];
  Map<String, String> capture() => {
    'blockEnabled': '$enabled',
    'blockOn': on.text,
    'blockOff': off.text,
    'blockAnchor': anchor.text,
  };
  void restore(Map<String, String> f) {
    enabled = f['blockEnabled'] == 'true';
    on.text = f['blockOn'] ?? '';
    off.text = f['blockOff'] ?? '';
    anchor.text = f['blockAnchor'] ?? '';
  }

  void load(OnOffPattern? p) {
    enabled = p != null;
    on.text = p == null ? '' : '${p.onDays}';
    off.text = p == null ? '' : '${p.offDays}';
    anchor.text = p?.anchor.toString() ?? '';
  }

  OnOffPattern? candidate() => !enabled
      ? null
      : OnOffPattern(
          anchor: CivilDate.parse(anchor.text.trim()),
          onDays: int.parse(on.text.trim()),
          offDays: int.parse(off.text.trim()),
        );
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

class OnOffEditor extends StatelessWidget {
  const OnOffEditor({
    super.key,
    required this.fields,
    required this.enabled,
    required this.onChanged,
  });
  final OnOffFormFields fields;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), f = fields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsToggleRow(
          label: t.simpleScheduleBreaks,
          description: t.simpleScheduleBreakHelp,
          value: f.enabled,
          enabled: enabled,
          reduceMotion: VitalMotion.reduced(context),
          onChanged: (value) {
            f.enabled = value;
            onChanged();
          },
        ),
        if (f.enabled) ...[
          Text(
            t.simpleScheduleBreakDates,
            style: VitalType.metadata.copyWith(
              color: VitalColors(context).muted,
            ),
          ),
          VitalRepeatStepper(
            label: t.pauseOnDays,
            controller: f.on,
            enabled: enabled,
            max: 9999,
          ),
          VitalRepeatStepper(
            label: t.pauseOffDays,
            controller: f.off,
            enabled: enabled,
            max: 9999,
          ),
          LabelledInput(
            picker: VitalPickerKind.date,
            key: const ValueKey('blockAnchor'),
            label: t.pauseBlockAnchor,
            helper: t.dateExample,
            controller: f.anchor,
            enabled: enabled,
            keyboardType: TextInputType.datetime,
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

DateTime parsePauseInstant(String text) {
  // Reuse the offset and calendar validation used by the interval form.
  final fields = IntervalFormFields();
  try {
    fields.duration.text = '1';
    fields.anchor.text = text;
    return fields
        .candidate(
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'count'),
        )
        .plannedAnchor!;
  } finally {
    fields.dispose();
  }
}

DailyPlanVersion pauseCandidate(
  DailyPlanVersion p, {
  required String versionId,
  required DateTime instant,
  required String choice,
  required String restartAnchor,
}) {
  final open = p.pauses.where((v) => v.resume == null).firstOrNull;
  var timing = p.timing;
  var calendar = p.calendar;
  var block = p.onOff;
  if (open != null && choice != 'preserve' && choice != 'restart') {
    throw const FormatException('resume_choice');
  }
  if (open != null && choice == 'restart') {
    if (timing case final ElapsedInterval interval) {
      if (interval.mode == IntervalMode.qualifyingActual) {
        throw const FormatException('actual_restart_requires_mode_review');
      }
      timing = ElapsedInterval(
        segmentId: versionId,
        duration: interval.duration,
        mode: interval.mode,
        amount: interval.amount,
        plannedAnchor: parsePauseInstant(restartAnchor),
        reminderEnabled: interval.reminderEnabled,
      );
    } else {
      final anchor = CivilDate.parse(restartAnchor.trim());
      calendar = switch (calendar) {
        EveryNDays(:final interval) => EveryNDays(
          anchor: anchor,
          interval: interval,
        ),
        EveryNWeeks(:final interval, :final weekdays) => EveryNWeeks(
          anchorWeekStart: anchor,
          interval: interval,
          weekdays: weekdays,
        ),
        EveryNMonths(:final interval, :final selector) => EveryNMonths(
          anchorMonth: anchor,
          interval: interval,
          selector: selector,
        ),
        _ => calendar,
      };
      if (block != null) {
        block = OnOffPattern(
          anchor: anchor,
          onDays: block.onDays,
          offDays: block.offDays,
        );
      }
    }
  }
  return DailyPlanVersion(
    personId: p.personId,
    itemId: p.itemId,
    planId: p.planId,
    versionId: versionId,
    start: p.start,
    endExclusive: p.endExclusive,
    effectiveFrom: p.effectiveFrom,
    effectiveUntil: p.effectiveUntil,
    timing: timing,
    zoneBasis: p.zoneBasis,
    calendar: calendar,
    onOff: block,
    instructions: p.instructions,
    timingPolicy: p.timingPolicy,
    requirements: p.requirements,
    doseDisplay: p.doseDisplay,
    stopCondition: p.stopCondition,
    pauses: open == null
        ? [...p.pauses, PlanPause(start: instant)]
        : [
            for (final pause in p.pauses)
              identical(pause, open)
                  ? PlanPause(start: pause.start, resume: instant)
                  : pause,
          ],
  );
}

typedef PauseWriter = Future<void> Function(
  String commandId,
  PauseChangeReview review,
  ReminderClockSample? sample,
);
final pauseWriterProvider = Provider<PauseWriter>(
  (ref) => (command, review, sample) async {
    await (await ref.read(recordStoreProvider.future)).savePauseChange(
      commandId: command,
      review: review,
      intervalClockSample: sample,
    );
  },
);

class PausePlanForm extends ConsumerStatefulWidget {
  const PausePlanForm({super.key, required this.itemId, required this.planId});
  final String itemId, planId;
  @override
  ConsumerState<PausePlanForm> createState() => _PausePlanFormState();
}

class _PausePlanFormState extends DurableFormState<PausePlanForm> {
  SavedDailyPlan? saved;
  AdultProfile? owner;
  final instant = TextEditingController(), anchor = TextEditingController();
  String versionId = newCommandId(), choice = '';
  PauseChangeReview? review;
  ReminderClockSample? sample;
  DateTime? reviewedAt;
  String? reviewedZone;
  bool initialised = false, previewing = false;
  int historyLimit = 50;
  @override
  DraftKind get entryKind => DraftKind.pausePlan;
  @override
  String? get entryPerson => owner?.id;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String get entryTarget => widget.itemId;
  @override
  int? get entryTargetRevision => saved?.revision;
  @override
  Map<String, String> captureEntry() => {
    'planId': widget.planId,
    'versionId': versionId,
    'pauseInstant': instant.text,
    'resumeChoice': choice,
    'restartAnchor': anchor.text,
    'intervalClockSample': encodeIntervalClock(sample),
    'reviewedAt': reviewedAt?.toIso8601String() ?? '',
    'reviewedZone': reviewedZone ?? '',
  };
  @override
  void restoreEntry(Map<String, String> f) {
    if (f['planId'] != widget.planId) {
      conflict = true;
      return;
    }
    versionId = f['versionId']!;
    instant.text = f['pauseInstant'] ?? '';
    choice = f['resumeChoice'] ?? '';
    anchor.text = f['restartAnchor'] ?? '';
    sample = decodeIntervalClock(f['intervalClockSample']);
    reviewedAt = DateTime.tryParse(f['reviewedAt'] ?? '');
    reviewedZone = f['reviewedZone'];
  }

  @override
  void initState() {
    super.initState();
    instant.text = DateTime.now().toUtc().toIso8601String();
    instant.addListener(changed);
    anchor.addListener(changed);
  }

  void changed() {
    review = null;
    if (!uncertain) {
      sample = null;
      reviewedAt = null;
      reviewedZone = null;
    }
    entryChanged();
    if (mounted && draftReady) setState(() {});
  }

  @override
  void dispose() {
    instant.dispose();
    anchor.dispose();
    super.dispose();
  }

  Future<void> preview() async {
    setState(() {
      previewing = true;
      error = null;
    });
    try {
      final p = saved!.plan;
      final zone = uncertain && reviewedZone?.isNotEmpty == true
          ? reviewedZone
          : p.zoneBasis is FixedHome
          ? (p.zoneBasis as FixedHome).zoneId
          : ref.read(observedDeviceZoneProvider).value?.zoneId;
      if (zone == null) throw const FormatException();
      final proposed = pauseCandidate(
        p,
        versionId: versionId,
        instant: parsePauseInstant(instant.text.trim()),
        choice: choice,
        restartAnchor: anchor.text,
      );
      final store = await ref.read(recordStoreProvider.future);
      final result = await store.previewPauseChange(
        plan: saved!,
        proposed: proposed,
        now: reviewedAt ??= DateTime.now().toUtc(),
        observedZone: zone,
        restartAt: choice == 'restart'
            ? parsePauseInstant(instant.text.trim())
            : null,
      );
      reviewedZone = zone;
      if (mounted) setState(() => review = result);
    } catch (_) {
      if (mounted) {
        setState(() => error = AppLocalizations.of(context).pauseInvalid);
      }
    } finally {
      if (mounted) setState(() => previewing = false);
    }
  }

  Future<void> save() async {
    if (review == null) {
      await preview();
      if (review == null) return;
    }
    final r = review!;
    if (choice == 'restart' &&
        r.proposed.timing is ElapsedInterval &&
        sample == null &&
        !uncertain) {
      setState(() => busy = true);
      try {
        sample = await captureIntervalClock(ref);
      } catch (_) {
        if (mounted) {
          setState(() => error = AppLocalizations.of(context).saveFailure);
        }
        return;
      } finally {
        if (mounted) setState(() => busy = false);
      }
      if (!mounted) return;
    }
    await commit((command) async {
      await ref.read(pauseWriterProvider)(command, r, sample);
      ref.invalidate(itemPlansProvider);
      ref.invalidate(scopePlansProvider);
      ref.invalidate(dailyFeedProvider);
      ref.invalidate(nextDailyPlansProvider);
    }, successPath: '/today');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    ref.listen(observedDeviceZoneProvider, (before, after) {
      if (before?.value?.zoneId != after.value?.zoneId &&
          !uncertain &&
          !busy &&
          review != null) {
        setState(() => review = null);
      }
    });
    final plans = ref.watch(itemPlansProvider(widget.itemId));
    final people = ref.watch(profilesProvider);
    final item = ref.watch(itemLookupProvider(widget.itemId));
    if (!plans.hasValue ||
        !people.hasValue ||
        !item.hasValue ||
        !initialised &&
            (plans.isLoading || people.isLoading || item.isLoading)) {
      return EntryPage(
        children: [
          if (plans.hasError || people.hasError || item.hasError)
            LoadFailure(
              onRetry: () {
                ref.invalidate(itemPlansProvider(widget.itemId));
                ref.invalidate(profilesProvider);
                ref.invalidate(itemLookupProvider(widget.itemId));
              },
            )
          else
            Text(t.loadingRecords),
        ],
      );
    }
    if (!initialised) {
      saved = plans.value!
          .where(
            (s) =>
                s.plan.planId == widget.planId &&
                s.plan.itemId == widget.itemId &&
                s.plan.personId == item.value?.personId,
          )
          .firstOrNull;
      owner = people.value!
          .where((p) => p.id == saved?.plan.personId)
          .firstOrNull;
      initialised = true;
    }
    if (saved == null || owner == null || item.value == null) {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final p = saved!.plan,
        open = p.pauses.where((v) => v.resume == null).firstOrNull;
    final valid = people.value!.any(
      (v) =>
          v.id == owner!.id &&
          !v.isArchived &&
          v.revision == capturedPersonRevision,
    );
    final enabled = valid && !busy && !uncertain && !conflict && !previewing;
    final canRestart =
        p.onOff != null ||
        p.calendar is EveryNDays ||
        p.calendar is EveryNWeeks ||
        p.calendar is EveryNMonths ||
        p.timing is ElapsedInterval;
    final actual =
        p.timing is ElapsedInterval &&
        (p.timing as ElapsedInterval).mode == IntervalMode.qualifyingActual;
    return wrap([
      Heading(open == null ? t.pauseHeading : t.pauseResume),
      Text(t.profileOwner(ownerLabel(ref, t, owner!.id))),
      Text(item.value!.name),
      Text(t.pauseConsequence),
      if (!valid) Text(t.profileChanged),
      LabelledInput(
        picker: VitalPickerKind.instant,
        key: const ValueKey('pauseInstant'),
        label: open == null ? t.pauseStart : t.pauseResumeAt,
        helper: t.intervalAnchorHelp,
        controller: instant,
        enabled: enabled,
        keyboardType: TextInputType.datetime,
      ),
      if (open != null) ...[
        Text(t.pauseChoice),
        CalendarChoices(
          value: choice,
          enabled: enabled,
          choices: [
            ('preserve', t.pausePreserve),
            if (!actual && canRestart) ('restart', t.pauseRestart),
          ],
          onSelected: (v) {
            choice = v;
            changed();
          },
        ),
        Text(choice == 'restart' ? t.pauseRestartHelp : t.pausePreserveHelp),
        if (choice == 'restart')
          LabelledInput(
            picker: p.timing is ElapsedInterval
                ? VitalPickerKind.instant
                : VitalPickerKind.date,
            key: const ValueKey('restartAnchor'),
            label: p.timing is ElapsedInterval
                ? t.intervalAnchor
                : t.pauseNewAnchor,
            controller: anchor,
            enabled: enabled,
            helper: p.timing is ElapsedInterval
                ? t.intervalAnchorHelp
                : t.pauseDateHelp,
            keyboardType: TextInputType.datetime,
          ),
        if (actual) ...[
          Text(t.pauseActualHelp),
          VitalButton.secondary(
            onPressed: enabled ? () => context.push('/item/${p.itemId}') : null,
            child: Text(t.review),
          ),
          VitalButton.secondary(
            onPressed: enabled
                ? () => context.push('/schedule/${p.itemId}?plan=${p.planId}')
                : null,
            child: Text(t.edit),
          ),
        ],
      ],
      ?failure(),
      VitalButton.secondary(
        onPressed: enabled ? preview : null,
        child: Text(t.planPreview),
      ),
      if (review case final r?) ...[
        Heading(t.planPreview),
        VitalButton.secondary(
          onPressed: enabled ? () => setState(() => review = null) : null,
          child: Text(t.cancel),
        ),
        Text(t.pauseBoundary(instant.text.trim())),
        if (r.proposed.pauses.any((p) => p.contains(r.now))) Text(t.pauseState),
        Text(
          t.pauseBefore(
            pauseNextLabel(
              context,
              ref,
              t,
              r.plan.plan,
              r.before,
              r.beforeDate,
              r.observedZone,
            ),
          ),
        ),
        Text(
          t.pauseAfter(
            pauseNextLabel(
              context,
              ref,
              t,
              r.proposed,
              r.after,
              r.afterDate,
              r.observedZone,
            ),
          ),
        ),
        if (r.proposed.onOff case final b?)
          Text(t.pauseBlockSummary(b.onDays, b.offDays, b.anchor.toString())),
        if (actual && r.after == null) Text(t.pauseActualHelp),
      ],
      VitalButton(
        onPressed:
            busy ||
                conflict ||
                previewing ||
                (!valid && !uncertain) ||
                (review == null && !uncertain)
            ? null
            : save,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.save,
        ),
      ),
      Heading(t.pauseHistory),
      Text(t.pauseHistoryHelp),
      if (p.pauses.isEmpty) Text(t.pauseNoHistory),
      for (final pause in p.pauses.reversed.take(historyLimit)) ...[
        Text(
          t.pausePeriod(
            displayStamp(context, ref, pause.start),
            (pause.resume == null
                    ? null
                    : displayStamp(context, ref, pause.resume!)) ??
                t.pauseOngoing,
          ),
        ),
        if (pause.resume != null)
          Text(
            t.pauseDuration(pause.resume!.difference(pause.start).inMinutes),
          ),
      ],
      if (p.pauses.length > historyLimit)
        VitalButton.secondary(
          onPressed: () => setState(() => historyLimit += 50),
          child: Text(t.more),
        ),
    ]);
  }
}

String pauseNextLabel(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations t,
  DailyPlanVersion plan,
  DailyExpectation? next,
  CivilDate? date,
  String observedZone,
) {
  if (next != null) return expectationLabel(context, ref, t, next);
  if (date != null) {
    if (plan.timing case DailyCount(:final count, :final amount)) {
      return t.planUntimed(
        date.toString(),
        count,
        amount.enteredText,
        amount.unit,
        plan.zoneBasis.zoneFor(observedZone),
      );
    }
  }
  return t.planNoNext;
}
