import 'dart:convert';

import '../domain/records.dart';
import '../domain/scheduling/daily_plan.dart';
import '../domain/scheduling/phase_plan.dart';

Map<String, dynamic> dailyObject(String encoded) =>
    jsonDecode(encoded) as Map<String, dynamic>;
List<int>? _time(WallTime? v) => v == null ? null : [v.hour, v.minute];
WallTime? _readTime(dynamic v) =>
    v == null ? null : WallTime((v as List)[0] as int, v[1] as int);
Map<String, Object?> _amount(PlannedAmount v) => {
  'entered': v.enteredText,
  'unit': v.unit,
};
PlannedAmount _readAmount(dynamic v) => PlannedAmount(
  quantity: ExactQuantity.parse(v['entered'] as String),
  enteredText: v['entered'] as String,
  unit: v['unit'] as String,
);
String dailyIdentityKey(DailyIdentity v) => jsonEncode(
  v.intervalSegmentId == null
      ? [v.personId, v.planId, v.originalDate.toString(), v.slotId]
      : [
          v.personId,
          v.planId,
          'interval',
          v.intervalSegmentId,
          v.intervalOrdinal,
          v.sourceActualId,
          v.sourceActualRevision,
        ],
);
Map<String, Object?> encodeDailyIdentity(DailyIdentity v) => {
  'person': v.personId,
  'plan': v.planId,
  'date': v.originalDate.toString(),
  'slot': v.slotId,
  if (v.intervalSegmentId != null) ...{
    'segment': v.intervalSegmentId,
    'ordinal': v.intervalOrdinal,
    'source': v.sourceActualId,
    'sourceRevision': v.sourceActualRevision,
  },
};
DailyIdentity decodeDailyIdentity(dynamic v) => DailyIdentity(
  personId: v['person'] as String,
  planId: v['plan'] as String,
  originalDate: CivilDate.parse(v['date'] as String),
  slotId: v['slot'] as String?,
  intervalSegmentId: v['segment'] as String?,
  intervalOrdinal: v['ordinal'] as int?,
  sourceActualId: v['source'] as String?,
  sourceActualRevision: v['sourceRevision'] as int?,
);
Map<String, Object?> encodeDailyPlan(DailyPlanVersion v) => {
  'person': v.personId,
  'plan': v.planId,
  'item': v.itemId,
  'version': v.versionId,
  'start': v.start.toString(),
  'end': v.endExclusive?.toString(),
  // Additive and omitted for blank text so frozen legacy command shapes stay
  // byte-compatible after an update.
  if (v.instructions.isNotEmpty) 'instructions': v.instructions,
  if (v.effectiveFrom != null)
    'effectiveFrom': v.effectiveFrom!.microsecondsSinceEpoch,
  if (v.effectiveUntil != null)
    'effectiveUntil': v.effectiveUntil!.microsecondsSinceEpoch,
  'home': v.zoneBasis is FixedHome ? (v.zoneBasis as FixedHome).zoneId : null,
  // Preserve legacy daily command payloads for retries after an app update.
  if (v.calendar is! EveryDay) 'calendar': encodeCalendarPattern(v.calendar),
  if (v.pauses.isNotEmpty)
    'pauses': [
      for (final p in v.pauses)
        {
          'start': p.start.microsecondsSinceEpoch,
          'resume': p.resume?.microsecondsSinceEpoch,
        },
    ],
  if (v.onOff != null)
    'onOff': {
      'anchor': v.onOff!.anchor.toString(),
      'on': v.onOff!.onDays,
      'off': v.onOff!.offDays,
    },
  'timing': switch (v.timing) {
    AsNeeded() => {'kind': 'prn'},
    ElapsedInterval(
      :final segmentId,
      :final duration,
      :final mode,
      :final amount,
      :final plannedAnchor,
      :final reminderEnabled,
    ) =>
      {
        'kind': 'interval',
        'segment': segmentId,
        'micros': duration.microseconds,
        'mode': mode.name,
        'amount': _amount(amount),
        'anchor': plannedAnchor?.microsecondsSinceEpoch,
        'reminder': reminderEnabled,
      },
    DailyWindows(:final windows) => {
      'kind': 'windows',
      'windows': [
        for (final w in windows)
          {
            'id': w.id,
            'start': _time(w.start),
            'end': _time(w.end),
            'amount': _amount(w.amount),
            'anchor': _time(w.reminderAnchor),
            'reminder': w.reminderEnabled,
          },
      ],
    },
    MixedDailyCount(:final count, :final amount, :final slots) => {
      'kind': 'mixed',
      'count': count,
      'amount': _amount(amount),
      'slots': [
        for (final s in slots)
          {
            'id': s.id,
            'time': _time(s.time),
            'amount': _amount(s.amount),
            'reminder': s.reminderEnabled,
          },
      ],
    },
    DailyCount(:final count, :final amount) => {
      'kind': 'count',
      'count': count,
      'amount': _amount(amount),
    },
    DailySlots(:final slots) => {
      'kind': 'slots',
      'slots': [
        for (final s in slots)
          {
            'id': s.id,
            'time': _time(s.time),
            'amount': _amount(s.amount),
            'reminder': s.reminderEnabled,
          },
      ],
    },
  },
};
DailyPlanVersion decodeDailyPlan(Map<String, dynamic> v) {
  final t = v['timing'] as Map<String, dynamic>;
  return DailyPlanVersion(
    personId: v['person'] as String,
    planId: v['plan'] as String,
    itemId: v['item'] as String,
    versionId: v['version'] as String,
    start: CivilDate.parse(v['start'] as String),
    endExclusive: v['end'] == null ? null : CivilDate.parse(v['end'] as String),
    instructions: v['instructions'] as String? ?? '',
    effectiveFrom: v['effectiveFrom'] == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(
            v['effectiveFrom'] as int,
            isUtc: true,
          ),
    effectiveUntil: v['effectiveUntil'] == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(
            v['effectiveUntil'] as int,
            isUtc: true,
          ),
    zoneBasis: v['home'] == null
        ? const FollowingLocal()
        : FixedHome(v['home'] as String),
    calendar: v['calendar'] == null
        ? const EveryDay()
        : decodeCalendarPattern(v['calendar'] as Map<String, dynamic>),
    pauses: [
      for (final p in (v['pauses'] as List? ?? const []))
        PlanPause(
          start: DateTime.fromMicrosecondsSinceEpoch(
            p['start'] as int,
            isUtc: true,
          ),
          resume: p['resume'] == null
              ? null
              : DateTime.fromMicrosecondsSinceEpoch(
                  p['resume'] as int,
                  isUtc: true,
                ),
        ),
    ],
    onOff: v['onOff'] == null
        ? null
        : OnOffPattern(
            anchor: CivilDate.parse(v['onOff']['anchor'] as String),
            onDays: v['onOff']['on'] as int,
            offDays: v['onOff']['off'] as int,
          ),
    timing: switch (t['kind']) {
      'prn' => const AsNeeded(),
      'interval' => ElapsedInterval(
        segmentId: t['segment'] as String,
        duration: ExactElapsed.fromMicroseconds(t['micros'] as int),
        mode: IntervalMode.values.byName(t['mode'] as String),
        amount: _readAmount(t['amount']),
        plannedAnchor: t['anchor'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(
                t['anchor'] as int,
                isUtc: true,
              ),
        reminderEnabled: t['reminder'] as bool,
      ),
      'windows' => DailyWindows(
        windows: [
          for (final w in t['windows'] as List)
            DailyWindow(
              id: w['id'] as String,
              start: _readTime(w['start'])!,
              end: _readTime(w['end'])!,
              amount: _readAmount(w['amount']),
              reminderAnchor: _readTime(w['anchor']),
              reminderEnabled: w['reminder'] as bool,
            ),
        ],
      ),
      'mixed' => MixedDailyCount(
        count: t['count'] as int,
        amount: _readAmount(t['amount']),
        slots: [
          for (final s in t['slots'] as List)
            DailySlot(
              id: s['id'] as String,
              time: _readTime(s['time'])!,
              amount: _readAmount(s['amount']),
              reminderEnabled: s['reminder'] as bool,
            ),
        ],
      ),
      'count' => DailyCount(t['count'] as int, _readAmount(t['amount'])),
      'slots' => DailySlots([
        for (final s in t['slots'] as List)
          DailySlot(
            id: s['id'] as String,
            time: _readTime(s['time'])!,
            amount: _readAmount(s['amount']),
            reminderEnabled: s['reminder'] as bool,
          ),
      ]),
      _ => throw const FormatException('daily_timing'),
    },
  );
}

Map<String, Object?> encodeDailyExpectation(DailyExpectation v) => {
  if (v.eligibilityConflict != null)
    'eligibilityConflict': v.eligibilityConflict,
  if (v.windowEndpoints.isNotEmpty)
    'windowEndpoints': [
      for (final e in v.windowEndpoints) encodeDailyExpectation(e),
    ],
  if (v.originalWindowStart != null)
    'originalWindowStart': v.originalWindowStart!.microsecondsSinceEpoch,
  if (v.originalWindowEnd != null)
    'originalWindowEnd': v.originalWindowEnd!.microsecondsSinceEpoch,
  if (v.originalReminderAnchor != null)
    'originalReminderAnchor': v.originalReminderAnchor!.microsecondsSinceEpoch,
  if (v.originalAmount != null) 'originalAmount': _amount(v.originalAmount!),
  if (v.originalInstant != null)
    'originalInstant': v.originalInstant!.microsecondsSinceEpoch,
  if (v.effectiveDate != null) 'effectiveDate': v.effectiveDate.toString(),
  if (v.windowStart != null)
    'windowStart': v.windowStart!.microsecondsSinceEpoch,
  if (v.windowEnd != null) 'windowEnd': v.windowEnd!.microsecondsSinceEpoch,
  if (v.reminderAnchor != null)
    'reminderAnchor': v.reminderAnchor!.microsecondsSinceEpoch,
  'identity': encodeDailyIdentity(v.identity),
  'item': v.itemId,
  'version': v.versionId,
  'zone': v.zoneId,
  'amount': _amount(v.amount),
  'resolution': v.resolution.name,
  'calculator': v.calculatorVersion,
  'tz': v.timezoneDataVersion,
  'original': _time(v.originalTime),
  'effective': _time(v.effectiveTime),
  'instant': v.instant?.microsecondsSinceEpoch,
  'count': v.plannedCount,
  'reminder': v.reminderEnabled,
  'candidates': [for (final c in v.clockCandidates) c.microsecondsSinceEpoch],
};
DailyExpectation decodeDailyExpectation(Map<String, dynamic> v) =>
    DailyExpectation(
      eligibilityConflict: v['eligibilityConflict'] as String?,
      windowEndpoints: [
        for (final e in v['windowEndpoints'] as List? ?? const [])
          decodeDailyExpectation(Map<String, dynamic>.from(e as Map)),
      ],
      originalWindowStart: _instant(v['originalWindowStart']),
      originalWindowEnd: _instant(v['originalWindowEnd']),
      originalReminderAnchor: _instant(v['originalReminderAnchor']),
      originalAmount: v['originalAmount'] == null
          ? null
          : _readAmount(v['originalAmount']),
      originalInstant: _instant(v['originalInstant']),
      effectiveDate: v['effectiveDate'] == null
          ? null
          : CivilDate.parse(v['effectiveDate'] as String),
      windowStart: _instant(v['windowStart']),
      windowEnd: _instant(v['windowEnd']),
      reminderAnchor: _instant(v['reminderAnchor']),
      identity: decodeDailyIdentity(v['identity']),
      itemId: v['item'] as String,
      versionId: v['version'] as String,
      zoneId: v['zone'] as String,
      amount: _readAmount(v['amount']),
      resolution: DailyResolution.values.byName(v['resolution'] as String),
      calculatorVersion: v['calculator'] as String,
      timezoneDataVersion: v['tz'] as String,
      originalTime: _readTime(v['original']),
      effectiveTime: _readTime(v['effective']),
      instant: v['instant'] == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              v['instant'] as int,
              isUtc: true,
            ),
      plannedCount: v['count'] as int?,
      reminderEnabled: v['reminder'] as bool,
      clockCandidates: [
        for (final c in v['candidates'] as List)
          DateTime.fromMicrosecondsSinceEpoch(c as int, isUtc: true),
      ],
    );
