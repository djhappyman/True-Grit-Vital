import '../records.dart';
import 'calendar_pattern.dart';
import 'pause_pattern.dart';
export 'calendar_pattern.dart';
export 'pause_pattern.dart';

/// A calendar date, never a midnight instant in an implicit device zone.
final class CivilDate implements Comparable<CivilDate> {
  CivilDate(this.year, this.month, this.day) {
    final check = DateTime.utc(year, month, day);
    if (year < 1 ||
        year > 9999 ||
        check.year != year ||
        check.month != month ||
        check.day != day) {
      throw ArgumentError('invalid_civil_date');
    }
  }
  factory CivilDate.fromDateTime(DateTime value) =>
      CivilDate(value.year, value.month, value.day);
  factory CivilDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('civil_date');
    }
    return CivilDate(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
      int.parse(value.substring(8, 10)),
    );
  }
  final int year, month, day;
  DateTime get calendarValue => DateTime.utc(year, month, day);
  CivilDate addDays(int days) =>
      CivilDate.fromDateTime(calendarValue.add(Duration(days: days)));
  @override
  int compareTo(CivilDate other) =>
      calendarValue.compareTo(other.calendarValue);
  @override
  bool operator ==(Object other) =>
      other is CivilDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;
  @override
  int get hashCode => Object.hash(year, month, day);
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

final class WallTime implements Comparable<WallTime> {
  WallTime(this.hour, this.minute) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ArgumentError('invalid_wall_time');
    }
  }
  final int hour, minute;
  DateTime on(CivilDate date) =>
      DateTime.utc(date.year, date.month, date.day, hour, minute);
  @override
  int compareTo(WallTime other) =>
      (hour * 60 + minute).compareTo(other.hour * 60 + other.minute);
  @override
  bool operator ==(Object other) =>
      other is WallTime && hour == other.hour && minute == other.minute;
  @override
  int get hashCode => Object.hash(hour, minute);
}

final class PlannedAmount {
  PlannedAmount({
    required this.quantity,
    required this.unit,
    String? enteredText,
  }) : enteredText = enteredText ?? quantity.canonical {
    if (ExactQuantity.parse(this.enteredText).scaled != quantity.scaled) {
      throw ArgumentError('planned_amount_text');
    }
    if (unit.trim().isEmpty) throw ArgumentError('empty_unit');
  }
  final ExactQuantity quantity;
  final String unit, enteredText;
}

sealed class DailyTiming {
  const DailyTiming();
}

final class DailyCount extends DailyTiming {
  DailyCount(this.count, this.amount) {
    if (count <= 0) throw ArgumentError('invalid_daily_count');
  }
  final int count;
  final PlannedAmount amount;
}

final class DailySlot {
  DailySlot({
    required this.id,
    required this.time,
    required this.amount,
    required this.reminderEnabled,
  }) {
    if (id.isEmpty) throw ArgumentError('empty_slot_id');
  }
  final String id;
  final WallTime time;
  final PlannedAmount amount;
  final bool reminderEnabled;
}

final class DailySlots extends DailyTiming {
  DailySlots(Iterable<DailySlot> slots) : slots = List.unmodifiable(slots) {
    if (this.slots.isEmpty ||
        this.slots.map((s) => s.id).toSet().length != this.slots.length) {
      throw ArgumentError('invalid_daily_slots');
    }
  }
  final List<DailySlot> slots;
}

/// A daily count with explicitly chosen slots and an untimed remainder.
final class MixedDailyCount extends DailyTiming {
  MixedDailyCount({
    required this.count,
    required this.amount,
    required Iterable<DailySlot> slots,
  }) : slots = List.unmodifiable(slots) {
    if (this.slots.isEmpty ||
        count <= this.slots.length ||
        this.slots.map((s) => s.id).toSet().length != this.slots.length) {
      throw ArgumentError('invalid_mixed_daily_count');
    }
  }
  final int count;
  final PlannedAmount amount;
  final List<DailySlot> slots;
}

