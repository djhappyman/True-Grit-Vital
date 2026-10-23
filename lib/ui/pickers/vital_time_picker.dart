import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'picker_adapters.dart';
import '../vital_motion.dart';
import '../../l10n/app_localizations.dart';

Future<TimeOfDay?> showVitalTimePicker({
  required BuildContext context,
  TimeOfDay? initialTime,
  String? title,
  String? confirmLabel,
  String? cancelLabel,
}) async {
  return showVitalPickerDialog<TimeOfDay>(
    context: context,
    builder: (_, handle) => _VitalTimePickerDialog(
      initialTime: initialTime ?? TimeOfDay.now(),
      title: title ?? AppLocalizations.of(context).pickerTime,
      confirmLabel: confirmLabel ?? AppLocalizations.of(context).done,
      cancelLabel: cancelLabel ?? AppLocalizations.of(context).cancel,
      overlayHandle: handle,
    ),
  );
}

enum _ClockSelection { hour, minute }

class _VitalTimePickerDialog extends StatefulWidget {
  const _VitalTimePickerDialog({
    required this.initialTime,
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.overlayHandle,
  });

  final TimeOfDay initialTime;
  final String title;
  final String confirmLabel;
  final String cancelLabel;
  final VitalPickerHandle<TimeOfDay> overlayHandle;

  @override
  State<_VitalTimePickerDialog> createState() => _VitalTimePickerDialogState();
}

