import 'daily_plan.dart';
import 'iana_clock.dart';
import 'interval_resolver.dart';
import 'pause_eligibility.dart';

enum DailyCalculationIssue {
  unsupportedTimezoneRange,
  observedZoneUnavailable,
  unsupportedCalendarComposition,
  calendarWorkLimit,
  calendarRangeLimit,
  intervalNoAnchor,
  intervalWorkLimit,
  intervalRangeLimit,
  phaseOriginUnavailable,
  phaseClockUnresolved,
}

final class DailyExpansion {
  DailyExpansion(
    Iterable<DailyExpectation> rows, {
    required this.complete,
    required this.datesExamined,
    this.resumeDate,
    this.resumeInstant,
    this.issue,
  }) : rows = List.unmodifiable(rows);
  final List<DailyExpectation> rows;
  final bool complete;
  final int datesExamined;

  /// If incomplete, restart at this date; no partial date is emitted.
  final CivilDate? resumeDate;

  /// Elapsed ranges resume exactly here; a date alone may repeat prior rows.
  final DateTime? resumeInstant;
  final DailyCalculationIssue? issue;
}

final class DailyNext {
  DailyNext({
    this.next,
    required this.complete,
    required this.datesExamined,
    this.issue,
    this.calendarDate,
    Iterable<DailyExpectation> needsReview = const [],
  }) : needsReview = List.unmodifiable(needsReview);
  final DailyExpectation? next;
  final CivilDate? calendarDate;
  final bool complete;
  final int datesExamined;
  final List<DailyExpectation> needsReview;
  final DailyCalculationIssue? issue;
}

/// The same pure calculation serves previews, feeds and historical capture.
/// No methods write records, infer actual use, or register OS reminders.
final class DailyResolver {
  DailyResolver({IanaClock? clock}) : clock = clock ?? IanaClock();
  final IanaClock clock;
  static const calculatorVersion = 'calendar-1';
  static const selector = CalendarSelector();

  CivilDate currentDate(
    DailyPlanVersion plan, {
    required DateTime now,
    required String observedZone,
  }) => clock.dateAt(now, plan.zoneBasis.zoneFor(observedZone));

  List<DailyExpectation> resolveDate(
    DailyPlanVersion plan,
    CivilDate date, {
    required String observedZone,
    Map<DailyIdentity, DailyClockChoice> decisions = const {},
    Map<DailyIdentity, DailyExpectation> historical = const {},
    Iterable<IntervalSource> intervalSources = const [],
    DateTime? now,
  }) {
    for (final entry in historical.entries) {
      if (entry.key != entry.value.identity) {
        throw ArgumentError('historical_identity_mismatch');
      }
    }
    if (!plan.includes(date)) return const [];
    if (plan.timing is ElapsedInterval) {
      final expansion = IntervalResolver(clock: clock).expandDates(
        plan,
        from: date,
        toExclusive: date.addDays(1),
        now: now ?? DateTime.now().toUtc(),
        observedZone: observedZone,
        sources: intervalSources,
        maxRows: 100000,
      );
      if (!expansion.complete) {
        throw StateError('incomplete_interval_date:${expansion.issue}');
      }
      return _intervalHistory(plan, expansion.rows, historical);
    }

    if (plan.calendar is UnsupportedCalendarPattern) {
      throw UnsupportedError('unsupported_calendar_composition');
    }
    if (!selector.includes(plan.calendar, date) ||
        plan.onOff != null && !plan.onOff!.includes(date)) {
      return const [];
    }
    final zoneId = plan.zoneBasis.zoneFor(observedZone);
    clock.validateZone(zoneId);
    final eligibility = PauseEligibility(clock);
    if (plan.timing is DailyCount &&
        !eligibility.hasActiveDate(plan, date, zoneId)) {
      return const [];
    }
    DailyExpectation retain(DailyExpectation row) {
      final saved = historical[row.identity];
      if (saved == null) return row;
      if (saved.identity != row.identity || saved.itemId != plan.itemId) {
        throw ArgumentError('historical_owner_or_item_mismatch');
      }
      return saved;
    }

    return switch (plan.timing) {
      AsNeeded() => const [],
      ElapsedInterval() => throw StateError('interval_already_resolved'),
      DailyCount(:final count, :final amount) => [
        retain(
          DailyExpectation(
            identity: DailyIdentity(
              personId: plan.personId,
              planId: plan.planId,
              originalDate: date,
            ),
            itemId: plan.itemId,
            versionId: plan.versionId,
            zoneId: zoneId,
            amount: amount,
            resolution: DailyResolution.untimed,
            calculatorVersion: calculatorVersion,
            timezoneDataVersion: IanaClock.dataVersion,
            plannedCount: count,
          ),
        ),
      ],
      MixedDailyCount(:final count, :final amount, :final slots) => [
        ...resolveDate(
          _timing(plan, DailySlots(slots)),
          date,
          observedZone: observedZone,
          decisions: decisions,
          historical: historical,
        ),
        ...resolveDate(
          _timing(plan, DailyCount(count - slots.length, amount)),
          date,
          observedZone: observedZone,
          historical: historical,
        ),
      ],
      DailyWindows(:final windows) =>
        [
              for (final window in windows)
                _window(plan, date, window, zoneId, decisions, historical),
            ]
            .where(
              (row) =>
                  row.eligibilityConflict != null ||
                  (row.windowStart != null
                      ? plan.includesInstant(row.windowStart!) &&
                            eligibility.containing(plan, row.windowStart!) ==
                                null
                      : eligibility.hasActiveDate(plan, date, zoneId)),
            )
            .toList(),
      DailySlots(:final slots) =>
        [
              for (final slot in slots)
                _slot(plan, date, slot, zoneId, decisions, historical),
            ]
            .where(
              (row) => row.instant != null
                  ? plan.includesInstant(row.instant!) &&
                        eligibility.containing(plan, row.instant!) == null
                  : eligibility.hasActiveDate(plan, date, zoneId) &&
                        (row.clockCandidates.isEmpty ||
                            row.clockCandidates.any(plan.includesInstant)),
            )
            .toList(),
    };
  }

