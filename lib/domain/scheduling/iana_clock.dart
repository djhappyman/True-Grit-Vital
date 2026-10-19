import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

import 'daily_plan.dart';

final class UnsupportedClockRange implements Exception {
  const UnsupportedClockRange(this.year);
  final int year;
  @override
  String toString() =>
      'UnsupportedClockRange($year; outside verified asset coverage)';
}

/// Named-zone conversion backed by the complete admitted IANA asset.
/// Device-zone discovery is intentionally supplied by the platform caller.
final class IanaClock {
  IanaClock() {
    _initialize();
  }
  static bool _initialized = false;
  static const dataVersion = '2026e';
  static void _initialize() {
    if (!_initialized) {
      data.initializeTimeZones();
      _initialized = true;
    }
  }

  void validateZone(String zoneId) {
    tz.getLocation(zoneId);
  }

  void _checkRange(DateTime instant, tz.Location location) {
    // A location with one offset has no transition policy to extrapolate.
    if (location.zones.map((zone) => zone.offset).toSet().length == 1) {
      return;
    }
    if (instant.year < 1902 || instant.year > 2037) {
      throw UnsupportedClockRange(instant.year);
    }
    // The generator substitutes a sentinel for the first transition, losing
    // its original boundary. Only later retained transitions establish an
    // exact historical baseline. A source-data extension is required earlier.
    final retained = location.transitionAt.where(
      (value) => value > -8000000000000000,
    );
    if (retained.isNotEmpty) {
      if (instant.millisecondsSinceEpoch < retained.first) {
        throw UnsupportedClockRange(instant.year);
      }
    } else if (instant.year < 1970) {
      throw UnsupportedClockRange(instant.year);
    }
  }

  /// Bounds all calendar dates possible at [instant] using offsets actually
  /// present in the admitted asset. This is an index seek bound, not a zone policy.
  (CivilDate, CivilDate) dateEnvelopeAt(DateTime instant) {
    var minimum = Duration.zero, maximum = Duration.zero;
    for (final location in tz.timeZoneDatabase.locations.values) {
      for (final zone in location.zones) {
        if (zone.offset < minimum) minimum = zone.offset;
        if (zone.offset > maximum) maximum = zone.offset;
      }
    }
    final first = CivilDate.fromDateTime(instant.toUtc().add(minimum));
    final last = CivilDate.fromDateTime(instant.toUtc().add(maximum));
    return (first, last.addDays(1));
  }

  CivilDate dateAt(DateTime instant, String zoneId) {
    final location = tz.getLocation(zoneId);
    _checkRange(instant.toUtc(), location);
    return CivilDate.fromDateTime(
      tz.TZDateTime.from(instant.toUtc(), location),
    );
  }

  WallTime timeAt(DateTime instant, String zoneId) {
    final location = tz.getLocation(zoneId);
    _checkRange(instant.toUtc(), location);
    final local = tz.TZDateTime.from(instant.toUtc(), location);
    return WallTime(local.hour, local.minute);
  }

  List<DateTime> candidates(CivilDate date, WallTime time, String zoneId) {
    final location = tz.getLocation(zoneId);
    final wall = time.on(date);
    _checkRange(wall, location);
    final result = <DateTime>{};
    // Enumerate the library's actual offsets, then round-trip through its
    // transition engine. Never let its wall-clock constructor choose a policy.
    for (final offset in location.zones.map((zone) => zone.offset).toSet()) {
      final candidate = wall.subtract(offset);
      _checkRange(candidate, location);
      final local = tz.TZDateTime.from(candidate, location);
      if (local.year == date.year &&
          local.month == date.month &&
          local.day == date.day &&
          local.hour == time.hour &&
          local.minute == time.minute &&
          local.second == 0) {
        result.add(candidate);
      }
    }
    return List.unmodifiable(result.toList()..sort());
  }
}
