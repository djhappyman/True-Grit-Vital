import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../data/daily_codec.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'calendar_editor.dart';
import 'interval_clock.dart';
import 'interval_editor.dart';
import 'pause_editor.dart';
import 'plan_form.dart';
import 'plan_providers.dart';

/// Raw controllers are checkpointed before validation, including incomplete rows.
class PhaseEntry {
  PhaseEntry({String? id}) : id = id ?? newCommandId();
  String id, mode = 'count';
  String replacementId = newCommandId();
  DailyPlanVersion? source;
  final start = TextEditingController(),
      last = TextEditingController(),
      count = TextEditingController(),
      amount = TextEditingController();
  final slots = <PlanSlotEntry>[];
  final calendar = CalendarFormFields(
    initialDate: CivilDate.fromDateTime(DateTime.now()),
  );
  final interval = IntervalFormFields();
  final blocks = OnOffFormFields();
  List<TextEditingController> get controllers => [
    start,
    last,
    count,
    amount,
    ...calendar.controllers,
    ...interval.controllers,
    ...blocks.controllers,
    for (final s in slots) ...[s.time, s.amount, s.end, s.anchor],
  ];
  Map<String, dynamic> capture() => {
    'id': id,
    'replacementId': replacementId,
    'source': source == null ? null : encodeDailyPlan(source!),
    'mode': mode,
    'start': start.text,
    'last': last.text,
    'count': count.text,
    'amount': amount.text,
    ...calendar.capture(),
    ...interval.capture(),
    ...blocks.capture(),
    'slots': [
      for (final s in slots)
        {
          'id': s.id,
          'time': s.time.text,
          'amount': s.amount.text,
          'end': s.end.text,
          'anchor': s.anchor.text,
          'reminder': s.reminderEnabled,
        },
    ],
  };
  void restore(Map<String, dynamic> f) {
    id = f['id'] as String;
    replacementId = f['replacementId'] as String? ?? newCommandId();
    mode = f['mode'] as String;
    if (f['source'] != null) {
      source = decodeDailyPlan(Map<String, dynamic>.from(f['source'] as Map));
    }
    start.text = f['start'] as String;
    last.text = f['last'] as String;
    count.text = f['count'] as String;
    amount.text = f['amount'] as String;
    final strings = {
      for (final e in f.entries)
        if (e.value is String) e.key: e.value as String,
    };
    calendar.restore(strings);
    if (source?.timing case final ElapsedInterval original) {
      interval.load(original);
    }
    interval.restore(strings);
    blocks.restore(strings);
    for (final s in slots) {
      s.dispose();
    }
    slots.clear();
    for (final raw in f['slots'] as List) {
      final s = Map<String, dynamic>.from(raw as Map);
      slots.add(
        PlanSlotEntry(
          id: s['id'] as String,
          time: s['time'] as String,
          amount: s['amount'] as String,
          end: s['end'] as String,
          anchor: s['anchor'] as String,
          reminderEnabled: s['reminder'] == true,
        ),
      );
    }
  }

  void load(DailyPlanVersion p) {
    source = p;
    id = p.versionId;
    start.text = p.start.toString();
    last.text = p.endExclusive?.addDays(-1).toString() ?? '';
    calendar.load(p.calendar);
    blocks.load(p.onOff);
    void loadSlots(List<DailySlot> values) {
      for (final s in values) {
        slots.add(
          PlanSlotEntry(
            id: s.id,
            time: wallLabel(s.time),
            amount: s.amount.enteredText,
            reminderEnabled: s.reminderEnabled,
          ),
        );
      }
    }

    switch (p.timing) {
      case DailyCount(:final count, :final amount):
        mode = 'count';
        this.count.text = '$count';
        this.amount.text = amount.enteredText;
      case MixedDailyCount(:final count, :final amount, :final slots):
        mode = 'mixed';
        this.count.text = '$count';
        this.amount.text = amount.enteredText;
        loadSlots(slots);
      case DailySlots(:final slots):
        mode = 'slots';
        loadSlots(slots);
      case DailyWindows(:final windows):
        mode = 'windows';
        for (final w in windows) {
          slots.add(
            PlanSlotEntry(
              id: w.id,
              time: wallLabel(w.start),
              end: wallLabel(w.end),
              anchor: w.reminderAnchor == null
                  ? ''
                  : wallLabel(w.reminderAnchor!),
              amount: w.amount.enteredText,
              reminderEnabled: w.reminderEnabled,
            ),
          );
        }
      case ElapsedInterval(:final amount):
        mode = 'interval';
        interval.load(p.timing as ElapsedInterval);
        this.amount.text = amount.enteredText;
      case AsNeeded():
        mode = 'prn';
    }
  }

  DailyPlanVersion candidate(DailyPlanVersion base, String unit) {
    PlannedAmount a(String text) => PlannedAmount(
      quantity: ExactQuantity.parse(text.trim()),
      unit: unit,
      enteredText: text.trim(),
    );
    WallTime time(String value) {
      final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value.trim());
      if (m == null) throw const FormatException();
      return WallTime(int.parse(m[1]!), int.parse(m[2]!));
    }