Map<String, Object?> encodeDailyChoice(DailyClockChoice v) => {
  'identity': encodeDailyIdentity(v.identity),
  'version': v.versionId,
  'zone': v.zoneId,
  'original': _time(v.originalTime),
  'decision': switch (v.decision) {
    NoAlert() => {'kind': 'none'},
    ChooseClockInstance(:final index) => {'kind': 'instance', 'index': index},
    ReplaceClockTime(:final time, :final instanceIndex) => {
      'kind': 'replace',
      'time': _time(time),
      'index': instanceIndex,
    },
  },
};
DailyClockChoice decodeDailyChoice(Map<String, dynamic> v) {
  final d = v['decision'] as Map<String, dynamic>;
  return DailyClockChoice(
    identity: decodeDailyIdentity(v['identity']),
    versionId: v['version'] as String,
    zoneId: v['zone'] as String,
    originalTime: _readTime(v['original'])!,
    decision: switch (d['kind']) {
      'none' => const NoAlert(),
      'instance' => ChooseClockInstance(d['index'] as int),
      'replace' => ReplaceClockTime(
        _readTime(d['time'])!,
        instanceIndex: d['index'] as int?,
      ),
      _ => throw const FormatException('daily_choice'),
    },
  );
}

/// Encodes a versioned calendar rule independently of its effective bounds.
Map<String, Object?> encodeCalendarPattern(CalendarPattern value) => {
  'version': 1,
  ...switch (value) {
    EveryDay() => {'kind': 'daily'},
    UnsupportedCalendarPattern(:final reason) => {
      'kind': 'unsupported',
      'reason': reason,
    },
    SelectedWeekdays(:final weekdays) => {
      'kind': 'weekdays',
      'days': weekdays.toList()..sort(),
    },
    EveryNDays(:final anchor, :final interval) => {
      'kind': 'days',
      'anchor': anchor.toString(),
      'interval': interval,
    },
    EveryNWeeks(:final anchorWeekStart, :final interval, :final weekdays) => {
      'kind': 'weeks',
      'anchor': anchorWeekStart.toString(),
      'interval': interval,
      'days': weekdays.toList()..sort(),
    },
    EveryNMonths(:final anchorMonth, :final interval, :final selector) => {
      'kind': 'months',
      'anchor': anchorMonth.toString(),
      'interval': interval,
      'selector': switch (selector) {
        DayOfMonth(:final day, :final missingDatePolicy) => {
          'kind': 'day',
          'day': day,
          'missing': missingDatePolicy?.name,
        },
        OrdinalWeekday(
          :final ordinal,
          :final weekday,
          :final missingDatePolicy,
        ) =>
          {
            'kind': 'ordinal',
            'ordinal': ordinal,
            'weekday': weekday,
            'missing': missingDatePolicy?.name,
          },
        LastWeekday(:final weekday) => {'kind': 'last', 'weekday': weekday},
      },
    },
  },
};
CalendarPattern decodeCalendarPattern(Map<String, dynamic> value) {
  if (value['version'] != 1) throw const FormatException('calendar_version');
  CivilDate anchor() => CivilDate.parse(value['anchor'] as String);
  List<int> weekdays() => (value['days'] as List).cast<int>();
  return switch (value['kind']) {
    'daily' => const EveryDay(),
    'unsupported' => UnsupportedCalendarPattern(value['reason'] as String),
    'weekdays' => SelectedWeekdays(weekdays()),
    'days' => EveryNDays(anchor: anchor(), interval: value['interval'] as int),
    'weeks' => EveryNWeeks(
      anchorWeekStart: anchor(),
      interval: value['interval'] as int,
      weekdays: weekdays(),
    ),
    'months' => EveryNMonths(
      anchorMonth: anchor(),
      interval: value['interval'] as int,
      selector: _decodeMonthSelector(value['selector'] as Map<String, dynamic>),
    ),
    _ => throw const FormatException('calendar_kind'),
  };
}

