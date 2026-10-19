import '../../app/app_lock.dart';

import 'dart:convert';

import 'package:fl_chart/fl_chart.dart' as plot;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/supporting.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'supporting_widgets.dart';

class SupportingTrendsPage extends ConsumerStatefulWidget {
  const SupportingTrendsPage({
    super.key,
    required this.personId,
    required this.metricId,
  });
  final String personId, metricId;
  @override
  ConsumerState<SupportingTrendsPage> createState() =>
      _SupportingTrendsPageState();
}

class _SupportingTrendsPageState extends ConsumerState<SupportingTrendsPage> {
  late final from = TextEditingController(
        text: CivilDate.fromDateTime(DateTime.now()).addDays(-365).toString(),
      ),
      before = TextEditingController(
        text: CivilDate.fromDateTime(DateTime.now()).addDays(1).toString(),
      );
  late CivilDate start = CivilDate.parse(from.text),
      end = CivilDate.parse(before.text);
  SupportingDateBasis basis = SupportingDateBasis.collection;
  int selectedGroup = 0, groupPage = 0, tablePage = 0;
  String? error;
  @override
  void dispose() {
    from.dispose();
    before.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(appLockProvider.select((s) => s.locked))) {
      return EntryPage(
        children: [Text(AppLocalizations.of(context).supportingLocked)],
      );
    }
    final t = AppLocalizations.of(context);
    if (widget.metricId.isEmpty) {
      return EntryPage(children: [Text(t.supportingUnavailable)]);
    }
    final query = SupportingTrendQuery(
      personId: widget.personId,
      metricId: widget.metricId,
      fromDate: start,
      beforeDate: end,
      dateBasis: basis,
      displayZone: ref.watch(displayZoneProvider),
    );
    final encoded = jsonEncode(query.toJson()),
        result = ref.watch(supportingTrendProvider(encoded));
    final model = result.value;
    final groups = model?.groups ?? <SupportingTrendGroup>[];
    final group = groups.isEmpty
        ? null
        : groups[selectedGroup.clamp(0, groups.length - 1)];
    final entries = [
      for (final g in groups) ...g.entries,
      ...?model?.unpositioned,
    ];
    return EntryPage(
      children: [
        Heading(t.supportingTrends),
        Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
        Text(t.supportingTrendScope),
        Text(t.supportingDateBasis),
        VitalSegments<SupportingDateBasis>(
          values: const [
            SupportingDateBasis.collection,
            SupportingDateBasis.report,
          ],
          selected: basis,
          onChanged: (v) => setState(() {
            basis = v;
            selectedGroup = 0;
            groupPage = 0;
            tablePage = 0;
          }),
          label: (v) => switch (v) {
            SupportingDateBasis.collection => t.supportingCollection,
            SupportingDateBasis.report => t.supportingReportChoice,
            SupportingDateBasis.entry => t.supportingEntryChoice,
          },
        ),
        LabelledInput(label: t.supportingFrom, controller: from),
        LabelledInput(label: t.supportingBefore, controller: before),
        Text(t.chartRangeSummary(start.toString(), end.toString())),
        Text(query.displayZone),
        VitalButton.secondary(
          onPressed: () {
            try {
              final a = CivilDate.parse(from.text),
                  b = CivilDate.parse(before.text);
              if (b.compareTo(a) <= 0) throw const FormatException();
              setState(() {
                start = a;
                end = b;
                selectedGroup = 0;
                groupPage = 0;
                tablePage = 0;
                error = null;
              });
            } catch (_) {
              setState(() => error = t.supportingInvalid);
            }
          },
          child: Text(t.supportingApply),
        ),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        if (result.hasError) ...[
          Text(
            result.error is SupportingLimitException
                ? t.supportingTooMany
                : t.supportingLoadFailure,
          ),
          VitalButton.secondary(
            onPressed: () => ref.invalidate(supportingTrendProvider(encoded)),
            child: Text(t.retry),
          ),
        ],
        if (result.isLoading) Text(t.loadingRecords),
        if (model != null && entries.isEmpty) Text(t.supportingNoTrend),
        if (groups.isNotEmpty)
          VitalSection(
            title: Text(t.supportingMetrics),
            children: [
              for (
                var i = groupPage * 25;
                i < groups.length && i < (groupPage + 1) * 25;
                i++
              )
                VitalButton.secondary(
                  multiline: true,
                  onPressed: () => setState(() => selectedGroup = i),
                  child: Text(
                    t.supportingGroupLabel(
                      groups[i].entries.first.result.markerName,
                      groups[i].key.unit ?? t.supportingUnknown,
                    ),
                  ),
                ),
              if (groups.length > 25)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    VitalButton.secondary(
                      onPressed: groupPage > 0
                          ? () => setState(() => groupPage--)
                          : null,
                      child: Text(t.supportingPrevious),
                    ),
                    VitalButton.secondary(
                      onPressed: (groupPage + 1) * 25 < groups.length
                          ? () => setState(() => groupPage++)
                          : null,
                      child: Text(t.supportingNext),
                    ),
                  ],
                ),
            ],
          ),
        if (group != null) ...[
          Text(
            t.supportingGroupLabel(
              group.entries.first.result.markerName,
              group.key.unit ?? t.supportingUnknown,
            ),
          ),
          SupportingProvenanceView(
            provenance:
                group.entries.first.result.provenance ??
                group.entries.first.record.snapshot.provenance,
          ),
          if (!group.canConnect) Text(t.supportingGroupUncertain),
          SupportingPlot(group: group),
        ],
        VitalSection(
          title: Text(t.supportingTable),
          children: [
            for (final entry in entries.skip(tablePage * 25).take(25))
              VitalSurface(
                key: ValueKey(entry.identity),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(entry.record.snapshot.title),
                    Text(supportingDateLabel(context, ref, entry.date)),
                    if (entry.positionZoneFallback)
                      Text(t.supportingOffsetFallback),
                    SupportingResultView(result: entry.result),
                    Text(t.supportingRevisionLabel(entry.record.revision)),
                    VitalButton.secondary(
                      onPressed: () => context.push(
                        '/supporting/${widget.personId}/${entry.record.id.id}?revision=${entry.record.revision}',
                      ),
                      child: Text(t.supportingSource),
                    ),
                  ],
                ),
              ),
            if (entries.length > 25)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  VitalButton.secondary(
                    onPressed: tablePage > 0
                        ? () => setState(() => tablePage--)
                        : null,
                    child: Text(t.supportingPrevious),
                  ),
                  VitalButton.secondary(
                    onPressed: (tablePage + 1) * 25 < entries.length
                        ? () => setState(() => tablePage++)
                        : null,
                    child: Text(t.supportingNext),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// The canvas is redundant with the complete, paged keyboard accessible table.
/// Exact arithmetic normalises signed values before the rendering-only doubles.
class SupportingPlot extends StatelessWidget {
  const SupportingPlot({super.key, required this.group});
  final SupportingTrendGroup group;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!group.canConnect) return Text(t.supportingGroupUncertain);
    final numeric = group.entries.where((e) => e.numericValue != null).toList();
    if (numeric.isEmpty) return Text(t.supportingNoTrend);
    var min = numeric.first.numericValue!, max = min;
    for (final e in numeric) {
      if (e.numericValue! < min) min = e.numericValue!;
      if (e.numericValue! > max) max = e.numericValue!;
    }
    final span = max - min;
    double y(SupportingTrendEntry e) => span == ExactAmount.zero
        ? 0.5
        : double.parse(
            ((e.numericValue! - min) / span).roundedDecimal(places: 12),
          );
    double x(SupportingTrendEntry e) =>
        e.day!.calendarValue.millisecondsSinceEpoch /
        Duration.millisecondsPerDay;
    final distinct = <double, ExactAmount>{};
    for (final e in numeric) {
      final value = y(e);
      if (distinct.containsKey(value) && distinct[value] != e.numericValue) {
        return Text(t.chartPlotUnavailable);
      }
      distinct[value] = e.numericValue!;
    }
    final xs = [for (final e in numeric) x(e)]..sort();
    final first = xs.first, last = xs.last;
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.supportingPlotBounds(
            supportingValueLabel(
              t,
              numeric.firstWhere((e) => e.numericValue == min).result,
            ),
            supportingValueLabel(
              t,
              numeric.firstWhere((e) => e.numericValue == max).result,
            ),
          ),
        ),
        Semantics(
          container: true,
          label: t.supportingPlotLabel(numeric.length),
          child: ExcludeSemantics(
            child: SizedBox(
              height: 240,
              child: plot.LineChart(
                plot.LineChartData(
                  minX: first - 0.5,
                  maxX: last + 0.5,
                  minY: -0.05,
                  maxY: 1.05,
                  lineBarsData: [
                    for (final run in group.runs)
                      plot.LineChartBarData(
                        spots: [for (final e in run) plot.FlSpot(x(e), y(e))],
                        isCurved: false,
                        color: color,
                        barWidth: 0,
                        dotData: const plot.FlDotData(show: true),
                      ),
                  ],
                  titlesData: const plot.FlTitlesData(show: false),
                  borderData: plot.FlBorderData(show: false),
                  gridData: const plot.FlGridData(show: false),
                  lineTouchData: const plot.LineTouchData(enabled: false),
                ),
                duration: Duration.zero,
              ),
            ),
          ),
        ),
        Text(
          t.supportingPlotDates(
            group.entries.first.day.toString(),
            group.entries.last.day.toString(),
          ),
        ),
      ],
    );
  }
}