    List<DailySlot> timed() => [
      for (final s in slots)
        DailySlot(
          id: s.id,
          time: time(s.time.text),
          amount: a(s.amount.text),
          reminderEnabled: s.reminderEnabled,
        ),
    ];
    final p = source ?? base;
    final result = DailyPlanVersion(
      personId: base.personId,
      itemId: base.itemId,
      planId: base.planId,
      versionId: id,
      start: CivilDate.parse(start.text.trim()),
      endExclusive: last.text.trim().isEmpty
          ? null
          : CivilDate.parse(last.text.trim()).addDays(1),
      effectiveFrom: source?.effectiveFrom,
      effectiveUntil: source?.effectiveUntil,
      zoneBasis: p.zoneBasis,
      pauses: p.pauses,
      onOff: mode == 'prn' ? null : blocks.candidate(),
      calendar: mode == 'interval' || mode == 'prn'
          ? const EveryDay()
          : calendar.candidate(),
      timing: switch (mode) {
        'mixed' => MixedDailyCount(
          count: int.parse(count.text.trim()),
          amount: a(amount.text),
          slots: timed(),
        ),
        'slots' => DailySlots(timed()),
        'windows' => DailyWindows(
          windows: [
            for (final s in slots)
              DailyWindow(
                id: s.id,
                start: time(s.time.text),
                end: time(s.end.text),
                amount: a(s.amount.text),
                reminderAnchor: s.anchor.text.trim().isEmpty
                    ? null
                    : time(s.anchor.text),
                reminderEnabled: s.reminderEnabled,
              ),
          ],
        ),
        'interval' => interval.candidate(a(amount.text)),
        'prn' => const AsNeeded(),
        _ => DailyCount(int.parse(count.text.trim()), a(amount.text)),
      },
    );
    if (source != null) {
      final before = Map<String, Object?>.from(encodeDailyPlan(source!))
        ..remove('end')
        ..remove('effectiveUntil');
      final after = Map<String, Object?>.from(encodeDailyPlan(result))
        ..remove('end')
        ..remove('effectiveUntil');
      if (jsonEncode(before) != jsonEncode(after)) {
        final encoded = encodeDailyPlan(result);
        encoded['version'] = replacementId;
        return decodeDailyPlan(encoded);
      }
    }
    return result;
  }

  void dispose() {
    for (final c in [start, last, count, amount]) {
      c.dispose();
    }
    for (final s in slots) {
      s.dispose();
    }
    calendar.dispose();
    interval.dispose();
    blocks.dispose();
  }
}

typedef PhaseWriter = Future<void> Function(
  String command,
  PhaseChangeReview review,
  ReminderClockSample? sample,
);
final phaseWriterProvider = Provider<PhaseWriter>(
  (ref) => (command, review, sample) async {
    await (await ref.read(recordStoreProvider.future)).savePhasePlan(
      commandId: command,
      review: review,
      intervalClockSample: sample,
    );
  },
);

class PhasePlanForm extends ConsumerStatefulWidget {
  const PhasePlanForm({super.key, required this.itemId, required this.planId});
  final String itemId, planId;
  @override
  ConsumerState<PhasePlanForm> createState() => _PhasePlanFormState();
}

