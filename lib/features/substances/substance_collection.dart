import 'dart:async';

import 'package:flutter/services.dart' show TextInputAction;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/device_zone.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart' show LoadFailure;
import '../../ui/vital_ui.dart';
import '../catalogue/item_types.dart' show itemTypeProvider;
import '../../ui/stitch_ui.dart';
import 'stitch_substance_card.dart';

/// One page key of the bounded Substances list. The 51st row of a page only
/// reveals the next page; search, the type filter and the status filter run
/// over the whole stored collection at the store, not over a loaded subset.
/// [asOf] and [zone] make the plan-status snapshot explicit; both paginated
/// results and counts use the same values.
final class SubstancesPageQuery {
  const SubstancesPageQuery({
    required this.scope,
    required this.search,
    required this.typeId,
    required this.offset,
    this.status = SubstanceStatusFilter.all,
    this.asOf,
    this.zone,
  });
  final FeedScope scope;
  final String search;
  final String typeId;
  final int offset;
  final SubstanceStatusFilter status;

  /// A minute-rounded instant used for plan boundaries. Null keeps the older
  /// store-only path used by focused page tests.
  final DateTime? asOf;
  final String? zone;

  @override
  bool operator ==(Object other) =>
      other is SubstancesPageQuery &&
      other.scope == scope &&
      other.search == search &&
      other.typeId == typeId &&
      other.offset == offset &&
      other.status == status &&
      other.asOf == asOf &&
      other.zone == zone;

  @override
  int get hashCode =>
      Object.hash(scope, search, typeId, offset, status, asOf, zone);
}

final substancesPageProvider = StreamProvider.autoDispose
    .family<List<SubstanceItem>, SubstancesPageQuery>(retry: (_, _) => null, (
      ref,
      query,
    ) async* {
      final storeFuture = ref.watch(recordStoreProvider.future);
      final asOf = query.asOf;
      if (asOf == null) {
        final store = await storeFuture;
        yield* store.watchItems(
          scope: query.scope,
          search: query.search,
          typeId: query.typeId.isEmpty ? null : query.typeId,
          limit: 51,
          offset: query.offset,
        );
        return;
      }
      final snapshotFuture = ref.watch(
        substanceStatusSnapshotProvider((
          scope: query.scope,
          search: query.search,
          typeId: query.typeId,
          asOf: asOf,
          zone: query.zone,
        )).future,
      );
      final store = await storeFuture;
      final snapshot = await snapshotFuture;
      final ids = snapshot
          .itemIdsFor(query.status)
          .skip(query.offset)
          .take(51)
          .toList();
      yield* store.watchItemsByIds(ids);
    });

typedef SubstancesTypeQuery = ({FeedScope scope, String search});

/// Whole-collection status totals under one name, type and time snapshot.
/// A mixed-plan item can be counted in more than one status.
typedef SubstanceStatusQuery = ({
  FeedScope scope,
  String search,
  String typeId,
  DateTime asOf,
  String? zone,
});

final substanceStatusSnapshotProvider = StreamProvider.autoDispose
    .family<SubstanceStatusSnapshot, SubstanceStatusQuery>(
      retry: (_, _) => null,
      (ref, query) async* {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchSubstanceStatusSnapshot(
              scope: query.scope,
              search: query.search,
              typeId: query.typeId.isEmpty ? null : query.typeId,
              now: query.asOf,
              observedZone: query.zone,
            );
      },
    );

final substanceTypesProvider = StreamProvider.autoDispose
    .family<List<SubstanceTypeSummary>, SubstancesTypeQuery>(
      retry: (_, _) => null,
      (ref, query) async* {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchItemTypeCounts(scope: query.scope, search: query.search);
      },
    );

/// The Substances destination: a persistent labelled name search over the
/// full local collection, actual item-type filters with one-action clearing,
/// bounded paging and distinct empty, filtered-empty, loading and failure
/// states. The scope stays the single local user.
class SubstanceCollection extends ConsumerStatefulWidget {
  const SubstanceCollection({super.key, required this.scope});
  final FeedScope scope;
  @override
  ConsumerState<SubstanceCollection> createState() =>
      _SubstanceCollectionState();
}

