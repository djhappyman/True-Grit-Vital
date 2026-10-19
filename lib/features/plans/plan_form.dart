import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'plan_providers.dart';
import 'pause_editor.dart';
import 'calendar_editor.dart';
import 'interval_editor.dart';
import 'interval_clock.dart';

class PlanSlotEntry {
  PlanSlotEntry({
    String? id,
    String time = '',
    String amount = '',
    String end = '',
    String anchor = '',
    this.reminderEnabled = false,
  }) : id = id ?? newCommandId(),
       time = TextEditingController(text: time),
       amount = TextEditingController(text: amount),
       end = TextEditingController(text: end),
       anchor = TextEditingController(text: anchor);
  final String id;
  final bool reminderEnabled;
  final TextEditingController time, amount, end, anchor;
  void dispose() {
    time.dispose();
    amount.dispose();
    end.dispose();
    anchor.dispose();
  }
}

class DailyPlanForm extends ConsumerStatefulWidget {
  const DailyPlanForm({super.key, required this.itemId, this.planId});
  final String itemId;
  final String? planId;
  @override
  ConsumerState<DailyPlanForm> createState() => _DailyPlanFormState();
}

class _DailyPlanFormState extends DurableFormState<DailyPlanForm> {
  SubstanceItem? item;
  AdultProfile? owner;
  SavedDailyPlan? original;
  String planId = newCommandId(), versionId = newCommandId();
  String mode = 'count', basis = 'local';
  bool initialised = false;
  final start = TextEditingController(),
      end = TextEditingController(),
      count = TextEditingController(),
      amount = TextEditingController(),
      home = TextEditingController();
  final slots = <PlanSlotEntry>[];
  late final CalendarFormFields calendar;
  late final IntervalFormFields interval;
  late final OnOffFormFields blocks;
  DailyPlanVersion? preview;
  String? previewZone;
  ReminderClockSample? intervalClockSample;

  @override
  DraftKind get entryKind => DraftKind.dailyPlan;
  @override
  String? get entryPerson => owner?.id;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String get entryTarget => widget.itemId;
  @override
  int? get entryTargetRevision => original?.revision;
  @override
  Map<String, String> captureEntry() => {
    'planId': planId,
    'versionId': versionId,
    'mode': mode,
    'basis': basis,
    'start': start.text,
    'end': end.text,
    'count': count.text,
    'amount': amount.text,
    'home': home.text,
    'intervalClockSample': encodeIntervalClock(intervalClockSample),
    ...calendar.capture(),
    ...blocks.capture(),
    ...interval.capture(),
    'slots': jsonEncode([
      for (final s in slots)
        {
          'id': s.id,
          'time': s.time.text,
          'amount': s.amount.text,
          'end': s.end.text,
          'anchor': s.anchor.text,
          'reminderEnabled': s.reminderEnabled,
        },
    ]),
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    planId = fields['planId']!;
    versionId = fields['versionId']!;
    mode = fields['mode']!;
    basis = fields['basis']!;
    start.text = fields['start'] ?? '';
    end.text = fields['end'] ?? '';
    count.text = fields['count'] ?? '';
    amount.text = fields['amount'] ?? '';
    home.text = fields['home'] ?? '';
    calendar.restore(fields);
    blocks.restore(fields);
    interval.restore(fields);
    for (final s in slots) {
      s.dispose();
    }
    slots.clear();
    for (final s in jsonDecode(fields['slots'] ?? '[]') as List) {
      addSlot(
        id: s['id'] as String,
        time: s['time'] as String,
        amount: s['amount'] as String,
        end: s['end'] as String? ?? '',
        anchor: s['anchor'] as String? ?? '',
        reminderEnabled: s['reminderEnabled'] == true,
      );
    }
    intervalClockSample = decodeIntervalClock(fields['intervalClockSample']);
  }

  @override
  void initState() {
    super.initState();
    final today = CivilDate.fromDateTime(DateTime.now());
    calendar = CalendarFormFields(initialDate: today);
    interval = IntervalFormFields();
    blocks = OnOffFormFields();
    for (final c in blocks.controllers) {
      c.addListener(changed);
    }
    for (final c in interval.controllers) {
      c.addListener(changed);
    }
    for (final c in calendar.controllers) {
      c.addListener(changed);
    }
    start.text = today.toString();
    for (final c in [start, end, count, amount, home]) {
      c.addListener(changed);
    }
    addSlot();
  }

