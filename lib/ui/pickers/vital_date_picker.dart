import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons;

import 'picker_adapters.dart';
import '../vital_motion.dart';
import '../../l10n/app_localizations.dart';
import 'vital_date_picker_math.dart';
import 'vital_week_picker_math.dart';
export 'vital_week_picker_math.dart';
import 'vital_date_picker_models.dart';
import 'vital_date_picker_navigation_views.dart';
import 'vital_time_picker.dart';

export 'vital_date_picker_models.dart';
export 'vital_time_picker.dart';

part 'vital_date_picker_selection_summary.dart';

enum VitalDatePickerGranularity { day, month, year }

enum _VitalDatePickerMode { single, dateTime, range }

enum _VitalDatePickerCalendarView { days, months, years }

Future<DateTime?> showVitalDatePicker({
  VitalDatePickerGranularity granularity = VitalDatePickerGranularity.day,
  required BuildContext context,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  DateTime? currentDate,
  String? title,
  String? subtitle,
  String? summaryTitle,
  bool showSelectionSummary = true,
  String? confirmLabel,
  String? cancelLabel,
  VitalDatePickerHistoricalDayTreatment historicalDayTreatment =
      VitalDatePickerHistoricalDayTreatment.none,
  VitalDatePickerDayMetadataBuilder? dayMetadataBuilder,
  VitalDatePickerMonthMetadataLoader? monthMetadataLoader,
  VitalDatePickerSelectableDayPredicate? selectableDayPredicate,
  Set<DateTime> highlightedDates = const <DateTime>{},
  String? Function(DateTime? date)? summaryValueBuilder,
}) {
  final now = currentDate ?? DateTime.now();
  return _showVitalDatePicker<DateTime>(
    context: context,
    mode: _VitalDatePickerMode.single,
    granularity: granularity,
    initialDate: initialDate,
    firstDate: firstDate ?? DateTime(now.year - 20),
    lastDate: lastDate ?? DateTime(now.year + 20, 12, 31),
    currentDate: now,
    title: title ?? AppLocalizations.of(context).pickerDate,
    subtitle: subtitle,
    summaryTitle: summaryTitle ?? AppLocalizations.of(context).pickerSelection,
    showSelectionSummary: showSelectionSummary,
    confirmLabel: confirmLabel ?? AppLocalizations.of(context).done,
    cancelLabel: cancelLabel ?? AppLocalizations.of(context).cancel,
    historicalDayTreatment: historicalDayTreatment,
    dayMetadataBuilder: dayMetadataBuilder,
    monthMetadataLoader: monthMetadataLoader,
    selectableDayPredicate: selectableDayPredicate,
    highlightedDates: highlightedDates,
    summaryValueBuilder: summaryValueBuilder,
    resultBuilder: (selection) {
      final date = selection.selectedDate!;
      return switch (granularity) {
        VitalDatePickerGranularity.day => date,
        VitalDatePickerGranularity.month => DateTime(date.year, date.month),
        VitalDatePickerGranularity.year => DateTime(date.year),
      };
    },
  );
}

Future<DateTime?> showVitalDateTimePicker({
  required BuildContext context,
  DateTime? initialDateTime,
  DateTime? firstDate,
  DateTime? lastDate,
  DateTime? currentDate,
  String? title,
  String? subtitle,
  String? summaryTitle,
  String? confirmLabel,
  String? cancelLabel,
  VitalDatePickerHistoricalDayTreatment historicalDayTreatment =
      VitalDatePickerHistoricalDayTreatment.none,
  VitalDatePickerDayMetadataBuilder? dayMetadataBuilder,
  VitalDatePickerMonthMetadataLoader? monthMetadataLoader,
  VitalDatePickerSelectableDayPredicate? selectableDayPredicate,
  Set<DateTime> highlightedDates = const <DateTime>{},
}) async {
  final selection = await showVitalDateTimeSelectionPicker(
    context: context,
    initialDateTime: initialDateTime,
    firstDate: firstDate,
    lastDate: lastDate,
    currentDate: currentDate,
    title: title ?? AppLocalizations.of(context).pickerDateTime,
    subtitle: subtitle,
    summaryTitle: summaryTitle ?? AppLocalizations.of(context).pickerSelection,
    confirmLabel: confirmLabel ?? AppLocalizations.of(context).done,
    cancelLabel: cancelLabel ?? AppLocalizations.of(context).cancel,
    historicalDayTreatment: historicalDayTreatment,
    dayMetadataBuilder: dayMetadataBuilder,
    monthMetadataLoader: monthMetadataLoader,
    selectableDayPredicate: selectableDayPredicate,
    highlightedDates: highlightedDates,
  );
  return selection?.dateTime;
}

Future<VitalDateTimeSelection?> showVitalDateTimeSelectionPicker({
  required BuildContext context,
  DateTime? initialDateTime,
  bool initialHasTime = true,
  DateTime? firstDate,
  DateTime? lastDate,
  DateTime? currentDate,
  String? title,
  String? subtitle,
  String? summaryTitle,
  String? confirmLabel,
  String? cancelLabel,
  VitalDatePickerHistoricalDayTreatment historicalDayTreatment =
      VitalDatePickerHistoricalDayTreatment.none,
  VitalDatePickerDayMetadataBuilder? dayMetadataBuilder,
  VitalDatePickerMonthMetadataLoader? monthMetadataLoader,
  VitalDatePickerSelectableDayPredicate? selectableDayPredicate,
  Set<DateTime> highlightedDates = const <DateTime>{},
}) {
  final now = currentDate ?? DateTime.now();
  final initial = initialDateTime ?? now;
  return _showVitalDatePicker<VitalDateTimeSelection>(
    context: context,
    mode: _VitalDatePickerMode.dateTime,
    initialDate: initial,
    initialTime: TimeOfDay.fromDateTime(initial),
    initialHasTime: initialHasTime,
    firstDate: firstDate ?? DateTime(now.year - 20),
    lastDate: lastDate ?? DateTime(now.year + 20, 12, 31),
    currentDate: now,
    title: title ?? AppLocalizations.of(context).pickerDateTime,
    subtitle: subtitle,
    summaryTitle: summaryTitle ?? AppLocalizations.of(context).pickerSelection,
    confirmLabel: confirmLabel ?? AppLocalizations.of(context).done,
    cancelLabel: cancelLabel ?? AppLocalizations.of(context).cancel,
    historicalDayTreatment: historicalDayTreatment,
    dayMetadataBuilder: dayMetadataBuilder,
    monthMetadataLoader: monthMetadataLoader,
    selectableDayPredicate: selectableDayPredicate,
    highlightedDates: highlightedDates,
    resultBuilder: (selection) => VitalDateTimeSelection(
      date: selection.selectedDate!,
      time: selection.hasTime ? selection.selectedTime : null,
    ),
  );
}