final class DailyWindow {
  DailyWindow({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    this.reminderAnchor,
    this.reminderEnabled = false,
  }) {
    if (id.isEmpty ||
        start == end ||
        reminderEnabled && reminderAnchor == null) {
      throw ArgumentError('invalid_daily_window');
    }
    if (reminderAnchor != null) {
      final anchor = reminderAnchor!;
      final inside = end.compareTo(start) > 0
          ? anchor.compareTo(start) >= 0 && anchor.compareTo(end) < 0
          : anchor.compareTo(start) >= 0 || anchor.compareTo(end) < 0;
      if (!inside) throw ArgumentError('window_anchor_outside');
    }
  }
  final String id;
  final WallTime start, end;
  final PlannedAmount amount;
  final WallTime? reminderAnchor;
  final bool reminderEnabled;
}

final class DailyWindows extends DailyTiming {
  DailyWindows({required Iterable<DailyWindow> windows})
    : windows = List.unmodifiable(windows) {
    if (this.windows.isEmpty ||
        this.windows.map((w) => w.id).toSet().length != this.windows.length) {
      throw ArgumentError('invalid_daily_windows');
    }
  }
  final List<DailyWindow> windows;
}

/// Explicitly entered elapsed time, represented exactly in integer microseconds.
final class ExactElapsed {
  ExactElapsed.fromMicroseconds(this.microseconds) {
    if (microseconds <= 0 || microseconds > 315537897599999999) {
      throw ArgumentError('invalid_elapsed_duration');
    }
  }
  factory ExactElapsed.parseHours(String text) {
    if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(text) || text.length > 40) {
      throw const FormatException('invalid_elapsed_hours');
    }
    final parts = text.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    final denominator = BigInt.from(10).pow(fraction.length);
    final numerator = BigInt.parse(parts.join()) * BigInt.from(3600000000);
    if (numerator.remainder(denominator) != BigInt.zero) {
      throw const FormatException('elapsed_precision');
    }
    final micros = numerator ~/ denominator;
    if (micros <= BigInt.zero || micros > BigInt.from(315537897599999999)) {
      throw const FormatException('elapsed_range');
    }
    return ExactElapsed.fromMicroseconds(micros.toInt());
  }
  final int microseconds;

  /// Exact decimal hours when finite; UI retains original entered draft text.
  String get hoursText {
    final whole = microseconds ~/ 3600000000;
    var remainder = microseconds % 3600000000;
    if (remainder == 0) return '$whole';
    final digits = StringBuffer();
    for (var i = 0; remainder != 0 && i < 12; i++) {
      remainder *= 10;
      digits.write(remainder ~/ 3600000000);
      remainder %= 3600000000;
    }
    if (remainder != 0) throw StateError('elapsed_hours_not_finite');
    return '$whole.$digits';
  }
}

enum IntervalMode { fixedPlanned, qualifyingActual }

/// An elapsed segment with an immutable anchor.
///
/// A restart creates a new segment identity.
final class ElapsedInterval extends DailyTiming {
  ElapsedInterval({
    required this.segmentId,
    required this.duration,
    required this.mode,
    required this.amount,
    this.plannedAnchor,
    this.reminderEnabled = false,
  }) {
    if (segmentId.isEmpty ||
        (mode == IntervalMode.fixedPlanned) != (plannedAnchor != null) ||
        plannedAnchor != null && !plannedAnchor!.isUtc) {
      throw ArgumentError('invalid_interval_anchor');
    }
    if (plannedAnchor != null &&
        (plannedAnchor!.year < 1 || plannedAnchor!.year > 9999)) {
      throw ArgumentError('interval_anchor_range');
    }
  }
  final String segmentId;
  final ExactElapsed duration;
  final IntervalMode mode;
  final PlannedAmount amount;
  final DateTime? plannedAnchor;
  final bool reminderEnabled;
}

/// A durable actual's current revision, not its entry or edit timestamp.
final class IntervalSource {
  IntervalSource({
    required this.actualId,
    required this.revision,
    required this.personId,
    required this.itemId,
    required this.planId,
    required this.segmentId,
    required this.instant,
    this.qualifies = true,
    this.isVoid = false,
  }) {
    if ([actualId, personId, itemId, planId, segmentId].any((s) => s.isEmpty) ||
        revision <= 0 ||
        !instant.isUtc) {
      throw ArgumentError('invalid_interval_source');
    }
  }
  final String actualId, personId, itemId, planId, segmentId;
  final int revision;
  final DateTime instant;
  final bool qualifies, isVoid;