class _SubstanceCollectionState extends ConsumerState<SubstanceCollection> {
  final _search = TextEditingController();
  String _typeId = '';
  SubstanceStatusFilter _status = SubstanceStatusFilter.all;
  // Fallback name while the selected type's live lookup loads. The separate
  // lookup keeps renames visible even when search-constrained counts omit it.
  String? _typeName;
  int _pages = 1;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    // Query changes reset paging; the field itself stays mounted while the
    // collection remains on the navigation stack, so its state survives
    // inspecting a detail view and returning.
    _search.addListener(() {
      if (mounted) {
        setState(() => _pages = 1);
      }
    });
    // Plan status changes at a pause resume, a plan end or a start instant.
    // A conservative minute refresh keeps the mounted list truthful without a
    // per-card timer. The result page and counts share the rounded instant.
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _search.clear();
      _typeId = '';
      _typeName = null;
      _status = SubstanceStatusFilter.all;
      _pages = 1;
    });
  }

  void _selectType(String typeId, String typeName) => setState(() {
    _typeId = typeId;
    _typeName = typeId.isEmpty ? null : typeName;
    _pages = 1;
  });

  void _selectStatus(SubstanceStatusFilter status) => setState(() {
    _status = status;
    _pages = 1;
  });

  void _retry() {
    ref.invalidate(substancesPageProvider);
    ref.invalidate(substanceTypesProvider);
    ref.invalidate(substanceStatusSnapshotProvider);
    setState(() => _pages = 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final search = _search.text.trim();
    final now = DateTime.now().toUtc();
    final asOf = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
    final statusQuery = (
      scope: widget.scope,
      search: search,
      typeId: _typeId,
      asOf: asOf,
      zone: zone,
    );
    final statusSnapshot = ref.watch(
      substanceStatusSnapshotProvider(statusQuery),
    );
    final pages = [
      for (var page = 0; page < _pages; page++)
        ref.watch(
          substancesPageProvider(
            SubstancesPageQuery(
              scope: widget.scope,
              search: search,
              typeId: _typeId,
              offset: page * 50,
              status: _status,
              asOf: asOf,
              zone: zone,
            ),
          ),
        ),
    ];
    final summaries = ref.watch(
      substanceTypesProvider((scope: widget.scope, search: search)),
    );
    final allTypes = search.isEmpty
        ? summaries
        : ref.watch(substanceTypesProvider((scope: widget.scope, search: '')));
    final total = allTypes.value?.fold<int>(
      0,
      (sum, entry) => sum + entry.count,
    );
    final personId = widget.scope.personId;
    final selectedType = _typeId.isEmpty || personId == null
        ? null
        : ref.watch(itemTypeProvider((personId: personId, typeId: _typeId)));
    final filtered =
        search.isNotEmpty ||
        _typeId.isNotEmpty ||
        _status != SubstanceStatusFilter.all;
    final counts = statusSnapshot.value?.counts;
    final countsKnown =
        statusSnapshot.hasValue &&
        !statusSnapshot.isLoading &&
        !statusSnapshot.hasError;
    // Search, the active type filter and the active status filter stay visible
    // while data fails, so a failure never removes the user's controls or
    // hides why results are absent; the retry sits with the result area below.
    final failed =
        pages.any((p) => p.hasError) ||
        summaries.hasError ||
        statusSnapshot.hasError;
    final rows = <SubstanceItem>[];
    final visited = <String>{};
    for (final page in pages) {
      if (!page.hasValue) continue;
      for (final item in page.requireValue.take(50)) {
        if (visited.add(item.id)) rows.add(item);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.substances, style: StitchType.title),
                const SizedBox(height: 3),
                if (total != null)
                  StitchBadge(t.stitchSubstanceCount(total), dot: true),
              ],
            ),
            SizedBox(
              width: 156,
              child: StitchButton(
                primary: true,
                icon: LucideIcons.plus,
                onPressed: () => context.push('/create'),
                child: Text(t.create),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: t.designSubstancesSearchLabel,
                child: TextField(
                  controller: _search,
                  placeholder: Text(t.stitchSearch, style: StitchType.body),
                  style: StitchType.body,
                  decoration: BoxDecoration(
                    color: StitchColors(context).inset,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  border: Border.all(color: Colors.transparent),
                  borderRadius: BorderRadius.circular(999),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  features: [
                    InputFeature.leading(
                      Icon(
                        LucideIcons.search,
                        size: 19,
                        color: StitchColors(context).muted,
                      ),
                    ),
                  ],
                  textInputAction: TextInputAction.search,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Semantics(
              label: t.stitchFilter,
              button: true,
              child: StitchButton(
                compact: true,
                onPressed: () =>
                    context.push('/types/${widget.scope.personId ?? meId}'),
                child: Icon(
                  LucideIcons.slidersHorizontal,
                  size: 20,
                  color: StitchColors(context).muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SubstanceTypeFilters(
          summaries: summaries.value ?? const [],
          selectedTypeId: _typeId,
          selectedTypeName: selectedType?.value?.name ?? _typeName,
          countsKnown:
              summaries.hasValue && !summaries.isLoading && !summaries.hasError,
          onSelected: _selectType,
        ),
        if ((counts?.all ?? 0) > 0 ||
            _status != SubstanceStatusFilter.all) ...[
          const SizedBox(height: 8),
          SubstanceStatusFilters(
            counts: counts,
            selected: _status,
            countsKnown: countsKnown,
            onSelected: _selectStatus,
          ),
          const SizedBox(height: 6),
          Text(
            t.featureStatusMixedHelp,
            style: StitchType.caption.copyWith(
              color: StitchColors(context).muted,
            ),
          ),
          if ((counts?.unresolved ?? 0) > 0) ...[
            const SizedBox(height: 3),
            Text(
              t.featureStatusUnresolvedHelp(counts!.unresolved),
              style: StitchType.caption.copyWith(
                color: StitchColors(context).amber,
              ),
            ),
          ],
        ],
        const SizedBox(height: 14),
        if (failed)
          LoadFailure(message: t.designSubstancesUnavailable, onRetry: _retry)
        else if (pages.every((p) => !p.hasValue))
          Text(t.loadingRecords)
        else if (rows.isEmpty && !filtered)
          VitalEmptyState(
            title: t.substances,
            description: t.substancesReady,
            icon: LucideIcons.pill,
            action: VitalButton(
              onPressed: () => context.push('/create'),
              child: Text(t.create),
            ),
          )
        else if (rows.isEmpty)
          VitalEmptyState(
            title: t.designSubstancesNoMatchesTitle,
            description: t.designSubstancesNoMatchesBody,
            icon: LucideIcons.search,
            action: VitalButton.secondary(
              onPressed: _clearFilters,
              child: Text(t.designSubstancesClear),
            ),
          )
        else ...[
          for (final item in rows)
            SubstanceIdentityCard(key: ValueKey(item.id), item: item),
          if ((pages.last.value?.length ?? 0) > 50)
            VitalButton.secondary(
              onPressed: () => setState(() => _pages++),
              child: Text(t.more),
            ),
          if (filtered) ...[
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: VitalButton.secondary(
                onPressed: _clearFilters,
                child: Text(t.designSubstancesClear),
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        StitchSurface(
          inset: true,
          child: Column(
            children: [
              const StitchIcon(
                LucideIcons.shieldCheck,
                size: 32,
                selected: true,
              ),
              const SizedBox(height: 6),
              Text(t.stitchStored, style: StitchType.small),
              const SizedBox(height: 4),
              Text(
                t.stitchLocalBody,
                textAlign: TextAlign.center,
                style: StitchType.caption.copyWith(
                  color: StitchColors(context).muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Actual item-type filters plus All. Values come from the stored types
/// present in the scoped collection under the current search, each with its
/// item count, so a pill never promises results it cannot show. The selected
/// type keeps its own pill when the current search hides all its items. Counts
/// appear only after the query completes; the parent supplies its live name,
/// with a cached fallback during loading. All always reverses the type filter.
class SubstanceTypeFilters extends StatelessWidget {
  const SubstanceTypeFilters({
    super.key,
    required this.summaries,
    required this.selectedTypeId,
    required this.selectedTypeName,
    required this.onSelected,
    this.countsKnown = true,
  });
  final List<SubstanceTypeSummary> summaries;
  final String selectedTypeId;
  final String? selectedTypeName;
  final bool countsKnown;
  final void Function(String typeId, String typeName) onSelected;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pills = [
      for (final summary in summaries)
        if (summary.typeId != null && summary.count > 0) summary,
    ];
    if (selectedTypeId.isNotEmpty &&
        selectedTypeName != null &&
        !pills.any((pill) => pill.typeId == selectedTypeId)) {
      pills.add(
        SubstanceTypeSummary(
          typeId: selectedTypeId,
          typeName: selectedTypeName!,
          count: 0,
        ),
      );
    }
    if (pills.isEmpty) return const SizedBox.shrink();
    final names = {for (final pill in pills) pill.typeId!: pill.typeName};
    final total = summaries.fold<int>(0, (sum, summary) => sum + summary.count);
    String label(String typeId) {
      final name = typeId.isEmpty
          ? t.designSubstancesAllFilter
          : names[typeId]!;
      if (!countsKnown) return name;
      final count = typeId.isEmpty
          ? total
          : pills.firstWhere((pill) => pill.typeId == typeId).count;
      return t.stitchFilterCount(name, count);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final typeId in ['', ...pills.map((pill) => pill.typeId!)])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Semantics(
                selected: selectedTypeId == typeId,
                child: StitchButton(
                  primary: selectedTypeId == typeId,
                  compact: true,
                  onPressed: () =>
                      onSelected(typeId, typeId.isEmpty ? '' : names[typeId]!),
                  child: Text(label(typeId), style: StitchType.small),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Whole-collection plan-status filters plus All statuses. Counts come from
/// the same name, type and instant snapshot as the results. Statuses can
/// overlap, so these pills are not a single mutually exclusive item state.
/// Unscheduled is never shown for an item whose plan could not be evaluated.
class SubstanceStatusFilters extends StatelessWidget {
  const SubstanceStatusFilters({
    super.key,
    required this.counts,
    required this.selected,
    required this.countsKnown,
    required this.onSelected,
  });
  final SubstanceStatusCounts? counts;
  final SubstanceStatusFilter selected;
  final bool countsKnown;
  final void Function(SubstanceStatusFilter status) onSelected;

  String _name(AppLocalizations t, SubstanceStatusFilter status) =>
      switch (status) {
        SubstanceStatusFilter.all => t.featureStatusAll,
        SubstanceStatusFilter.active => t.featureStatusActive,
        SubstanceStatusFilter.paused => t.featureStatusPaused,
        SubstanceStatusFilter.asNeeded => t.featureStatusAsNeeded,
        SubstanceStatusFilter.unscheduled => t.featureStatusUnscheduled,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: t.featureStatusFiltersLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final status in SubstanceStatusFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Semantics(
                  selected: selected == status,
                  child: StitchButton(
                    primary: selected == status,
                    compact: true,
                    onPressed: () => onSelected(status),
                    child: Text(
                      countsKnown && counts != null
                          ? t.stitchFilterCount(
                              _name(t, status),
                              counts!.count(status),
                            )
                          : _name(t, status),
                      style: StitchType.small,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact identity card. The whole identity row opens the substance's
/// unified overview. Recording stays directly available; schedule, stock,
/// combined logging and full history remain reachable from that overview.
class SubstanceIdentityCard extends StatelessWidget {
  const SubstanceIdentityCard({super.key, required this.item});
  final SubstanceItem item;

  @override
  Widget build(BuildContext context) => StitchSubstanceCard(item: item);
}