  void addSlot({
    String? id,
    String time = '',
    String amount = '',
    String end = '',
    String anchor = '',
    bool reminderEnabled = false,
  }) {
    final s = PlanSlotEntry(
      id: id,
      time: time,
      amount: amount,
      end: end,
      anchor: anchor,
      reminderEnabled: reminderEnabled,
    );
    s.time.addListener(changed);
    s.amount.addListener(changed);
    s.end.addListener(changed);
    s.anchor.addListener(changed);
    slots.add(s);
  }

  void changed() {
    preview = null;
    if (!uncertain) intervalClockSample = null;
    entryChanged();
    if (mounted && draftReady) setState(() {});
  }

  @override
  void dispose() {
    calendar.dispose();
    blocks.dispose();
    interval.dispose();
    for (final c in [start, end, count, amount, home]) {
      c.dispose();
    }
    for (final s in slots) {
      s.dispose();
    }
    super.dispose();
  }

  WallTime parseTime(String value) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value.trim());
    if (m == null) throw const FormatException('wall_time');
    return WallTime(int.parse(m[1]!), int.parse(m[2]!));
  }

  PlannedAmount parseAmount(String value) => PlannedAmount(
    quantity: ExactQuantity.parse(value.trim()),
    unit: item!.unit,
    enteredText: value.trim(),
  );
  DailyPlanVersion candidate() => DailyPlanVersion(
    personId: owner!.id,
    itemId: item!.id,
    planId: planId,
    versionId: versionId,
    pauses: original?.plan.pauses ?? const [],
    effectiveFrom: original?.plan.effectiveFrom,
    effectiveUntil: original?.plan.effectiveUntil,
    onOff: mode == 'prn' ? null : blocks.candidate(),
    start: CivilDate.parse(start.text.trim()),
    endExclusive: end.text.trim().isEmpty
        ? null
        : CivilDate.parse(end.text.trim()).addDays(1),
    zoneBasis: basis == 'local'
        ? const FollowingLocal()
        : FixedHome(home.text.trim()),
    calendar: mode == 'prn' || mode == 'interval'
        ? const EveryDay()
        : calendar.candidate(),
    timing: switch (mode) {
      'prn' => const AsNeeded(),
      'interval' => interval.candidate(parseAmount(amount.text)),
      'windows' => DailyWindows(
        windows: [
          for (final s in slots)
            DailyWindow(
              id: s.id,
              start: parseTime(s.time.text),
              end: parseTime(s.end.text),
              amount: parseAmount(s.amount.text),
              reminderAnchor: s.anchor.text.trim().isEmpty
                  ? null
                  : parseTime(s.anchor.text),
              reminderEnabled: s.reminderEnabled,
            ),
        ],
      ),
      'mixed' => MixedDailyCount(
        count: int.parse(count.text.trim()),
        amount: parseAmount(amount.text),
        slots: [
          for (final s in slots)
            DailySlot(
              id: s.id,
              time: parseTime(s.time.text),
              amount: parseAmount(s.amount.text),
              reminderEnabled: s.reminderEnabled,
            ),
        ],
      ),
      'slots' => DailySlots([
        for (final s in slots)
          DailySlot(
            id: s.id,
            time: parseTime(s.time.text),
            amount: parseAmount(s.amount.text),
            reminderEnabled: s.reminderEnabled,
          ),
      ]),
      _ => DailyCount(int.parse(count.text.trim()), parseAmount(amount.text)),
    },
  );
  void makePreview() {
    final t = AppLocalizations.of(context);
    try {
      final plan = candidate();
      final zone = basis == 'home'
          ? home.text.trim()
          : ref.read(observedDeviceZoneProvider).value?.zoneId;
      if (zone == null) {
        setState(() => error = t.planZoneUnavailable);
        return;
      }
      DailyResolver().clock.validateZone(zone);
      setState(() {
        preview = plan;
        previewZone = zone;
        error = null;
      });
    } catch (_) {
      setState(
        () => error = mode == 'interval'
            ? t.intervalInputInvalid
            : calendar.error == null
            ? t.planInputInvalid
            : null,
      );
      entryChanged();
    }
  }

  Future<void> save() async {
    if (preview == null) {
      makePreview();
      if (!uncertain || preview == null) return;
    }
    final t = AppLocalizations.of(context);
    final plan = preview!;
    if (plan.timing is ElapsedInterval &&
        intervalClockSample == null &&
        !uncertain) {
      setState(() => busy = true);
      try {
        intervalClockSample = await captureIntervalClock(ref);
      } catch (_) {
        if (mounted) setState(() => error = t.saveFailure);
        return;
      } finally {
        if (mounted) setState(() => busy = false);
      }
      if (!mounted) return;
    }
    await commit((command) async {
      final store = await ref.read(recordStoreProvider.future);
      await store.saveDailyPlan(
        commandId: command,
        plan: plan,
        expectedPersonRevision: capturedPersonRevision!,
        expectedPlanRevision: capturedTargetRevision,
        expectedGeneration: store.generation,
        intervalClockSample: intervalClockSample,
      );
      ref.invalidate(dailyFeedProvider);
      ref.invalidate(nextDailyPlansProvider);
      ref.invalidate(itemPlansProvider);
      ref.invalidate(scopePlansProvider);
    }, successPath: '/today');
  }

  void loadPlan(SavedDailyPlan saved) {
    original = saved;
    final p = saved.plan;
    calendar.load(p.calendar);
    blocks.load(p.onOff);
    planId = p.planId;
    start.text = p.start.toString();
    end.text = p.endExclusive?.addDays(-1).toString() ?? '';
    basis = p.zoneBasis is FixedHome ? 'home' : 'local';
    home.text = p.zoneBasis is FixedHome
        ? (p.zoneBasis as FixedHome).zoneId
        : '';
    switch (p.timing) {
      case ElapsedInterval():
        mode = 'interval';
        interval.load(p.timing as ElapsedInterval);
        amount.text = (p.timing as ElapsedInterval).amount.enteredText;
      case AsNeeded():
        mode = 'prn';
      case DailyCount(:final count, :final amount):
        mode = 'count';
        this.count.text = '$count';
        this.amount.text = amount.enteredText;
      case DailyWindows(:final windows):
        mode = 'windows';
        for (final s in slots) {
          s.dispose();
        }
        slots.clear();
        for (final w in windows) {
          addSlot(
            id: w.id,
            time: wallLabel(w.start),
            end: wallLabel(w.end),
            anchor: w.reminderAnchor == null
                ? ''
                : wallLabel(w.reminderAnchor!),
            amount: w.amount.enteredText,
            reminderEnabled: w.reminderEnabled,
          );
        }
      case MixedDailyCount(:final count, :final amount, :final slots):
        mode = 'mixed';
        this.count.text = '$count';
        this.amount.text = amount.enteredText;
        for (final s in this.slots) {
          s.dispose();
        }
        this.slots.clear();
        for (final s in slots) {
          addSlot(
            id: s.id,
            time: wallLabel(s.time),
            amount: s.amount.enteredText,
            reminderEnabled: s.reminderEnabled,
          );
        }
      case DailySlots(:final slots):
        mode = 'slots';
        for (final s in this.slots) {
          s.dispose();
        }
        this.slots.clear();
        for (final s in slots) {
          addSlot(
            id: s.id,
            time: wallLabel(s.time),
            amount: s.amount.enteredText,
            reminderEnabled: s.reminderEnabled,
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    ref.listen(observedDeviceZoneProvider, (previous, next) {
      if (basis == 'local' &&
          previous?.value?.zoneId != next.value?.zoneId &&
          preview != null &&
          !busy &&
          !uncertain) {
        setState(() {
          preview = null;
          previewZone = null;
        });
      }
    });
    final lookup = ref.watch(itemLookupProvider(widget.itemId));
    final people = ref.watch(profilesProvider);
    final plans = ref.watch(itemPlansProvider(widget.itemId));
    if (!lookup.hasValue ||
        !people.hasValue ||
        !plans.hasValue ||
        !initialised &&
            (lookup.isLoading || people.isLoading || plans.isLoading)) {
      return EntryPage(
        children: [
          if (lookup.hasError || people.hasError || plans.hasError)
            LoadFailure(
              onRetry: () {
                ref.invalidate(itemLookupProvider(widget.itemId));
                ref.invalidate(profilesProvider);
                ref.invalidate(itemPlansProvider(widget.itemId));
              },
            )
          else
            Text(t.loadingRecords),
        ],
      );
    }
    if (lookup.value == null) {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!initialised) {
      item = lookup.value;
      owner = people.value!.where((p) => p.id == item!.personId).firstOrNull;
      final saved = plans.value!
          .where((p) => widget.planId == null || p.plan.planId == widget.planId)
          .firstOrNull;
      if (saved != null) loadPlan(saved);
      initialised = true;
      dirty = false;
    }
    if (owner == null || !people.value!.any((p) => p.id == owner!.id)) {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid = people.value!.any(
      (p) =>
          p.id == owner!.id &&
          !p.isArchived &&
          p.revision == capturedPersonRevision,
    );
    final enabled = valid && !busy && !uncertain && !conflict;
    return wrap([
      Heading(t.schedule),
      Text(t.profileOwner(ownerLabel(ref, t, owner!.id))),
      Text(item!.name),
      if (!valid) Text(t.profileChanged),
      if (original != null) Text(t.planEditHelp),
      if (original?.plan.timing is ElapsedInterval) Text(t.intervalEditHelp),
      Text(t.planPattern),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (value, label) in [
            ('count', t.planCount),
            ('slots', t.planTimes),
            ('prn', t.planAsNeeded),
            ('interval', t.intervalPattern),
            ('mixed', t.phaseMixed),
            ('windows', t.phaseWindows),
          ])
            Semantics(
              selected: mode == value,
              child: VitalButton.secondary(
                multiline: true,
                onPressed: enabled
                    ? () => setState(() {
                        mode = value;
                        changed();
                      })
                    : null,
                child: Text(label),
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      if (mode == 'interval') ...[
        IntervalEditor(fields: interval, enabled: enabled, onChanged: changed),
        LabelledInput(
          label: t.amountLabel,
          controller: amount,
          helper: item!.unit,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
      if (mode == 'count' || mode == 'mixed') ...[
        LabelledInput(
          label: t.planCount,
          controller: count,
          enabled: enabled,
          keyboardType: TextInputType.number,
        ),
        LabelledInput(
          label: t.amountLabel,
          controller: amount,
          helper: item!.unit,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        Text(t.planCountHelp),
      ],
      if (mode == 'mixed') Text(t.phaseMixedHelp),
      if (mode == 'windows') Text(t.phaseWindowHelp),
      if (mode == 'slots' || mode == 'mixed' || mode == 'windows') ...[
        for (final s in slots)
          Padding(
            key: ValueKey(s.id),
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabelledInput(
                  label: mode == 'windows' ? t.phaseWindowStart : t.planTime,
                  controller: s.time,
                  helper: t.timeExample,
                  enabled: enabled,
                  keyboardType: TextInputType.datetime,
                ),
                if (mode == 'windows') ...[
                  LabelledInput(
                    label: t.phaseWindowEnd,
                    controller: s.end,
                    helper: t.phaseWindowEndHelp,
                    enabled: enabled,
                    keyboardType: TextInputType.datetime,
                  ),
                  LabelledInput(
                    label: t.phaseWindowAnchor,
                    controller: s.anchor,
                    helper: t.phaseWindowAnchorHelp,
                    enabled: enabled,
                    keyboardType: TextInputType.datetime,
                  ),
                ],
                LabelledInput(
                  label: t.amountLabel,
                  controller: s.amount,
                  helper: item!.unit,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                if (slots.length > 1)
                  VitalButton.secondary(
                    onPressed: enabled
                        ? () => setState(() {
                            slots.remove(s);
                            s.dispose();
                            changed();
                          })
                        : null,
                    child: Text(t.remove),
                  ),
              ],
            ),
          ),
        VitalButton.secondary(
          onPressed: enabled
              ? () => setState(() {
                  addSlot();
                  changed();
                })
              : null,
          child: Text(t.add),
        ),
      ],
      if (mode == 'prn') Text(t.planPrnHelp),
      const SizedBox(height: 20),
      LabelledInput(
        label: original == null ? t.planStart : t.planEffective,
        controller: start,
        helper: t.dateExample,
        enabled: enabled,
        keyboardType: TextInputType.datetime,
      ),
      LabelledInput(
        label: t.planEnd,
        controller: end,
        helper: t.planEndHelp,
        enabled: enabled,
        keyboardType: TextInputType.datetime,
      ),
      if (mode != 'prn' && mode != 'interval')
        CalendarEditor(fields: calendar, enabled: enabled, onChanged: changed),
      if (mode != 'prn')
        OnOffEditor(fields: blocks, enabled: enabled, onChanged: changed),
      Text(t.planZone),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (value, label) in [
            ('local', t.planLocal),
            ('home', t.planHome),
          ])
            Semantics(
              selected: basis == value,
              child: VitalButton.secondary(
                multiline: true,
                onPressed: enabled
                    ? () => setState(() {
                        basis = value;
                        changed();
                      })
                    : null,
                child: Text(label),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (basis == 'home')
        LabelledInput(
          label: t.planHomeZone,
          controller: home,
          helper: t.planZoneExample,
          enabled: enabled,
        )
      else
        Text(
          t.planObserved(
            ref.watch(observedDeviceZoneProvider).value?.zoneId ??
                t.planZoneUnknown,
          ),
        ),
      ?failure(),
      const SizedBox(height: 20),
      VitalButton.secondary(
        onPressed: enabled ? makePreview : null,
        child: Text(t.planPreview),
      ),
      if (preview != null)
        preview!.timing is ElapsedInterval
            ? IntervalPlanPreview(plan: preview!, observedZone: previewZone!)
            : PlanPreview(plan: preview!, observedZone: previewZone!),
      const SizedBox(height: 20),
      VitalButton(
        onPressed:
            busy ||
                conflict ||
                (!valid && !uncertain) ||
                (preview == null && !uncertain)
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
      SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
    ]);
  }
}

String wallLabel(WallTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

class PlanPreview extends ConsumerStatefulWidget {
  const PlanPreview({
    super.key,
    required this.plan,
    required this.observedZone,
  });
  final DailyPlanVersion plan;
  final String observedZone;
  @override
  ConsumerState<PlanPreview> createState() => _PlanPreviewState();
}

class _PlanPreviewState extends ConsumerState<PlanPreview> {
  late CivilDate from;
  late DailyNext next;
  late DailyExpansion expansion;
  DailyExpectation? boundary;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    calculate();
  }

  @override
  void didUpdateWidget(covariant PlanPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.plan, widget.plan) ||
        oldWidget.observedZone != widget.observedZone) {
      calculate();
    }
  }

  void calculate() {
    final plan = widget.plan, observedZone = widget.observedZone;
    final instant = DateTime.now().toUtc();
    failed = false;
    try {
      final resolver = DailyResolver();
      final now = resolver.currentDate(
        plan,
        now: instant,
        observedZone: observedZone,
      );
      from = now.compareTo(plan.start) < 0 ? plan.start : now;
      next =
          plan.timing is DailySlots ||
              plan.timing is DailyWindows &&
                  (plan.timing as DailyWindows).windows.every(
                    (w) => w.reminderAnchor != null,
                  )
          ? resolver.nextInstant(
              plan,
              after: instant,
              observedZone: observedZone,
              maxDates: 370,
            )
          : resolver.nextDate(plan, from: from, observedZone: observedZone);
      expansion = resolver.expand(
        plan,
        from: from,
        toExclusive: from.addDays(370),
        observedZone: observedZone,
        maxDates: 370,
        maxRows: 20000,
      );
      boundary = null;
      Duration? previousOffset;
      for (final row in expansion.rows) {
        final offset = row.instant == null || row.effectiveTime == null
            ? null
            : row.effectiveTime!
                  .on(row.identity.originalDate)
                  .difference(row.instant!);
        if (row.resolution == DailyResolution.missingClock ||
            row.resolution == DailyResolution.repeatedClock ||
            previousOffset != null && offset != previousOffset) {
          boundary = row;
          break;
        }
        previousOffset = offset;
      }
    } catch (_) {
      failed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), plan = widget.plan;
    if (failed) return Text(t.planCalculationIssue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Heading(t.planPreview),
        Text(t.planPreviewRange(from.toString(), from.addDays(6).toString())),
        if (plan.timing is AsNeeded)
          Text(t.planPrnHelp)
        else if (!next.complete) ...[
          if (next.calendarDate != null)
            Text(t.calendarKnownDate(next.calendarDate.toString())),
          Text(next.issue == null ? t.planIncomplete : t.planCalculationIssue),
        ] else
          Text(
            next.next == null
                ? t.planNoNext
                : t.planNext(next.next!.identity.originalDate.toString()),
          ),
        if ((next.next?.identity.originalDate ?? next.calendarDate)
            case final CivilDate date)
          if (date.compareTo(from.addDays(7)) >= 0)
            Text(t.calendarBeyondPreview),
        if (plan.onOff case final b?)
          Text(t.pauseBlockSummary(b.onDays, b.offDays, b.anchor.toString())),
        if (plan.onOff != null) Text(t.pauseIntersection),
        CalendarBoundaryPreview(plan: plan, from: from),
        for (final review in next.needsReview)
          Text(expectationLabel(context, ref, t, review)),
        for (final row
            in expansion.rows
                .where(
                  (r) => r.identity.originalDate.compareTo(from.addDays(7)) < 0,
                )
                .take(20))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(expectationLabel(context, ref, t, row)),
          ),
        if (expansion.rows
                .where(
                  (r) => r.identity.originalDate.compareTo(from.addDays(7)) < 0,
                )
                .length >
            20)
          Text(t.planPreviewLimited),
        if (!expansion.complete) Text(t.planIncomplete),
        if (boundary != null) ...[
          Heading(t.planBoundary),
          Text(expectationLabel(context, ref, t, boundary!)),
        ],
        if (plan.endExclusive != null)
          Text(t.planEnds(plan.endExclusive!.addDays(-1).toString())),
      ],
    );
  }
}

String expectationLabel(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations t,
  DailyExpectation row,
) {
  final amount = row.amount.enteredText,
      unit = row.amount.unit,
      date = row.identity.originalDate.toString();
  if (row.originalWindowStart != null &&
      row.originalWindowEnd != null &&
      row.windowStart != null &&
      row.windowEnd != null) {
    return t.phaseWindowChanged(
      displayStamp(context, ref, row.originalWindowStart!, zoneId: row.zoneId),
      displayStamp(context, ref, row.originalWindowEnd!, zoneId: row.zoneId),
      (row.originalReminderAnchor == null
              ? null
              : displayStamp(
                  context,
                  ref,
                  row.originalReminderAnchor!,
                  zoneId: row.zoneId,
                )) ??
          t.phaseNoAnchor,
      row.originalAmount!.enteredText,
      row.originalAmount!.unit,
      displayStamp(context, ref, row.windowStart!, zoneId: row.zoneId),
      displayStamp(context, ref, row.windowEnd!, zoneId: row.zoneId),
      (row.reminderAnchor == null
              ? null
              : displayStamp(
                  context,
                  ref,
                  row.reminderAnchor!,
                  zoneId: row.zoneId,
                )) ??
          t.phaseNoAnchor,
      amount,
      unit,
      row.zoneId,
    );
  }
  if (row.windowStart != null && row.windowEnd != null) {
    return t.phaseWindowSummary(
      date,
      displayStamp(context, ref, row.windowStart!, zoneId: row.zoneId),
      displayStamp(context, ref, row.windowEnd!, zoneId: row.zoneId),
      amount,
      unit,
      (row.reminderAnchor == null
              ? null
              : displayStamp(
                  context,
                  ref,
                  row.reminderAnchor!,
                  zoneId: row.zoneId,
                )) ??
          t.phaseNoAnchor,
      row.zoneId,
    );
  }
  if (row.windowEndpoints.length >= 2) {
    final start = row.windowEndpoints[0], end = row.windowEndpoints[1];
    return t.phaseWindowPending(
      start.identity.originalDate.toString(),
      displayWallTime(context, ref, start.originalTime!),
      end.identity.originalDate.toString(),
      displayWallTime(context, ref, end.originalTime!),
      amount,
      unit,
      row.zoneId,
    );
  }
  if (row.originalAmount != null && row.originalTime == null) {
    return t.phaseOverrideSummary(
      date,
      row.originalAmount!.enteredText,
      row.originalAmount!.unit,
      date,
      amount,
      unit,
    );
  }
  if (row.originalInstant != null &&
      (row.instant != row.originalInstant ||
          row.originalAmount != null &&
              row.amount.quantity.scaled !=
                  row.originalAmount!.quantity.scaled)) {
    return t.phaseOverrideSummary(
      displayStamp(context, ref, row.originalInstant!, zoneId: row.zoneId),
      row.originalAmount!.enteredText,
      row.originalAmount!.unit,
      (row.instant == null
              ? null
              : displayStamp(context, ref, row.instant!, zoneId: row.zoneId)) ??
          date,
      amount,
      unit,
    );
  }
  if (row.originalTime == null) {
    return t.planUntimed(date, row.plannedCount!, amount, unit, row.zoneId);
  }
  return t.planTimed(
    date,
    displayWallTime(context, ref, row.originalTime!),
    amount,
    unit,
    row.zoneId,
    switch (row.resolution) {
      DailyResolution.missingClock => t.planMissingClock,
      DailyResolution.repeatedClock => t.planRepeatedClock,
      DailyResolution.noAlert => t.planNoAlert,
      _ =>
        row.effectiveTime == row.originalTime
            ? t.planPlanned
            : t.planReplacement(
                displayWallTime(context, ref, row.effectiveTime!),
              ),
    },
  );
}