  DailyPlanVersion _timing(DailyPlanVersion plan, DailyTiming timing) =>
      DailyPlanVersion(
        personId: plan.personId,
        planId: plan.planId,
        itemId: plan.itemId,
        versionId: plan.versionId,
        start: plan.start,
        endExclusive: plan.endExclusive,
        timing: timing,
        zoneBasis: plan.zoneBasis,
        calendar: plan.calendar,
        pauses: plan.pauses,
        onOff: plan.onOff,
        effectiveFrom: plan.effectiveFrom,
        effectiveUntil: plan.effectiveUntil,
      );

  DailyExpectation _window(
    DailyPlanVersion plan,
    CivilDate date,
    DailyWindow window,
    String zoneId,
    Map<DailyIdentity, DailyClockChoice> decisions,
    Map<DailyIdentity, DailyExpectation> historical,
  ) {
    final identity = DailyIdentity(
      personId: plan.personId,
      planId: plan.planId,
      originalDate: date,
      slotId: window.id,
    );
    if (historical[identity] case final saved?) return saved;
    final endDate = window.end.compareTo(window.start) <= 0
        ? date.addDays(1)
        : date;
    // Endpoint choices are scoped independently; neither endpoint is a dose.
    DailyExpectation endpoint(String suffix, CivilDate day, WallTime time) =>
        _slot(
          plan,
          day,
          DailySlot(
            id: '${window.id}:$suffix',
            time: time,
            amount: window.amount,
            reminderEnabled: false,
          ),
          zoneId,
          decisions,
          const {},
        );
    final start = endpoint('start', date, window.start);
    final end = endpoint('end', endDate, window.end);
    DailyExpectation? anchor;
    if (window.reminderAnchor case final time?) {
      final anchorDate = endDate != date && time.compareTo(window.start) < 0
          ? endDate
          : date;
      anchor = _slot(
        plan,
        anchorDate,
        DailySlot(
          id: window.id,
          time: time,
          amount: window.amount,
          reminderEnabled: window.reminderEnabled,
        ),
        zoneId,
        decisions,
        const {},
      );
    }
    final unresolved = [
      start,
      end,
      ?anchor,
    ].where((row) => row.resolution != DailyResolution.exact).firstOrNull;
    String? eligibilityConflict;
    if (start.instant != null && end.instant != null) {
      if (!end.instant!.isAfter(start.instant!)) {
        throw ArgumentError('invalid_window_clock_order');
      }
      final lower = plan.effectiveFrom;
      final upper = plan.effectiveUntil;
      final civilUpper = plan.endExclusive == null
          ? null
          : PauseEligibility(clock).boundary(plan.endExclusive!, zoneId);
      if (lower != null &&
              start.instant!.isBefore(lower) &&
              end.instant!.isAfter(lower) ||
          [upper, civilUpper].whereType<DateTime>().any(
            (bound) =>
                start.instant!.isBefore(bound) && end.instant!.isAfter(bound),
          )) {
        eligibilityConflict = 'window_crosses_version_boundary';
      }
      final eligibility = PauseEligibility(clock);
      if (plan.pauses.any(
        (p) =>
            p.start.isBefore(end.instant!) &&
            (p.resume == null || p.resume!.isAfter(start.instant!)) &&
            !(!p.start.isAfter(start.instant!) &&
                (p.resume == null || !p.resume!.isBefore(end.instant!))),
      )) {
        eligibilityConflict = 'window_crosses_pause';
      }
      // Exercise the same supported-zone boundary policy as exact slots.
      eligibility.hasActiveDate(plan, date, zoneId);
    }
    return DailyExpectation(
      identity: identity,
      itemId: plan.itemId,
      versionId: plan.versionId,
      zoneId: zoneId,
      amount: window.amount,
      resolution:
          unresolved?.resolution ??
          (anchor == null ? DailyResolution.noAlert : DailyResolution.exact),
      calculatorVersion: calculatorVersion,
      timezoneDataVersion: IanaClock.dataVersion,
      originalTime: window.start,
      effectiveTime: anchor?.effectiveTime ?? window.start,
      instant: unresolved == null ? anchor?.instant : null,
      clockCandidates:
          unresolved?.clockCandidates ?? anchor?.clockCandidates ?? const [],
      reminderEnabled: window.reminderEnabled,
      eligibilityConflict: eligibilityConflict,
      windowEndpoints: [start, end, ?anchor],
      windowStart: start.instant,
      windowEnd: end.instant,
      reminderAnchor: anchor?.instant,
    );
  }

