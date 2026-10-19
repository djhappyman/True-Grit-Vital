import 'package:fl_chart/fl_chart.dart' as plot;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/charts.dart';
import '../../domain/charts/charts.dart';
import '../../domain/history/display_time.dart';
import '../../domain/stock/exact_amount.dart';
import '../../domain/scheduling/iana_clock.dart';
import '../../l10n/app_localizations.dart';

/// Engine-specific drawing only. Authoritative quantities and accessible
/// inspection stay in the exact domain/table, never in fl_chart tooltips.
class ChartPlot extends StatelessWidget {
  const ChartPlot({
    super.key,
    required this.series,
    required this.summary,
    required this.annotations,
    required this.onBucket,
  });
  final ChartSeriesWindow series;
  final String summary;
  final List<ChartAnnotation> annotations;
  final ValueChanged<int> onBucket;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        colors = Theme.of(context).colorScheme;
    if (series.buckets.isEmpty) {
      return Text(
        series.total.hasUnknownContributions ? t.chartUnknown : t.chartEmpty,
      );
    }
    final max = series.buckets
        .map((b) => b.amount)
        .reduce((a, b) => a > b ? a : b);
    final normalised = <double>[];
    for (final bucket in series.buckets) {
      final value = double.parse(
        (bucket.amount / max).roundedDecimal(places: 12),
      );
      if (!value.isFinite || value <= 0) return Text(t.chartPlotUnavailable);
      normalised.add(value);
    }
    if (MediaQuery.textScalerOf(context).scale(16) > 24 ||
        chartExactAmount(max).length > 12 ||
        series.key.unit.length > 12) {
      return Text(t.chartPlotUnavailable);
    }
    final byIndex = {
      for (var i = 0; i < series.buckets.length; i++)
        series.viewport.indexOf(series.buckets[i].bounds.fromInstant):
            normalised[i],
    };
    final n = series.viewport.bucketCount;
    final spots = <plot.FlSpot>[
      for (var index = 0; index < n; index++)
        if (byIndex[index] case final value?)
          plot.FlSpot(index + 0.5, value)
        else
          plot.FlSpot.nullSpot,
    ];
    final interval = n > 3 ? (n / 2).ceilToDouble() : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(series.key.unit),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          label: summary,
          child: ExcludeSemantics(
            child: SizedBox(
              height: 260,
              child: plot.LineChart(
                plot.LineChartData(
                  minX: 0,
                  maxX: n.toDouble(),
                  minY: 0,
                  maxY: 1.1,
                  lineBarsData: [
                    plot.LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: colors.primary,
                      barWidth: 2,
                      dotData: const plot.FlDotData(show: true),
                      belowBarData: plot.BarAreaData(show: false),
                    ),
                  ],
                  borderData: plot.FlBorderData(show: false),
                  gridData: plot.FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 0.5,
                    getDrawingHorizontalLine: (_) =>
                        plot.FlLine(color: colors.border, strokeWidth: 1),
                  ),
                  titlesData: plot.FlTitlesData(
                    topTitles: const plot.AxisTitles(
                      sideTitles: plot.SideTitles(showTitles: false),
                    ),
                    rightTitles: const plot.AxisTitles(
                      sideTitles: plot.SideTitles(showTitles: false),
                    ),
                    bottomTitles: plot.AxisTitles(
                      sideTitles: plot.SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: interval,
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (index < 0 || index >= n) {
                            return const SizedBox.shrink();
                          }
                          final date =
                              series.viewport.buckets[index].civilStart;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${date.day}/${date.month}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: plot.AxisTitles(
                      sideTitles: plot.SideTitles(
                        showTitles: true,
                        reservedSize: 72,
                        interval: 0.5,
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value > 1) {
                            return const SizedBox.shrink();
                          }
                          final amount =
                              max *
                              ExactAmount(
                                BigInt.from((value * 2).round()),
                                BigInt.two,
                              );
                          return Text(
                            chartExactAmount(amount),
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ),
                  ),
                  extraLinesData: plot.ExtraLinesData(
                    verticalLines: [
                      for (final annotation in annotations.take(200))
                        if (_annotationX(annotation) case final x?)
                          plot.VerticalLine(
                            x: x,
                            color: colors.mutedForeground,
                            strokeWidth: 1,
                            dashArray: [3, 4],
                          ),
                    ],
                  ),
                  lineTouchData: plot.LineTouchData(
                    handleBuiltInTouches: false,
                    touchCallback: (event, response) {
                      if (event is plot.FlTapUpEvent &&
                          response?.lineBarSpots?.isNotEmpty == true) {
                        onBucket(
                          response!.lineBarSpots!.first.x.floor().clamp(
                            0,
                            n - 1,
                          ),
                        );
                      }
                    },
                  ),
                ),
                duration: Duration.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }

  double? _annotationX(ChartAnnotation annotation) {
    try {
      var at = annotation.position(IanaClock());
      // A saved date describes its whole civil day, not an invented exact
      // time. Clamp an overlapping day to the visible left boundary.
      if (annotation.at.isDateOnly &&
          at.isBefore(series.viewport.fromInstant)) {
        final bounds = DisplayTime().dayBounds(
          annotation.at.civilDate!,
          annotation.at.zoneId!,
        );
        if (bounds.endExclusive.isAfter(series.viewport.fromInstant)) {
          at = series.viewport.fromInstant;
        }
      }
      final index = series.viewport.indexOf(at);
      if (index < 0) return null;
      final bucket = series.viewport.buckets[index];
      return index +
          at.difference(bucket.fromInstant).inMicroseconds /
              bucket.duration.inMicroseconds;
    } catch (_) {
      return null;
    }
  }
}