class _VitalTimePickerDialogState extends State<_VitalTimePickerDialog> {
  late TimeOfDay _selectedTime;
  _ClockSelection _selection = _ClockSelection.hour;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.initialTime;
  }

  void _updateTime(TimeOfDay value) {
    if (value == _selectedTime) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedTime = value);
  }

  void _adjust(int delta) {
    if (_selection == _ClockSelection.hour) {
      _updateTime(
        TimeOfDay(
          hour: (_selectedTime.hour + delta) % 24,
          minute: _selectedTime.minute,
        ),
      );
      return;
    }
    _updateTime(
      TimeOfDay(
        hour: _selectedTime.hour,
        minute: (_selectedTime.minute + delta) % 60,
      ),
    );
  }

  void _confirm() {
    HapticFeedback.lightImpact();
    widget.overlayHandle.complete(_selectedTime);
  }

  void _finishClockSelection() {
    if (_selection == _ClockSelection.hour) {
      setState(() => _selection = _ClockSelection.minute);
      return;
    }
    _confirm();
  }

  @override
  Widget build(BuildContext context) {
    final use24Hour = vitalPickerUses24Hour(context);
    final reduceMotion = VitalMotion.reduced(context);
    return KeyedSubtree(
      key: const ValueKey('vital_time_picker_dialog'),
      child: VitalPickerFrame(
        maxWidth: 360,
        title: widget.title,
        titleTextStyle: VitalPickerTheme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
        scrollMode: VitalPickerScrollMode.bounded,
        headerBodySpacing: 12,
        footerSpacing: 14,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TimeDisplay(
              value: _selectedTime,
              selection: _selection,
              use24Hour: use24Hour,
              onSelectionChanged: (selection) {
                setState(() => _selection = selection);
              },
              onPeriodChanged: (period) {
                _updateTime(
                  TimeOfDay(
                    hour:
                        (_selectedTime.hour % 12) +
                        (period == DayPeriod.pm ? 12 : 0),
                    minute: _selectedTime.minute,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: const ValueKey('vital_time_picker_clock_face'),
              child: AnimatedSwitcher(
                key: const ValueKey('vital_time_picker_clock_transition'),
                duration: reduceMotion
                    ? Duration.zero
                    : VitalMotion.duration(context, VitalMotion.choice),
                reverseDuration: reduceMotion
                    ? Duration.zero
                    : VitalPickerMotion.header(context),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _ClockFace(
                  key: ValueKey(_selection),
                  value: _selectedTime,
                  selection: _selection,
                  use24Hour: use24Hour,
                  onChanged: _updateTime,
                  onSelectionFinished: _finishClockSelection,
                  onIncrease: () => _adjust(1),
                  onDecrease: () => _adjust(-1),
                ),
              ),
            ),
          ],
        ),
        footer: VitalPickerActionBar(
          actions: [
            VitalPickerAction.secondary(
              label: widget.cancelLabel,
              onPressed: widget.overlayHandle.cancel,
            ),
            VitalPickerAction.primary(
              label: widget.confirmLabel,
              onPressed: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeDisplay extends StatelessWidget {
  const _TimeDisplay({
    required this.value,
    required this.selection,
    required this.use24Hour,
    required this.onSelectionChanged,
    required this.onPeriodChanged,
  });

  final TimeOfDay value;
  final _ClockSelection selection;
  final bool use24Hour;
  final ValueChanged<_ClockSelection> onSelectionChanged;
  final ValueChanged<DayPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final hour = use24Hour
        ? value.hour
        : (value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TimePartButton(
          key: const ValueKey('vital_time_picker_hour_button'),
          label: hour.toString().padLeft(2, '0'),
          selected: selection == _ClockSelection.hour,
          semanticLabel: AppLocalizations.of(context).pickerHour,
          onPressed: () => onSelectionChanged(_ClockSelection.hour),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            ':',
            style: VitalPickerTheme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        _TimePartButton(
          key: const ValueKey('vital_time_picker_minute_button'),
          label: value.minute.toString().padLeft(2, '0'),
          selected: selection == _ClockSelection.minute,
          semanticLabel: AppLocalizations.of(context).pickerMinute,
          onPressed: () => onSelectionChanged(_ClockSelection.minute),
        ),
        if (!use24Hour) ...[
          const SizedBox(width: 10),
          Column(
            children: [
              _PeriodButton(
                label: 'AM',
                selected: value.period == DayPeriod.am,
                onPressed: () => onPeriodChanged(DayPeriod.am),
              ),
              const SizedBox(height: 2),
              _PeriodButton(
                label: 'PM',
                selected: value.period == DayPeriod.pm,
                onPressed: () => onPeriodChanged(DayPeriod.pm),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TimePartButton extends StatelessWidget {
  const _TimePartButton({
    super.key,
    required this.label,
    required this.selected,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = VitalPickerTheme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: VitalPickerTap(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: VitalMotion.duration(context, VitalMotion.choice),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : scheme.onSurface.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: VitalPickerTheme.of(context).textTheme.headlineSmall
                ?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = VitalPickerTheme.of(context).colorScheme;
    return VitalPickerTap(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: VitalPickerTheme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ClockFace extends StatelessWidget {
  const _ClockFace({
    super.key,
    required this.value,
    required this.selection,
    required this.use24Hour,
    required this.onChanged,
    required this.onSelectionFinished,
    required this.onIncrease,
    required this.onDecrease,
  });

  final TimeOfDay value;
  final _ClockSelection selection;
  final bool use24Hour;
  final ValueChanged<TimeOfDay> onChanged;
  final VoidCallback onSelectionFinished;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  void _update(Offset position, Size size) {
    final center = size.center(Offset.zero);
    final offset = position - center;
    var angle = math.atan2(offset.dx, -offset.dy);
    if (angle < 0) angle += math.pi * 2;

    if (selection == _ClockSelection.minute) {
      final minute = (angle / (math.pi * 2) * 60).round() % 60;
      onChanged(TimeOfDay(hour: value.hour, minute: minute));
      return;
    }

    final slot = (angle / (math.pi * 2) * 12).round() % 12;
    final hourOnOuterRing = slot == 0 ? 12 : slot;
    if (use24Hour) {
      final radius = size.shortestSide / 2;
      final innerRing = offset.distance < radius * 0.64;
      final hour = innerRing ? (slot == 0 ? 0 : slot + 12) : hourOnOuterRing;
      onChanged(TimeOfDay(hour: hour, minute: value.minute));
      return;
    }

    final hour =
        (hourOnOuterRing % 12) + (value.period == DayPeriod.pm ? 12 : 0);
    onChanged(TimeOfDay(hour: hour, minute: value.minute));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final formatted = localizations.formatTimeOfDay(value);
    final previousValue = selection == _ClockSelection.hour
        ? TimeOfDay(hour: (value.hour - 1) % 24, minute: value.minute)
        : TimeOfDay(hour: value.hour, minute: (value.minute - 1) % 60);
    final nextValue = selection == _ClockSelection.hour
        ? TimeOfDay(hour: (value.hour + 1) % 24, minute: value.minute)
        : TimeOfDay(hour: value.hour, minute: (value.minute + 1) % 60);
    return Semantics(
      slider: true,
      label: selection == _ClockSelection.hour
          ? AppLocalizations.of(context).pickerClockHour
          : AppLocalizations.of(context).pickerClockMinute,
      value: formatted,
      increasedValue: localizations.formatTimeOfDay(nextValue),
      decreasedValue: localizations.formatTimeOfDay(previousValue),
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = math.min(constraints.maxWidth, 260.0);
          final faceSize = Size.square(size);
          return Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                _update(details.localPosition, faceSize);
                onSelectionFinished();
              },
              onPanStart: (details) => _update(details.localPosition, faceSize),
              onPanUpdate: (details) =>
                  _update(details.localPosition, faceSize),
              onPanEnd: (_) => onSelectionFinished(),
              child: CustomPaint(
                size: faceSize,
                painter: _ClockFacePainter(
                  value: value,
                  selection: selection,
                  use24Hour: use24Hour,
                  colorScheme: VitalPickerTheme.of(context).colorScheme,
                  textStyle: VitalPickerTheme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ClockFacePainter extends CustomPainter {
  const _ClockFacePainter({
    required this.value,
    required this.selection,
    required this.use24Hour,
    required this.colorScheme,
    required this.textStyle,
  });

  final TimeOfDay value;
  final _ClockSelection selection;
  final bool use24Hour;
  final ColorScheme colorScheme;
  final TextStyle? textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = colorScheme.onSurface.withValues(alpha: 0.045),
    );

    final selectedAngle = selection == _ClockSelection.hour
        ? (value.hour % 12) / 12 * math.pi * 2 - math.pi / 2
        : value.minute / 60 * math.pi * 2 - math.pi / 2;
    final selectedRadius = _selectedRadius(radius);
    final selectedCenter =
        center +
        Offset(math.cos(selectedAngle), math.sin(selectedAngle)) *
            selectedRadius;
    final primaryPaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, selectedCenter, primaryPaint);
    canvas.drawCircle(selectedCenter, 19, primaryPaint);
    canvas.drawCircle(center, 4, primaryPaint);

    if (selection == _ClockSelection.minute) {
      for (var slot = 0; slot < 12; slot++) {
        _paintLabel(
          canvas,
          center,
          radius * 0.78,
          slot,
          (slot * 5).toString().padLeft(2, '0'),
          value.minute == slot * 5,
        );
      }
      return;
    }

    for (var slot = 0; slot < 12; slot++) {
      final outerHour = slot == 0 ? 12 : slot;
      _paintLabel(
        canvas,
        center,
        radius * 0.78,
        slot,
        '$outerHour',
        use24Hour
            ? value.hour == outerHour
            : (value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod) == outerHour,
      );
      if (use24Hour) {
        final innerHour = slot == 0 ? 0 : slot + 12;
        _paintLabel(
          canvas,
          center,
          radius * 0.50,
          slot,
          innerHour.toString().padLeft(2, '0'),
          value.hour == innerHour,
          compact: true,
        );
      }
    }
  }

  double _selectedRadius(double radius) {
    if (selection == _ClockSelection.minute || !use24Hour) {
      return radius * 0.78;
    }
    return value.hour == 0 || value.hour > 12 ? radius * 0.50 : radius * 0.78;
  }

  void _paintLabel(
    Canvas canvas,
    Offset center,
    double labelRadius,
    int slot,
    String label,
    bool selected, {
    bool compact = false,
  }) {
    final angle = slot / 12 * math.pi * 2 - math.pi / 2;
    final labelCenter =
        center + Offset(math.cos(angle), math.sin(angle)) * labelRadius;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: textStyle?.copyWith(
          color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
          fontSize: compact ? 11 : 13,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      labelCenter - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_ClockFacePainter oldDelegate) {
    return value != oldDelegate.value ||
        selection != oldDelegate.selection ||
        use24Hour != oldDelegate.use24Hour ||
        colorScheme != oldDelegate.colorScheme ||
        textStyle != oldDelegate.textStyle;
  }
}
