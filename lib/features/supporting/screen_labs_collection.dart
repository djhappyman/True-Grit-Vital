import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/display_preferences.dart';
import '../../app/settings_toggle_row.dart';
import '../../app/supporting.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart';
import 'screen_labs_latest.dart';
import 'screen_labs_widgets.dart';
import 'supporting_widgets.dart';

/// Canonical `/supporting` collection, rebuilt around the saved labs reference.
/// It reuses the existing query, paging, filters, forms, detail, trends, files
/// and reports. No example value is written or shown.
class ScreenLabsCollectionPage extends ConsumerStatefulWidget {
  const ScreenLabsCollectionPage({super.key, required this.location});
  final String location;
  @override
  ConsumerState<ScreenLabsCollectionPage> createState() =>
      _ScreenLabsCollectionPageState();
}

class _ScreenLabsCollectionPageState
    extends ConsumerState<ScreenLabsCollectionPage> {
  static const _initialLatestCards = 4;

  late final seed = Uri.parse(widget.location).queryParameters;
  String get person => meId;

  /// The latest section reads a bounded marker page. Loading another page
  /// moves through stable-size requests without rereading a growing prefix.
  int latestMarkerOffset = 0;

  /// Null means all saved records. The form route below follows the choice.
  late SupportingRecordKind? kind = switch (seed['kind']) {
    'observation' => SupportingRecordKind.observation,
    'labPanel' => SupportingRecordKind.labPanel,
    _ => null,
  };
  late SupportingDateBasis basis =
      SupportingDateBasis.values
          .where((value) => value.name == seed['basis'])
          .firstOrNull ??
      SupportingDateBasis.collection;
  bool filters = false, latestExpanded = false;
  late bool unknown = seed['unknown'] != 'false',
      voided = seed['voided'] == 'true';
  late final from = TextEditingController(text: seed['from'] ?? ''),
      before = TextEditingController(text: seed['before'] ?? '');
  late CivilDate? appliedFrom = _date(seed['from']),
      appliedBefore = _date(seed['before']);
  CivilDate? _date(String? value) {
    try {
      return value == null ? null : CivilDate.parse(value);
    } catch (_) {
      return null;
    }
  }

  String viewLocation() => Uri(
    path: '/supporting',
    queryParameters: {
      'person': person,
      if (seed['item'] != null) 'item': seed['item']!,
      if (seed['event'] != null) 'event': seed['event']!,
      if (kind != null) 'kind': kind!.name,
      'basis': basis.name,
      'unknown': unknown.toString(),
      'voided': voided.toString(),
      if (appliedFrom != null) 'from': appliedFrom.toString(),
      if (appliedBefore != null) 'before': appliedBefore.toString(),
    },
  ).toString();

  String? error;
  final cursors = <SupportingCursor?>[null];

  @override
  void dispose() {
    from.dispose();
    before.dispose();
    super.dispose();
  }

  void reset() {
    cursors
      ..clear()
      ..add(null);
    latestMarkerOffset = 0;
    latestExpanded = false;
  }

  bool get _filtered =>
      kind != null ||
      basis != SupportingDateBasis.collection ||
      appliedFrom != null ||
      appliedBefore != null ||
      !unknown ||
      voided;

  void clearFilters() => setState(() {
    kind = null;
    basis = SupportingDateBasis.collection;
    unknown = true;
    voided = false;
    appliedFrom = null;
    appliedBefore = null;
    from.clear();
    before.clear();
    filters = false;
    error = null;
    reset();
  });

  String _rangeSummary(AppLocalizations t) {
    if (appliedFrom == null && appliedBefore == null) {
      return t.supportingAllDates;
    }
    if (appliedBefore == null) {
      return t.screenLabsRangeFrom(appliedFrom.toString());
    }
    if (appliedFrom == null) {
      return t.screenLabsRangeBefore(appliedBefore.toString());
    }
    return t.chartRangeSummary(
      appliedFrom.toString(),
      appliedBefore.toString(),
    );
  }

  void applyFilters(AppLocalizations t) {
    try {
      final start = from.text.isEmpty ? null : CivilDate.parse(from.text),
          end = before.text.isEmpty ? null : CivilDate.parse(before.text);
      if (start != null && end != null && end.compareTo(start) <= 0) {
        throw const FormatException();
      }
      setState(() {
        appliedFrom = start;
        appliedBefore = end;
        error = null;
        reset();
      });
    } catch (_) {
      setState(() => error = t.supportingFilterInvalid);
    }
  }

  String _addRoute() => Uri(
    path:
        '/supporting/$person/${kind == SupportingRecordKind.observation ? 'add-observation' : 'add-panel'}',
    queryParameters: {
      'return': viewLocation(),
      if (seed['item'] != null) 'item': seed['item']!,
      if (seed['event'] != null) 'event': seed['event']!,
    },
  ).toString();

  String _reportsRoute() => Uri(
    path: '/reports',
    queryParameters: {
      'return': viewLocation(),
      if (appliedFrom != null) 'from': appliedFrom.toString(),
      if (appliedBefore != null) 'before': appliedBefore.toString(),
    },
  ).toString();

  @override
  Widget build(BuildContext context) {
    if (ref.watch(appLockProvider.select((state) => state.locked))) {
      return EntryPage(
        children: [Text(AppLocalizations.of(context).supportingLocked)],
      );
    }
    final t = AppLocalizations.of(context),
        zone = ref.watch(displayZoneProvider);
    final query = SupportingQuery(
      personId: person,
      kind: kind,
      dateBasis: basis,
      fromDate: appliedFrom,
      beforeDate: appliedBefore,
      includeUnknownDates: unknown,
      includeVoided: voided,
      itemId: seed['item'],
      eventId: seed['event'],
      displayZone: zone,
    );
    final records = ref.watch(
      supportingPageProvider(
        SupportingPageRequest(query, cursor: cursors.last),
      ),
    );
    final page = records.value;
    final latestRequest = (
      personId: person,
      displayZone: zone,
      kind: kind,
      itemId: seed['item'],
      eventId: seed['event'],
      fromDate: appliedFrom,
      beforeDate: appliedBefore,
      markerLimit: screenLabsMarkerPageSize,
      markerOffset: latestMarkerOffset,
    );
    final latest = ref.watch(screenLabsLatestProvider(latestRequest));
    final latestValue = latest.isLoading || latest.hasError
        ? null
        : latest.value;
    final latestPending = latest.isLoading;
    final latestCount = latestValue?.values.length ?? 0;
    final empty =
        page != null &&
        page.entries.isEmpty &&
        latestCount == 0 &&
        latest.hasValue &&
        !latest.hasError &&
        !latestPending;
    return EntryPage(
      panelled: false,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(seed['return'] ?? '/today');
        }
      },
      children: [
        Heading(t.screenLabsHeading),
        Text(
          t.screenLabsSubtitle,
          style: StitchType.caption.copyWith(
            color: StitchColors(context).muted,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: StitchButton(
            primary: true,
            icon: LucideIcons.plus,
            onPressed: () => context.push(_addRoute()),
            child: Text(t.supportingAdd),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip(
              t.screenLabsAllRecords,
              selected: kind == null,
              onPressed: () => setState(() {
                kind = null;
                reset();
              }),
            ),
            _filterChip(
              t.supportingPanels,
              selected: kind == SupportingRecordKind.labPanel,
              onPressed: () => setState(() {
                kind = SupportingRecordKind.labPanel;
                reset();
              }),
            ),
            _filterChip(
              t.supportingObservations,
              selected: kind == SupportingRecordKind.observation,
              onPressed: () => setState(() {
                kind = SupportingRecordKind.observation;
                reset();
              }),
            ),
            VitalLocalOptions(
              label: t.supportingFilters,
              content: StitchSurface(
                inset: true,
                radius: VitalLayout.sectionRadius,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(t.supportingFilters, style: StitchType.name),
                    ),
                    const SizedBox(height: 12),
                    Text(t.supportingDateBasis, style: StitchType.label),
                    const SizedBox(height: 8),
                    VitalSegments<SupportingDateBasis>(
                      values: SupportingDateBasis.values,
                      selected: basis,
                      onChanged: (value) => setState(() {
                        basis = value;
                        reset();
                      }),
                      label: (value) => switch (value) {
                        SupportingDateBasis.collection =>
                          kind == SupportingRecordKind.observation
                              ? t.supportingMeasured
                              : t.supportingCollection,
                        SupportingDateBasis.report => t.supportingReportChoice,
                        SupportingDateBasis.entry => t.supportingEntryChoice,
                      },
                    ),
                    const SizedBox(height: 12),
                    VitalDateRangeField(
                      start: from,
                      end: before,
                      startLabel: t.supportingFrom,
                      endLabel: t.supportingBefore,
                      endExclusive: true,
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 8),
                    Text(
                      _rangeSummary(t),
                      style: StitchType.caption.copyWith(
                        color: StitchColors(context).muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SettingsToggleRow(
                      label: t.supportingIncludeUnknown,
                      description: t.supportingIncludeUnknownHint,
                      value: unknown,
                      reduceMotion: MediaQuery.disableAnimationsOf(context),
                      onChanged: (value) => setState(() {
                        unknown = value;
                        reset();
                      }),
                    ),
                    SettingsToggleRow(
                      label: t.supportingIncludeVoided,
                      description: t.supportingIncludeVoidedHint,
                      value: voided,
                      reduceMotion: MediaQuery.disableAnimationsOf(context),
                      onChanged: (value) => setState(() {
                        voided = value;
                        reset();
                      }),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: StitchButton(
                        primary: true,
                        onPressed: () => applyFilters(t),
                        child: Text(t.supportingApply),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_filtered) ...[
          const SizedBox(height: 12),
          ScreenLabsFilterBadges(
            basis: basis,
            from: appliedFrom,
            before: appliedBefore,
            includeUnknown: unknown,
            includeVoided: voided,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: StitchType.body.copyWith(
                color: Theme.of(context).colorScheme.destructive,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (records.hasError)
          LoadFailure(
            message: t.supportingLoadFailure,
            onRetry: () {
              reset();
              ref.invalidate(supportingPageProvider);
              ref.invalidate(screenLabsLatestProvider(latestRequest));
              setState(() {});
            },
          )
        else if (page == null)
          Text(
            t.loadingRecords,
            style: StitchType.caption.copyWith(
              color: StitchColors(context).muted,
            ),
          )
        else if (empty)
          VitalEmptyState(
            title: _filtered
                ? t.screenLabsNoMatchTitle
                : t.screenLabsEmptyTitle,
            description: _filtered
                ? t.screenLabsNoMatchBody
                : t.screenLabsEmptyBody,
            icon: LucideIcons.flaskConical,
            action: _filtered
                ? StitchButton(
                    compact: true,
                    onPressed: clearFilters,
                    child: Text(t.clear),
                  )
                : null,
          )
        else ...[
          _latestSection(t, latest, latestRequest, latestValue),
          const SizedBox(height: 24),
          ScreenLabsSectionHeader(
            title: t.screenLabsRecordsEyebrow,
            trailing: Text(t.screenLabsRecordsCount(page.entries.length)),
          ),
          const SizedBox(height: 4),
          Text(
            t.screenLabsNewestFirst,
            style: StitchType.caption.copyWith(
              color: StitchColors(context).muted,
            ),
          ),
          const SizedBox(height: 12),
          if (page.entries.isEmpty)
            StitchSurface(
              inset: true,
              radius: VitalLayout.sectionRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      t.screenLabsNoMatchTitle,
                      style: StitchType.name,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.screenLabsNoMatchBody,
                    style: StitchType.caption.copyWith(
                      color: StitchColors(context).muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StitchButton(
                      compact: true,
                      onPressed: clearFilters,
                      child: Text(t.clear),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final entry in page.entries.indexed) ...[
              ScreenLabsRecordCard(
                record: entry.$2,
                person: person,
                returnLocation: viewLocation(),
                basis: basis,
                primary: entry.$1 == 0,
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StitchButton(
              compact: true,
              onPressed: () => context.push(_reportsRoute()),
              child: Text(t.reports),
            ),
          ),
          if (cursors.length > 1 || page.next != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StitchButton(
                  compact: true,
                  onPressed: cursors.length > 1
                      ? () => setState(() => cursors.removeLast())
                      : null,
                  child: Text(t.supportingPrevious),
                ),
                StitchButton(
                  compact: true,
                  onPressed: page.next == null
                      ? null
                      : () => setState(() => cursors.add(page.next)),
                  child: Text(t.supportingNext),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 24),
        const ScreenLabsPrivacyCard(),
      ],
    );
  }

  Widget _filterChip(
    String label, {
    required bool selected,
    required VoidCallback onPressed,
    IconData? icon,
  }) => MergeSemantics(
    child: Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: icon == null,
      child: StitchButton(
        primary: selected,
        compact: true,
        icon: icon,
        onPressed: onPressed,
        child: Text(label),
      ),
    ),
  );

  Widget _latestSection(
    AppLocalizations t,
    AsyncValue<ScreenLabsLatest> latest,
    ScreenLabsLatestRequest request,
    ScreenLabsLatest? latestValue,
  ) {
    final header = ScreenLabsSectionHeader(
      title: t.screenLabsLatestEyebrow,
      trailing: latestValue == null
          ? null
          : Text(
              latestValue.values.isEmpty
                  ? t.screenLabsLatestCount(0)
                  : latestValue.markerOffset > 0 || latestValue.hasMoreMarkers
                  ? t.featureLabsPageRange(
                      latestValue.values.isEmpty
                          ? 0
                          : latestValue.markerOffset + 1,
                      latestValue.markerOffset + latestValue.values.length,
                      latestValue.markerCount,
                    )
                  : t.screenLabsLatestCount(latestValue.values.length),
            ),
    );
    if (latest.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          LoadFailure(
            message: t.supportingLoadFailure,
            onRetry: () => ref.invalidate(screenLabsLatestProvider(request)),
          ),
        ],
      );
    }
    if (latestValue == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          Text(
            t.loadingRecords,
            style: StitchType.caption.copyWith(
              color: StitchColors(context).muted,
            ),
          ),
        ],
      );
    }
    if (latestValue.values.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          StitchSurface(
            inset: true,
            radius: VitalLayout.sectionRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    t.screenLabsNoLatestTitle,
                    style: StitchType.name,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  latestMarkerOffset > 0
                      ? t.featureLabsEmptyPage
                      : t.screenLabsNoLatestBody,
                  style: StitchType.caption.copyWith(
                    color: StitchColors(context).muted,
                  ),
                ),
                if (latestMarkerOffset > 0) ...[
                  const SizedBox(height: 12),
                  StitchButton(
                    onPressed: () => setState(() {
                      latestMarkerOffset =
                          (latestMarkerOffset - screenLabsMarkerPageSize).clamp(
                            0,
                            latestMarkerOffset,
                          );
                      latestExpanded = true;
                    }),
                    child: Text(t.previous),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }
    final visible = latestExpanded
        ? latestValue.values
        : latestValue.values.take(_initialLatestCards).toList();
    final groups = groupSupportingCategories(
      visible,
      (value) => value.result.category,
    );
    final showCategories = groups.any((group) => !group.isUnnamed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 8),
        Text(
          t.screenLabsLatestWindow(latestValue.recordCount),
          style: StitchType.caption.copyWith(
            color: StitchColors(context).muted,
          ),
        ),
        if (basis != SupportingDateBasis.collection)
          Text(
            t.screenLabsLatestDateScope,
            style: StitchType.caption.copyWith(
              color: StitchColors(context).muted,
            ),
          ),
        if (latestValue.values.any(
          (value) =>
              (value.sparkline?.hasPoints ?? false) ||
              value.previousResult != null,
        ))
          Text(
            t.featureLabsCoverage(
              screenLabsSparkSampleLimit,
              supportingLatestCandidateLimit,
            ),
            style: StitchType.caption.copyWith(
              color: StitchColors(context).muted,
            ),
          ),
        Text(
          t.screenLabsLatestExcluded,
          style: StitchType.caption.copyWith(
            color: StitchColors(context).muted,
          ),
        ),
        if (latestValue.linksTruncated)
          Text(
            t.featureLabsLinksPartial,
            style: StitchType.caption.copyWith(
              color: StitchColors(context).muted,
            ),
          ),
        const SizedBox(height: 12),
        for (final group in groups) ...[
          if (showCategories)
            SupportingCategoryHeading(
              label: group.isUnnamed ? t.screenLabsCategoryOther : group.label!,
            ),
          for (final value in group.values) ...[
            ScreenLabsLatestCard(
              value: value,
              person: person,
              returnLocation: viewLocation(),
            ),
            const SizedBox(height: 12),
          ],
        ],
        if (latestValue.values.length > _initialLatestCards ||
            latestValue.hasMoreMarkers ||
            latestMarkerOffset > 0)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (latestValue.values.length > _initialLatestCards)
                StitchButton(
                  quiet: true,
                  compact: true,
                  onPressed: () =>
                      setState(() => latestExpanded = !latestExpanded),
                  child: Text(latestExpanded ? t.screenLabsLess : t.more),
                ),
              if (latestMarkerOffset > 0)
                StitchButton(
                  quiet: true,
                  compact: true,
                  onPressed: () => setState(() {
                    latestMarkerOffset =
                        (latestMarkerOffset - screenLabsMarkerPageSize).clamp(
                          0,
                          latestMarkerOffset,
                        );
                    latestExpanded = true;
                  }),
                  child: Text(t.previous),
                ),
              if (latestValue.hasMoreMarkers)
                StitchButton(
                  quiet: true,
                  compact: true,
                  onPressed: () => setState(() {
                    latestMarkerOffset += screenLabsMarkerPageSize;
                    latestExpanded = true;
                  }),
                  child: Text(t.featureLabsLoad),
                ),
            ],
          ),
      ],
    );
  }
}
