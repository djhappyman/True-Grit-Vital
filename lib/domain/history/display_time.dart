import '../scheduling/daily_plan.dart';
import '../scheduling/iana_clock.dart';

/// Display-only 12/24-hour choice. Stored instants and amounts never change.
enum TimeFormat { system, h12, h24 }

extension TimeFormatResolution on TimeFormat {
  /// Resolves the user's choice against the platform 24-hour flag.
  bool resolvesTo24Hour({required bool systemUses24Hour}) => switch (this) {
    TimeFormat.system => systemUses24Hour,
    TimeFormat.h12 => false,
    TimeFormat.h24 => true,
  };

  String get storageValue => name;
}

/// Reads a persisted preference; unknown or missing values keep the system default.
TimeFormat timeFormatFromStorage(String? value) => switch (value) {
  'h12' => TimeFormat.h12,
  'h24' => TimeFormat.h24,
  _ => TimeFormat.system,
};

/// The zone actually used for display. An unavailable requested zone shows UTC.
final class DisplayZone {
  const DisplayZone._({required this.zoneId, required this.isFallback});

  const DisplayZone.utc() : zoneId = 'UTC', isFallback = false;

  final String zoneId;

  /// True when the requested zone was unavailable and UTC is shown instead.
  final bool isFallback;

  static DisplayZone resolve(String requestedZone, IanaClock clock) {
    if (requestedZone == 'UTC') return const DisplayZone.utc();
    try {
      clock.validateZone(requestedZone);
      return DisplayZone._(zoneId: requestedZone, isFallback: false);
    } catch (_) {
      return const DisplayZone._(zoneId: 'UTC', isFallback: true);
    }
  }
}

/// One exact UTC instant resolved into the shown zone.
///
/// [instant] is never rounded or rewritten. The civil fields and the shown zone
/// are the only display projection.
final class DisplayInstant {
  const DisplayInstant._({
    required this.instant,
    required this.zoneId,
    required this.zoneFallback,
    required this.civilDate,
    required this.hour,
    required this.minute,
    required this.second,
    required this.millisecond,
    required this.microsecond,
  });

  final DateTime instant;
  final String zoneId;
  final bool zoneFallback;
  final CivilDate civilDate;
  final int hour, minute, second, millisecond, microsecond;

  String get dateText => civilDate.toString();

  String get time24 => '${_two(hour)}:${_two(minute)}';

  String get time24WithSeconds => '$time24:${_two(second)}';

  /// Microsecond-exact UTC representation for inspection and tie review.
  String get instantIso8601 => instant.toIso8601String();

  /// Wall time as a UTC-shaped value, for formatting and tests only.
  DateTime get wallValue => DateTime.utc(
    civilDate.year,
    civilDate.month,
    civilDate.day,
    hour,
    minute,
    second,
    millisecond,
    microsecond,
  );
}

/// Half-open UTC bounds of one civil date in the shown zone.
final class DisplayDayBounds {
  const DisplayDayBounds._({
    required this.date,
    required this.zoneId,
    required this.zoneFallback,
    required this.start,
    required this.endExclusive,
  });

  final CivilDate date;
  final String zoneId;
  final bool zoneFallback;
  final DateTime start, endExclusive;

  bool get isEmpty => !endExclusive.isAfter(start);

  Duration get duration => endExclusive.difference(start);

  bool contains(DateTime instant) {
    final utc = instant.toUtc();
    return !utc.isBefore(start) && utc.isBefore(endExclusive);
  }
}

/// Named-zone conversion, civil-day bounds and the display fallback policy.
final class DisplayTime {
  DisplayTime({IanaClock? clock}) : _clock = clock ?? IanaClock();

  final IanaClock _clock;

  DisplayZone resolveZone(String requestedZone) =>
      DisplayZone.resolve(requestedZone, _clock);

