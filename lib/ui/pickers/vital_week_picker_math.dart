import 'package:flutter/material.dart';

/// Calendar arithmetic keeps seven local dates intact across DST changes.
DateTimeRange vitalDatePickerWeekRange(
  DateTime day, {
  int firstWeekday = DateTime.monday,
}) {
  assert(
    firstWeekday >= DateTime.monday && firstWeekday <= DateTime.sunday,
    'firstWeekday must be a weekday from Monday (1) to Sunday (7).',
  );
  final offset = (day.weekday - firstWeekday) % DateTime.daysPerWeek;
  final start = DateTime(day.year, day.month, day.day - offset);
  return DateTimeRange(
    start: start,
    end: DateTime(start.year, start.month, start.day + 6),
  );
}