MonthSelector _decodeMonthSelector(Map<String, dynamic> value) {
  final missing = value['missing'] == null
      ? null
      : MissingDatePolicy.values.byName(value['missing'] as String);
  return switch (value['kind']) {
    'day' => DayOfMonth(value['day'] as int, missingDatePolicy: missing),
    'ordinal' => OrdinalWeekday(
      value['ordinal'] as int,
      value['weekday'] as int,
      missingDatePolicy: missing,
    ),
    'last' => LastWeekday(value['weekday'] as int),
    _ => throw const FormatException('calendar_selector'),
  };
}

DateTime? _instant(dynamic value) => value == null
    ? null
    : DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true);
Map<String, Object?> encodePhasePlan(PhasePlan plan) => {
  'phases': [for (final p in plan.phases) encodeDailyPlan(p)],
  if (plan.originPhases.isNotEmpty)
    'originPhases': [for (final p in plan.originPhases) encodeDailyPlan(p)],
  if (plan.end != null)
    'end': {
      'zone': plan.end!.zoneId,
      'instant': plan.end!.exclusiveInstant.microsecondsSinceEpoch,
      'lastDate': plan.end!.lastDate?.toString(),
    },
  if (plan.overrides.isNotEmpty)
    'overrides': [
      for (final o in plan.overrides)
        {
          'identity': encodeDailyIdentity(o.identity),
          'version': o.versionId,
          if (o.windowTarget != null)
            'windowTarget': {
              'start': o.windowTarget!.start.microsecondsSinceEpoch,
              'end': o.windowTarget!.end.microsecondsSinceEpoch,
              'zone': o.windowTarget!.zoneId,
              'anchor': o.windowTarget!.reminderAnchor?.microsecondsSinceEpoch,
            },
          if (o.targetInstant != null)
            'target': o.targetInstant!.microsecondsSinceEpoch,
          if (o.targetZoneId != null) 'zone': o.targetZoneId,
          if (o.amount != null) 'amount': _amount(o.amount!),
          'collisions': [
            for (final c in o.reviewedCollisions) encodeDailyIdentity(c),
          ],
        },
    ],
};
PhasePlan decodePhasePlan(Map<String, dynamic> v) => PhasePlan(
  phases: [
    for (final p in v['phases'] as List)
      decodeDailyPlan(Map<String, dynamic>.from(p as Map)),
  ],
  originPhases: [
    for (final p in v['originPhases'] as List? ?? const [])
      decodeDailyPlan(Map<String, dynamic>.from(p as Map)),
  ],
  end: v['end'] == null
      ? null
      : PlanEnd(
          zoneId: v['end']['zone'] as String,
          exclusiveInstant: _instant(v['end']['instant'])!,
          lastDate: v['end']['lastDate'] == null
              ? null
              : CivilDate.parse(v['end']['lastDate'] as String),
        ),
  overrides: [
    for (final o in v['overrides'] as List? ?? const [])
      OccurrenceOverride(
        identity: decodeDailyIdentity(o['identity']),
        versionId: o['version'] as String,
        windowTarget: o['windowTarget'] == null
            ? null
            : WindowOverrideTarget(
                start: _instant(o['windowTarget']['start'])!,
                end: _instant(o['windowTarget']['end'])!,
                zoneId: o['windowTarget']['zone'] as String,
                reminderAnchor: _instant(o['windowTarget']['anchor']),
              ),
        targetInstant: _instant(o['target']),
        targetZoneId: o['zone'] as String?,
        amount: o['amount'] == null ? null : _readAmount(o['amount']),
        reviewedCollisions: [
          for (final c in o['collisions'] as List) decodeDailyIdentity(c),
        ],
      ),
  ],
);
