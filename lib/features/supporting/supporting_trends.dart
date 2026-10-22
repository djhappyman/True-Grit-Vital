import '../../app/app_lock.dart';

import 'dart:convert';

import 'package:fl_chart/fl_chart.dart' as plot;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../app/supporting.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'supporting_source_link.dart';
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

class _SupportingTrendsPageState extends ConsumerState<SupportingTrendsPage>
    with WidgetsBindingObserver {
  /// The applied range and basis are initialised once from the route. A return
  /// link can then rebuild the exact comparison view after a direct open.
  late TextEditingController from, before;
  late CivilDate start, end;
  SupportingDateBasis basis = SupportingDateBasis.collection;
  bool _restoredRoute = false;
  bool _routeRangeInvalid = false, _openingSource = false;

  /// Whether the app window is foreground. The route below covers the page
  /// while a record is open; both states detach the expensive trend watcher.
  bool _foreground = true;

  /// The chosen comparison identity, never a position in the sorted group list.
  /// A live refresh, correction, void or range change can reorder or remove
  /// groups; only the matching exact identity keeps the selection.
  String? selectedGroupIdentity;

  /// Last readable summary for [selectedGroupIdentity]. A group that leaves the
  /// current range can still be named while it has no points to plot.
  String? selectedGroupLabel;
  int groupPage = 0, tablePage = 0, undatedPage = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    final today = CivilDate.fromDateTime(DateTime.now());
    start = today.addDays(-365);
    end = today.addDays(1);
    from = TextEditingController(text: start.toString());
    before = TextEditingController(text: end.toString());
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Reads the applied comparison and its browsing position from this route.
  ///
  /// Only a complete, increasing range is restored. Explicit malformed dates
  /// remain editable and block querying until Apply validates them.
  /// Entry time cannot position a measurement, so it is not restored as a
  /// trend basis.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredRoute) return;
    _restoredRoute = true;
    final params = GoRouterState.of(context).uri.queryParameters;
    final today = CivilDate.fromDateTime(DateTime.now());
    var restoredFrom = today.addDays(-365), restoredBefore = today.addDays(1);
    final fromText = params['from'], beforeText = params['before'];
    if (fromText != null || beforeText != null) {
      try {
        final a = CivilDate.parse(fromText ?? ''),
            b = CivilDate.parse(beforeText ?? '');
        if (b.compareTo(a) <= 0) throw const FormatException();
        restoredFrom = a;
        restoredBefore = b;
      } catch (_) {
        _routeRangeInvalid = true;
      }
    }
    start = restoredFrom;
    end = restoredBefore;
    from.text = _routeRangeInvalid ? fromText ?? '' : start.toString();
    before.text = _routeRangeInvalid ? beforeText ?? '' : end.toString();
    basis = params['basis'] == SupportingDateBasis.report.name
        ? SupportingDateBasis.report
        : SupportingDateBasis.collection;
    final group = params['group'];
    selectedGroupIdentity = group == null || group.isEmpty ? null : group;
    groupPage = _restoredPage(params['groupPage']);
    tablePage = _restoredPage(params['table']);
    undatedPage = _restoredPage(params['undated']);
  }

  static int _restoredPage(String? value) {
    final page = int.tryParse(value ?? '');
    return page == null || page < 0 ? 0 : page;
  }

  /// The exact comparison view currently on screen. Its own date basis, chosen
  /// identity and table pages are carried, not a default Labs destination.
  String _returnLocation() => supportingTrendsLocation(
    personId: widget.personId,
    metricId: widget.metricId,
    from: start,
    before: end,
    basis: basis,
    group: selectedGroupIdentity,
    groupPage: groupPage,
    tablePage: tablePage,
    undatedPage: undatedPage,
  );

  /// Opens the exact saved revision summarised by this row.
  ///
  /// The location is built from the record's captured owner and identity, never
  /// from the page's current filter or a displayed name. A lock or an already
  /// covered route therefore cannot open a source from a stale frame.
  Future<void> _openSource(
    SupportingTrendEntry entry,
    String generation,
  ) async {
    if (!mounted ||
        _openingSource ||
        ref.read(appLockProvider).locked ||
        ref.read(recordStoreProvider).value?.generation != generation) {
      return;
    }
    // A trend entry belongs to this owner's dataset. Never turn a mismatched
    // or missing identity into a source route for someone else.
    if (entry.record.id.personId != widget.personId) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _openingSource = true;
    try {
      await context.push(
        supportingSourceLocation(
          entry.record.id,
          revision: entry.record.revision,
          returnLocation: _returnLocation(),
        ),
      );
    } finally {
      if (mounted) _openingSource = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    from.dispose();
    before.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground != _foreground && mounted) {
      setState(() => _foreground = foreground);
    }
  }

  @override
  void didUpdateWidget(covariant SupportingTrendsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A deliberate change of marker or owner is a different question, so the
    // old comparison choice does not carry across. The page may then choose
    // its first group once, as an unselected page does.
    if (oldWidget.personId != widget.personId ||
        oldWidget.metricId != widget.metricId) {
      selectedGroupIdentity = null;
      selectedGroupLabel = null;
      groupPage = 0;
      tablePage = 0;
      undatedPage = 0;
    }
  }

  /// Range and date-basis changes only reset browsing pages. They must not
  /// discard the chosen comparison identity.
  void resetPages() {
    groupPage = 0;
    tablePage = 0;
    undatedPage = 0;
  }

  SupportingTrendGroup? _selection(
    AppLocalizations t,
    List<SupportingTrendGroup> orderedGroups,
  ) {
    if (orderedGroups.isEmpty) return null;
    final identity = selectedGroupIdentity;
    if (identity == null) {
      // An unselected page adopts the first chronological group once. Later
      // inserts and corrections keep that identity rather than this position.
      selectedGroupIdentity = orderedGroups.first.key.identity;
      selectedGroupLabel = _groupLabel(t, orderedGroups.first);
      return orderedGroups.first;
    }
    for (final group in orderedGroups) {
      if (group.key.identity == identity) {
        selectedGroupLabel = _groupLabel(t, group);
        return group;
      }
    }
    return null;
  }

  void _chooseGroup(AppLocalizations t, SupportingTrendGroup group) {
    setState(() {
      selectedGroupIdentity = group.key.identity;
      selectedGroupLabel = _groupLabel(t, group);
    });
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
    final encoded = jsonEncode(query.toJson());
    // A covered route, a backgrounded app or the lock screen must not keep a
    // store subscription open. The route dependency and the lifecycle observer
    // rebuild this page on return, which watches the current query afresh
    // without changing the chosen comparison identity.
    final visible =
        !_routeRangeInvalid &&
        _foreground &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    AsyncValue<SupportingTrendPage?>? result;
    String? liveGeneration;
    if (visible) {
      final record = ref.watch(recordStoreProvider);
      liveGeneration = record.isLoading || record.hasError
          ? null
          : record.value?.generation;
      result = ref.watch(supportingTrendProvider(encoded));
    }
    final candidate = result?.value;
    // A retained AsyncValue from a retired store or a previous query is not
    // current data, even while the replacement request is still loading.
    final model =
        candidate != null &&
            liveGeneration != null &&
            candidate.query.identity == query.identity &&
            candidate.datasetGeneration == liveGeneration
        ? candidate
        : null;
    final groups = model?.groups ?? <SupportingTrendGroup>[];
    // The selector follows the first positioned date, not comparison-key hash
    // order, so the first group is the earliest saved result in this view.
    final orderedGroups = [...groups]..sort(_compareGroup);
    final group = _selection(t, orderedGroups);
    final selectedIndex = selectedGroupIdentity == null
        ? -1
        : orderedGroups.indexWhere(
            (candidate) => candidate.key.identity == selectedGroupIdentity,
          );
    final lastGroupPage = orderedGroups.isEmpty
        ? 0
        : (orderedGroups.length - 1) ~/ 25;
    final visibleGroupPage = groupPage.clamp(0, lastGroupPage);
    final groupNumbers = <String, int>{
      for (var i = 0; i < orderedGroups.length; i++)
        orderedGroups[i].key.identity: i + 1,
    };
    final undated = <SupportingTrendEntry>[...?model?.unpositioned]
      ..sort((a, b) => a.identity.compareTo(b.identity));
    final groupSummaries = <String, String>{
      for (var i = 0; i < orderedGroups.length; i++)
        orderedGroups[i].key.identity: _entrySummary(
          t,
          orderedGroups[i].entries.first,
          number: i + 1,
          count: orderedGroups.length,
        ),
    };
    final undatedSummaries = <String, String>{
      for (final entry in undated)
        entry.identity: _entrySummary(t, entry, number: null, count: 0),
    };
    // The exact table is the primary view. Flattening the groups and sorting
    // again restores the declared date-basis chronology instead of leaving
    // entries in comparison-key batches. Each row keeps its group number so
    // identical marker/unit labels cannot hide a different source identity.
    final positioned = <SupportingTrendEntry>[
      for (final g in groups) ...g.entries,
    ]..sort(_compareEntry);
    if (model != null) {
      // Clamp only after the current dataset answers. Loading must not erase
      // a restored page before its rows arrive.
      groupPage = visibleGroupPage;
      tablePage = tablePage.clamp(
        0,
        positioned.isEmpty ? 0 : (positioned.length - 1) ~/ 25,
      );
      undatedPage = undatedPage.clamp(
        0,
        undated.isEmpty ? 0 : (undated.length - 1) ~/ 25,
      );
    }
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
            resetPages();
          }),
          label: (v) => switch (v) {
            SupportingDateBasis.collection => t.supportingCollection,
            SupportingDateBasis.report => t.supportingReportChoice,
            SupportingDateBasis.entry => t.supportingEntryChoice,
          },
        ),
        LabelledInput(label: t.supportingFrom, controller: from),
        LabelledInput(label: t.supportingBefore, controller: before),
        if (!_routeRangeInvalid)
          Text(t.chartRangeSummary(start.toString(), end.toString())),
        Text(t.supportingDisplayZone(query.displayZone)),
        VitalButton.secondary(
          onPressed: () {
            try {
              final a = CivilDate.parse(from.text),
                  b = CivilDate.parse(before.text);
              if (b.compareTo(a) <= 0) throw const FormatException();
              setState(() {
                start = a;
                end = b;
                resetPages();
                error = null;
                _routeRangeInvalid = false;
              });
            } catch (_) {
              setState(() => error = t.supportingFilterInvalid);
            }
          },
          child: Text(t.supportingApply),
        ),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        if (_routeRangeInvalid)
          Semantics(liveRegion: true, child: Text(t.supportingFilterInvalid)),
        if (result != null && result.hasError) ...[
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
        if (visible && model == null && (result?.isLoading ?? true))
          Text(t.loadingRecords),
        if (model != null && groups.isEmpty && undated.isEmpty)
          Text(t.supportingNoMatches),
        if (positioned.isNotEmpty)
          VitalSection(
            title: Text(t.supportingTable),
            children: [
              Text(t.supportingTableOrder),
              for (final entry in positioned.skip(tablePage * 25).take(25))
                _TrendTableRow(
                  entry: entry,
                  groupLabel: t.supportingGroupShort(
                    groupNumbers[entry.groupKey.identity] ?? 0,
                  ),
                  groupSummary: groupSummaries[entry.groupKey.identity] ?? '',
                  ref: ref,
                  onOpen: () => _openSource(entry, model!.datasetGeneration),
                ),
              if (positioned.length > 25)
                _pager(
                  t,
                  page: tablePage,
                  count: positioned.length,
                  onChanged: (value) => setState(() => tablePage = value),
                ),
            ],
          ),
        if (undated.isNotEmpty)
          VitalSection(
            title: Text(t.supportingUndatedResults),
            children: [
              Text(t.supportingUndatedHelp),
              for (final entry in undated.skip(undatedPage * 25).take(25))
                _TrendTableRow(
                  entry: entry,
                  groupLabel: t.supportingUndatedGroup,
                  groupSummary: undatedSummaries[entry.identity] ?? '',
                  ref: ref,
                  onOpen: () => _openSource(entry, model!.datasetGeneration),
                ),
              if (undated.length > 25)
                _pager(
                  t,
                  page: undatedPage,
                  count: undated.length,
                  onChanged: (value) => setState(() => undatedPage = value),
                ),
            ],
          ),
        if (model != null &&
            (orderedGroups.isNotEmpty || selectedGroupIdentity != null))
          VitalSection(
            title: Text(t.chartPlot),
            children: [
              if (orderedGroups.isNotEmpty &&
                  (orderedGroups.length > 1 || selectedIndex < 0)) ...[
                Text(t.supportingGroups),
                for (
                  var i = visibleGroupPage * 25;
                  i < orderedGroups.length && i < (visibleGroupPage + 1) * 25;
                  i++
                )
                  MergeSemantics(
                    child: Semantics(
                      selected: i == selectedIndex,
                      child: i == selectedIndex
                          ? VitalButton(
                              multiline: true,
                              onPressed: () =>
                                  _chooseGroup(t, orderedGroups[i]),
                              child: Text(
                                groupSummaries[orderedGroups[i].key.identity]!,
                              ),
                            )
                          : VitalButton.secondary(
                              multiline: true,
                              onPressed: () =>
                                  _chooseGroup(t, orderedGroups[i]),
                              child: Text(
                                groupSummaries[orderedGroups[i].key.identity]!,
                              ),
                            ),
                    ),
                  ),
                if (orderedGroups.length > 25)
                  _pager(
                    t,
                    page: visibleGroupPage,
                    count: orderedGroups.length,
                    onChanged: (value) => setState(() => groupPage = value),
                  ),
              ],
              Text(t.supportingSelectedGroup),
              if (group != null) ...[
                Text(
                  groupSummaries[group.key.identity] ??
                      _entrySummary(
                        t,
                        group.entries.first,
                        number: groupNumbers[group.key.identity] ?? 0,
                        count: orderedGroups.length,
                      ),
                ),
                SupportingProvenanceView(
                  provenance:
                      group.entries.first.result.provenance ??
                      group.entries.first.record.snapshot.provenance,
                ),
                if (group.hasUnpositionedGap) Text(t.supportingGroupUndated),
                SupportingPlot(group: group),
              ] else ...[
                if (selectedGroupLabel case final label?) Text(label),
                Semantics(
                  liveRegion: true,
                  child: Text(t.supportingGroupNoResults),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

Widget _pager(
  AppLocalizations t, {
  required int page,
  required int count,
  required ValueChanged<int> onChanged,
}) => Wrap(
  spacing: 12,
  runSpacing: 12,
  children: [
    VitalButton.secondary(
      onPressed: page > 0 ? () => onChanged(page - 1) : null,
      child: Text(t.supportingPrevious),
    ),
    VitalButton.secondary(
      onPressed: (page + 1) * 25 < count ? () => onChanged(page + 1) : null,
      child: Text(t.supportingNext),
    ),
  ],
);

String _identityPart(String? name, String? id, String unknown) {
  if (name == null || name.isEmpty) return id ?? unknown;
  if (id == null || id.isEmpty || id == name) return name;
  return '$name ($id)';
}

int _compareGroup(SupportingTrendGroup a, SupportingTrendGroup b) {
  final ad = a.entries.firstOrNull?.day, bd = b.entries.firstOrNull?.day;
  if (ad != null && bd != null) {
    final byDay = ad.compareTo(bd);
    if (byDay != 0) return byDay;
  } else if (ad != null) {
    return -1;
  } else if (bd != null) {
    return 1;
  }
  return a.key.identity.compareTo(b.key.identity);
}

String _groupLabel(AppLocalizations t, SupportingTrendGroup group) =>
    _entrySummary(t, group.entries.first, number: null, count: 0);

String _entrySummary(
  AppLocalizations t,
  SupportingTrendEntry entry, {
  required int? number,
  required int count,
}) {
  final key = entry.groupKey;
  final provenance =
      entry.result.provenance ?? entry.record.snapshot.provenance;
  final summary = key.kind == SupportingMetricKind.observation
      ? t.supportingGroupObservation(
          entry.result.markerName,
          key.unit ?? t.supportingUnknown,
        )
      : t.supportingGroupSummary(
          entry.result.markerName,
          key.unit ?? t.supportingUnknown,
          _identityPart(
            provenance.laboratoryName,
            provenance.laboratoryId,
            t.supportingUnknown,
          ),
          _identityPart(
            provenance.methodText,
            provenance.methodId,
            t.supportingUnknown,
          ),
          _identityPart(
            provenance.specimenText,
            provenance.specimenId,
            t.supportingUnknown,
          ),
        );
  final uncertain = key.certain
      ? ''
      : key.kind == SupportingMetricKind.observation
      ? ' ${t.supportingGroupObservationSeparate}'
      : ' ${t.supportingGroupUncertain} '
            '${t.supportingTarget(entry.record.snapshot.title)} '
            '${t.supportingRevisionLabel(entry.record.revision)}';
  return number == null
      ? '$summary$uncertain'
      : '${t.supportingGroupNumber(number, count)} $summary$uncertain';
}

int _compareEntry(SupportingTrendEntry a, SupportingTrendEntry b) {
  final day = a.day!.compareTo(b.day!);
  if (day != 0) return day;
  final ai = a.exactInstant, bi = b.exactInstant;
  if (ai != null && bi != null) {
    final at = ai.compareTo(bi);
    if (at != 0) return at;
  } else if (ai != null) {
    return -1;
  } else if (bi != null) {
    return 1;
  }
  return a.identity.compareTo(b.identity);
}

class _TrendTableRow extends StatelessWidget {
  const _TrendTableRow({
    required this.entry,
    required this.groupLabel,
    required this.groupSummary,
    required this.ref,
    required this.onOpen,
  });
  final SupportingTrendEntry entry;
  final String groupLabel;
  final String groupSummary;
  final WidgetRef ref;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return VitalSurface(
      key: ValueKey(entry.identity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: groupSummary,
            child: Text(
              groupLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            entry.record.snapshot.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(supportingDateLabel(context, ref, entry.date)),
          if (supportingDateSourceLabel(context, ref, entry.date)
              case final source?)
            Text(source),
          if (entry.positionZoneFallback) Text(t.supportingOffsetFallback),
          SupportingResultView(result: entry.result),
          Text(t.supportingRevisionLabel(entry.record.revision)),
          Semantics(
            label: t.supportingOpenRecord(entry.record.snapshot.title),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: VitalButton.secondary(
                onPressed: onOpen,
                child: Text(t.supportingOpen),
              ),
            ),
          ),
        ],
      ),
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
    if (!group.canConnect) {
      return Text(
        group.key.kind == SupportingMetricKind.observation
            ? t.supportingGroupObservationSeparate
            : t.supportingGroupUncertain,
      );
    }
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
