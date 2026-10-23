import 'package:flutter/material.dart';

DateTime vitalDatePickerDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime vitalDatePickerMonthOnly(DateTime value) =>
    DateTime(value.year, value.month);

DateTime vitalDatePickerClampDate(
  DateTime value,
  DateTime firstDate,
  DateTime lastDate,
) {
  final normalized = vitalDatePickerDateOnly(value);
  if (normalized.isBefore(firstDate)) return firstDate;
  if (normalized.isAfter(lastDate)) return lastDate;
  return normalized;
}

int vitalDatePickerMonthDelta(DateTime from, DateTime to) =>
    ((to.year - from.year) * 12) + to.month - from.month;

DateTime vitalDatePickerMonthForPage(DateTime firstMonth, int page) =>
    DateTime(firstMonth.year, firstMonth.month + page);

int vitalDatePickerLeadingDayCount(DateTime month, int firstDayOfWeekIndex) {
  final sundayBasedWeekday = DateTime(month.year, month.month).weekday % 7;
  return (sundayBasedWeekday - firstDayOfWeekIndex) % DateTime.daysPerWeek;
}

int vitalDatePickerRowsForMonth(DateTime month, int firstDayOfWeekIndex) {
  final leading = vitalDatePickerLeadingDayCount(month, firstDayOfWeekIndex);
  final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
  final rows = (leading + daysInMonth + 6) ~/ DateTime.daysPerWeek;
  return rows.clamp(5, 6);
}

List<DateTime?> vitalDatePickerCellsForMonth(
  DateTime month,
  int firstDayOfWeekIndex,
) {
  final leading = vitalDatePickerLeadingDayCount(month, firstDayOfWeekIndex);
  final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
  final cellCount =
      vitalDatePickerRowsForMonth(month, firstDayOfWeekIndex) *
      DateTime.daysPerWeek;
  return List<DateTime?>.generate(cellCount, (index) {
    final day = index - leading + 1;
    if (day < 1 || day > daysInMonth) return null;
    return DateTime(month.year, month.month, day);
  }, growable: false);
}

String vitalDatePickerDayKey(DateTime value) {
  final day = vitalDatePickerDateOnly(value);
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

bool isSameVitalDatePickerDay(DateTime? left, DateTime? right) {
  if (left == null || right == null) return false;
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
