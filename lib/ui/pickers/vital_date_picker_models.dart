import 'package:flutter/material.dart';

enum VitalDatePickerHistoricalDayTreatment { none, dimPast }

enum VitalDatePickerRangeEndpoint { start, end }

enum VitalDatePickerRangeSelectionBehavior {
  restart,
  editActiveEndpoint,
  editNearestEndpoint,
}

@immutable
class VitalDateTimeSelection {
  const VitalDateTimeSelection({required this.date, this.time});

  final DateTime date;
  final TimeOfDay? time;

  bool get isAllDay => time == null;

  DateTime get dateTime => DateTime(
    date.year,
    date.month,
    date.day,
    time?.hour ?? 0,
    time?.minute ?? 0,
  );
}

@immutable
class VitalOptionalDateTimeSelection {
  const VitalOptionalDateTimeSelection({this.date, this.time});

  final DateTime? date;
  final TimeOfDay? time;

  bool get isScheduled => date != null;
  bool get isAllDay => date != null && time == null;

  DateTime? get dateTime {
    final selectedDate = date;
    if (selectedDate == null) return null;
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
  }
}

@immutable
class VitalDatePickerDayMetadata {
  const VitalDatePickerDayMetadata({
    this.enabled = true,
    this.highlighted = false,
    this.accentColors = const <Color>[],
    this.semanticLabel,
  });

  final bool enabled;
  final bool highlighted;
  final List<Color> accentColors;
  final String? semanticLabel;

  VitalDatePickerDayMetadata copyWith({
    bool? enabled,
    bool? highlighted,
    List<Color>? accentColors,
    String? semanticLabel,
  }) {
    return VitalDatePickerDayMetadata(
      enabled: enabled ?? this.enabled,
      highlighted: highlighted ?? this.highlighted,
      accentColors: accentColors ?? this.accentColors,
      semanticLabel: semanticLabel ?? this.semanticLabel,
    );
  }
}

typedef VitalDatePickerDayMetadataBuilder = VitalDatePickerDayMetadata Function(
  DateTime day,
);

typedef VitalDatePickerMonthMetadataLoader =
    Future<Map<DateTime, VitalDatePickerDayMetadata>> Function(
      DateTime visibleMonth,
    );

typedef VitalDatePickerSelectableDayPredicate = bool Function(DateTime day);
