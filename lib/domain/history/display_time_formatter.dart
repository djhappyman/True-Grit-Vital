import 'package:flutter/material.dart'
    show MaterialLocalizations, TimeOfDay, HourFormat, hourFormat;

import 'display_time.dart';

/// Shared 12/24-hour display formatting.
///
/// The UI supplies the current [MaterialLocalizations] and the platform
/// 24-hour flag. This class never changes a stored instant, amount or unit.
final class DisplayTimeFormatter {
  const DisplayTimeFormatter({
    required this.localizations,
    required this.preference,
    required this.systemUses24Hour,
  });

  final MaterialLocalizations localizations;
  final TimeFormat preference;
  final bool systemUses24Hour;

  bool get use24Hour => switch (preference) {
    TimeFormat.h12 => false,
    TimeFormat.h24 => true,
    TimeFormat.system =>
      hourFormat(
            of: localizations.timeOfDayFormat(
              alwaysUse24HourFormat: systemUses24Hour,
            ),
          ) !=
          HourFormat.h,
  };

  String date(DisplayInstant value, {bool full = false}) => full
      ? localizations.formatFullDate(value.civilDate.calendarValue)
      : localizations.formatMediumDate(value.civilDate.calendarValue);

  String time(DisplayInstant value) => wallTime(value.hour, value.minute);

  /// Formats a displayed wall time; entry and schedule values remain unchanged.
  String wallTime(int hour, int minute) {
    // A false alwaysUse24HourFormat follows the locale; it does not force 12h.
    if (preference == TimeFormat.h12) {
      final hour12 = hour % 12 == 0 ? 12 : hour % 12;
      final period = hour < 12
          ? localizations.anteMeridiemAbbreviation
          : localizations.postMeridiemAbbreviation;
      return '$hour12:${_two(minute)} $period';
    }
    return localizations.formatTimeOfDay(
      TimeOfDay(hour: hour, minute: minute),
      alwaysUse24HourFormat: use24Hour,
    );
  }

  /// Minute precision plus seconds, for tie-breaking or inspection only.
  String timeWithSeconds(DisplayInstant value) {
    if (use24Hour) return value.time24WithSeconds;
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour < 12
        ? localizations.anteMeridiemAbbreviation
        : localizations.postMeridiemAbbreviation;
    return '$hour:${_two(value.minute)}:${_two(value.second)} $period';
  }

  /// Raw IANA id. The UI adds the approved `Shown in` copy.
  String zone(DisplayInstant value) => value.zoneId;

  /// Includes the UTC offset so repeated local clock times stay distinguishable.
  String zoneWithOffset(DisplayInstant value) {
    final offset = value.wallValue.difference(value.instant).inMinutes;
    final minutes = offset.abs();
    final sign = offset < 0 ? '-' : '+';
    return '${zone(value)} (UTC$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)})';
  }

  /// Exact date, chosen 12/24-hour time and shown zone.
  String format(
    DisplayInstant value, {
    bool includeSeconds = false,
    bool includeOffset = false,
  }) =>
      '${date(value, full: true)}, '
      '${includeSeconds ? timeWithSeconds(value) : time(value)}, '
      '${includeOffset ? zoneWithOffset(value) : zone(value)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