Future<VitalOptionalDateTimeSelection?>
showVitalOptionalDateTimeSelectionPicker({
  required BuildContext context,
  DateTime? initialDateTime,
  bool initialHasTime = false,
  DateTime? firstDate,
  DateTime? lastDate,
  DateTime? currentDate,
  String? title,
  String? subtitle,
  String? summaryTitle,
  String? confirmLabel,
  String? cancelLabel,
}) {
  final now = currentDate ?? DateTime.now();
  final initial = initialDateTime ?? now;
  return _showVitalDatePicker<VitalOptionalDateTimeSelection>(
    context: context,
    mode: _VitalDatePickerMode.dateTime,
    initialDate: initial,
    initialTime: TimeOfDay.fromDateTime(initial),
    initialHasTime: initialHasTime,
    firstDate: firstDate ?? DateTime(now.year - 1),
    lastDate: lastDate ?? DateTime(now.year + 3, 12, 31),
    currentDate: now,
    title: title ?? AppLocalizations.of(context).schedule,
    subtitle: subtitle,
    summaryTitle: summaryTitle ?? AppLocalizations.of(context).pickerSelection,
    confirmLabel: confirmLabel ?? AppLocalizations.of(context).done,
    cancelLabel: cancelLabel ?? AppLocalizations.of(context).cancel,
    historicalDayTreatment: VitalDatePickerHistoricalDayTreatment.dimPast,
    allowEmptySelection: true,
    resultBuilder: (selection) => VitalOptionalDateTimeSelection(
      date: selection.selectedDate,
      time: selection.selectedDate != null && selection.hasTime
          ? selection.selectedTime
          : null,
    ),
  );
}

Future<DateTimeRange?> showVitalDateRangePicker({
  bool weekSelection = false,
  int firstWeekday = DateTime.monday,
  required BuildContext context,
  DateTimeRange? initialRange,
  DateTime? firstDate,
  DateTime? lastDate,
  DateTime? currentDate,
  DateTime? initialDisplayDate,
  String? title,
  String? subtitle,
  String? summaryTitle,
  String? confirmLabel,
  String? cancelLabel,
  VitalDatePickerHistoricalDayTreatment historicalDayTreatment =
      VitalDatePickerHistoricalDayTreatment.none,
  VitalDatePickerDayMetadataBuilder? dayMetadataBuilder,
  VitalDatePickerMonthMetadataLoader? monthMetadataLoader,
  VitalDatePickerSelectableDayPredicate? selectableDayPredicate,
  Set<DateTime> highlightedDates = const <DateTime>{},
  VitalDatePickerRangeSelectionBehavior selectionBehavior =
      VitalDatePickerRangeSelectionBehavior.restart,
  VitalDatePickerRangeEndpoint? activeEndpoint,
  ValueChanged<DateTimeRange?>? onSelectionChanged,
}) {
  final now = currentDate ?? DateTime.now();
  return _showVitalDatePicker<DateTimeRange>(
    context: context,
    mode: _VitalDatePickerMode.range,
    weekSelection: weekSelection,
    firstWeekday: firstWeekday,
    initialRange: initialRange,
    initialDisplayDate: initialDisplayDate,
    firstDate: firstDate ?? DateTime(now.year - 20),
    lastDate: lastDate ?? DateTime(now.year + 20, 12, 31),
    currentDate: now,
    title: title ?? AppLocalizations.of(context).pickerRange,
    subtitle: subtitle,
    summaryTitle: summaryTitle ?? AppLocalizations.of(context).pickerSelection,
    confirmLabel: confirmLabel ?? AppLocalizations.of(context).done,
    cancelLabel: cancelLabel ?? AppLocalizations.of(context).cancel,
    historicalDayTreatment: historicalDayTreatment,
    dayMetadataBuilder: dayMetadataBuilder,
    monthMetadataLoader: monthMetadataLoader,
    selectableDayPredicate: selectableDayPredicate,
    highlightedDates: highlightedDates,
    rangeSelectionBehavior: selectionBehavior,
    activeRangeEndpoint: activeEndpoint,
    onRangeSelectionChanged: onSelectionChanged,
    resultBuilder: (selection) =>
        DateTimeRange(start: selection.rangeStart!, end: selection.rangeEnd!),
  );
}

Future<T?> _showVitalDatePicker<T>({
  bool weekSelection = false,
  int firstWeekday = DateTime.monday,
  VitalDatePickerGranularity granularity = VitalDatePickerGranularity.day,
  required BuildContext context,
  required _VitalDatePickerMode mode,
  required DateTime firstDate,
  required DateTime lastDate,
  required DateTime currentDate,
  required String title,
  String? subtitle,
  required String summaryTitle,
  bool showSelectionSummary = true,
  required String confirmLabel,
  required String cancelLabel,
  required VitalDatePickerHistoricalDayTreatment historicalDayTreatment,
  required T Function(_VitalDatePickerSelection selection) resultBuilder,
  DateTime? initialDate,
  DateTimeRange? initialRange,
  DateTime? initialDisplayDate,
  TimeOfDay? initialTime,
  bool initialHasTime = false,
  VitalDatePickerDayMetadataBuilder? dayMetadataBuilder,
  VitalDatePickerMonthMetadataLoader? monthMetadataLoader,
  VitalDatePickerSelectableDayPredicate? selectableDayPredicate,
  Set<DateTime> highlightedDates = const <DateTime>{},
  String? Function(DateTime? date)? summaryValueBuilder,
  VitalDatePickerRangeSelectionBehavior rangeSelectionBehavior =
      VitalDatePickerRangeSelectionBehavior.restart,
  VitalDatePickerRangeEndpoint? activeRangeEndpoint,
  ValueChanged<DateTimeRange?>? onRangeSelectionChanged,
  bool allowEmptySelection = false,
}) async {
  final normalizedFirst = vitalDatePickerDateOnly(firstDate);
  final normalizedLast = vitalDatePickerDateOnly(lastDate);
  if (normalizedLast.isBefore(normalizedFirst)) {
    throw ArgumentError.value(
      lastDate,
      'lastDate',
      'The last date must not be before the first date.',
    );
  }
  return showVitalPickerDialog<T>(
    context: context,
    builder: (dialogContext, handle) => _VitalDatePickerDialog<T>(
      mode: mode,
      weekSelection: weekSelection,
      firstWeekday: firstWeekday,
      granularity: granularity,
      initialDate: initialDate,
      initialRange: initialRange,
      initialDisplayDate: initialDisplayDate,
      initialTime: initialTime ?? const TimeOfDay(hour: 9, minute: 0),
      initialHasTime: initialHasTime,
      firstDate: normalizedFirst,
      lastDate: normalizedLast,
      currentDate: vitalDatePickerDateOnly(currentDate),
      title: title,
      subtitle: subtitle,
      summaryTitle: summaryTitle,
      showSelectionSummary: showSelectionSummary,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      historicalDayTreatment: historicalDayTreatment,
      dayMetadataBuilder: dayMetadataBuilder,
      monthMetadataLoader: monthMetadataLoader,
      selectableDayPredicate: selectableDayPredicate,
      highlightedDates: highlightedDates,
      summaryValueBuilder: summaryValueBuilder,
      rangeSelectionBehavior: rangeSelectionBehavior,
      activeRangeEndpoint: activeRangeEndpoint,
      onRangeSelectionChanged: onRangeSelectionChanged,
      allowEmptySelection: allowEmptySelection,
      resultBuilder: resultBuilder,
      overlayHandle: handle,
    ),
  );
}