  void validateQualificationAt(DateTime now) {
    if (qualifies && !isVoid && instant.isAfter(now)) {
      throw ArgumentError('future_interval_qualification');
    }
  }
}

final class AsNeeded extends DailyTiming {
  const AsNeeded();
}

sealed class DailyZoneBasis {
  const DailyZoneBasis();
  String zoneFor(String observedZone);
}

final class FollowingLocal extends DailyZoneBasis {
  const FollowingLocal();
  @override
  String zoneFor(String observedZone) => observedZone;
}

final class FixedHome extends DailyZoneBasis {
  FixedHome(this.zoneId) {
    if (zoneId.isEmpty) throw ArgumentError('empty_home_zone');
  }
  final String zoneId;
  @override
  String zoneFor(String observedZone) => zoneId;
}

/// Effective dates are inclusive at start and exclusive at end, in plan days.
final class DailyPlanVersion {
  DailyPlanVersion({
    required this.personId,
    required this.planId,
    required this.itemId,
    required this.versionId,
    required this.start,
    this.endExclusive,
    required this.timing,
    required this.zoneBasis,
    this.calendar = const EveryDay(),
    Iterable<PlanPause> pauses = const [],
    this.onOff,
    this.effectiveFrom,
    this.effectiveUntil,
  }) : pauses = List.unmodifiable(pauses) {
    if ((timing is AsNeeded || timing is ElapsedInterval) &&
        calendar is! EveryDay) {
      throw ArgumentError('unsupported_as_needed_calendar');
    }
    if ([personId, planId, itemId, versionId].any((id) => id.isEmpty)) {
      throw ArgumentError('empty_plan_identity');
    }
    if (endExclusive != null && endExclusive!.compareTo(start) <= 0) {
      throw ArgumentError('invalid_plan_bounds');
    }
    if ([effectiveFrom, effectiveUntil].whereType<DateTime>().any(
          (instant) =>
              !instant.isUtc || instant.year < 1 || instant.year > 9999,
        ) ||
        effectiveFrom != null &&
            effectiveUntil != null &&
            !effectiveUntil!.isAfter(effectiveFrom!)) {
      throw ArgumentError('invalid_plan_instant_bounds');
    }
  }
  final String personId, planId, itemId, versionId;
  final CivilDate start;
  final CivilDate? endExclusive;
  final DailyTiming timing;
  final DailyZoneBasis zoneBasis;
  final CalendarPattern calendar;
  final List<PlanPause> pauses;
  final OnOffPattern? onOff;

  /// Independent half-open UTC bounds for an immutable intraday version.
  final DateTime? effectiveFrom, effectiveUntil;

  /// Whether [instant] belongs to this version's exact effective interval.
  bool includesInstant(DateTime instant) =>
      (effectiveFrom == null || !instant.isBefore(effectiveFrom!)) &&
      (effectiveUntil == null || instant.isBefore(effectiveUntil!));

  bool includes(CivilDate date) =>
      date.compareTo(start) >= 0 &&
      (endExclusive == null || date.compareTo(endExclusive!) < 0);
}

/// Version, zone and effective instant deliberately do not enter logical identity.
final class DailyIdentity {
  const DailyIdentity({
    required this.personId,
    required this.planId,
    required this.originalDate,
    this.slotId,
    this.intervalSegmentId,
    this.intervalOrdinal,
    this.sourceActualId,
    this.sourceActualRevision,
  });
  final String personId, planId;
  final CivilDate originalDate;

  /// Null identifies the one untimed count bucket on this date.
  final String? slotId;
  final String? intervalSegmentId, sourceActualId;
  final int? intervalOrdinal, sourceActualRevision;
  @override
  bool operator ==(Object other) =>
      other is DailyIdentity &&
      personId == other.personId &&
      planId == other.planId &&
      (intervalSegmentId != null || originalDate == other.originalDate) &&
      slotId == other.slotId &&
      intervalSegmentId == other.intervalSegmentId &&
      intervalOrdinal == other.intervalOrdinal &&
      sourceActualId == other.sourceActualId &&
      sourceActualRevision == other.sourceActualRevision;
  @override
  int get hashCode => Object.hash(
    personId,
    planId,
    intervalSegmentId == null ? originalDate : null,
    slotId,
    intervalSegmentId,
    intervalOrdinal,
    sourceActualId,
    sourceActualRevision,
  );
}