  DailyExpectation _slot(
    DailyPlanVersion plan,
    CivilDate date,
    DailySlot slot,
    String zoneId,
    Map<DailyIdentity, DailyClockChoice> decisions,
    Map<DailyIdentity, DailyExpectation> historical,
  ) {
    final identity = DailyIdentity(
      personId: plan.personId,
      planId: plan.planId,
      originalDate: date,
      slotId: slot.id,
    );
    final captured = historical[identity];
    if (captured != null) {
      if (captured.itemId != plan.itemId) {
        throw ArgumentError('historical_owner_or_item_mismatch');
      }
      return captured;
    }
    final original = clock.candidates(date, slot.time, zoneId);
    final choice = decisions[identity];
    if (choice != null &&
        (choice.identity != identity ||
            choice.versionId != plan.versionId ||
            choice.zoneId != zoneId ||
            choice.originalTime != slot.time)) {
      throw ArgumentError('stale_clock_choice');
    }
    final decision = choice?.decision;
    var effectiveTime = slot.time;
    var candidates = original;
    int? selected;
    var noAlert = false;
    switch (decision) {
      case null:
        break;
      case NoAlert():
        if (original.isNotEmpty) {
          throw ArgumentError('no_alert_requires_missing_clock');
        }
        noAlert = true;
      case ChooseClockInstance(:final index):
        if (original.length < 2 || index < 0 || index >= original.length) {
          throw ArgumentError('invalid_clock_instance');
        }
        selected = index;
      case ReplaceClockTime(:final time, :final instanceIndex):
        if (original.isNotEmpty) {
          throw ArgumentError('replacement_requires_missing_clock');
        }
        effectiveTime = time;
        candidates = clock.candidates(date, time, zoneId);
        if (candidates.isEmpty ||
            (candidates.length > 1 && instanceIndex == null) ||
            (instanceIndex != null &&
                (instanceIndex < 0 || instanceIndex >= candidates.length))) {
          throw ArgumentError('invalid_clock_replacement');
        }
        selected = instanceIndex ?? 0;
    }
    final resolution = noAlert
        ? DailyResolution.noAlert
        : candidates.isEmpty
        ? DailyResolution.missingClock
        : candidates.length > 1 && selected == null
        ? DailyResolution.repeatedClock
        : DailyResolution.exact;
    return DailyExpectation(
      identity: identity,
      itemId: plan.itemId,
      versionId: plan.versionId,
      zoneId: zoneId,
      amount: slot.amount,
      resolution: resolution,
      calculatorVersion: calculatorVersion,
      timezoneDataVersion: IanaClock.dataVersion,
      originalTime: slot.time,
      effectiveTime: effectiveTime,
      instant: resolution == DailyResolution.exact
          ? candidates[selected ?? 0]
          : null,
      reminderEnabled: slot.reminderEnabled,
      clockCandidates: candidates,
    );
  }