  /// Resolves an instant for display without changing it.
  ///
  /// An unavailable zone, an instant outside the verified [IanaClock] range or
  /// an unexpected conversion failure falls back to UTC and sets
  /// [DisplayInstant.zoneFallback]. An instant outside the representable
  /// civil-date range (years 1..9999) is invalid input and cannot be projected.
  DisplayInstant instant(DateTime instant, String requestedZone) {
    final utc = instant.toUtc();
    // CivilDate, and therefore every stored instant accepted by the domain,
    // is bounded to years 1..9999. An instant outside that range is invalid
    // input rather than an unavailable zone; it cannot be projected safely.
    if (utc.year < 1 || utc.year > 9999) {
      throw ArgumentError.value(instant, 'instant', 'outside_civil_date_range');
    }
    final zone = resolveZone(requestedZone);
    if (zone.isFallback) return _utcInstant(utc, fallback: true);
    if (zone.zoneId == 'UTC') return _utcInstant(utc);
    try {
      final date = _clock.dateAt(utc, zone.zoneId);
      final time = _clock.timeAt(utc, zone.zoneId);
      final parts = _wallSecond(utc, date, time, zone.zoneId);
      return DisplayInstant._(
        instant: utc,
        zoneId: zone.zoneId,
        zoneFallback: false,
        civilDate: date,
        hour: time.hour,
        minute: time.minute,
        second: parts.$1,
        millisecond: parts.$2,
        microsecond: parts.$3,
      );
    } on UnsupportedClockRange {
      return _utcInstant(utc, fallback: true);
    } catch (_) {
      return _utcInstant(utc, fallback: true);
    }
  }

  /// Returns the earliest instant whose local civil date is [date].
  ///
  /// Searches 00:00–03:00 for the first valid wall minute, then the next two
  /// dates for a fully skipped civil date. A repeated midnight keeps the earlier
  /// candidate; a skipped midnight starts at the first valid local minute.
  DisplayDayBounds dayBounds(CivilDate date, String requestedZone) {
    final zone = resolveZone(requestedZone);
    if (zone.isFallback || zone.zoneId == 'UTC') {
      return _utcDayBounds(date, fallback: zone.isFallback);
    }
    try {
      final start = _firstInstantOnOrAfter(date, zone.zoneId);
      final next = date.addDays(1);
      final end = _firstInstantOnOrAfter(next, zone.zoneId);
      if (start == null && end == null) {
        return _utcDayBounds(date, fallback: true);
      }
      final resolvedStart = start ?? end!;
      final resolvedEnd = end ?? resolvedStart;
      return DisplayDayBounds._(
        date: date,
        zoneId: zone.zoneId,
        zoneFallback: false,
        start: resolvedStart,
        endExclusive: resolvedEnd,
      );
    } on UnsupportedClockRange {
      return _utcDayBounds(date, fallback: true);
    } catch (_) {
      return _utcDayBounds(date, fallback: true);
    }
  }

  DisplayInstant _utcInstant(DateTime utc, {bool fallback = false}) =>
      DisplayInstant._(
        instant: utc,
        zoneId: 'UTC',
        zoneFallback: fallback,
        civilDate: CivilDate.fromDateTime(utc),
        hour: utc.hour,
        minute: utc.minute,
        second: utc.second,
        millisecond: utc.millisecond,
        microsecond: utc.microsecond,
      );

  DisplayDayBounds _utcDayBounds(CivilDate date, {required bool fallback}) {
    final next = date.addDays(1);
    return DisplayDayBounds._(
      date: date,
      zoneId: 'UTC',
      zoneFallback: fallback,
      start: DateTime.utc(date.year, date.month, date.day),
      endExclusive: DateTime.utc(next.year, next.month, next.day),
    );
  }

  DateTime? _firstInstantOnOrAfter(CivilDate date, String zoneId) {
    for (var dayOffset = 0; dayOffset <= 2; dayOffset++) {
      final day = date.addDays(dayOffset);
      for (var minute = 0; minute <= 180; minute++) {
        final candidates = _clock.candidates(
          day,
          WallTime(minute ~/ 60, minute % 60),
          zoneId,
        );
        if (candidates.isNotEmpty) return candidates.first;
      }
    }
    return null;
  }

  /// Seconds within the resolved wall minute.
  ///
  /// The verified IANA offsets are whole minutes, so the UTC sub-minute fields
  /// are exact. The candidate round-trip keeps the result tied to the same wall
  /// minute even across a repeated clock.
  (int, int, int) _wallSecond(
    DateTime utc,
    CivilDate date,
    WallTime time,
    String zoneId,
  ) {
    DateTime? minuteStart;
    for (final candidate in _clock.candidates(date, time, zoneId)) {
      if (!candidate.isAfter(utc) &&
          utc.difference(candidate) < const Duration(minutes: 1)) {
        minuteStart = candidate;
      }
    }
    if (minuteStart == null) {
      return (utc.second, utc.millisecond, utc.microsecond);
    }
    final delta = utc.difference(minuteStart);
    return (
      delta.inSeconds,
      delta.inMilliseconds % 1000,
      delta.inMicroseconds % 1000,
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');