class _VitalDatePickerSelection {
  const _VitalDatePickerSelection({
    required this.selectedDate,
    required this.selectedTime,
    required this.hasTime,
    required this.rangeStart,
    required this.rangeEnd,
  });

  final DateTime? selectedDate;
  final TimeOfDay selectedTime;
  final bool hasTime;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
}

class _VitalDatePickerDialog<T> extends StatefulWidget {
  const _VitalDatePickerDialog({
    this.weekSelection = false,
    this.firstWeekday = DateTime.monday,
    required this.mode,
    required this.granularity,
    required this.initialDate,
    required this.initialRange,
    required this.initialDisplayDate,
    required this.initialTime,
    required this.initialHasTime,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.title,
    required this.subtitle,
    required this.summaryTitle,
    required this.showSelectionSummary,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.historicalDayTreatment,
    required this.dayMetadataBuilder,
    required this.monthMetadataLoader,
    required this.selectableDayPredicate,
    required this.highlightedDates,
    required this.summaryValueBuilder,
    required this.rangeSelectionBehavior,
    required this.activeRangeEndpoint,
    required this.onRangeSelectionChanged,
    required this.resultBuilder,
    required this.overlayHandle,
    required this.allowEmptySelection,
  });

  final bool weekSelection;
  final int firstWeekday;
  final VitalDatePickerGranularity granularity;
  final _VitalDatePickerMode mode;
  final DateTime? initialDate;
  final DateTimeRange? initialRange;
  final DateTime? initialDisplayDate;
  final TimeOfDay initialTime;
  final bool initialHasTime;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final String title;
  final String? subtitle;
  final String summaryTitle;
  final bool showSelectionSummary;
  final String confirmLabel;
  final String cancelLabel;
  final VitalDatePickerHistoricalDayTreatment historicalDayTreatment;
  final VitalDatePickerDayMetadataBuilder? dayMetadataBuilder;
  final VitalDatePickerMonthMetadataLoader? monthMetadataLoader;
  final VitalDatePickerSelectableDayPredicate? selectableDayPredicate;
  final Set<DateTime> highlightedDates;
  final String? Function(DateTime? date)? summaryValueBuilder;
  final VitalDatePickerRangeSelectionBehavior rangeSelectionBehavior;
  final VitalDatePickerRangeEndpoint? activeRangeEndpoint;
  final ValueChanged<DateTimeRange?>? onRangeSelectionChanged;
  final T Function(_VitalDatePickerSelection selection) resultBuilder;
  final VitalPickerHandle<T> overlayHandle;
  final bool allowEmptySelection;

  @override
  State<_VitalDatePickerDialog<T>> createState() =>
      _VitalDatePickerDialogState<T>();
}

class _VitalDatePickerDialogState<T> extends State<_VitalDatePickerDialog<T>> {
  static const _dayExtent = 48.0;
  static const _yearsPerPage = 12;

  late final DateTime _firstMonth;
  late final int _monthCount;
  late PageController _pageController;
  late PageController _monthPickerController;
  late PageController _yearPickerController;
  late DateTime _visibleMonth;
  late int _visibleYearPage;
  _VitalDatePickerCalendarView _calendarView =
      _VitalDatePickerCalendarView.days;
  late TimeOfDay _selectedTime;
  late bool _hasTime;
  late final Set<String> _highlightedDayKeys;
  DateTime? _selectedDate;
  int _weekRevealGeneration = 0;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  final Map<String, VitalDatePickerDayMetadata> _loadedMetadata = {};
  final Set<String> _requestedMonths = {};