sealed class ClockDecision {
  const ClockDecision();
}

final class NoAlert extends ClockDecision {
  const NoAlert();
}

final class ChooseClockInstance extends ClockDecision {
  const ChooseClockInstance(this.index);

  /// Zero-based index in UTC order; no choice means no default fold instance.
  final int index;
}

final class ReplaceClockTime extends ClockDecision {
  const ReplaceClockTime(this.time, {this.instanceIndex});
  final WallTime time;
  final int? instanceIndex;
}

/// A one-occurrence choice scoped to the exact semantic basis reviewed.
final class DailyClockChoice {
  const DailyClockChoice({
    required this.identity,
    required this.versionId,
    required this.zoneId,
    required this.originalTime,
    required this.decision,
  });
  factory DailyClockChoice.capture(
    DailyExpectation row,
    ClockDecision decision,
  ) {
    if (row.originalTime == null) {
      throw ArgumentError('clock_choice_requires_timed_slot');
    }
    return DailyClockChoice(
      identity: row.identity,
      versionId: row.versionId,
      zoneId: row.zoneId,
      originalTime: row.originalTime!,
      decision: decision,
    );
  }
  final DailyIdentity identity;
  final String versionId, zoneId;
  final WallTime originalTime;
  final ClockDecision decision;
}

enum DailyResolution { untimed, exact, missingClock, repeatedClock, noAlert }

enum DailyReminderState {
  untimed,
  disabled,
  reviewClock,
  noAlert,
  past,
  eligible,
}

