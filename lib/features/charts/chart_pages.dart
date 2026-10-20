import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' show MaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/charts.dart';
import '../../app/display_preferences.dart';
import '../../data/record_store.dart';
import '../../domain/charts/charts.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../history/history_pages.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'chart_plot.dart';

class ChartsPage extends ConsumerStatefulWidget {
  const ChartsPage({super.key, this.location = '/charts'});
  final String location;
  @override
  ConsumerState<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends ConsumerState<ChartsPage> {
  late final seed = Uri.parse(widget.location).queryParameters;
  final from = TextEditingController(), before = TextEditingController();
  static const personId = meId;
  ChartBucketSize granularity = ChartBucketSize.day;
  DateTime? lower, upper;
  String? zone, configured, error, repairedZone;

  /// One exact selected series. Kept across range, granularity and data
  /// changes so a narrower view never silently charts a different substance.
  ChartSeriesKey? seriesKey;

  /// Last saved name shown for [seriesKey]. Used when a range has no points
  /// for it, because the current batch then has no name to offer.
  String? seriesLabel;
  bool table = false, filters = false, seriesOpen = false, sourcesOpen = false;

  /// The source list starts with current contributing records because chart
  /// totals exclude voided revisions. Voided history stays reachable only
  /// through this explicit local choice.
  TimelineStatus sourcesStatus = TimelineStatus.recorded;
  int tablePage = 0;
  int? selectedBucket;
  ChartDrilldownCursor? restoredSourceCursor;
  List<ChartDrilldownCursor?> restoredSourceCursors = [null];
  final tableFocus = FocusNode(
    debugLabel: 'chart table page',
    skipTraversal: true,
  );
  final rangeFocus = FocusNode(debugLabel: 'chart range', skipTraversal: true);
  ChartController get controller =>
      ref.read(chartControllerProvider(widget.location).notifier);
  @override
  void dispose() {
    tableFocus.dispose();
    rangeFocus.dispose();
    from.dispose();
    before.dispose();
    super.dispose();
  }

  void resetRange(DateTime a, DateTime b, String shownZone) {
    lower = a;
    upper = b;
    final display = DisplayTime();
    from.text = display.instant(a, shownZone).dateText;
    before.text = display.instant(b, shownZone).dateText;
    selectedBucket = null;
    tablePage = 0;
    restoredSourceCursor = null;
    restoredSourceCursors = [null];
    sourcesOpen = false;
  }

  /// Restores the one exact series a route names, if any.
  ///
  /// Route parameters are user-editable input. An empty or over-long subject
  /// or unit is ignored instead of failing the page; the normal first
  /// compatible series is then used.
  void restoreSeedSeries() {
    final subject = seed['subject'], unit = seed['unit'];
    if (subject == null || unit == null) return;
    try {
      seriesKey = ChartSeriesKey(
        personId: personId,
        subject: seed['kind'] == 'ingredient'
            ? ChartSubject.ingredient(subject)
            : ChartSubject.item(subject),
        unit: unit,
      );
    } on ChartModelException {
      seriesKey = null;
      seriesLabel = null;
    }
  }

  String returnLocation(ChartSeriesKey key, {ChartDrilldownCursor? cursor}) =>
      Uri(
        path: '/charts',
        queryParameters: {
          'scope': personId,
          'from': lower!.toIso8601String(),
          'before': upper!.toIso8601String(),
          'bucket': granularity.name,
          'subject': key.subject.id,
          'kind': key.subject.kind.name,
          'unit': key.unit,
          'mode': table ? 'table' : 'chart',
          'page': '$tablePage',
          if (seed['return'] != null) 'return': seed['return']!,
          if (selectedBucket != null) 'selected': '$selectedBucket',
          if (sourcesOpen) 'sources': 'true',
          'sourcesStatus': sourcesStatus.name,
          if (cursor != null) 'cursor': cursor.encode(),
          if (cursor != null)
            'cursors': jsonEncode(
              restoredSourceCursors.map((value) => value?.encode()).toList(),
            ),
        },
      ).toString();

  @override
  Widget build(BuildContext context) {
    final observedZone = ref.watch(displayZoneProvider);
    final String shownZone = repairedZone ?? observedZone;
    final t = AppLocalizations.of(context),
        state = ref.watch(chartControllerProvider(widget.location)),
        people = ref.watch(profilesProvider);
    ref.watch(displayPreferencesProvider);
    if (!people.hasValue) return EntryPage(children: [Text(t.loadingRecords)]);
    if (!people.requireValue.any((person) => person.id == personId)) {
      return EntryPage(children: [Text(t.profileUnavailable)]);
    }
    if (lower == null) {
      final display = DisplayTime(),
          today = display.instant(DateTime.now().toUtc(), shownZone).civilDate;
      resetRange(
        DateTime.tryParse(seed['from'] ?? '')?.toUtc() ??
            display.dayBounds(today.addDays(-29), shownZone).start,
        DateTime.tryParse(seed['before'] ?? '')?.toUtc() ??
            display.dayBounds(today, shownZone).endExclusive,
        shownZone,
      );
      granularity =
          ChartBucketSize.values
              .where((value) => value.name == seed['bucket'])
              .firstOrNull ??
          ChartBucketSize.day;
      restoreSeedSeries();
      table = seed['mode'] == 'table';
      tablePage = math.max(0, int.tryParse(seed['page'] ?? '') ?? 0);
      final restoredBucket = int.tryParse(seed['selected'] ?? '');
      selectedBucket = restoredBucket != null && restoredBucket >= 0
          ? restoredBucket
          : null;
      sourcesOpen = seed['sources'] == 'true';
      sourcesStatus = seed['sourcesStatus'] == 'voided'
          ? TimelineStatus.voided
          : TimelineStatus.recorded;
      try {
        if (seed['cursor'] != null) {
          restoredSourceCursor = ChartDrilldownCursor.decode(seed['cursor']!);
          restoredSourceCursors = [null, restoredSourceCursor];
          if (seed['cursors'] case final encoded?) {
            final chain = jsonDecode(encoded) as List;
            if (chain.isNotEmpty &&
                chain.length <= 400 &&
                chain.first == null &&
                chain.last == seed['cursor']) {
              restoredSourceCursors = chain
                  .map(
                    (value) => value == null
                        ? null
                        : ChartDrilldownCursor.decode(value as String),
                  )
                  .toList();
            }
          }
        }
      } catch (_) {
        restoredSourceCursor = null;
        restoredSourceCursors = [null];
      }
    }
    if (zone != shownZone) {
      zone = shownZone;
      configured = null;
    }
    ChartQuery? query;
    Object? viewportError;
    try {
      query = ChartQuery(
        personId: personId,
        viewport: ChartViewport(
          fromInstant: lower!,
          beforeInstant: upper!,
          displayZone: shownZone,
          bucketSize: granularity,
        ),
      );
    } catch (failure) {
      viewportError = failure;
    }
    if (query != null &&
        (configured != query.identity || state.query == null)) {
      configured = query.identity;
      final next = query;
      scheduleMicrotask(() => controller.configure(next));
    }
    final invalidZone =
        viewportError is ChartRangeException &&
        viewportError.code == 'invalid_zone';
    final visible = ModalRoute.of(context)?.isCurrent != false;
    scheduleMicrotask(() => controller.visible(visible));
    final model = query?.identity == state.model?.query.identity
        ? state.model
        : null;
    final choices = _seriesChoices(model, state.batch);
    final _SeriesChoice? choice;
    if (seriesKey case final selected?) {
      // The exact selection wins. A missing series stays selected with no
      // points; its sources remain inspectable. Never substitute another
      // substance just because the current range has no rows for this one.
      final matched = choices
          .where((entry) => entry.key.identity == selected.identity)
          .firstOrNull;
      if (matched != null) seriesLabel = matched.label;
      choice =
          matched ??
          _SeriesChoice(selected, seriesLabel ?? selected.subject.id);
    } else {
      final linked = seed['item'] == null
          ? null
          : choices
                .where((entry) => entry.key.subject.id == seed['item'])
                .firstOrNull;
      if (linked != null) {
        // A History item link is an explicit choice. Remember the resolved
        // unit so a later range keeps the same series.
        seriesKey = linked.key;
        seriesLabel = linked.label;
      }
      choice = linked ?? choices.firstOrNull;
    }
    final series = choice == null ? null : model?.seriesFor(choice.key);
    final contextRequest = model == null || choice == null
        ? null
        : ChartContextRequest(
            ChartQuery(
              personId: personId,
              viewport: model.viewport,
              focus: choice.key,
            ),
            model.token.generation,
          );
    final contextual = contextRequest == null
        ? null
        : ref.watch(chartContextProvider(contextRequest));
    ChartAnnotationSet? annotations;
    try {
      if (model != null && contextual?.value != null) {
        annotations = ChartAnnotationSet.bounded(
          viewport: model.viewport,
          personId: personId,
          annotations: contextual!.value!.annotations,
        );
      }
    } catch (_) {
      /* A boundary without a usable saved zone is never invented. */
    }
    final unknown = model == null || choice == null || state.batch == null
        ? <int, int>{}
        : chartUnknownCounts(state.batch!, choice.key, model.viewport);
    final combinedBuckets =
        model == null || choice == null || state.batch == null
        ? const <int>{}
        : _combinedSourceBuckets(state.batch!, choice.key, model.viewport);
    final visibleTablePage = model == null
        ? 0
        : math.min(tablePage, (model.viewport.bucketCount - 1) ~/ 20);
    final canNarrow = _zoomedRange(false) != null;
    final canWiden = _zoomedRange(true) != null;
    void selectBucket(int index) => setState(() {
      selectedBucket = index;
      sourcesOpen = true;
      restoredSourceCursor = null;
      restoredSourceCursors = [null];
    });
    return FocusScope(
      autofocus: true,
      child: EntryPage(
        onBack: () => context.canPop()
            ? context.pop()
            : context.go(seed['return'] ?? '/history?scope=$personId'),
        children: [
          Heading(t.chartsTitle),
          Text(t.profileOwner(ownerLabel(ref, t, personId))),
          Text(
            t.shownInZone(
              model?.viewport.buckets.first.zoneId ??
                  DisplayTime().instant(lower!, shownZone).zoneId,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MergeSemantics(
                child: Semantics(
                  expanded: filters,
                  child: VitalButton.secondary(
                    onPressed: () => setState(() => filters = !filters),
                    child: Text(t.chartRange),
                  ),
                ),
              ),
              VitalButton.secondary(
                onPressed: () => move(-1),
                child: Text(t.chartPrevious),
              ),
              VitalButton.secondary(
                onPressed: () => move(1),
                child: Text(t.chartNext),
              ),
              VitalButton.secondary(
                onPressed: canNarrow ? () => zoom(false) : null,
                child: Text(t.chartZoomIn),
              ),
              VitalButton.secondary(
                onPressed: canWiden ? () => zoom(true) : null,
                child: Text(t.chartZoomOut),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t.chartRangeSummary(
              displayStamp(context, ref, lower!),
              displayStamp(context, ref, upper!),
            ),
          ),
          if (filters) ...[
            Focus(
              focusNode: rangeFocus,
              child: LabelledInput(
                label: t.chartFrom,
                controller: from,
                helper: t.historyDateHelp,
              ),
            ),
            LabelledInput(
              label: t.chartBefore,
              controller: before,
              helper: t.historyDateHelp,
            ),
            if (error != null) Semantics(liveRegion: true, child: Text(error!)),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: VitalButton(onPressed: apply, child: Text(t.chartApply)),
            ),
          ],
          const SizedBox(height: 16),
          VitalSegments<ChartBucketSize>(
            values: ChartBucketSize.values,
            selected: granularity,
            label: (value) => switch (value) {
              ChartBucketSize.day => t.chartDay,
              ChartBucketSize.week => t.chartWeek,
              ChartBucketSize.month => t.chartMonth,
            },
            onChanged: (value) => setState(() {
              granularity = value;
              selectedBucket = null;
              tablePage = 0;
              error = null;
            }),
          ),
          const SizedBox(height: 20),
          if (state.loading) Text(t.chartLoading),
          if (state.error != null || query == null) ...[
            Text(
              (viewportError ?? state.error) is ChartRangeException
                  ? ((viewportError ?? state.error) as ChartRangeException)
                                .code ==
                            'invalid_zone'
                        ? t.chartInvalidZone
                        : ((viewportError ?? state.error)
                                      as ChartRangeException)
                                  .code ==
                              'invalid_range'
                        ? t.chartRangeInvalid
                        : t.chartTooLarge
                  : t.chartLoadFailed,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: VitalButton.secondary(
                onPressed: query == null
                    ? () {
                        if (invalidZone) {
                          setState(() {
                            repairedZone = 'UTC';
                            configured = null;
                          });
                          return;
                        }
                        setState(() => filters = true);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) rangeFocus.requestFocus();
                        });
                      }
                    : controller.refresh,
                child: Text(
                  query == null
                      ? invalidZone
                            ? t.reset
                            : t.chartRange
                      : t.retry,
                ),
              ),
            ),
          ],
          if (model != null && choices.isEmpty) Text(t.chartEmpty),
          if (choice != null && model != null) ...[
            MergeSemantics(
              child: Semantics(
                expanded: seriesOpen,
                child: VitalButton.secondary(
                  multiline: true,
                  trailing: const Icon(LucideIcons.chevronDown),
                  onPressed: () => setState(() => seriesOpen = !seriesOpen),
                  child: Text(
                    t.chartSeriesLabel(choice.label, choice.key.unit),
                  ),
                ),
              ),
            ),
            if (seriesOpen) ...[
              const SizedBox(height: 12),
              for (final option in choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    selected: choice.key == option.key,
                    child: VitalButton.secondary(
                      multiline: true,
                      onPressed: () => setState(() {
                        seriesKey = option.key;
                        seriesLabel = option.label;
                        seriesOpen = false;
                        selectedBucket = null;
                        sourcesOpen = false;
                        restoredSourceCursor = null;
                        restoredSourceCursors = [null];
                      }),
                      child: Text(
                        t.chartSeriesLabel(option.label, option.key.unit),
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (series != null)
              VitalSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(totalHeading(t, series.total)),
                    Text(
                      totalAmount(t, series),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _sourceCountLabel(
                        t,
                        choice.key,
                        series.total.knownContributions +
                            series.total.unknownContributions,
                      ),
                    ),
                    if (combinedBuckets.isNotEmpty)
                      Text(t.chartCombinedCountHelp),
                    if (series.total.hasUnknownContributions)
                      Text(t.chartIncomplete),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            VitalSegments<bool>(
              values: const [false, true],
              selected: table,
              label: (value) => value ? t.chartTable : t.chartPlot,
              onChanged: (value) => setState(() => table = value),
            ),
            const SizedBox(height: 16),
            if (!table && series != null)
              ChartPlot(
                series: series,
                summary: [
                  t.chartCanvasSummary(choice.label, choice.key.unit),
                  t.profileOwner(ownerLabel(ref, t, personId)),
                  t.chartRangeSummary(
                    displayStamp(context, ref, lower!),
                    displayStamp(context, ref, upper!),
                  ),
                  totalHeading(t, series.total),
                  totalAmount(t, series),
                  _sourceCountLabel(
                    t,
                    choice.key,
                    series.total.knownContributions +
                        series.total.unknownContributions,
                  ),
                  if (combinedBuckets.isNotEmpty) t.chartCombinedCountHelp,
                ].join('\n'),
                annotations: annotations?.visible ?? [],
                onBucket: selectBucket,
              )
            else if (!table)
              Text(t.chartEmpty),
            if (table) ...[
              Focus(focusNode: tableFocus, child: Text(t.chartTable)),
              for (
                var index = visibleTablePage * 20;
                index <
                    math.min(
                      model.viewport.bucketCount,
                      (visibleTablePage + 1) * 20,
                    );
                index++
              )
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: VitalSurface(
                    role: VitalSurfaceRole.section,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          bucketLabel(context, model.viewport.buckets[index]),
                        ),
                        if (series?.buckets
                                .where(
                                  (bucket) =>
                                      bucket.bounds.fromInstant ==
                                      model.viewport.buckets[index].fromInstant,
                                )
                                .firstOrNull
                            case final bucket?) ...[
                          if ((unknown[index] ?? 0) > 0)
                            Text(t.chartKnownTotal),
                          Text(
                            t.chartAmount(
                              chartExactAmount(bucket.amount),
                              choice.key.unit,
                            ),
                          ),
                          Text(
                            _sourceCountLabel(
                              t,
                              choice.key,
                              bucket.contributionCount + (unknown[index] ?? 0),
                            ),
                          ),
                          if (combinedBuckets.contains(index))
                            Text(t.chartCombinedCountHelp),
                        ] else
                          Text(
                            (unknown[index] ?? 0) > 0
                                ? t.chartUnknown
                                : t.chartGap,
                          ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Semantics(
                            label: bucketSourceLabel(
                              context,
                              t,
                              choice.label,
                              choice.key.unit,
                              model.viewport.buckets[index],
                            ),
                            child: VitalButton.secondary(
                              onPressed: () => selectBucket(index),
                              child: ExcludeSemantics(child: Text(t.view)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (visibleTablePage > 0)
                    VitalButton.secondary(
                      onPressed: () => changeTablePage(visibleTablePage - 1),
                      child: Text(t.previous),
                    ),
                  if ((visibleTablePage + 1) * 20 < model.viewport.bucketCount)
                    VitalButton.secondary(
                      onPressed: () => changeTablePage(visibleTablePage + 1),
                      child: Text(t.next),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            VitalSection(
              title: Text(t.chartSources),
              action: MergeSemantics(
                child: Semantics(
                  expanded: sourcesOpen,
                  label: t.chartViewRangeSources(
                    choice.label,
                    choice.key.unit,
                    t.chartRangeSummary(
                      displayStamp(context, ref, lower!),
                      displayStamp(context, ref, upper!),
                    ),
                  ),
                  child: VitalButton.secondary(
                    onPressed: () => setState(() {
                      selectedBucket = null;
                      sourcesOpen = !sourcesOpen;
                      restoredSourceCursor = null;
                      restoredSourceCursors = [null];
                    }),
                    child: ExcludeSemantics(child: Text(t.view)),
                  ),
                ),
              ),
              children: [
                if (sourcesOpen) ...[
                  VitalSegments<TimelineStatus>(
                    key: const ValueKey('chart-source-status'),
                    values: const [
                      TimelineStatus.recorded,
                      TimelineStatus.voided,
                    ],
                    selected: sourcesStatus,
                    label: (value) => value == TimelineStatus.voided
                        ? t.statusVoided
                        : t.statusRecorded,
                    onChanged: (value) {
                      if (value == sourcesStatus) return;
                      setState(() {
                        sourcesStatus = value;
                        restoredSourceCursor = null;
                        restoredSourceCursors = [null];
                      });
                    },
                  ),
                  if (sourcesStatus == TimelineStatus.voided)
                    Text(t.chartVoidedSourcesHelp),
                  ChartSourcePanel(
                    key: ValueKey(
                      '${choice.key.identity}:$selectedBucket:${model.token.datasetGeneration}',
                    ),
                    request: ChartDrilldownRequest(
                      series: choice.key,
                      fromInstant:
                          selectedBucket != null &&
                              selectedBucket! < model.viewport.bucketCount
                          ? model.viewport.buckets[selectedBucket!].fromInstant
                          : lower!,
                      beforeInstant:
                          selectedBucket != null &&
                              selectedBucket! < model.viewport.bucketCount
                          ? model
                                .viewport
                                .buckets[selectedBucket!]
                                .beforeExclusive
                          : upper!,
                      displayZone: shownZone,
                      status: sourcesStatus,
                    ),
                    initialCursors: restoredSourceCursors,
                    onCursorsChanged: (chain) {
                      restoredSourceCursors = chain;
                      restoredSourceCursor = chain.last;
                    },
                    revision: model.token.generation,
                    location: (cursor) =>
                        returnLocation(choice!.key, cursor: cursor),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (contextual != null &&
                (contextual.hasError ||
                    contextual.value?.complete == false ||
                    annotations == null && contextual.hasValue))
              Text(t.chartContextUnavailable),
            if (annotations != null && !annotations.isEmpty) ...[
              Heading(t.chartAnnotations),
              for (final annotation in annotations.visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(annotationLabel(t, annotation.kind)),
                      if (annotation.label != null) Text(annotation.label!),
                      Text(
                        annotation.at.isDateOnly
                            ? t.historyDateZone(
                                MaterialLocalizations.of(context)
                                    .formatMediumDate(
                                      annotation.at.civilDate!.calendarValue,
                                    ),
                                annotation.at.zoneId!,
                              )
                            : displayStamp(
                                context,
                                ref,
                                annotation.at.instant!,
                                includeSeconds: true,
                              ),
                      ),
                    ],
                  ),
                ),
              if (contextual?.value?.complete == true &&
                  annotations.hiddenCount > 0)
                Text(t.chartAnnotationOverflow(annotations.hiddenCount)),
            ],
          ],
        ],
      ),
    );
  }

  void changeTablePage(int page) {
    setState(() => tablePage = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tableFocus.requestFocus();
    });
  }

  void apply() {
    try {
      final a = CivilDate.parse(from.text.trim()),
          b = CivilDate.parse(before.text.trim());
      final display = DisplayTime();
      final start = display.dayBounds(a, zone!).start,
          end = display.dayBounds(b, zone!).start;
      if (!end.isAfter(start)) throw const FormatException();
      setState(() {
        resetRange(start, end, zone!);
        error = null;
      });
    } catch (_) {
      setState(() => error = AppLocalizations.of(context).chartRangeInvalid);
    }
  }

  void move(int direction) {
    final duration = upper!.difference(lower!);
    final delta = Duration(microseconds: duration.inMicroseconds * direction);
    final a = lower!.add(delta), b = upper!.add(delta);
    if (a.year < 1902 || b.year > 2037) return;
    setState(() {
      resetRange(a, b, zone!);
      error = null;
    });
  }

  /// The next zoomed range, or null when zooming this way would not change the
  /// exact bounds. A null result disables the command instead of rebuilding the
  /// same range and clearing the chosen bucket or open sources for no reason.
  ({DateTime from, DateTime before})? _zoomedRange(bool widen) {
    final length = upper!.difference(lower!).inMicroseconds;
    final next = widen
        ? length * 2
        : math.max(const Duration(days: 1).inMicroseconds, length ~/ 2);
    if (next == length || next <= 0) return null;
    if (next > const Duration(days: 3650).inMicroseconds) return null;
    final middle = lower!.add(Duration(microseconds: length ~/ 2));
    final a = middle.subtract(Duration(microseconds: next ~/ 2)),
        b = middle.add(Duration(microseconds: next - next ~/ 2));
    if (a.year < 1902 || b.year > 2037) return null;
    return (from: a, before: b);
  }

  void zoom(bool widen) {
    final range = _zoomedRange(widen);
    if (range == null) return;
    setState(() {
      resetRange(range.from, range.before, zone!);
      error = null;
    });
  }
}

class _SeriesChoice {
  const _SeriesChoice(this.key, this.label);
  final ChartSeriesKey key;
  final String label;
}

List<_SeriesChoice> _seriesChoices(
  ChartModel? model,
  ChartObservationBatch? batch,
) {
  final choices = <String, _SeriesChoice>{
    for (final series in model?.series ?? <ChartSeriesWindow>[])
      series.key.identity: _SeriesChoice(
        series.key,
        series.label ?? series.key.subject.id,
      ),
  };
  for (final observation in batch?.observations ?? <ChartObservation>[]) {
    final item = ChartSeriesKey(
      personId: observation.personId,
      subject: ChartSubject.item(observation.itemId),
      unit: observation.unit,
    );
    choices.putIfAbsent(
      item.identity,
      () => _SeriesChoice(item, observation.itemName),
    );
    for (final component
        in observation.product?.label.components ?? <ProductComponent>[]) {
      final key = ChartSeriesKey(
        personId: observation.personId,
        subject: ChartSubject.ingredient(component.ingredientId),
        unit: component.massUnit,
      );
      choices.putIfAbsent(
        key.identity,
        () => _SeriesChoice(key, component.name),
      );
    }
  }
  return choices.values.toList()..sort((a, b) => a.key.compareTo(b.key));
}

/// Names the exact counted unit: one recorded dose for an item series, or one
/// ingredient amount from a recorded product. A combined source card can hold
/// several of either, so it is never called one administration here.
String _sourceCountLabel(AppLocalizations t, ChartSeriesKey key, int count) =>
    key.subject.kind == ChartSubjectKind.item
    ? t.chartDoseCount(count)
    : t.chartIngredientCount(count);

/// Buckets whose current contributions include a combined record.
///
/// Used only to explain why one source card can account for more than one
/// counted amount. Voided revisions never contribute.
Set<int> _combinedSourceBuckets(
  ChartObservationBatch batch,
  ChartSeriesKey key,
  ChartViewport viewport,
) {
  final buckets = <int>{};
  for (final observation in batch.observations) {
    if (observation.isVoided ||
        observation.source.combinedActionId == null ||
        !_observationContributesTo(observation, key)) {
      continue;
    }
    final index = viewport.indexOf(observation.occurredAt);
    if (index >= 0) buckets.add(index);
  }
  return buckets;
}

/// Mirrors the model's contribution identity, including the saved-label unit
/// rule for product ingredients.
bool _observationContributesTo(
  ChartObservation observation,
  ChartSeriesKey key,
) {
  if (key.subject.kind == ChartSubjectKind.item) {
    return observation.itemId == key.subject.id && observation.unit == key.unit;
  }
  final product = observation.product;
  if (product == null) return false;
  for (final componentAmount in product.components) {
    final component = componentAmount.component;
    if (component.ingredientId != key.subject.id) continue;
    final unit = componentAmount.amount == null ? component.massUnit : 'mg';
    if (unit == key.unit) return true;
  }
  return false;
}

String bucketLabel(BuildContext context, ChartBucketBounds bucket) {
  final locale = MaterialLocalizations.of(context),
      t = AppLocalizations.of(context);
  final start = locale.formatMediumDate(bucket.civilStart.calendarValue),
      end = locale.formatMediumDate(bucket.civilEndInclusive.calendarValue);
  return start == end ? start : t.chartDateRange(start, end);
}

/// Exact accessible name for one bucket's one-word View command.
///
/// The visible table label omits the year, so the accessible name uses the full
/// localised civil dates and the bucket's actual display zone. It deliberately
/// says a civil period, not an invented exact source time.
String bucketSourceLabel(
  BuildContext context,
  AppLocalizations t,
  String series,
  String unit,
  ChartBucketBounds bucket,
) {
  final locale = MaterialLocalizations.of(context);
  final start = locale.formatFullDate(bucket.civilStart.calendarValue),
      end = locale.formatFullDate(bucket.civilEndInclusive.calendarValue);
  return t.chartViewBucketSources(
    series,
    unit,
    start == end ? start : t.chartDateRange(start, end),
    bucket.zoneId,
  );
}

String annotationLabel(AppLocalizations t, ChartAnnotationKind kind) =>
    switch (kind) {
      ChartAnnotationKind.eventStart => t.chartEventStart,
      ChartAnnotationKind.eventEnd => t.chartEventEnd,
      ChartAnnotationKind.planChanged => t.chartPlanChanged,
      ChartAnnotationKind.pauseStart => t.chartPauseStart,
      ChartAnnotationKind.pauseEnd => t.chartPauseEnd,
      ChartAnnotationKind.phaseStart => t.chartPhaseStart,
      ChartAnnotationKind.phaseEnd => t.chartPhaseEnd,
      ChartAnnotationKind.planEnd => t.chartPlanEnd,
    };

class ChartSourcePanel extends ConsumerStatefulWidget {
  const ChartSourcePanel({
    super.key,
    required this.request,
    required this.location,
    this.initialCursors = const [null],
    this.revision = 0,
    required this.onCursorsChanged,
  });
  final ChartDrilldownRequest request;
  final String Function(ChartDrilldownCursor?) location;
  final List<ChartDrilldownCursor?> initialCursors;
  final int revision;
  final ValueChanged<List<ChartDrilldownCursor?>> onCursorsChanged;
  @override
  ConsumerState<ChartSourcePanel> createState() => _ChartSourcePanelState();
}

class _ChartSourcePanelState extends ConsumerState<ChartSourcePanel> {
  late final cursors = _initialCursors();
  late int index = cursors.length - 1;
  final pageFocus = FocusNode(
    debugLabel: 'chart source page',
    skipTraversal: true,
  );
  @override
  void dispose() {
    pageFocus.dispose();
    super.dispose();
  }

  /// A restored chain belongs to one exact request. A cursor from another
  /// status, range or subject is discarded instead of showing a stale page.
  List<ChartDrilldownCursor?> _initialCursors() {
    final chain = widget.initialCursors;
    if (chain.isEmpty ||
        chain.any(
          (cursor) =>
              cursor != null &&
              cursor.requestIdentity != widget.request.identity,
        )) {
      return [null];
    }
    return List.of(chain);
  }

  void pageChanged() {
    widget.onCursorsChanged(cursors.take(index + 1).toList());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) pageFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(ChartSourcePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.identity != widget.request.identity) {
      cursors
        ..clear()
        ..addAll(_initialCursors());
      index = cursors.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        request = ChartPageRequest(
          widget.request,
          cursors[index],
          revision: widget.revision,
        );
    final result = ref.watch(chartSourcePageProvider(request));
    final formatter = displayFormatter(
      context,
      ref.watch(displayPreferencesProvider).timeFormat,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(focusNode: pageFocus, child: Text(t.chartFrom)),
        Text(
          displayStamp(
            context,
            ref,
            widget.request.fromInstant,
            zoneId: widget.request.displayZone,
            includeSeconds: true,
          ),
        ),
        Text(t.chartBefore),
        Text(
          displayStamp(
            context,
            ref,
            widget.request.beforeInstant,
            zoneId: widget.request.displayZone,
            includeSeconds: true,
          ),
        ),
        if (result.isLoading) Text(t.loadingRecords),
        if (result.hasError) ...[
          Text(t.historyLoadFailed),
          VitalButton.secondary(
            onPressed: () => setState(() {
              cursors.clear();
              cursors.add(null);
              index = 0;
              pageChanged();
              ref.invalidate(chartSourcePageProvider);
            }),
            child: Text(t.reset),
          ),
        ],
        if (result.value case final page?) ...[
          if (page.entries.isEmpty)
            Text(switch (widget.request.status) {
              TimelineStatus.voided => t.chartNoVoidedSources,
              TimelineStatus.recorded => t.chartNoRecordedSources,
              _ => t.historyNoEntries,
            }),
          for (final entry in page.entries)
            HistoryEntryCard(
              entry: entry,
              formatter: formatter,
              zone: widget.request.displayZone,
              onInspect: () => context.push(
                Uri(
                  path:
                      '/history-source/${entry.id.kind.name}/${entry.id.value}',
                  queryParameters: {
                    'person': entry.personId,
                    'return': widget.location(cursors[index]),
                  },
                ).toString(),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (index > 0)
                VitalButton.secondary(
                  onPressed: () {
                    setState(() => index--);
                    pageChanged();
                  },
                  child: Text(t.previous),
                ),
              if (page.next != null)
                VitalButton.secondary(
                  onPressed: () => setState(() {
                    if (cursors.length > index + 1) {
                      cursors.removeRange(index + 1, cursors.length);
                    }
                    cursors.add(page.next);
                    index++;
                    pageChanged();
                  }),
                  child: Text(t.next),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String totalHeading(AppLocalizations t, ChartSeriesTotal total) =>
    total.knownContributions == 0 && total.hasUnknownContributions
    ? t.chartUnknown
    : total.complete
    ? t.chartTotal
    : t.chartKnownTotal;
String totalAmount(AppLocalizations t, ChartSeriesWindow series) =>
    series.total.knownContributions == 0 && series.total.hasUnknownContributions
    ? t.chartUnknown
    : t.chartAmount(
        chartExactAmount(series.total.exactTotal ?? series.total.knownSubtotal),
        series.key.unit,
      );