  /// Expands plan calendar dates [from, toExclusive), never implicit midnights.
  DailyExpansion expand(
    DailyPlanVersion plan, {
    required CivilDate from,
    required CivilDate toExclusive,
    required String observedZone,
    required int maxDates,
    required int maxRows,
    Map<DailyIdentity, DailyClockChoice> decisions = const {},
    Map<DailyIdentity, DailyExpectation> historical = const {},
    Iterable<IntervalSource> intervalSources = const [],
    DateTime? now,
  }) {
    _budget(maxDates, maxRows);
    if (plan.timing is ElapsedInterval) {
      final result = IntervalResolver(clock: clock).expandDates(
        plan,
        from: from,
        toExclusive: toExclusive,
        now: now ?? DateTime.now().toUtc(),
        observedZone: observedZone,
        sources: intervalSources,
        maxRows: maxRows,
      );
      return DailyExpansion(
        _intervalHistory(plan, result.rows, historical),
        complete: result.complete,
        datesExamined: 0,
        issue: intervalIssue(result.issue),
        resumeInstant: result.resumeInstant,
        resumeDate: result.resumeInstant == null
            ? null
            : clock.dateAt(
                result.resumeInstant!,
                plan.zoneBasis.zoneFor(observedZone),
              ),
      );
    }

    if (toExclusive.compareTo(from) < 0) throw ArgumentError('reversed_range');
    if (plan.timing is AsNeeded) {
      return DailyExpansion([], complete: true, datesExamined: 0);
    }
    var date = from.compareTo(plan.start) < 0 ? plan.start : from;
    final end =
        plan.endExclusive != null &&
            plan.endExclusive!.compareTo(toExclusive) < 0
        ? plan.endExclusive!
        : toExclusive;
    final rows = <DailyExpectation>[];
    var examined = 0;
    while (date.compareTo(end) < 0) {
      final CalendarResult selected;
      try {
        selected = PauseEligibility(clock).selected(
          plan,
          date,
          zoneId: plan.zoneBasis.zoneFor(observedZone),
          endExclusive: end,
        );
      } on UnsupportedClockRange {
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: date,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      } on PauseBoundaryUnavailable {
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: date,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      }
      if (!selected.complete) {
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: date,
          issue: _calendarIssue(selected.issue),
        );
      }
      if (selected.date == null) break;
      date = selected.date!;
      if (examined >= maxDates) {
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: date,
        );
      }
      final rowsPerDay = switch (plan.timing) {
        AsNeeded() => 0,
        ElapsedInterval() => throw StateError('interval_already_expanded'),
        DailyCount() => 1,
        MixedDailyCount(:final slots) => slots.length + 1,
        DailyWindows(:final windows) => windows.length,
        DailySlots(:final slots) => slots.length,
      };
      if (rows.length + rowsPerDay > maxRows) {
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: date,
        );
      }
      final List<DailyExpectation> dayRows;
      try {
        dayRows = resolveDate(
          plan,
          date,
          observedZone: observedZone,
          decisions: decisions,
          historical: historical,
        );
      } on PauseBoundaryUnavailable {
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: date,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      } on UnsupportedClockRange {
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: date,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      }
      if (rows.length + dayRows.length > maxRows) {
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: date,
        );
      }
      rows.addAll(dayRows);
      examined++;
      if (date == CivilDate(9999, 12, 31)) break;
      date = date.addDays(1);
    }
    return DailyExpansion(rows, complete: true, datesExamined: examined);
  }

  /// Strict next calendar date, independent of clocks and reminder horizons.
  CalendarResult nextCalendarDate(
    DailyPlanVersion plan, {
    required CivilDate after,
    int maxCandidates = 4800,
  }) {
    if (plan.timing is AsNeeded || plan.timing is ElapsedInterval) {
      return const CalendarResult(complete: true, candidatesExamined: 0);
    }
    if (after == CivilDate(9999, 12, 31)) {
      return const CalendarResult(
        complete: false,
        candidatesExamined: 0,
        issue: CalendarIssue.calendarRangeLimit,
      );
    }
    return _selected(plan, after.addDays(1), maxCandidates: maxCandidates);
  }

  CalendarResult _selected(
    DailyPlanVersion plan,
    CivilDate from, {
    int maxCandidates = 4800,
    String? observedZone,
  }) => PauseEligibility(clock).selected(
    plan,
    from,
    zoneId: observedZone == null ? null : plan.zoneBasis.zoneFor(observedZone),
    maxCandidates: maxCandidates,
  );

  DailyCalculationIssue? _calendarIssue(CalendarIssue? issue) =>
      switch (issue) {
        null => null,
        CalendarIssue.workLimit => DailyCalculationIssue.calendarWorkLimit,
        CalendarIssue.unsupportedComposition =>
          DailyCalculationIssue.unsupportedCalendarComposition,
        CalendarIssue.calendarRangeLimit =>
          DailyCalculationIssue.calendarRangeLimit,
      };

  /// Earliest planned calendar date on/after [from], including untimed/review.
  DailyNext nextDate(
    DailyPlanVersion plan, {
    required CivilDate from,
    required String observedZone,
    Map<DailyIdentity, DailyClockChoice> decisions = const {},
    Map<DailyIdentity, DailyExpectation> historical = const {},
    Iterable<IntervalSource> intervalSources = const [],
    DateTime? now,
  }) {
    if (plan.timing is ElapsedInterval) {
      final result = IntervalResolver(clock: clock).nextDate(
        plan,
        from: from,
        now: now ?? DateTime.now().toUtc(),
        observedZone: observedZone,
        sources: intervalSources,
      );
      return DailyNext(
        next: result.next,
        complete: result.complete,
        datesExamined: 0,
        issue: intervalIssue(result.issue),
      );
    }
    if (plan.timing is AsNeeded) {
      return DailyNext(complete: true, datesExamined: 0);
    }
    var cursor = from;
    for (var examined = 0; examined < 4800; examined++) {
      CivilDate? date;
      try {
        final selected = _selected(plan, cursor, observedZone: observedZone);
        date = selected.date;
        if (date == null) {
          return DailyNext(
            complete: selected.complete,
            datesExamined: examined,
            issue: _calendarIssue(selected.issue),
          );
        }
        final rows = resolveDate(
          plan,
          date,
          observedZone: observedZone,
          decisions: decisions,
          historical: historical,
        );
        final ordered = rows.toList()
          ..sort((a, b) {
            if (a.originalTime == null || b.originalTime == null) return 0;
            final time = a.originalTime!.compareTo(b.originalTime!);
            return time != 0
                ? time
                : a.identity.slotId!.compareTo(b.identity.slotId!);
          });
        if (ordered.isNotEmpty) {
          return DailyNext(
            next: ordered.first,
            calendarDate: date,
            complete: true,
            datesExamined: examined + 1,
          );
        }
      } on UnsupportedClockRange {
        return DailyNext(
          complete: false,
          datesExamined: examined,
          calendarDate: date,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      } on PauseBoundaryUnavailable {
        return DailyNext(
          complete: false,
          datesExamined: examined,
          calendarDate: date,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      }
      if (date == CivilDate(9999, 12, 31)) {
        return DailyNext(complete: true, datesExamined: examined + 1);
      }
      cursor = date.addDays(1);
    }
    return DailyNext(
      complete: false,
      datesExamined: 4800,
      issue: DailyCalculationIssue.calendarWorkLimit,
    );
  }

  /// Strict instant seek counts selected dates, never replays unselected days.
  DailyNext nextInstant(
    DailyPlanVersion plan, {
    required DateTime after,
    required String observedZone,
    required int maxDates,
    Map<DailyIdentity, DailyClockChoice> decisions = const {},
    Map<DailyIdentity, DailyExpectation> historical = const {},
    Iterable<IntervalSource> intervalSources = const [],
    DateTime? now,
  }) {
    _budget(maxDates, 1);
    if (plan.timing is ElapsedInterval) {
      final result = IntervalResolver(clock: clock).next(
        plan,
        after: after.toUtc(),
        now: now ?? after.toUtc(),
        observedZone: observedZone,
        sources: intervalSources,
      );
      return DailyNext(
        next: result.next,
        complete: result.complete,
        datesExamined: 0,
        issue: intervalIssue(result.issue),
      );
    }
    if (plan.timing is! DailySlots &&
        plan.timing is! DailyWindows &&
        plan.timing is! MixedDailyCount) {
      return DailyNext(complete: true, datesExamined: 0);
    }
    CivilDate from;
    try {
      from = currentDate(plan, now: after, observedZone: observedZone);
    } on UnsupportedClockRange {
      return DailyNext(
        complete: false,
        datesExamined: 0,
        issue: DailyCalculationIssue.unsupportedTimezoneRange,
      );
    }
    final review = <DailyExpectation>[];
    for (var examined = 0; examined < maxDates; examined++) {
      final CalendarResult selected;
      try {
        selected = _selected(plan, from, observedZone: observedZone);
      } on UnsupportedClockRange {
        return DailyNext(
          complete: false,
          datesExamined: examined,
          needsReview: review,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      } on PauseBoundaryUnavailable {
        return DailyNext(
          complete: false,
          datesExamined: examined,
          needsReview: review,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      }
      final date = selected.date;
      if (date == null) {
        return DailyNext(
          complete: selected.complete,
          datesExamined: examined,
          needsReview: review,
          issue: _calendarIssue(selected.issue),
        );
      }
      final List<DailyExpectation> rows;
      try {
        rows = resolveDate(
          plan,
          date,
          observedZone: observedZone,
          decisions: decisions,
          historical: historical,
        );
      } on PauseBoundaryUnavailable {
        return DailyNext(
          complete: false,
          datesExamined: examined,
          calendarDate: date,
          needsReview: review,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      } on UnsupportedClockRange {
        return DailyNext(
          complete: false,
          datesExamined: examined,
          calendarDate: date,
          needsReview: review,
          issue: DailyCalculationIssue.unsupportedTimezoneRange,
        );
      }
      review.addAll(
        rows.where(
          (r) =>
              r.resolution == DailyResolution.missingClock ||
              r.resolution == DailyResolution.repeatedClock,
        ),
      );
      final candidates =
          rows
              .where((r) => r.instant != null && r.instant!.isAfter(after))
              .toList()
            ..sort((a, b) {
              final instant = a.instant!.compareTo(b.instant!);
              return instant != 0
                  ? instant
                  : a.identity.slotId!.compareTo(b.identity.slotId!);
            });
      if (candidates.isNotEmpty) {
        return DailyNext(
          next: candidates.first,
          calendarDate: date,
          complete: true,
          datesExamined: examined + 1,
          needsReview: review,
        );
      }
      if (date == CivilDate(9999, 12, 31)) {
        return DailyNext(
          complete: true,
          datesExamined: examined + 1,
          needsReview: review,
        );
      }
      from = date.addDays(1);
    }
    final CalendarResult following;
    try {
      following = _selected(plan, from, observedZone: observedZone);
    } on UnsupportedClockRange {
      return DailyNext(
        complete: false,
        datesExamined: maxDates,
        needsReview: review,
        issue: DailyCalculationIssue.unsupportedTimezoneRange,
      );
    } on PauseBoundaryUnavailable {
      return DailyNext(
        complete: false,
        datesExamined: maxDates,
        needsReview: review,
        issue: DailyCalculationIssue.unsupportedTimezoneRange,
      );
    }
    return DailyNext(
      complete: following.date == null && following.complete,
      datesExamined: maxDates,
      needsReview: review,
      calendarDate: following.date,
      issue: _calendarIssue(following.issue),
    );
  }

  List<DailyExpectation> _intervalHistory(
    DailyPlanVersion plan,
    Iterable<DailyExpectation> rows,
    Map<DailyIdentity, DailyExpectation> historical,
  ) {
    for (final entry in historical.entries) {
      if (entry.key != entry.value.identity) {
        throw ArgumentError('historical_identity_mismatch');
      }
    }
    return [
      for (final row in rows)
        _retainInterval(plan, row, historical[row.identity]),
    ];
  }

  DailyExpectation _retainInterval(
    DailyPlanVersion plan,
    DailyExpectation row,
    DailyExpectation? saved,
  ) {
    if (saved == null) return row;
    if (saved.identity != row.identity || saved.itemId != plan.itemId) {
      throw ArgumentError('historical_owner_or_item_mismatch');
    }
    return saved;
  }

  static DailyCalculationIssue? intervalIssue(IntervalIssue? issue) =>
      switch (issue) {
        null => null,
        IntervalIssue.noAnchor => DailyCalculationIssue.intervalNoAnchor,
        IntervalIssue.workLimit => DailyCalculationIssue.intervalWorkLimit,
        IntervalIssue.rangeLimit => DailyCalculationIssue.intervalRangeLimit,
        IntervalIssue.unsupportedTimezoneRange =>
          DailyCalculationIssue.unsupportedTimezoneRange,
      };

  void _budget(int dates, int rows) {
    if (dates <= 0 || dates > 100000 || rows <= 0 || rows > 100000) {
      throw ArgumentError('invalid_calculation_budget');
    }
  }
}