  @override
  void initState() {
    super.initState();
    _calendarView = switch (widget.granularity) {
      VitalDatePickerGranularity.day => _VitalDatePickerCalendarView.days,
      VitalDatePickerGranularity.month => _VitalDatePickerCalendarView.months,
      VitalDatePickerGranularity.year => _VitalDatePickerCalendarView.years,
    };
    _firstMonth = vitalDatePickerMonthOnly(widget.firstDate);
    final lastMonth = vitalDatePickerMonthOnly(widget.lastDate);
    _monthCount = vitalDatePickerMonthDelta(_firstMonth, lastMonth) + 1;
    _selectedTime = widget.initialTime;
    _highlightedDayKeys = widget.highlightedDates
        .map(vitalDatePickerDayKey)
        .toSet();
    _hasTime =
        widget.mode == _VitalDatePickerMode.dateTime && widget.initialHasTime;

    if (widget.mode == _VitalDatePickerMode.range) {
      final initialRange = widget.initialRange;
      if (initialRange != null) {
        final start = vitalDatePickerClampDate(
          initialRange.start,
          widget.firstDate,
          widget.lastDate,
        );
        final end = vitalDatePickerClampDate(
          initialRange.end,
          widget.firstDate,
          widget.lastDate,
        );
        _rangeStart = end.isBefore(start) ? end : start;
        _rangeEnd = end.isBefore(start) ? start : end;
      }
    } else if (widget.initialDate != null) {
      _selectedDate = vitalDatePickerClampDate(
        widget.initialDate!,
        widget.firstDate,
        widget.lastDate,
      );
    }

    final anchor =
        widget.initialDisplayDate ??
        _rangeEnd ??
        _rangeStart ??
        _selectedDate ??
        vitalDatePickerClampDate(
          widget.currentDate,
          widget.firstDate,
          widget.lastDate,
        );
    _visibleMonth = vitalDatePickerMonthOnly(anchor);
    _pageController = PageController(
      initialPage: vitalDatePickerMonthDelta(_firstMonth, _visibleMonth),
    );
    _monthPickerController = PageController(
      initialPage: _visibleMonth.year - widget.firstDate.year,
    );
    _visibleYearPage =
        (_visibleMonth.year - widget.firstDate.year) ~/ _yearsPerPage;
    _yearPickerController = PageController(initialPage: _visibleYearPage);
    unawaited(_loadMetadata(_visibleMonth));
    if (widget.weekSelection && _rangeStart != null) {
      final week = vitalDatePickerWeekRange(
        _rangeStart!,
        firstWeekday: widget.firstWeekday,
      );
      _rangeStart = week.start;
      _rangeEnd = week.end;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_revealWeek());
      });
    }
  }

  @override
  void dispose() {
    _weekRevealGeneration++;
    _pageController.dispose();
    _monthPickerController.dispose();
    _yearPickerController.dispose();
    super.dispose();
  }

  bool get _hasCompleteSelection =>
      widget.allowEmptySelection ||
      switch (widget.mode) {
        _VitalDatePickerMode.single => _selectedDate != null,
        _VitalDatePickerMode.dateTime => _selectedDate != null,
        _VitalDatePickerMode.range => _rangeStart != null && _rangeEnd != null,
      };

  Future<void> _loadMetadata(DateTime month) async {
    final loader = widget.monthMetadataLoader;
    if (loader == null) return;
    final monthKey = '${month.year}-${month.month}';
    if (!_requestedMonths.add(monthKey)) return;
    try {
      final metadata = await loader(vitalDatePickerMonthOnly(month));
      if (!mounted) return;
      setState(() {
        for (final entry in metadata.entries) {
          _loadedMetadata[vitalDatePickerDayKey(entry.key)] = entry.value;
        }
      });
    } catch (_) {
      // Item accents are supplementary. Date selection remains usable if the
      // feature-owned metadata source cannot be loaded.
    }
  }

  VitalDatePickerDayMetadata _metadataFor(DateTime day) {
    final key = vitalDatePickerDayKey(day);
    final metadata =
        _loadedMetadata[key] ??
        widget.dayMetadataBuilder?.call(day) ??
        const VitalDatePickerDayMetadata();
    return _highlightedDayKeys.contains(key)
        ? metadata.copyWith(highlighted: true)
        : metadata;
  }

  bool _isSelectable(DateTime day) {
    if (day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate)) {
      return false;
    }
    if (widget.weekSelection) {
      final week = vitalDatePickerWeekRange(
        day,
        firstWeekday: widget.firstWeekday,
      );
      if (week.start.isBefore(widget.firstDate) ||
          week.end.isAfter(widget.lastDate)) {
        return false;
      }
      for (var offset = 0; offset < 7; offset++) {
        final date = DateTime(
          week.start.year,
          week.start.month,
          week.start.day + offset,
        );
        if (!(widget.selectableDayPredicate?.call(date) ?? true) ||
            !_metadataFor(date).enabled) {
          return false;
        }
      }
    }
    if (!(widget.selectableDayPredicate?.call(day) ?? true)) return false;
    return _metadataFor(day).enabled;
  }

  Future<void> _revealWeek() async {
    final generation = ++_weekRevealGeneration;
    final start = _rangeStart, end = _rangeEnd;
    if (start == null ||
        end == null ||
        start.month == end.month && start.year == end.year) {
      return;
    }
    if (VitalMotion.reduced(context)) {
      return;
    }
    Future<void> showMonth(DateTime date) async {
      if (!mounted ||
          generation != _weekRevealGeneration ||
          !_pageController.hasClients) {
        return;
      }
      final page = vitalDatePickerMonthDelta(
        _firstMonth,
        date,
      ).clamp(0, _monthCount - 1);
      await _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    }

    await showMonth(start);
    if (!mounted || generation != _weekRevealGeneration) return;
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted || generation != _weekRevealGeneration) return;
    await showMonth(end);
  }

  void _selectDay(DateTime day) {
    if (!_isSelectable(day)) return;
    HapticFeedback.selectionClick();
    _weekRevealGeneration++;
    if (widget.weekSelection) {
      final week = vitalDatePickerWeekRange(
        day,
        firstWeekday: widget.firstWeekday,
      );
      if (week.start.isBefore(widget.firstDate) ||
          week.end.isAfter(widget.lastDate)) {
        return;
      }
      setState(() {
        _rangeStart = week.start;
        _rangeEnd = week.end;
      });
      _notifyRangeSelectionChanged();
      unawaited(_revealWeek());
      return;
    }
    setState(() {
      if (widget.mode != _VitalDatePickerMode.range) {
        _selectedDate = day;
        return;
      }
      if (widget.rangeSelectionBehavior ==
              VitalDatePickerRangeSelectionBehavior.editActiveEndpoint &&
          widget.activeRangeEndpoint != null &&
          _rangeStart != null &&
          _rangeEnd != null) {
        final other =
            widget.activeRangeEndpoint == VitalDatePickerRangeEndpoint.start
            ? _rangeEnd!
            : _rangeStart!;
        if (widget.activeRangeEndpoint == VitalDatePickerRangeEndpoint.start) {
          _rangeStart = day.isAfter(other) ? other : day;
          _rangeEnd = day.isAfter(other) ? day : other;
        } else {
          _rangeStart = day.isBefore(other) ? day : other;
          _rangeEnd = day.isBefore(other) ? other : day;
        }
        return;
      }
      if (widget.rangeSelectionBehavior ==
              VitalDatePickerRangeSelectionBehavior.editNearestEndpoint &&
          _rangeStart != null &&
          _rangeEnd != null) {
        final startDistance = day.difference(_rangeStart!).abs();
        final endDistance = day.difference(_rangeEnd!).abs();
        if (startDistance <= endDistance) {
          final other = _rangeEnd!;
          _rangeStart = day.isAfter(other) ? other : day;
          _rangeEnd = day.isAfter(other) ? day : other;
        } else {
          final other = _rangeStart!;
          _rangeStart = day.isBefore(other) ? day : other;
          _rangeEnd = day.isBefore(other) ? other : day;
        }
        return;
      }
      if (_rangeStart == null || _rangeEnd != null) {
        _rangeStart = day;
        _rangeEnd = null;
        return;
      }
      if (day.isBefore(_rangeStart!)) {
        _rangeEnd = _rangeStart;
        _rangeStart = day;
      } else {
        _rangeEnd = day;
      }
    });
    _notifyRangeSelectionChanged();
  }

  void _clearSelection() {
    _weekRevealGeneration++;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDate = null;
      if (widget.mode == _VitalDatePickerMode.dateTime) _hasTime = false;
      _rangeStart = null;
      _rangeEnd = null;
    });
    if (widget.mode == _VitalDatePickerMode.range) {
      widget.onRangeSelectionChanged?.call(null);
    }
  }

  void _notifyRangeSelectionChanged() {
    if (widget.mode != _VitalDatePickerMode.range) return;
    final start = _rangeStart;
    final end = _rangeEnd;
    widget.onRangeSelectionChanged?.call(
      start == null || end == null
          ? null
          : DateTimeRange(start: start, end: end),
    );
  }

  Future<void> _openTimePicker() async {
    final selectedTime = await showVitalTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (!mounted || selectedTime == null) return;
    setState(() {
      _selectedTime = selectedTime;
      _hasTime = true;
    });
  }

  void _confirm() {
    if (!_hasCompleteSelection) return;
    HapticFeedback.lightImpact();
    widget.overlayHandle.complete(
      widget.resultBuilder(
        _VitalDatePickerSelection(
          selectedDate: _selectedDate,
          selectedTime: _selectedTime,
          hasTime: _hasTime,
          rangeStart: _rangeStart,
          rangeEnd: _rangeEnd,
        ),
      ),
    );
  }

  void _selectToday() {
    final today = widget.currentDate;
    if (today.isBefore(widget.firstDate) || today.isAfter(widget.lastDate)) {
      return;
    }
    if (widget.granularity == VitalDatePickerGranularity.month) {
      _selectMonth(today);
      _syncMonthPickerController();
      return;
    }
    if (widget.granularity == VitalDatePickerGranularity.year) {
      _selectYear(today.year);
      _syncYearPickerController();
      return;
    }
    final page = vitalDatePickerMonthDelta(_firstMonth, today);
    setState(() {
      _visibleMonth = vitalDatePickerMonthOnly(today);
      _calendarView = _VitalDatePickerCalendarView.days;
    });
    _animateToPage(page);
    _selectDay(today);
  }

  void _animateToPage(int page) {
    _weekRevealGeneration++;
    final target = page.clamp(0, _monthCount - 1);
    if (!_pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _animateToPage(target);
      });
      return;
    }
    final reduceMotion = VitalMotion.reduced(context);
    if (reduceMotion) {
      _pageController.jumpToPage(target);
    } else {
      _pageController.animateToPage(
        target,
        duration: VitalPickerMotion.page(context),
        curve: Curves.easeOutCubic,
      );
    }
  }

  int get _yearCount => widget.lastDate.year - widget.firstDate.year + 1;

  int get _yearPageCount => (_yearCount / _yearsPerPage).ceil();

  void _showCalendarView(_VitalDatePickerCalendarView view) {
    if (_calendarView == view) return;
    HapticFeedback.selectionClick();
    if (view == _VitalDatePickerCalendarView.months) {
      _syncMonthPickerController();
    } else if (view == _VitalDatePickerCalendarView.years) {
      _syncYearPickerController();
    }
    setState(() => _calendarView = view);
  }

  void _syncMonthPickerController() {
    final page = _visibleMonth.year - widget.firstDate.year;
    if (_monthPickerController.hasClients) {
      _monthPickerController.jumpToPage(page);
      return;
    }
    _monthPickerController.dispose();
    _monthPickerController = PageController(initialPage: page);
  }

  void _syncYearPickerController() {
    final page = (_visibleMonth.year - widget.firstDate.year) ~/ _yearsPerPage;
    _visibleYearPage = page;
    if (_yearPickerController.hasClients) {
      _yearPickerController.jumpToPage(page);
      return;
    }
    _yearPickerController.dispose();
    _yearPickerController = PageController(initialPage: page);
  }

  void _prepareDayPickerPage(int page) {
    final target = page.clamp(0, _monthCount - 1);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(target);
      return;
    }
    _pageController.dispose();
    _pageController = PageController(initialPage: target);
  }

  void _animatePickerPage(PageController controller, int page, int count) {
    final target = page.clamp(0, count - 1);
    final reduceMotion = VitalMotion.reduced(context);
    if (reduceMotion) {
      controller.jumpToPage(target);
    } else {
      controller.animateToPage(
        target,
        duration: VitalPickerMotion.page(context),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _selectMonth(DateTime month) {
    HapticFeedback.selectionClick();
    final target = vitalDatePickerMonthOnly(month);
    if (widget.granularity == VitalDatePickerGranularity.month) {
      setState(() {
        _selectedDate = target;
        _visibleMonth = target;
      });
      return;
    }
    _prepareDayPickerPage(vitalDatePickerMonthDelta(_firstMonth, target));
    setState(() {
      _visibleMonth = target;
      _calendarView = _VitalDatePickerCalendarView.days;
    });
    unawaited(_loadMetadata(target));
  }

  void _selectYear(int year) {
    HapticFeedback.selectionClick();
    if (widget.granularity == VitalDatePickerGranularity.year) {
      setState(() {
        _selectedDate = DateTime(year);
        _visibleMonth = DateTime(year);
      });
      return;
    }
    final targetMonth = DateTime(year, _visibleMonth.month);
    setState(() {
      _visibleMonth = targetMonth;
      _calendarView = _VitalDatePickerCalendarView.months;
    });
    _syncMonthPickerController();
  }

  Widget _calendarTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(opacity: curved, child: child);
  }

  Widget _buildCalendarView(
    MaterialLocalizations localizations,
    int firstDayOfWeekIndex,
    int visiblePage,
  ) {
    return switch (_calendarView) {
      _VitalDatePickerCalendarView.days => Column(
        key: const ValueKey('vital_date_picker_day_view'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _MonthNavigation(
            label: localizations.formatMonthYear(_visibleMonth),
            labelKey: const ValueKey('vital_date_picker_month_year_header'),
            labelTooltip: AppLocalizations.of(context).pickerMonthYear,
            previousKey: const ValueKey('vital_date_picker_previous_month'),
            nextKey: const ValueKey('vital_date_picker_next_month'),
            canGoBack: visiblePage > 0,
            canGoForward: visiblePage < _monthCount - 1,
            onLabelTap: () =>
                _showCalendarView(_VitalDatePickerCalendarView.months),
            onBack: () => _animateToPage(visiblePage - 1),
            onForward: () => _animateToPage(visiblePage + 1),
          ),
          const SizedBox(height: 10),
          _WeekdayHeader(firstDayOfWeekIndex: firstDayOfWeekIndex),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _pageController,
            child: Listener(
              onPointerDown: (_) => _weekRevealGeneration++,
              child: PageView.builder(
                key: const ValueKey('vital_date_picker_month_pages'),
                controller: _pageController,
                itemCount: _monthCount,
                onPageChanged: (page) {
                  final month = vitalDatePickerMonthForPage(_firstMonth, page);
                  setState(() => _visibleMonth = month);
                  unawaited(_loadMetadata(month));
                },
                itemBuilder: (context, page) {
                  final month = vitalDatePickerMonthForPage(_firstMonth, page);
                  final monthHeight =
                      vitalDatePickerRowsForMonth(month, firstDayOfWeekIndex) *
                      _dayExtent;
                  return OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 0,
                    maxHeight: monthHeight,
                    child: SizedBox(
                      height: monthHeight,
                      child: _MonthGrid(
                        month: month,
                        firstDayOfWeekIndex: firstDayOfWeekIndex,
                        currentDate: widget.currentDate,
                        selectedDate: _selectedDate,
                        rangeStart: _rangeStart,
                        rangeEnd: _rangeEnd,
                        dimOutsideRange: widget.weekSelection,
                        historicalDayTreatment: widget.historicalDayTreatment,
                        metadataFor: _metadataFor,
                        isSelectable: _isSelectable,
                        onSelected: _selectDay,
                      ),
                    ),
                  );
                },
              ),
            ),
            builder: (context, child) {
              final page = _pageController.hasClients
                  ? _pageController.page ?? visiblePage.toDouble()
                  : visiblePage.toDouble();
              return ClipRect(
                child: SizedBox(
                  height: _calendarHeightForPage(page, firstDayOfWeekIndex),
                  child: child,
                ),
              );
            },
          ),
        ],
      ),
      _VitalDatePickerCalendarView.months => Column(
        key: const ValueKey('vital_date_picker_month_view'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _MonthNavigation(
            label: '${_visibleMonth.year}',
            labelKey: const ValueKey('vital_date_picker_year_header'),
            labelTooltip: AppLocalizations.of(context).pickerYear,
            previousKey: const ValueKey('vital_date_picker_previous_year'),
            nextKey: const ValueKey('vital_date_picker_next_year'),
            canGoBack: _visibleMonth.year > widget.firstDate.year,
            canGoForward: _visibleMonth.year < widget.lastDate.year,
            onLabelTap: () =>
                _showCalendarView(_VitalDatePickerCalendarView.years),
            onBack: () => _animatePickerPage(
              _monthPickerController,
              _visibleMonth.year - widget.firstDate.year - 1,
              _yearCount,
            ),
            onForward: () => _animatePickerPage(
              _monthPickerController,
              _visibleMonth.year - widget.firstDate.year + 1,
              _yearCount,
            ),
          ),
          const SizedBox(height: 8),
          VitalDatePickerMonthPager(
            controller: _monthPickerController,
            firstYear: widget.firstDate.year,
            yearCount: _yearCount,
            selectedMonth: _visibleMonth,
            firstDate: widget.firstDate,
            lastDate: widget.lastDate,
            currentDate: widget.currentDate,
            onYearChanged: (year) => setState(
              () => _visibleMonth = DateTime(year, _visibleMonth.month),
            ),
            onMonthSelected: _selectMonth,
          ),
        ],
      ),
      _VitalDatePickerCalendarView.years => Column(
        key: const ValueKey('vital_date_picker_year_view'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _MonthNavigation(
            label: _yearRangeLabel(_visibleYearPage),
            labelKey: const ValueKey('vital_date_picker_year_range_header'),
            labelTooltip: null,
            previousKey: const ValueKey('vital_date_picker_previous_year_page'),
            nextKey: const ValueKey('vital_date_picker_next_year_page'),
            canGoBack: _visibleYearPage > 0,
            canGoForward: _visibleYearPage < _yearPageCount - 1,
            onBack: () => _animatePickerPage(
              _yearPickerController,
              _visibleYearPage - 1,
              _yearPageCount,
            ),
            onForward: () => _animatePickerPage(
              _yearPickerController,
              _visibleYearPage + 1,
              _yearPageCount,
            ),
          ),
          const SizedBox(height: 8),
          VitalDatePickerYearPager(
            controller: _yearPickerController,
            firstYear: widget.firstDate.year,
            lastYear: widget.lastDate.year,
            yearsPerPage: _yearsPerPage,
            selectedYear: _visibleMonth.year,
            currentYear: widget.currentDate.year,
            onPageChanged: (page) => setState(() => _visibleYearPage = page),
            onYearSelected: _selectYear,
          ),
        ],
      ),
    };
  }

  String _yearRangeLabel(int page) {
    final start = widget.firstDate.year + (page * _yearsPerPage);
    final end = (start + _yearsPerPage - 1).clamp(
      widget.firstDate.year,
      widget.lastDate.year,
    );
    return '$start–$end';
  }

  double _calendarHeightForPage(double page, int firstDayOfWeekIndex) {
    final lowerPage = page.floor().clamp(0, _monthCount - 1);
    final upperPage = page.ceil().clamp(0, _monthCount - 1);
    final lowerRows = vitalDatePickerRowsForMonth(
      vitalDatePickerMonthForPage(_firstMonth, lowerPage),
      firstDayOfWeekIndex,
    );
    final upperRows = vitalDatePickerRowsForMonth(
      vitalDatePickerMonthForPage(_firstMonth, upperPage),
      firstDayOfWeekIndex,
    );
    return (lowerRows + ((upperRows - lowerRows) * (page - page.floor()))) *
        _dayExtent;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final firstDayOfWeekIndex = widget.weekSelection
        ? widget.firstWeekday % 7
        : localizations.firstDayOfWeekIndex;
    final visiblePage = vitalDatePickerMonthDelta(_firstMonth, _visibleMonth);
    final todayEnabled =
        !widget.currentDate.isBefore(widget.firstDate) &&
        !widget.currentDate.isAfter(widget.lastDate);
    final reduceMotion = VitalMotion.reduced(context);

    return KeyedSubtree(
      key: const ValueKey('vital_date_picker_dialog'),
      child: VitalPickerFrame(
        title: widget.title,
        titleTextStyle: VitalPickerTheme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w800),
        trailing: VitalPickerTextButton.icon(
          key: const ValueKey('vital_date_picker_today'),
          onPressed: todayEnabled ? _selectToday : null,
          icon: const Icon(LucideIcons.calendarDays, size: 18),
          label: Text(switch (widget.granularity) {
            VitalDatePickerGranularity.day => AppLocalizations.of(
              context,
            ).today,
            VitalDatePickerGranularity.month => AppLocalizations.of(
              context,
            ).pickerThisMonth,
            VitalDatePickerGranularity.year => AppLocalizations.of(
              context,
            ).pickerThisYear,
          }),
        ),
        scrollMode: VitalPickerScrollMode.bounded,
        headerBodySpacing: 14,
        footerSpacing: 16,
        body: AnimatedSize(
          duration: reduceMotion
              ? Duration.zero
              : VitalPickerMotion.bounds(context),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : VitalPickerMotion.page(context),
                reverseDuration: reduceMotion
                    ? Duration.zero
                    : VitalPickerMotion.leave(context),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: _calendarTransition,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    for (final previous in previousChildren)
                      IgnorePointer(
                        child: ExcludeSemantics(
                          child: FocusScope(
                            canRequestFocus: false,
                            child: previous,
                          ),
                        ),
                      ),
                    ?currentChild,
                  ],
                ),
                child: _buildCalendarView(
                  localizations,
                  firstDayOfWeekIndex,
                  visiblePage,
                ),
              ),
              if (widget.showSelectionSummary) ...[
                const SizedBox(height: 14),
                _SelectionSummary(
                  mode: widget.mode,
                  title: widget.summaryTitle,
                  selectedDate: _selectedDate,
                  selectedTime: _hasTime ? _selectedTime : null,
                  rangeStart: _rangeStart,
                  rangeEnd: _rangeEnd,
                  onClear: _hasCompleteSelection || _rangeStart != null
                      ? _clearSelection
                      : null,
                  valueBuilder: widget.summaryValueBuilder,
                ),
              ],
              if (widget.mode == _VitalDatePickerMode.dateTime) ...[
                const SizedBox(height: 12),
                _DatePickerTimeAction(
                  value: _hasTime ? _selectedTime : null,
                  onPressed: _selectedDate == null ? null : _openTimePicker,
                ),
              ],
            ],
          ),
        ),
        footer: VitalPickerActionBar(
          actions: [
            VitalPickerAction.secondary(
              label: widget.cancelLabel,
              onPressed: widget.overlayHandle.cancel,
            ),
            VitalPickerAction.primary(
              label: widget.confirmLabel,
              onPressed: _hasCompleteSelection ? _confirm : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthNavigation extends StatelessWidget {
  const _MonthNavigation({
    required this.label,
    required this.labelKey,
    required this.labelTooltip,
    required this.previousKey,
    required this.nextKey,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    this.onLabelTap,
  });

  final String label;
  final Key labelKey;
  final String? labelTooltip;
  final Key previousKey;
  final Key nextKey;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback? onLabelTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = VitalMotion.reduced(context);
    final labelContent = VitalPickerTap(
      key: labelKey,
      borderRadius: BorderRadius.circular(16),
      onTap: onLabelTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : VitalPickerMotion.header(context),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Text(
            label,
            key: ValueKey(label),
            textAlign: TextAlign.center,
            style: VitalPickerTheme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );

    return Row(
      children: [
        VitalPickerIconButton(
          key: previousKey,
          tooltip: AppLocalizations.of(context).back,
          onPressed: canGoBack ? onBack : null,
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        Expanded(
          child: Semantics(
            header: true,
            button: onLabelTap != null,
            child: labelTooltip == null
                ? labelContent
                : Tooltip(message: labelTooltip!, child: labelContent),
          ),
        ),
        VitalPickerIconButton(
          key: nextKey,
          tooltip: AppLocalizations.of(context).next,
          onPressed: canGoForward ? onForward : null,
          icon: const Icon(LucideIcons.chevronRight),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.firstDayOfWeekIndex});

  final int firstDayOfWeekIndex;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final scheme = VitalPickerTheme.of(context).colorScheme;
    final labels = localizations.narrowWeekdays;
    return Row(
      children: [
        for (var index = 0; index < DateTime.daysPerWeek; index++)
          Expanded(
            child: Text(
              labels[(firstDayOfWeekIndex + index) % DateTime.daysPerWeek]
                  .toUpperCase(),
              textAlign: TextAlign.center,
              style: VitalPickerTheme.of(context).textTheme.labelSmall
                  ?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.firstDayOfWeekIndex,
    required this.currentDate,
    required this.selectedDate,
    required this.rangeStart,
    required this.rangeEnd,
    this.dimOutsideRange = false,
    required this.historicalDayTreatment,
    required this.metadataFor,
    required this.isSelectable,
    required this.onSelected,
  });

  final DateTime month;
  final int firstDayOfWeekIndex;
  final DateTime currentDate;
  final DateTime? selectedDate;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final bool dimOutsideRange;
  final VitalDatePickerHistoricalDayTreatment historicalDayTreatment;
  final VitalDatePickerDayMetadata Function(DateTime day) metadataFor;
  final bool Function(DateTime day) isSelectable;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final cells = vitalDatePickerCellsForMonth(month, firstDayOfWeekIndex);
    return Column(
      children: [
        for (var row = 0; row < cells.length ~/ DateTime.daysPerWeek; row++)
          SizedBox(
            height: _VitalDatePickerDialogState._dayExtent,
            child: Row(
              children: [
                for (var column = 0; column < DateTime.daysPerWeek; column++)
                  Expanded(
                    child: _DateCell(
                      day: cells[(row * DateTime.daysPerWeek) + column],
                      column: column,
                      currentDate: currentDate,
                      selectedDate: selectedDate,
                      rangeStart: rangeStart,
                      rangeEnd: rangeEnd,
                      dimOutsideRange: dimOutsideRange,
                      historicalDayTreatment: historicalDayTreatment,
                      metadataFor: metadataFor,
                      isSelectable: isSelectable,
                      onSelected: onSelected,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.day,
    required this.column,
    required this.currentDate,
    required this.selectedDate,
    required this.rangeStart,
    required this.rangeEnd,
    this.dimOutsideRange = false,
    required this.historicalDayTreatment,
    required this.metadataFor,
    required this.isSelectable,
    required this.onSelected,
  });

  final DateTime? day;
  final int column;
  final DateTime currentDate;
  final DateTime? selectedDate;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final bool dimOutsideRange;
  final VitalDatePickerHistoricalDayTreatment historicalDayTreatment;
  final VitalDatePickerDayMetadata Function(DateTime day) metadataFor;
  final bool Function(DateTime day) isSelectable;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final value = day;
    if (value == null) return const SizedBox.expand();

    final scheme = VitalPickerTheme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final metadata = metadataFor(value);
    final enabled = isSelectable(value);
    final isHighlighted = metadata.highlighted;
    final isSelected = isSameVitalDatePickerDay(value, selectedDate);
    final isRangeStart = isSameVitalDatePickerDay(value, rangeStart);
    final isRangeEnd = isSameVitalDatePickerDay(value, rangeEnd);
    final isEndpoint = isSelected || isRangeStart || isRangeEnd;
    final hasCompleteRange = rangeStart != null && rangeEnd != null;
    final isInsideRange =
        hasCompleteRange &&
        value.isAfter(rangeStart!) &&
        value.isBefore(rangeEnd!);
    final hasRangeBand =
        hasCompleteRange &&
        (isRangeStart || isRangeEnd || isInsideRange) &&
        !isSameVitalDatePickerDay(rangeStart, rangeEnd);
    final isToday = isSameVitalDatePickerDay(value, currentDate);
    final historical = value.isBefore(currentDate);
    final dimHistorical =
        historical &&
        historicalDayTreatment ==
            VitalDatePickerHistoricalDayTreatment.dimPast &&
        !isEndpoint &&
        !isInsideRange;
    final dimOutside =
        dimOutsideRange && hasCompleteRange && !isEndpoint && !isInsideRange;
    final textColor = dimOutside
        ? scheme.onSurface.withValues(alpha: .25)
        : isEndpoint
        ? scheme.onPrimary
        : isHighlighted
        ? scheme.primary
        : isToday
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: dimHistorical ? 0.42 : 0.88);
    final semantics = <String>[
      localizations.formatFullDate(value),
      if (isRangeStart) AppLocalizations.of(context).pickerRangeStart,
      if (isRangeEnd) AppLocalizations.of(context).pickerRangeEnd,
      if (isInsideRange) AppLocalizations.of(context).pickerInsideRange,
      if (metadata.semanticLabel case final label? when label.isNotEmpty) label,
      if (isHighlighted) AppLocalizations.of(context).pickerHighlighted,
      if (!enabled) AppLocalizations.of(context).pickerUnavailable,
    ].join(', ');

    return Semantics(
      button: true,
      selected: isEndpoint || isInsideRange,
      enabled: enabled,
      label: semantics,
      child: VitalPickerTap(
        key: ValueKey('vital_date_picker_day_${vitalDatePickerDayKey(value)}'),
        radius: 24,
        onTap: enabled ? () => onSelected(value) : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (hasRangeBand)
              Positioned.fill(
                key: ValueKey(
                  'vital_date_picker_range_band_${vitalDatePickerDayKey(value)}',
                ),
                top: 7,
                bottom: 7,
                child: _RangeBand(
                  isStart: isRangeStart,
                  isEnd: isRangeEnd,
                  column: column,
                  color: scheme.primary.withValues(alpha: 0.14),
                ),
              ),
            AnimatedScale(
              duration: VitalMotion.duration(context, VitalMotion.choice),
              curve: Curves.easeOutCubic,
              scale: isEndpoint ? 1 : 0.96,
              child: SizedBox.square(
                dimension: 38,
                child: DecoratedBox(
                  key: isHighlighted && !isEndpoint
                      ? ValueKey(
                          'vital_date_picker_highlight_${vitalDatePickerDayKey(value)}',
                        )
                      : null,
                  decoration: BoxDecoration(
                    color: isEndpoint
                        ? scheme.primary
                        : isHighlighted
                        ? scheme.primary.withValues(
                            alpha: enabled ? 0.10 : 0.04,
                          )
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isToday && !isEndpoint
                        ? Border.all(
                            color: scheme.primary.withValues(alpha: 0.72),
                            width: 1.1,
                          )
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${value.day}',
                      style: VitalPickerTheme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            color: enabled
                                ? textColor
                                : textColor.withValues(alpha: 0.34),
                            fontWeight: isEndpoint || isToday || isHighlighted
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            ),
            if (metadata.accentColors.isNotEmpty)
              Positioned(
                bottom: 2,
                child: Opacity(
                  key: ValueKey(
                    'vital_date_picker_item_markers_${vitalDatePickerDayKey(value)}',
                  ),
                  opacity: dimHistorical ? 0.48 : 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final color in metadata.accentColors.take(3))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(dimension: 4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RangeBand extends StatelessWidget {
  const _RangeBand({
    required this.isStart,
    required this.isEnd,
    required this.column,
    required this.color,
  });

  final bool isStart;
  final bool isEnd;
  final int column;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final atRowStart = column == 0;
    final atRowEnd = column == DateTime.daysPerWeek - 1;
    final widthFactor = isStart || isEnd ? 0.5 : 1.0;
    final alignment = isStart
        ? Alignment.centerRight
        : isEnd
        ? Alignment.centerLeft
        : Alignment.center;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: alignment,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.horizontal(
            left: atRowStart || isStart
                ? const Radius.circular(18)
                : Radius.zero,
            right: atRowEnd || isEnd ? const Radius.circular(18) : Radius.zero,
          ),
        ),
      ),
    );
  }
}