class _PhasePlanFormState extends DurableFormState<PhasePlanForm> {
  SavedDailyPlan? saved;
  AdultProfile? owner;
  SubstanceItem? item;
  bool initialised = false, loading = false, previewing = false;
  String endMode = 'none', versionId = newCommandId();
  final endValue = TextEditingController(),
      endZone = TextEditingController(),
      originalDate = TextEditingController(),
      target = TextEditingController(),
      windowEnd = TextEditingController(),
      windowAnchor = TextEditingController(),
      targetZone = TextEditingController(),
      overrideAmount = TextEditingController();
  final phases = <PhaseEntry>[];
  final overrides = <OccurrenceOverride>[];
  final origins = <DailyPlanVersion>[];
  List<DailyExpectation> choices = [], collisions = [];
  DailyExpectation? selected;
  final reviewedCollisions = <DailyIdentity>{};
  PhaseChangeReview? review;
  ReminderClockSample? sample;
  DateTime? reviewedAt;
  String? reviewedZone;
  @override
  DraftKind get entryKind => DraftKind.phasePlan;
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
    'phases': jsonEncode([for (final p in phases) p.capture()]),
    'originPhases': jsonEncode([for (final p in origins) encodeDailyPlan(p)]),
    'endMode': endMode,
    'endValue': endValue.text,
    'endZone': endZone.text,
    'overrides': jsonEncode([
      for (final o in overrides)
        {
          'identity': encodeDailyIdentity(o.identity),
          'version': o.versionId,
          'target': o.targetInstant?.microsecondsSinceEpoch,
          'zone': o.targetZoneId,
          'window': o.windowTarget == null
              ? null
              : {
                  'start': o.windowTarget!.start.microsecondsSinceEpoch,
                  'end': o.windowTarget!.end.microsecondsSinceEpoch,
                  'anchor':
                      o.windowTarget!.reminderAnchor?.microsecondsSinceEpoch,
                  'zone': o.windowTarget!.zoneId,
                },
          'amount': o.amount == null
              ? null
              : {'entered': o.amount!.enteredText, 'unit': o.amount!.unit},
          'collisions': [
            for (final c in o.reviewedCollisions) encodeDailyIdentity(c),
          ],
        },
    ]),
    'originalDate': originalDate.text,
    'targetInstant': target.text,
    'windowEnd': windowEnd.text,
    'windowAnchor': windowAnchor.text,
    'targetZone': targetZone.text,
    'overrideAmount': overrideAmount.text,
    'selectedExpectation': selected == null
        ? ''
        : jsonEncode(encodeDailyExpectation(selected!)),
    'collisionRows': jsonEncode([
      for (final r in collisions) encodeDailyExpectation(r),
    ]),
    'collisionReviewed': jsonEncode([
      for (final id in reviewedCollisions) encodeDailyIdentity(id),
    ]),
    'selectedIdentity': selected == null
        ? ''
        : dailyIdentityKey(selected!.identity),
    'reviewedAt': reviewedAt?.toIso8601String() ?? '',
    'reviewedZone': reviewedZone ?? '',
    'intervalClockSample': encodeIntervalClock(sample),
  };
  @override
  void restoreEntry(Map<String, String> f) {
    if (f['planId'] != widget.planId) {
      conflict = true;
      return;
    }
    versionId = f['versionId']!;
    endMode = f['endMode']!;
    endValue.text = f['endValue']!;
    endZone.text = f['endZone']!;
    originalDate.text = f['originalDate'] ?? '';
    target.text = f['targetInstant'] ?? '';
    windowEnd.text = f['windowEnd'] ?? '';
    windowAnchor.text = f['windowAnchor'] ?? '';
    targetZone.text = f['targetZone'] ?? '';
    overrideAmount.text = f['overrideAmount'] ?? '';
    for (final p in phases) {
      p.dispose();
    }
    phases.clear();
    for (final raw in jsonDecode(f['phases']!) as List) {
      final p = PhaseEntry()..restore(Map<String, dynamic>.from(raw as Map));
      phases.add(p);
      listen(p);
    }
    origins
      ..clear()
      ..addAll([
        for (final raw in jsonDecode(f['originPhases'] ?? '[]') as List)
          decodeDailyPlan(Map<String, dynamic>.from(raw as Map)),
      ]);
    overrides.clear();
    for (final raw in jsonDecode(f['overrides']!) as List) {
      final o = Map<String, dynamic>.from(raw as Map);
      final a = o['amount'];
      overrides.add(
        OccurrenceOverride(
          identity: decodeDailyIdentity(o['identity']),
          versionId: o['version'] as String,
          targetInstant: o['target'] == null
              ? null
              : DateTime.fromMicrosecondsSinceEpoch(
                  o['target'] as int,
                  isUtc: true,
                ),
          targetZoneId: o['zone'] as String?,
          windowTarget: o['window'] == null
              ? null
              : WindowOverrideTarget(
                  start: DateTime.fromMicrosecondsSinceEpoch(
                    o['window']['start'] as int,
                    isUtc: true,
                  ),
                  end: DateTime.fromMicrosecondsSinceEpoch(
                    o['window']['end'] as int,
                    isUtc: true,
                  ),
                  reminderAnchor: o['window']['anchor'] == null
                      ? null
                      : DateTime.fromMicrosecondsSinceEpoch(
                          o['window']['anchor'] as int,
                          isUtc: true,
                        ),
                  zoneId: o['window']['zone'] as String,
                ),
          amount: a == null
              ? null
              : PlannedAmount(
                  quantity: ExactQuantity.parse(a['entered'] as String),
                  unit: a['unit'] as String,
                  enteredText: a['entered'] as String,
                ),
          reviewedCollisions: [
            for (final c in o['collisions'] as List) decodeDailyIdentity(c),
          ],
        ),
      );
    }
    selected = (f['selectedExpectation'] ?? '').isEmpty
        ? null
        : decodeDailyExpectation(
            Map<String, dynamic>.from(
              jsonDecode(f['selectedExpectation']!) as Map,
            ),
          );
    collisions = [
      for (final raw in jsonDecode(f['collisionRows'] ?? '[]') as List)
        decodeDailyExpectation(Map<String, dynamic>.from(raw as Map)),
    ];
    reviewedCollisions
      ..clear()
      ..addAll([
        for (final raw in jsonDecode(f['collisionReviewed'] ?? '[]') as List)
          decodeDailyIdentity(raw),
      ]);
    reviewedAt = DateTime.tryParse(f['reviewedAt'] ?? '');
    reviewedZone = f['reviewedZone'];
    sample = decodeIntervalClock(f['intervalClockSample']);
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      endValue,
      endZone,
      originalDate,
      target,
      windowEnd,
      windowAnchor,
      targetZone,
      overrideAmount,
    ]) {
      c.addListener(changed);
    }
    originalDate.text = CivilDate.fromDateTime(DateTime.now()).toString();
  }

  void listen(PhaseEntry p) {
    for (final c in p.controllers) {
      c.addListener(changed);
    }
  }

  void changed() {
    review = null;
    collisions = [];
    reviewedCollisions.clear();
    if (!uncertain) {
      reviewedAt = null;
      reviewedZone = null;
      sample = null;
    }
    entryChanged();
    if (mounted && draftReady) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      endValue,
      endZone,
      originalDate,
      target,
      windowEnd,
      windowAnchor,
      targetZone,
      overrideAmount,
    ]) {
      c.dispose();
    }
    for (final p in phases) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> load(SavedDailyPlan s) async {
    loading = true;
    try {
      final store = await ref.read(recordStoreProvider.future);
      final aggregate = await store.phasePlan(
        planId: s.plan.planId,
        personId: s.plan.personId,
      );
      final versions =
          aggregate?.phases ??
          (await store.dailyPlanVersions(
            s.plan.planId,
            personId: s.plan.personId,
            limit: 101,
          )).map((v) => v.plan).toList();
      for (final v in versions) {
        final p = PhaseEntry()..load(v);
        phases.add(p);
        listen(p);
      }
      overrides.addAll(aggregate?.overrides ?? []);
      origins.addAll(aggregate?.originPhases ?? []);
      if (aggregate?.end case final e?) {
        endMode = e.lastDate == null ? 'exact' : 'date';
        endValue.text =
            e.lastDate?.toString() ?? e.exclusiveInstant.toIso8601String();
        endZone.text = e.zoneId;
      } else {
        endZone.text = s.plan.zoneBasis is FixedHome
            ? (s.plan.zoneBasis as FixedHome).zoneId
            : ref.read(observedDeviceZoneProvider).value?.zoneId ?? '';
      }
      if (mounted) setState(() => initialised = true);
    } catch (_) {
      if (mounted) {
        setState(() => error = AppLocalizations.of(context).saveFailure);
      }
    } finally {
      loading = false;
    }
  }

  String zone() => reviewedZone?.isNotEmpty == true && uncertain
      ? reviewedZone!
      : saved!.plan.zoneBasis.zoneFor(
          ref.read(observedDeviceZoneProvider).value?.zoneId ?? '',
        );
  PhasePlan candidate() {
    final versions = [
      for (final p in phases) p.candidate(saved!.plan, item!.unit),
    ];
    final retained = {
      for (final p in origins) p.versionId: p,
      for (final p in phases)
        if (p.source != null &&
            overrides.any((o) => o.versionId == p.source!.versionId))
          p.source!.versionId: p.source!,
    };
    retained.removeWhere((id, _) => versions.any((p) => p.versionId == id));
    return PhasePlan(
      phases: versions,
      overrides: overrides,
      originPhases: retained.values,
      end: endMode == 'none'
          ? null
          : endMode == 'date'
          ? PlanEnd.onDate(
              lastDate: CivilDate.parse(endValue.text.trim()),
              zoneId: endZone.text.trim(),
              clock: DailyResolver().clock,
            )
          : PlanEnd(
              zoneId: endZone.text.trim(),
              exclusiveInstant: parsePauseInstant(endValue.text.trim()),
            ),
    );
  }

  Future<void> preview() async {
    setState(() => previewing = true);
    try {
      final proposed = candidate();
      final store = await ref.read(recordStoreProvider.future);
      final z = zone();
      final r = await store.previewPhasePlan(
        plan: saved!,
        proposed: proposed,
        now: reviewedAt ??= DateTime.now().toUtc(),
        observedZone: z,
      );
      reviewedZone = z;
      if (mounted) {
        setState(() {
          review = r;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        setState(
          () => error =
              failure is CommandConflict && failure.code == 'phase_calculation'
              ? t.planCalculationIssue
              : t.phaseInvalid,
        );
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
    if (r.proposed.phases.any((p) => p.timing is ElapsedInterval) &&
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
      await ref.read(phaseWriterProvider)(command, r, sample);
      ref.invalidate(itemPlansProvider);
      ref.invalidate(scopePlansProvider);
      ref.invalidate(dailyFeedProvider);
      ref.invalidate(nextDailyPlansProvider);
      ref.invalidate(phaseDetailsProvider);
    }, successPath: '/today');
  }

  Future<void> choose() async {
    try {
      final p = candidate();
      final rows = PhaseResolver().resolveDate(
        PhasePlan(phases: p.phases, originPhases: p.originPhases, end: p.end),
        CivilDate.parse(originalDate.text.trim()),
        observedZone: zone(),
      );
      setState(() {
        choices = rows;
        selected = null;
        error = null;
      });
    } catch (_) {
      setState(() => error = AppLocalizations.of(context).phaseInvalid);
    }
  }

  void addOverride() {
    final t = AppLocalizations.of(context);
    if (selected == null) {
      setState(() => error = t.phaseNotSelected);
      return;
    }
    try {
      final origin = selected!,
          z = targetZone.text.trim().isEmpty ? zone() : targetZone.text.trim();
      final moving = target.text.trim().isNotEmpty;
      final instant = moving ? parsePauseInstant(target.text.trim()) : null;
      final window = origin.windowStart == null || !moving
          ? null
          : WindowOverrideTarget(
              start: instant!,
              end: parsePauseInstant(windowEnd.text.trim()),
              zoneId: z,
              reminderAnchor: windowAnchor.text.trim().isEmpty
                  ? null
                  : parsePauseInstant(windowAnchor.text.trim()),
            );
      final amount = overrideAmount.text.trim().isEmpty
          ? null
          : PlannedAmount(
              quantity: ExactQuantity.parse(overrideAmount.text.trim()),
              unit: item!.unit,
              enteredText: overrideAmount.text.trim(),
            );
      if (instant != null) {
        final date = DailyResolver().clock.dateAt(instant, z);
        final until = window == null
            ? date.addDays(1)
            : DailyResolver().clock.dateAt(window.end, z).addDays(1);
        final expanded = PhaseResolver().expand(
          candidate(),
          from: date.addDays(-1),
          toExclusive: until,
          observedZone: zone(),
          maxDates: 10000,
          maxRows: 10000,
        );
        if (!expanded.complete) {
          throw const FormatException();
        }
        final found = expanded.rows.where((r) {
          if (r.identity == origin.identity) {
            return false;
          }
          if (window == null) {
            return r.instant == instant ||
                r.windowStart != null &&
                    r.windowEnd != null &&
                    !instant.isBefore(r.windowStart!) &&
                    instant.isBefore(r.windowEnd!);
          }
          if (r.windowStart != null && r.windowEnd != null) {
            return r.windowStart!.isBefore(window.end) &&
                r.windowEnd!.isAfter(window.start);
          }
          return r.instant != null &&
              !r.instant!.isBefore(window.start) &&
              r.instant!.isBefore(window.end);
        }).toList();
        if (found.any((r) => !reviewedCollisions.contains(r.identity))) {
          setState(() => collisions = found);
          return;
        }
      }
      final o = OccurrenceOverride(
        identity: origin.identity,
        versionId: origin.versionId,
        targetInstant: window == null ? instant : null,
        targetZoneId: window == null && instant != null ? z : null,
        windowTarget: window,
        amount: amount,
        reviewedCollisions: reviewedCollisions,
      );
      final list = [...overrides.where((v) => v.identity != o.identity), o],
          p = candidate();
      PhaseResolver().resolveDate(
        PhasePlan(
          phases: p.phases,
          originPhases: p.originPhases,
          end: p.end,
          overrides: list,
        ),
        instant == null
            ? origin.identity.originalDate
            : DailyResolver().clock.dateAt(instant, z),
        observedZone: zone(),
      );
      overrides
        ..clear()
        ..addAll(list);
      selected = null;
      choices = [];
      changed();
    } catch (_) {
      setState(() => error = t.phaseReviewIssue);
    }
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
    final lookup = ref.watch(itemLookupProvider(widget.itemId));
    if (!plans.hasValue || !people.hasValue || !lookup.hasValue) {
      return EntryPage(
        children: [
          if (plans.hasError || people.hasError || lookup.hasError)
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
    saved ??= plans.value!
        .where((v) => v.plan.planId == widget.planId)
        .firstOrNull;
    item ??= lookup.value;
    owner ??= people.value!
        .where((p) => p.id == saved?.plan.personId)
        .firstOrNull;
    if (saved == null || item == null || owner == null) {
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!initialised) {
      if (!loading && error == null) load(saved!);
      return EntryPage(
        children: [
          if (error != null)
            LoadFailure(
              onRetry: () => setState(() {
                loading = false;
                error = null;
              }),
            )
          else
            Text(t.loadingRecords),
        ],
      );
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid = people.value!.any(
      (p) =>
          p.id == owner!.id &&
          !p.isArchived &&
          p.revision == capturedPersonRevision,
    );
    final enabled = valid && !busy && !uncertain && !conflict && !previewing;
    return wrap([
      Heading(t.phaseHeading),
      Text(t.profileOwner(ownerLabel(ref, t, owner!.id))),
      Text(item!.name),
      Text(t.phaseHelp),
      if (!valid) Text(t.profileChanged),
      for (final p in phases) phaseCard(p, enabled, t),
      VitalButton.secondary(
        onPressed: enabled
            ? () {
                final p = PhaseEntry();
                try {
                  p.start.text = phases.last.last.text.isEmpty
                      ? ''
                      : CivilDate.parse(phases.last.last.text)
                            .addDays(1)
                            .toString();
                } catch (_) {
                  p.start.text = '';
                }
                p.slots.add(PlanSlotEntry());
                listen(p);
                phases.add(p);
                changed();
              }
            : null,
        child: Text(t.add),
      ),
      Heading(t.phaseEndHeading),
      CalendarChoices(
        value: endMode,
        enabled: enabled,
        choices: [
          ('none', t.phaseNoEnd),
          ('date', t.phaseDateEnd),
          ('exact', t.phaseExactEnd),
        ],
        onSelected: (v) {
          endMode = v;
          changed();
        },
      ),
      if (endMode != 'none') ...[
        LabelledInput(
          key: const ValueKey('phaseEndValue'),
          label: endMode == 'date' ? t.phaseDateEnd : t.phaseExactEnd,
          controller: endValue,
          helper: endMode == 'date' ? t.dateExample : t.phaseExactHelp,
          enabled: enabled,
          keyboardType: TextInputType.datetime,
        ),
        LabelledInput(
          key: const ValueKey('phaseEndZone'),
          label: t.phaseEndZone,
          controller: endZone,
          helper: t.planZoneExample,
          enabled: enabled,
        ),
        Text(t.phaseEndHelp),
      ],
      Heading(t.phaseChangeHeading),
      Text(t.phaseChangeHelp),
      LabelledInput(
        key: const ValueKey('phaseOriginalDate'),
        label: t.phaseOriginalDate,
        controller: originalDate,
        helper: t.dateExample,
        enabled: enabled,
        keyboardType: TextInputType.datetime,
      ),
      VitalButton.secondary(
        onPressed: enabled ? choose : null,
        child: Text(t.review),
      ),
      for (final row in choices)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(expectationLabel(context, ref, t, row)),
            Text(t.phaseSource(dailyIdentityKey(row.identity))),
            if ((row.plannedCount ?? 1) > 1) ...[
              Text(t.phaseBucketHelp(row.plannedCount!)),
              VitalButton.secondary(
                onPressed: enabled
                    ? () => context.push(
                        '/schedule/${item!.id}?plan=${widget.planId}',
                      )
                    : null,
                child: Text(t.edit),
              ),
              VitalButton.secondary(
                onPressed: enabled
                    ? () => context.push('/record/${item!.id}')
                    : null,
                child: Text(t.record),
              ),
            ] else
              Semantics(
                selected: selected?.identity == row.identity,
                child: VitalButton.secondary(
                  onPressed: enabled
                      ? () {
                          selected = row;
                          target.text = '';
                          windowEnd.text = '';
                          windowAnchor.text = '';
                          targetZone.text = row.zoneId;
                          overrideAmount.text = '';
                          changed();
                        }
                      : null,
                  child: Text(t.select),
                ),
              ),
          ],
        ),
      if (selected != null) ...[
        Text(expectationLabel(context, ref, t, selected!)),
        if (selected!.originalTime == null && selected!.windowStart == null)
          Text(t.phaseSingleCount),
        if (selected!.originalTime != null || selected!.windowStart != null)
          LabelledInput(
            key: const ValueKey('phaseTarget'),
            label: selected!.windowStart == null
                ? t.phaseTarget
                : t.phaseWindowStart,
            controller: target,
            helper: t.phaseTargetHelp,
            enabled: enabled,
            keyboardType: TextInputType.datetime,
          ),
        if (selected!.windowStart != null) ...[
          LabelledInput(
            key: const ValueKey('phaseWindowTargetEnd'),
            label: t.phaseWindowEnd,
            controller: windowEnd,
            helper: t.phaseExactHelp,
            enabled: enabled,
            keyboardType: TextInputType.datetime,
          ),
          LabelledInput(
            key: const ValueKey('phaseWindowTargetAnchor'),
            label: t.phaseWindowAnchor,
            controller: windowAnchor,
            helper: t.phaseWindowMoveHelp,
            enabled: enabled,
            keyboardType: TextInputType.datetime,
          ),
        ],
        if ((selected!.originalTime != null || selected!.windowStart != null) &&
            target.text.trim().isNotEmpty)
          LabelledInput(
            key: const ValueKey('phaseTargetZone'),
            label: t.planZone,
            controller: targetZone,
            helper: t.planZoneExample,
            enabled: enabled,
          ),
        LabelledInput(
          key: const ValueKey('phaseOverrideAmount'),
          label: t.phaseAmount,
          controller: overrideAmount,
          helper: '${t.phaseAmountHelp} ${item!.unit}',
          enabled: enabled,
        ),
        for (final row in collisions) ...[
          Text(t.phaseCollision),
          Text(expectationLabel(context, ref, t, row)),
          Text(t.phaseCollisionLabel(dailyIdentityKey(row.identity))),
          if (reviewedCollisions.contains(row.identity)) Text(t.phaseReviewed),
          VitalButton.secondary(
            onPressed: enabled
                ? () {
                    setState(() => reviewedCollisions.add(row.identity));
                    entryChanged();
                  }
                : null,
            child: Text(t.review),
          ),
        ],
        VitalButton.secondary(
          onPressed: enabled ? addOverride : null,
          child: Text(t.add),
        ),
      ],
      for (final o in overrides) ...[
        Text(t.phaseSource(dailyIdentityKey(o.identity))),
        ...overrideReview(o, t),
        VitalButton.secondary(
          onPressed: enabled
              ? () {
                  overrides.remove(o);
                  changed();
                }
              : null,
          child: Text(t.remove),
        ),
      ],
      ?failure(),
      VitalButton.secondary(
        onPressed: enabled ? preview : null,
        child: Text(t.planPreview),
      ),
      if (review case final r?) ...[
        Heading(t.planPreview),
        Text(t.phaseReviewHelp),
        Text(
          t.phaseBefore(
            phaseReviewNextLabel(
              context,
              ref,
              t,
              r.before,
              r.beforeIssue,
              r.plan.plan.pauses.any((p) => p.contains(r.now)),
            ),
          ),
        ),
        Text(
          t.phaseAfter(
            phaseReviewNextLabel(
              context,
              ref,
              t,
              r.after,
              r.afterIssue,
              r.proposed.phases.any(
                (p) => p.pauses.any((v) => v.contains(r.now)),
              ),
            ),
          ),
        ),
        if (r.after == null &&
            r.afterIssue == DailyCalculationIssue.intervalNoAnchor) ...[
          Text(t.intervalNoAnchorHelp),
          VitalButton.secondary(
            onPressed: enabled
                ? () => context.push('/record/${item!.id}')
                : null,
            child: Text(t.record),
          ),
        ],
        PhaseReviewPreview(review: r),
        if (r.proposed.end case final e?)
          Text(
            t.phaseEndSummary(
              e.lastDate?.toString() ??
                  displayStamp(context, ref, e.exclusiveInstant),
              e.zoneId,
            ),
          ),
        VitalButton.secondary(
          onPressed: enabled ? () => setState(() => review = null) : null,
          child: Text(t.cancel),
        ),
      ],
      VitalButton(
        onPressed:
            busy ||
                previewing ||
                conflict ||
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
      SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
    ]);
  }

  List<Widget> overrideReview(OccurrenceOverride o, AppLocalizations t) {
    try {
      final p = candidate(),
          source = [
            ...p.phases,
            ...p.originPhases,
          ].firstWhere((p) => p.versionId == o.versionId);
      final original = DailyResolver()
          .resolveDate(source, o.identity.originalDate, observedZone: zone())
          .firstWhere((r) => r.identity == o.identity);
      final at = o.windowTarget?.start ?? o.targetInstant;
      final date = at == null
          ? o.identity.originalDate
          : DailyResolver().clock.dateAt(
              at,
              o.windowTarget?.zoneId ?? o.targetZoneId!,
            );
      final effective = PhaseResolver()
          .resolveDate(p, date, observedZone: zone())
          .firstWhere((r) => r.identity == o.identity);
      return [
        Text(t.phaseBefore(expectationLabel(context, ref, t, original))),
        Text(t.phaseAfter(expectationLabel(context, ref, t, effective))),
      ];
    } catch (_) {
      return [Text(t.phaseReviewIssue)];
    }
  }

  Widget phaseCard(PhaseEntry p, bool enabled, AppLocalizations t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Heading(t.phaseHeading),
      if (p.source != null) Text(t.phaseEditHelp),
      if (p.source?.effectiveFrom != null)
        Text(
          t.phaseFrom(
            displayStamp(
              context,
              ref,
              p.source!.effectiveFrom!,
              zoneId: p.source!.zoneBasis.zoneFor(zone()),
            ),
          ),
        ),
      if (p.source?.effectiveUntil != null)
        Text(
          t.phaseUntil(
            displayStamp(
              context,
              ref,
              p.source!.effectiveUntil!,
              zoneId: p.source!.zoneBasis.zoneFor(zone()),
            ),
          ),
        ),
      LabelledInput(
        key: ValueKey('phaseStart-${p.id}'),
        label: t.phaseStart,
        controller: p.start,
        helper: t.dateExample,
        enabled: enabled,
        keyboardType: TextInputType.datetime,
      ),
      LabelledInput(
        key: ValueKey('phaseLast-${p.id}'),
        label: t.phaseLast,
        controller: p.last,
        helper: t.planEndHelp,
        enabled: enabled,
        keyboardType: TextInputType.datetime,
      ),
      CalendarChoices(
        value: p.mode,
        enabled: enabled,
        choices: [
          ('count', t.planCount),
          ('slots', t.planTimes),
          ('mixed', t.phaseMixed),
          ('windows', t.phaseWindows),
          ('interval', t.intervalPattern),
          ('prn', t.planAsNeeded),
        ],
        onSelected: (v) {
          p.mode = v;
          if (p.slots.isEmpty) {
            final s = PlanSlotEntry();
            p.slots.add(s);
            for (final c in [s.time, s.amount, s.end, s.anchor]) {
              c.addListener(changed);
            }
          }
          changed();
        },
      ),
      if (p.mode == 'count' || p.mode == 'mixed')
        LabelledInput(
          label: t.planCount,
          controller: p.count,
          enabled: enabled,
          keyboardType: TextInputType.number,
        ),
      if (p.mode == 'count' || p.mode == 'mixed' || p.mode == 'interval')
        LabelledInput(
          label: t.amountLabel,
          controller: p.amount,
          helper: item!.unit,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      if (p.mode == 'mixed') Text(t.phaseMixedHelp),
      if (p.mode == 'windows') Text(t.phaseWindowHelp),
      if (p.mode == 'interval')
        IntervalEditor(
          fields: p.interval,
          enabled: enabled,
          onChanged: changed,
        ),
      if (p.mode == 'slots' || p.mode == 'mixed' || p.mode == 'windows') ...[
        for (final s in p.slots) ...[
          LabelledInput(
            label: p.mode == 'windows' ? t.phaseWindowStart : t.planTime,
            controller: s.time,
            helper: t.timeExample,
            enabled: enabled,
            keyboardType: TextInputType.datetime,
          ),
          if (p.mode == 'windows') ...[
            LabelledInput(
              label: t.phaseWindowEnd,
              controller: s.end,
              helper: t.phaseWindowEndHelp,
              enabled: enabled,
            ),
            LabelledInput(
              label: t.phaseWindowAnchor,
              controller: s.anchor,
              helper: t.phaseWindowAnchorHelp,
              enabled: enabled,
            ),
          ],
          LabelledInput(
            label: t.amountLabel,
            controller: s.amount,
            helper: item!.unit,
            enabled: enabled,
          ),
          if (p.slots.length > 1)
            VitalButton.secondary(
              onPressed: enabled
                  ? () {
                      p.slots.remove(s);
                      s.dispose();
                      changed();
                    }
                  : null,
              child: Text(t.remove),
            ),
        ],
        VitalButton.secondary(
          onPressed: enabled
              ? () {
                  final s = PlanSlotEntry();
                  p.slots.add(s);
                  for (final c in [s.time, s.amount, s.end, s.anchor]) {
                    c.addListener(changed);
                  }
                  changed();
                }
              : null,
          child: Text(t.add),
        ),
      ],
      if (p.mode != 'interval' && p.mode != 'prn')
        CalendarEditor(
          fields: p.calendar,
          enabled: enabled,
          onChanged: changed,
        ),
      if (p.mode != 'prn')
        OnOffEditor(fields: p.blocks, enabled: enabled, onChanged: changed),
      if (phases.length > 1) ...[
        Text(t.phaseRemoveHelp),
        VitalButton.secondary(
          onPressed: enabled
              ? () {
                  phases.remove(p);
                  p.dispose();
                  changed();
                }
              : null,
          child: Text(t.remove),
        ),
      ],
      const SizedBox(height: 24),
    ],
  );
}

class PhaseReviewPreview extends ConsumerWidget {
  const PhaseReviewPreview({super.key, required this.review});
  final PhaseChangeReview review;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context), r = review;
    final ordered = r.proposed.phases.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final date = DailyResolver().clock.dateAt(r.now, r.observedZone);
    final from = date.compareTo(ordered.first.start) < 0
        ? ordered.first.start
        : date;
    DailyExpansion? result;
    try {
      result = PhaseResolver().expand(
        r.proposed,
        from: from,
        toExclusive: from.addDays(7),
        observedZone: r.observedZone,
        maxDates: 700,
        maxRows: 1000,
        now: r.now,
      );
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.planPreviewRange(from.toString(), from.addDays(6).toString())),
        if (result == null)
          Text(t.phaseReviewIssue)
        else ...[
          for (final row in result.rows.take(20))
            Text(expectationLabel(context, ref, t, row)),
          if (result.rows.length > 20) Text(t.planPreviewLimited),
          if (!result.complete) Text(t.planIncomplete),
        ],
        for (var i = 0; i < ordered.length; i++) ...[
          ...phaseTimingSummary(context, ref, t, ordered[i]),
          Text(
            t.phaseBoundary(
              (ordered[i].effectiveFrom == null
                      ? null
                      : displayStamp(
                          context,
                          ref,
                          ordered[i].effectiveFrom!,
                          zoneId: ordered[i].zoneBasis.zoneFor(r.observedZone),
                        )) ??
                  ordered[i].start.toString(),
            ),
          ),
          if (ordered[i].effectiveUntil != null)
            Text(
              t.phaseEndSummary(
                displayStamp(
                  context,
                  ref,
                  ordered[i].effectiveUntil!,
                  zoneId: ordered[i].zoneBasis.zoneFor(r.observedZone),
                ),
                ordered[i].zoneBasis.zoneFor(r.observedZone),
              ),
            ),
          if (ordered[i].endExclusive != null)
            Text(t.planEnds(ordered[i].endExclusive!.addDays(-1).toString())),
          if (i > 0 &&
              ordered[i - 1].endExclusive != null &&
              ordered[i - 1].endExclusive!.compareTo(ordered[i].start) < 0)
            Text(
              t.phaseGap(
                ordered[i - 1].endExclusive!.toString(),
                ordered[i].start.addDays(-1).toString(),
              ),
            ),
        ],
      ],
    );
  }
}

List<Widget> phaseTimingSummary(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations t,
  DailyPlanVersion p,
) {
  return switch (p.timing) {
    AsNeeded() => [Text(t.planPrnHelp)],
    DailyCount(:final count, :final amount) => [
      Text(t.phaseCountSummary('$count', amount.enteredText, amount.unit)),
    ],
    MixedDailyCount(:final count, :final amount, :final slots) => [
      Text(
        t.phaseMixedSummary(
          '$count',
          '${slots.length}',
          amount.enteredText,
          amount.unit,
        ),
      ),
      ...slots.map(
        (s) => Text(
          t.phaseSlotSummary(
            displayWallTime(context, ref, s.time),
            s.amount.enteredText,
            s.amount.unit,
          ),
        ),
      ),
    ],
    DailySlots(:final slots) => [
      for (final s in slots)
        Text(
          t.phaseSlotSummary(
            displayWallTime(context, ref, s.time),
            s.amount.enteredText,
            s.amount.unit,
          ),
        ),
    ],
    DailyWindows(:final windows) => [
      for (final w in windows)
        Text(
          t.phaseWindowEntered(
            displayWallTime(context, ref, w.start),
            displayWallTime(context, ref, w.end),
            w.amount.enteredText,
            w.amount.unit,
            w.reminderAnchor == null
                ? t.phaseNoAnchor
                : displayWallTime(context, ref, w.reminderAnchor!),
          ),
        ),
    ],
    ElapsedInterval(:final duration, :final amount) => [
      Text(
        t.phaseIntervalSummary(
          duration.hoursText,
          amount.enteredText,
          amount.unit,
        ),
      ),
    ],
  };
}

String phaseReviewNextLabel(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations t,
  DailyExpectation? row,
  DailyCalculationIssue? issue,
  bool paused,
) {
  if (row != null) {
    return expectationLabel(context, ref, t, row);
  }
  if (issue == DailyCalculationIssue.intervalNoAnchor) {
    return t.intervalNoAnchor;
  }
  if (issue != null) {
    return t.planCalculationIssue;
  }
  return paused ? t.pauseState : t.planNoNext;
}