/// Persist this resolved meaning when an expectation becomes historical.
/// Actual/entry instants and Taken/Skip status belong to separate durable records.
final class DailyExpectation {
  DailyExpectation({
    required this.identity,
    required this.itemId,
    required this.versionId,
    required this.zoneId,
    required this.amount,
    required this.resolution,
    required this.calculatorVersion,
    required this.timezoneDataVersion,
    this.originalTime,
    this.effectiveTime,
    this.instant,
    this.plannedCount,
    this.windowStart,
    this.windowEnd,
    this.reminderAnchor,
    this.originalInstant,
    this.originalAmount,
    this.originalWindowStart,
    this.originalWindowEnd,
    this.originalReminderAnchor,
    this.effectiveDate,
    this.eligibilityConflict,
    this.reminderEnabled = false,
    Iterable<DateTime> clockCandidates = const [],
    Iterable<DailyExpectation> windowEndpoints = const [],
  }) : clockCandidates = List.unmodifiable(clockCandidates),
       windowEndpoints = List.unmodifiable(windowEndpoints) {
    if (identity.personId.isEmpty ||
        identity.planId.isEmpty ||
        itemId.isEmpty ||
        versionId.isEmpty ||
        zoneId.isEmpty ||
        calculatorVersion.isEmpty ||
        timezoneDataVersion.isEmpty) {
      throw ArgumentError('invalid_expectation_identity');
    }
    final segment = identity.intervalSegmentId;
    if (segment == null) {
      if (identity.intervalOrdinal != null ||
          identity.sourceActualId != null ||
          identity.sourceActualRevision != null) {
        throw ArgumentError('invalid_interval_identity');
      }
    } else {
      final fixed =
          identity.intervalOrdinal != null &&
          identity.intervalOrdinal! >= 0 &&
          identity.sourceActualId == null &&
          identity.sourceActualRevision == null;
      final actual =
          identity.intervalOrdinal == null &&
          identity.sourceActualId != null &&
          identity.sourceActualId!.isNotEmpty &&
          identity.sourceActualRevision != null &&
          identity.sourceActualRevision! > 0;
      if (segment.isEmpty ||
          identity.slotId != 'interval' ||
          !(fixed || actual) ||
          resolution != DailyResolution.exact) {
        throw ArgumentError('invalid_interval_identity');
      }
    }
    if ([
          windowStart,
          windowEnd,
          reminderAnchor,
          originalInstant,
          originalWindowStart,
          originalWindowEnd,
          originalReminderAnchor,
        ].whereType<DateTime>().any((value) => !value.isUtc) ||
        windowStart != null &&
            windowEnd != null &&
            !windowEnd!.isAfter(windowStart!) ||
        reminderAnchor != null &&
            instant != null &&
            reminderAnchor != instant) {
      throw ArgumentError('invalid_window_metadata');
    }
    if (instant != null && !instant!.isUtc ||
        this.clockCandidates.any((candidate) => !candidate.isUtc)) {
      throw ArgumentError('expectation_requires_utc');
    }
    if (resolution == DailyResolution.untimed) {
      if (identity.slotId != null ||
          plannedCount == null ||
          plannedCount! <= 0 ||
          originalTime != null ||
          effectiveTime != null ||
          instant != null ||
          reminderEnabled ||
          this.clockCandidates.isNotEmpty) {
        throw ArgumentError('invalid_untimed_expectation');
      }
    } else {
      if (identity.slotId == null ||
          identity.slotId!.isEmpty ||
          originalTime == null ||
          effectiveTime == null ||
          plannedCount != null) {
        throw ArgumentError('invalid_timed_expectation');
      }
      if ((resolution == DailyResolution.exact) != (instant != null)) {
        throw ArgumentError('invalid_resolved_instant');
      }
      if (instant != null && !this.clockCandidates.contains(instant)) {
        throw ArgumentError('instant_not_a_candidate');
      }
      if (resolution == DailyResolution.missingClock &&
              this.clockCandidates.isNotEmpty ||
          resolution == DailyResolution.repeatedClock &&
              this.clockCandidates.length < 2) {
        throw ArgumentError('invalid_clock_candidates');
      }
    }
  }
  final DailyIdentity identity;
  final String itemId,
      versionId,
      zoneId,
      calculatorVersion,
      timezoneDataVersion;
  final PlannedAmount amount;
  final DailyResolution resolution;
  final WallTime? originalTime, effectiveTime;
  final DateTime? instant;
  final DateTime? windowStart, windowEnd, reminderAnchor, originalInstant;
  final DateTime? originalWindowStart,
      originalWindowEnd,
      originalReminderAnchor;
  final PlannedAmount? originalAmount;
  final CivilDate? effectiveDate;
  final String? eligibilityConflict;
  final int? plannedCount;
  final bool reminderEnabled;
  final List<DateTime> clockCandidates;
  final List<DailyExpectation> windowEndpoints;
  DailyExpectation withEligibilityConflict(String code) => DailyExpectation(
    identity: identity,
    itemId: itemId,
    versionId: versionId,
    zoneId: zoneId,
    amount: amount,
    resolution: resolution,
    calculatorVersion: calculatorVersion,
    timezoneDataVersion: timezoneDataVersion,
    originalTime: originalTime,
    effectiveTime: effectiveTime,
    instant: instant,
    plannedCount: plannedCount,
    windowStart: windowStart,
    windowEnd: windowEnd,
    reminderAnchor: reminderAnchor,
    originalInstant: originalInstant,
    originalAmount: originalAmount,
    originalWindowStart: originalWindowStart,
    originalWindowEnd: originalWindowEnd,
    originalReminderAnchor: originalReminderAnchor,
    effectiveDate: effectiveDate,
    reminderEnabled: reminderEnabled,
    clockCandidates: clockCandidates,
    windowEndpoints: windowEndpoints,
    eligibilityConflict: code,
  );

  DailyReminderState reminderStateAt(DateTime now) =>
      eligibilityConflict != null
      ? DailyReminderState.noAlert
      : switch (resolution) {
          DailyResolution.untimed => DailyReminderState.untimed,
          DailyResolution.missingClock ||
          DailyResolution.repeatedClock => DailyReminderState.reviewClock,
          DailyResolution.noAlert => DailyReminderState.noAlert,
          DailyResolution.exact when !reminderEnabled =>
            DailyReminderState.disabled,
          DailyResolution.exact when !instant!.isAfter(now) =>
            DailyReminderState.past,
          DailyResolution.exact => DailyReminderState.eligible,
        };
}
