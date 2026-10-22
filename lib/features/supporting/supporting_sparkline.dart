import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/stock/exact_amount.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import '../../ui/vital_motion.dart';
import 'screen_labs_latest.dart';
import 'supporting_source_link.dart';
import 'supporting_widgets.dart';

/// A bounded, factual trend through exact numeric points from the same saved
/// comparison identity. It draws no target line, zero baseline or fill, and it
/// never invents a value for a censored, qualitative or missing result.
class ScreenLabsSparkline extends ConsumerStatefulWidget {
  const ScreenLabsSparkline({
    super.key,
    required this.series,
    required this.unit,
    required this.returnLocation,
  });
  final ScreenLabsSparkSeries series;
  final String? unit;
  final String returnLocation;

  @override
  ConsumerState<ScreenLabsSparkline> createState() =>
      _ScreenLabsSparklineState();
}

class _ScreenLabsSparklineState extends ConsumerState<ScreenLabsSparkline> {
  bool table = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), colors = StitchColors(context);
    final points = [for (final segment in widget.series.segments) ...segment];
    final first = widget.series.first;
    final latest = widget.series.latest;
    if (first == null || latest == null) return const SizedBox.shrink();
    final summary = t.screenLabsSparklineSummary(
      points.length,
      supportingDateLabel(context, ref, first.record.snapshot.collectionDate),
      supportingDateLabel(context, ref, latest.record.snapshot.collectionDate),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: summary,
          child: ExcludeSemantics(
            child: SizedBox(
              height: 52,
              child: CustomPaint(
                painter: _SparkPainter(
                  series: widget.series,
                  color: colors.accent,
                  muted: colors.muted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          t.screenLabsSparklineExactOnly,
          style: StitchType.caption.copyWith(color: colors.muted),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SupportingDisclosure(
            label: t.supportingTable,
            semanticLabel: t.screenLabsSparklineTable,
            open: table,
            onPressed: () => setState(() => table = !table),
          ),
        ),
        VitalReveal(
          expanded: table,
          child: StitchSurface(
            inset: true,
            radius: 12,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.screenLabsSparklineDate,
                        style: StitchType.caption.copyWith(color: colors.muted),
                      ),
                    ),
                    Text(
                      t.screenLabsSparklineValue,
                      style: StitchType.caption.copyWith(color: colors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final point in points)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _ScreenLabsSparkTableRow(
                      point: point,
                      date: supportingDateLabel(
                        context,
                        ref,
                        point.record.snapshot.collectionDate,
                      ),
                      value: supportingValueLabel(t, point.result),
                      returnLocation: widget.returnLocation,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One disclosed exact point. Its source command uses the saved record and
/// owner identity, never the displayed date, value or title, and it only pushes
/// the existing canonical detail route so the Labs collection stays beneath it.
class _ScreenLabsSparkTableRow extends StatelessWidget {
  const _ScreenLabsSparkTableRow({
    required this.point,
    required this.date,
    required this.value,
    required this.returnLocation,
  });
  final ScreenLabsSparkPoint point;
  final String date, value, returnLocation;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final source = Semantics(
      key: ValueKey('spark-source-${point.record.id.id}-${point.result.id}'),
      label: t.directLabSourceAction(point.record.snapshot.title, date, value),
      child: StitchButton(
        quiet: true,
        compact: true,
        onPressed: () => context.push(
          supportingSourceLocation(
            point.record.id,
            returnLocation: returnLocation,
          ),
        ),
        child: Text(t.supportingOpen),
      ),
    );
    final dateText = Text(date, style: StitchType.caption);
    final valueText = Text(value, style: StitchType.caption);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dateText,
              const SizedBox(height: 4),
              valueText,
              const SizedBox(height: 4),
              Align(alignment: AlignmentDirectional.centerStart, child: source),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: dateText),
            const SizedBox(width: 12),
            Expanded(child: valueText),
            const SizedBox(width: 8),
            source,
          ],
        );
      },
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.series,
    required this.color,
    required this.muted,
  });
  final ScreenLabsSparkSeries series;
  final Color color, muted;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [for (final segment in series.segments) ...segment];
    if (points.isEmpty || size.isEmpty) return;
    final days = points
        .map((point) => point.day.calendarValue.millisecondsSinceEpoch)
        .toList(growable: false);
    final values = points
        .map((point) => point.result.value.exactAmount!)
        .toList(growable: false);
    var minDay = days.reduce(math.min), maxDay = days.reduce(math.max);
    var minValue = values.first, maxValue = values.first;
    for (final value in values.skip(1)) {
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
    const inset = 6.0;
    final width = math.max(1.0, size.width - inset * 2);
    final height = math.max(1.0, size.height - inset * 2);
    double xFor(int day) => maxDay == minDay
        ? size.width / 2
        : inset + (day - minDay) / (maxDay - minDay) * width;
    double yFor(ExactAmount value) {
      if (minValue == maxValue) return size.height / 2;
      final fraction = (value - minValue) / (maxValue - minValue);
      // Bounded output-only normalisation avoids infinity for large rationals.
      final scale = BigInt.from(1000000);
      final ratio =
          (fraction.numerator * scale ~/ fraction.denominator).toDouble() /
          1000000;
      return inset + height - ratio.clamp(0.0, 1.0) * height;
    }

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final segment in series.segments) {
      if (segment.isEmpty) continue;
      final path = Path();
      for (var index = 0; index < segment.length; index++) {
        final point = segment[index];
        final x = xFor(point.day.calendarValue.millisecondsSinceEpoch);
        final y = yFor(point.result.value.exactAmount!);
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      if (segment.length > 1) canvas.drawPath(path, line);
    }
    final dot = Paint()..color = color;
    final radius = points.length == 1 ? 3.2 : 2.2;
    for (final point in points) {
      canvas.drawCircle(
        Offset(
          xFor(point.day.calendarValue.millisecondsSinceEpoch),
          yFor(point.result.value.exactAmount!),
        ),
        radius,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.color != color ||
      oldDelegate.muted != muted;
}
