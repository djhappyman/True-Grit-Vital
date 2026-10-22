import 'vial_preparation_editor.dart';
import '../substances/substance_detail_providers.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../app/settings_toggle_row.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';
import '../products/product_widgets.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key, required this.personId, this.itemId});
  final String personId;
  final String? itemId;
  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  final _search = TextEditingController();
  StockInventoryFilter _filter = StockInventoryFilter.all;
  int _pages = 1;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() => _pages = 1);
    });
    // Plan pauses, plan ends and the conditional run-out date change with the
    // clock. One conservative minute refresh keeps the whole page truthful.
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

  void _clearFilters() => setState(() {
    _search.clear();
    _filter = StockInventoryFilter.all;
    _pages = 1;
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final people = ref.watch(profilesProvider);
    final owner = people.value
        ?.where((p) => p.id == widget.personId)
        .firstOrNull;
    if (people.isLoading) return EntryPage(children: [Text(t.loadingRecords)]);
    if (people.hasError) {
      return EntryPage(
        children: [
          LoadFailure(onRetry: () => ref.invalidate(profilesProvider)),
        ],
      );
    }
    if (owner == null) return EntryPage(children: [Text(t.profileUnavailable)]);
    final archived = owner.isArchived;
    final search = _search.text.trim();
    final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
    final now = DateTime.now().toUtc();
    final asOf = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final query = (
      personId: owner.id,
      itemId: widget.itemId,
      search: search,
      filter: _filter,
      asOf: asOf,
      zone: zone,
    );
    final inventory = ref.watch(stockInventoryProvider(query));
    final filtered = search.isNotEmpty || _filter != StockInventoryFilter.all;
    final snapshot = inventory.isLoading || inventory.hasError
        ? null
        : inventory.value;
    final expiryFilter =
        _filter == StockInventoryFilter.expired ||
        _filter == StockInventoryFilter.today;
    final expiryUnavailable = snapshot != null && snapshot.expiryDay == null;
    final rows = snapshot?.containers ?? const <StoredStockContainer>[];
    final shown = rows.take(_pages * 50).toList();
    return EntryPage(
      panelled: false,
      children: [
        Heading(t.stock),
        _StockIntro(archived: archived),
        const SizedBox(height: 24),
        if (!archived && widget.itemId == null) ...[
          _StockAttention(personId: owner.id),
          const SizedBox(height: 24),
        ],
        if (!archived || rows.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: t.featureStockSearchLabel,
                  child: TextField(
                    controller: _search,
                    enabled: !archived,
                    placeholder: Text(
                      t.featureStockSearchHint,
                      style: StitchType.body,
                    ),
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
                  ),
                ),
              ),
              const SizedBox(width: 6),
              VitalLocalOptions(
                label: t.featureStockFilters,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t.featureStockFilters, style: VitalType.section),
                    const SizedBox(height: 12),
                    StockInventoryFilters(
                      counts: snapshot?.complete == true
                          ? snapshot!.counts
                          : null,
                      selected: _filter,
                      onSelected: (filter) => setState(() {
                        _filter = filter;
                        _pages = 1;
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(t.featureStockFilterOverlapHelp),
                    if (expiryUnavailable) ...[
                      const SizedBox(height: 8),
                      Text(
                        t.directExpiryUnavailableBody,
                        style: StitchType.caption.copyWith(
                          color: StitchColors(context).amber,
                        ),
                      ),
                    ],
                    if ((snapshot?.counts.unresolved ?? 0) > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        t.featureStockUnresolvedHelp(
                          snapshot!.counts.unresolved,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    VitalButton.secondary(
                      onPressed: _clearFilters,
                      child: Text(t.clear),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StockInventoryFilters(
            counts: snapshot?.complete == true ? snapshot!.counts : null,
            selected: _filter,
            onSelected: (filter) => setState(() {
              _filter = filter;
              _pages = 1;
            }),
          ),
          if (snapshot != null && !snapshot.complete) ...[
            const SizedBox(height: 6),
            Text(
              t.featureStockCountsIncomplete,
              style: StitchType.caption.copyWith(
                color: StitchColors(context).amber,
              ),
            ),
          ],
          if ((snapshot?.counts.unresolved ?? 0) > 0 &&
              snapshot?.complete == true) ...[
            const SizedBox(height: 6),
            Text(
              t.featureStockUnresolvedHelp(snapshot!.counts.unresolved),
              style: StitchType.caption.copyWith(
                color: StitchColors(context).amber,
              ),
            ),
          ],
          const SizedBox(height: 14),
        ],
        if (inventory.hasError)
          LoadFailure(onRetry: () => ref.invalidate(stockInventoryProvider))
        else if (inventory.isLoading || !inventory.hasValue)
          Text(t.loadingRecords)
        else if (rows.isEmpty && !filtered && !archived)
          VitalEmptyState(
            title: t.screenStockNoContainers,
            description: t.screenStockNoContainersHelp,
            icon: LucideIcons.boxes,
          )
        else if (rows.isEmpty && expiryFilter && expiryUnavailable)
          VitalEmptyState(
            title: t.directExpiryUnavailableTitle,
            description: t.directExpiryUnavailableBody,
            icon: LucideIcons.calendarClock,
            action: VitalButton.secondary(
              onPressed: _clearFilters,
              child: Text(t.clear),
            ),
          )
        else if (rows.isEmpty)
          VitalEmptyState(
            title: t.featureStockFilterEmptyTitle,
            description: t.featureStockFilterEmptyBody,
            icon: LucideIcons.search,
            action: VitalButton.secondary(
              onPressed: _clearFilters,
              child: Text(t.clear),
            ),
          )
        else
          _StockContainerList(
            rows: shown,
            counts: snapshot!.counts,
            complete: snapshot.complete,
            personRevision: owner.revision,
            archived: archived,
            inventory: snapshot,
            onNext: rows.length > shown.length
                ? () => setState(() => _pages++)
                : null,
          ),
        if (!archived) ...[
          const SizedBox(height: 24),
          _StockAdd(personId: owner.id, itemId: widget.itemId),
        ],
        const SizedBox(height: 24),
        const _StockPrivacy(),
      ],
    );
  }
}

/// Header context for the vault. The archived state stays read only and does
/// not offer stock mutations or notice controls.
class _StockIntro extends StatelessWidget {
  const _StockIntro({required this.archived});
  final bool archived;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.stockLocalNoticeHelp,
          style: StitchType.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StitchBadge(t.stitchStored, dot: true),
            if (archived)
              VitalBadge(t.archived, tone: VitalTone.warning, compact: true),
          ],
        ),
        if (archived) ...[
          const SizedBox(height: 12),
          VitalNotice(
            icon: LucideIcons.archive,
            tone: VitalTone.warning,
            child: Text(t.screenStockArchived),
          ),
        ],
      ],
    );
  }
}

/// Low and refill notices from a bounded page of the collection-wide query.
/// The loaded notice page is ordered by urgency; more notices remain explicit.
class _StockAttention extends ConsumerWidget {
  const _StockAttention({required this.personId});
  final String personId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final query = (scope: FeedScope.person(personId), offset: 0);
    return ref
        .watch(stockNoticeProvider(query))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => LoadFailure(
            onRetry: () => ref.invalidate(stockNoticeProvider(query)),
          ),
          data: (page) {
            final rows = [...page.rows]
              ..sort((a, b) {
                final rank = _stockNoticeRank(a.container.notice)
                    .compareTo(_stockNoticeRank(b.container.notice));
                if (rank != 0) return rank;
                final item = a.itemName.toLowerCase().compareTo(
                  b.itemName.toLowerCase(),
                );
                if (item != 0) return item;
                return a.container.label.toLowerCase().compareTo(
                  b.container.label.toLowerCase(),
                );
              });
            if (rows.isEmpty) return const SizedBox.shrink();
            final shown = rows.take(3).toList();
            return Column(
              key: const ValueKey('stock-attention'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    t.screenStockActionNeeded.toUpperCase(),
                    style: StitchType.small.copyWith(
                      color: c.amber,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .9,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final row in shown) ...[
                  _StockNoticeCard(
                    key: ValueKey('stock-attention-${row.container.id}'),
                    row: row,
                  ),
                  const SizedBox(height: 12),
                ],
                if (rows.length > shown.length || page.hasMore)
                  Text(
                    t.screenStockMoreNotices,
                    style: StitchType.caption.copyWith(color: c.muted),
                  ),
              ],
            );
          },
        );
  }
}

class _StockNoticeCard extends StatelessWidget {
  const _StockNoticeCard({super.key, required this.row});
  final StockNoticeRow row;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        c = row.container,
        colors = StitchColors(context);
    final caption = StitchType.caption.copyWith(color: colors.muted);
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StockIdentity(
            icon: c.notice == StockNoticeState.limitReached
                ? LucideIcons.circleAlert
                : LucideIcons.triangleAlert,
            name: row.itemName,
            containerLabel: c.label,
            strength: c.strength.label,
            badge: _stockNoticeBadge(t, c),
          ),
          const SizedBox(height: 12),
          _StockBalanceLine(container: c),
          StockPackFacts(container: c),
          const SizedBox(height: 6),
          StockForecastLine(container: c),
          if (c.lowThreshold != null) ...[
            const SizedBox(height: 6),
            Text(
              t.stockThresholdValue(
                stockAmountText(t, c.lowThreshold!, c.unit),
              ),
              style: caption,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StitchButton(
                primary: true,
                icon: LucideIcons.scale,
                onPressed: () =>
                    context.push('/stock/${c.personId}/adjust/${c.id}'),
                child: Text(t.stockAdjustAction),
              ),
              StitchButton(
                icon: LucideIcons.bellRing,
                onPressed: () => context.push(
                  '/stock/${c.personId}/adjust/${c.id}?notices=true',
                ),
                child: Text(t.screenStockNoticesAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bounded container page with truthful paging. Counts come from the whole
/// store-backed inventory snapshot, never only the visible page.
class _StockContainerList extends StatelessWidget {
  const _StockContainerList({
    required this.rows,
    required this.counts,
    required this.complete,
    required this.personRevision,
    required this.archived,
    required this.inventory,
    required this.onNext,
  });
  final List<StoredStockContainer> rows;
  final StockInventoryCounts counts;
  final bool complete;
  final int personRevision;
  final bool archived;
  final StockInventorySnapshot inventory;
  final VoidCallback? onNext;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final paging = onNext != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StockSectionTitle(
          label: complete
              ? t.stitchFilterCount(t.screenStockContainers, counts.all)
              : t.screenStockContainers,
          trailing: paging ? t.screenStockLoadedOnly : null,
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          VitalEmptyState(
            title: t.screenStockNoContainers,
            description: t.screenStockNoContainersHelp,
            icon: LucideIcons.boxes,
          )
        else
          for (final c in rows) ...[
            _StockContainerCard(
              key: ValueKey('stock-card-${c.id}'),
              container: c,
              personRevision: personRevision,
              archived: archived,
              planState: inventory.planStateFor(c.id),
              balanceState: inventory.balanceFor(c.id),
              expiryDay: inventory.expiryDay,
            ),
            const SizedBox(height: 12),
          ],
        if (paging) ...[
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StitchButton(onPressed: onNext, child: Text(t.more)),
          ),
        ],
      ],
    );
  }
}

/// Whole-collection balance and plan filters. Balance values and pause state
/// may overlap, so the labels stay factual rather than exclusive.
class StockInventoryFilters extends StatelessWidget {
  const StockInventoryFilters({
    super.key,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });
  final StockInventoryCounts? counts;
  final StockInventoryFilter selected;
  final ValueChanged<StockInventoryFilter> onSelected;

  String _name(AppLocalizations t, StockInventoryFilter filter) =>
      switch (filter) {
        StockInventoryFilter.all => t.featureStockFilterAll,
        StockInventoryFilter.low => t.featureStockFilterLow,
        StockInventoryFilter.adequate => t.featureStockFilterAdequate,
        StockInventoryFilter.paused => t.featureStockFilterPaused,
        StockInventoryFilter.unknown => t.featureStockFilterUnknown,
        StockInventoryFilter.expired => t.directExpiryFilterExpired,
        StockInventoryFilter.today => t.directExpiryFilterToday,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: t.featureStockFilters,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in StockInventoryFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Semantics(
                  selected: selected == filter,
                  child: StitchButton(
                    primary: selected == filter,
                    compact: true,
                    onPressed: () => onSelected(filter),
                    child: Text(switch (counts?.count(filter)) {
                      final int count => t.stitchFilterCount(
                        _name(t, filter),
                        count,
                      ),
                      null => _name(t, filter),
                    }, style: StitchType.small),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StockContainerCard extends ConsumerWidget {
  const _StockContainerCard({
    super.key,
    required this.container,
    required this.personRevision,
    required this.archived,
    required this.planState,
    required this.balanceState,
    required this.expiryDay,
  });
  final StoredStockContainer container;
  final int personRevision;
  final bool archived;
  final StockInventoryPlanState planState;
  final StockInventoryBalance balanceState;
  final CivilDate? expiryDay;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final itemName = ref
        .watch(itemLookupProvider(container.itemId))
        .value
        ?.name;
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StockIdentity(
            icon: _stockUnitIcon(container.unit),
            name: itemName ?? container.label,
            containerLabel: itemName == null ? null : container.label,
            strength: container.strength.label,
            badge: _stockNoticeBadge(t, container),
          ),
          StockPackFacts(
            container: container,
            expiryDay: expiryDay,
            expiryUnavailable: expiryDay == null,
          ),
          const SizedBox(height: 12),
          _StockBalanceLine(container: container),
          const SizedBox(height: 10),
          StockCapacityProgress(container: container),
          const SizedBox(height: 6),
          StockForecastLine(container: container),
          const SizedBox(height: 8),
          StockPlanStateLine(state: planState),
          if (!archived) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: c.line),
            const SizedBox(height: 12),
            StockNoticeSettings(
              key: ValueKey(container.id),
              container: container,
              personRevision: personRevision,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                StitchButton(
                  key: ValueKey('stock-restock-${container.id}'),
                  icon: LucideIcons.packagePlus,
                  onPressed: () => context.push(
                    '/stock/${container.personId}/restock/${container.id}',
                  ),
                  child: Text(t.stockRestock),
                ),
                StitchButton(
                  key: ValueKey('stock-details-${container.id}'),
                  icon: LucideIcons.packageOpen,
                  onPressed: () => context.push(
                    '/stock/${container.personId}/adjust/${container.id}?details=true',
                  ),
                  child: Text(t.details),
                ),
                StitchButton(
                  key: ValueKey('stock-adjust-${container.id}'),
                  primary: true,
                  icon: LucideIcons.scale,
                  onPressed: () => context.push(
                    '/stock/${container.personId}/adjust/${container.id}',
                  ),
                  child: Text(t.stockAdjustAction),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Factual schedule state shown beside the balance, so Paused is never
/// inferred from stock or item type and unscheduled/mixed stay explicit.
class StockPlanStateLine extends StatelessWidget {
  const StockPlanStateLine({super.key, required this.state});
  final StockInventoryPlanState state;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = StitchColors(context);
    final (label, tone) = switch (state) {
      StockInventoryPlanState.paused => (
        t.featureStockPlanPaused,
        VitalTone.warning,
      ),
      StockInventoryPlanState.mixed => (
        t.featureStockPlanMixed,
        VitalTone.warning,
      ),
      StockInventoryPlanState.unscheduled => (
        t.featureStockPlanUnscheduled,
        VitalTone.neutral,
      ),
      StockInventoryPlanState.unresolved => (
        t.featureStockPlanUnresolved,
        VitalTone.warning,
      ),
      StockInventoryPlanState.active => (null, VitalTone.neutral),
      StockInventoryPlanState.asNeeded => (t.planAsNeeded, VitalTone.neutral),
    };
    if (label == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          state == StockInventoryPlanState.unresolved
              ? LucideIcons.circleAlert
              : LucideIcons.calendarClock,
          size: 15,
          color: tone == VitalTone.warning ? colors.amber : colors.muted,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: StitchType.caption.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// Identity block reused by notice and container cards. The status pill stays
/// beside the name while it fits and moves below the identity at narrow widths
/// or larger text, so a complete name never shares a cramped line.
class _StockIdentity extends StatelessWidget {
  const _StockIdentity({
    required this.icon,
    required this.name,
    required this.strength,
    required this.badge,
    this.containerLabel,
  });
  final IconData icon;
  final String name, strength;
  final Widget badge;
  final String? containerLabel;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(14) >= 21;
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StitchIcon(icon, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(name, style: StitchType.name.copyWith(color: c.ink)),
                      VitalBadge(strength, compact: true),
                    ],
                  ),
                  if (containerLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      containerLabel!,
                      style: StitchType.caption.copyWith(color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
        if (!stacked) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: identity),
              const SizedBox(width: 8),
              badge,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [identity, const SizedBox(height: 8), badge],
        );
      },
    );
  }
}

/// The stored balance in the established `Remaining: <amount> <unit>` wording.
/// An unknown or over-limit balance is spelled out instead of showing zero.
class _StockBalanceLine extends StatelessWidget {
  const _StockBalanceLine({required this.container});
  final StoredStockContainer container;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final balance = container.balance;
    final known = balance.value != null && !balance.limitReached;
    final line = balance.limitReached
        ? t.stockLimit
        : balance.value == null
        ? t.stockUnknown
        : t.stockBalance(stockAmountText(t, balance.value!, container.unit));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line,
          style: known
              ? StitchType.body.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w600,
                )
              : StitchType.caption.copyWith(color: c.muted),
        ),
        if (balance.isDeficit) ...[
          const SizedBox(height: 2),
          Text(
            t.stockDeficit,
            style: StitchType.caption.copyWith(color: c.danger),
          ),
        ],
      ],
    );
  }
}

class _StockSectionTitle extends StatelessWidget {
  const _StockSectionTitle({required this.label, this.trailing});
  final String label;
  final String? trailing;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Semantics(
          header: true,
          child: Text(label, style: StitchType.name.copyWith(color: c.ink)),
        ),
        if (trailing != null)
          Text(trailing!, style: StitchType.small.copyWith(color: c.muted)),
      ],
    );
  }
}

/// Manual stock addition stays real for an item-scoped vault. The unscoped
/// vault has no item identity to attach a container to, so it opens the
/// collection instead. Scanning, lots, expiry and forecasts stay named gaps.
class _StockAdd extends StatelessWidget {
  const _StockAdd({required this.personId, required this.itemId});
  final String personId;
  final String? itemId;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final itemScoped = itemId != null;
    final caption = StitchType.caption.copyWith(color: c.muted);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.screenStockAddHeading,
          style: StitchType.name.copyWith(color: c.ink),
        ),
        const SizedBox(height: 2),
        Text(
          itemScoped ? t.screenStockAddItemHelp : t.screenStockAddAllHelp,
          style: caption,
        ),
      ],
    );
    return StitchSurface(
      key: const ValueKey('stock-add'),
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(14) >= 21;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StitchIcon(LucideIcons.scanBarcode, size: 44),
                    const SizedBox(height: 8),
                    copy,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StitchIcon(LucideIcons.scanBarcode, size: 44),
                  const SizedBox(width: 12),
                  Expanded(child: copy),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(t.screenStockGaps, style: caption),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StitchButton(
              key: const ValueKey('stock-add-action'),
              primary: true,
              icon: itemScoped ? LucideIcons.plus : LucideIcons.pill,
              onPressed: () => context.push(
                itemScoped
                    ? '/stock/$personId/create?item=$itemId'
                    : '/substances',
              ),
              child: Text(itemScoped ? t.add : t.substances),
            ),
          ),
        ],
      ),
    );
  }
}

/// Local encrypted storage is real; network, sync and complete-verification
/// claims are not made here.
class _StockPrivacy extends StatelessWidget {
  const _StockPrivacy();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    return StitchSurface(
      inset: true,
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchIcon(LucideIcons.lock, size: 36, selected: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.stitchStored,
                  style: StitchType.label.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.stitchLocalBody,
                  style: StitchType.caption.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _stockNoticeRank(StockNoticeState state) => switch (state) {
  StockNoticeState.refill => 0,
  StockNoticeState.low => 1,
  StockNoticeState.unknown => 2,
  StockNoticeState.limitReached => 3,
  StockNoticeState.none => 4,
};

Widget _stockNoticeBadge(AppLocalizations t, StoredStockContainer c) {
  return switch (c.notice) {
    StockNoticeState.none => StitchBadge(t.screenStockStocked),
    StockNoticeState.low => StitchBadge(t.stockLow, warning: true),
    StockNoticeState.refill => StitchBadge(t.stockRefillDue, warning: true),
    StockNoticeState.unknown => VitalBadge(t.screenStockUnknown, compact: true),
    StockNoticeState.limitReached => VitalBadge(
      t.screenStockUnavailable,
      compact: true,
    ),
  };
}

IconData _stockUnitIcon(String unit) => switch (unit) {
  'ml' => LucideIcons.droplets,
  'count' => LucideIcons.package,
  _ => LucideIcons.pill,
};

class StockContainerForm extends ConsumerStatefulWidget {
  const StockContainerForm({
    super.key,
    required this.personId,
    required this.itemId,
    this.returnToSetup = false,
  });
  final String personId, itemId;
  final bool returnToSetup;
  @override
  ConsumerState<StockContainerForm> createState() => _StockContainerFormState();
}

class _StockContainerFormState extends DurableFormState<StockContainerForm> {
  final label = TextEditingController(),
      strength = TextEditingController(),
      concentration = TextEditingController(),
      opening = TextEditingController(),
      threshold = TextEditingController(),
      lot = TextEditingController(),
      expiry = TextEditingController(),
      capacity = TextEditingController();
  ProductLabelSnapshot? productLabel;
  late final productEditor = ProductEditorData(entryChanged);
  late final preparationEditor = VialPreparationEditorData(entryChanged);
  bool mixed = false;
  bool strengthPerCount = false;
  String strengthMassUnit = 'mg';
  String unit = 'ml';
  bool knownStrength = false,
      knownOpening = false,
      refill = false,
      initialised = false;
  AdultProfile? owner;
  SubstanceItem? item;
  String? invalid;
  @override
  DraftKind get entryKind => DraftKind.stockContainer;
  @override
  String? get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.itemId;
  @override
  int? get entryTargetRevision => item?.revision;
  @override
  Map<String, String> captureEntry() => {
    'mixed': '$mixed',
    'preparation': preparationEditor.encode(),
    'strengthPerCount': '$strengthPerCount',
    'strengthMassUnit': strengthMassUnit,
    'label': label.text,
    'unit': unit,
    'strength': strength.text,
    'strengthKnown': '$knownStrength',
    'concentration': concentration.text,
    'opening': opening.text,
    'openingKnown': '$knownOpening',
    'threshold': threshold.text,
    'refill': '$refill',
    'lot': lot.text,
    'expiry': expiry.text,
    'capacity': capacity.text,
    'productLabel': productLabel == null
        ? ''
        : jsonEncode(productLabel!.toJson()),
    'productComponents': productEditor.encode(),
  };
  @override
  void restoreEntry(Map<String, String> f) {
    productLabel = f['productLabel']?.isNotEmpty == true
        ? ProductLabelSnapshot.fromJson(
            jsonDecode(f['productLabel']!) as Map<String, dynamic>,
          )
        : productLabel;
    if (f['productComponents'] case final encoded?) {
      productEditor.restore(encoded);
    }
    mixed = f['mixed'] == 'true';
    if (f['preparation'] case final v?) preparationEditor.restore(v);
    strengthPerCount = f['strengthPerCount'] == 'true';
    strengthMassUnit = f['strengthMassUnit'] ?? 'mg';
    label.text = f['label'] ?? '';
    strength.text = f['strength'] ?? '';
    concentration.text = f['concentration'] ?? '';
    opening.text = f['opening'] ?? '';
    threshold.text = f['threshold'] ?? '';
    lot.text = f['lot'] ?? '';
    expiry.text = f['expiry'] ?? '';
    capacity.text = f['capacity'] ?? '';
    unit = f['unit'] ?? 'ml';
    knownStrength = f['strengthKnown'] == 'true';
    knownOpening = f['openingKnown'] == 'true';
    refill = f['refill'] == 'true';
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      label,
      strength,
      concentration,
      opening,
      threshold,
      lot,
      expiry,
      capacity,
    ]) {
      c.addListener(entryChanged);
    }
  }

  @override
  void dispose() {
    preparationEditor.dispose();
    productEditor.dispose();
    for (final c in [
      label,
      strength,
      concentration,
      opening,
      threshold,
      lot,
      expiry,
      capacity,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (label.text.trim().isEmpty ||
        (productLabel == null && !mixed && strength.text.trim().isEmpty)) {
      setState(() {
        invalid = 'label';
        error = t.stockLabelRequired;
      });
      return;
    }
    VialPreparation? preparation;
    if (mixed && productLabel == null) {
      try {
        preparation = preparationEditor.read();
      } catch (_) {
        setState(() => error = t.vialInvalid);
        return;
      }
    }
    ExactAmount? c, o, low, packCapacity;
    CivilDate? packExpiry;
    String? packLot;
    try {
      if (productLabel == null && knownStrength && !mixed) {
        c =
            ExactAmount.parseEntry(stockDecimal(concentration.text)) /
            ExactAmount(BigInt.from(strengthMassUnit == 'mcg' ? 1000 : 1));
      }
    } catch (_) {
      setState(() {
        invalid = 'concentration';
        error = t.stockAmountInvalid;
      });
      return;
    }
    try {
      if (knownOpening) o = stockMeasurement(opening.text);
    } catch (_) {
      setState(() {
        invalid = 'opening';
        error = t.stockMeasurementInvalid;
      });
      return;
    }
    try {
      if (threshold.text.trim().isNotEmpty) {
        low = stockMeasurement(threshold.text);
      }
    } catch (_) {
      setState(() {
        invalid = 'threshold';
        error = t.stockMeasurementInvalid;
      });
      return;
    }
    if (expiry.text.trim().isNotEmpty) {
      try {
        packExpiry = CivilDate.parse(expiry.text.trim());
      } catch (_) {
        setState(() {
          invalid = 'expiry';
          error = t.featureStockExpiryInvalid;
        });
        return;
      }
    }
    try {
      if (capacity.text.trim().isNotEmpty) {
        packCapacity = stockCapacityEntry(capacity.text);
      }
    } catch (_) {
      setState(() {
        invalid = 'capacity';
        error = t.featureStockCapacityInvalid;
      });
      return;
    }
    packLot = lot.text.trim().isEmpty ? null : lot.text.trim();
    if (packLot != null && packLot.length > 200) {
      setState(() {
        invalid = 'lot';
        error = t.featureStockCapacityInvalid;
      });
      return;
    }
    ProductLabelSnapshot? sourceLabel;
    if (productLabel != null) {
      try {
        sourceLabel = ProductLabelSnapshot(
          personId: widget.personId,
          itemId: widget.itemId,
          revision: productLabel!.revision,
          components: productEditor.components(),
        );
      } catch (_) {
        setState(() => error = t.productIngredientInvalid);
        return;
      }
    }
    invalid = null;
    await commit(
      (command) async {
        final store = await ref.read(recordStoreProvider.future);
        await store.createStockContainer(
          commandId: command,
          expectedGeneration: capturedGeneration!,
          personId: widget.personId,
          expectedPersonRevision: capturedPersonRevision!,
          itemId: widget.itemId,
          label: label.text.trim(),
          unit: unit,
          strength: LabelledStrength(
            ingredientId: widget.itemId,
            label: mixed
                ? item!.name
                : productLabel == null
                ? strength.text.trim()
                : item!.name,
            mgPerMl: preparation?.mgPerMl ?? (strengthPerCount ? null : c),
            mgPerCount: !mixed && strengthPerCount ? c : null,
            preparation: preparation,
          ),
          opening: o,
          lowThreshold: low,
          lot: packLot,
          expiryDate: packExpiry,
          capacity: packCapacity,
          refillEnabled: refill,
          productLabel: sourceLabel,
        );
      },
      successPath: widget.returnToSetup
          ? '/substance/${widget.itemId}/setup'
          : '/stock/${widget.personId}?item=${widget.itemId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider),
        current = ref.watch(itemLookupProvider(widget.itemId));
    if (people.hasError || current.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(itemLookupProvider(widget.itemId));
            },
          ),
        ],
      );
    }
    if (!people.hasValue || !current.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final currentProduct = ref.watch(
      productLabelProvider((personId: widget.personId, itemId: widget.itemId)),
    );
    if (currentProduct.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () => ref.invalidate(
              productLabelProvider((
                personId: widget.personId,
                itemId: widget.itemId,
              )),
            ),
          ),
        ],
      );
    }
    if (!currentProduct.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final liveOwner = people.value!
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    if (liveOwner == null ||
        current.value == null ||
        current.value!.personId != widget.personId) {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    final detail = ref.watch(itemDetailProvider(widget.itemId));
    if (detail.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () => ref.invalidate(itemDetailProvider(widget.itemId)),
          ),
        ],
      );
    }
    if (!detail.hasValue) return EntryPage(children: [Text(t.loadingRecords)]);
    if (!initialised) {
      owner = liveOwner;
      item = current.value;
      unit = item!.unit;
      final profile = detail.value?.profile;
      mixed = profile?.form == SubstanceForm.powderToMix;
      strengthPerCount = profile?.isCount ?? item!.unit == 'count';
      if (profile?.strengthText != null) {
        strength.text = item!.name;
        knownStrength = true;
        concentration.text = profile!.strengthText!;
        strengthMassUnit = profile.massUnit;
      }
      productLabel = currentProduct.value;
      if (productLabel != null) {
        productEditor.initialise(productLabel!.components);
      }
      initialised = true;
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        !liveOwner.isArchived &&
        liveOwner.revision == capturedPersonRevision &&
        current.value!.revision == capturedTargetRevision;
    final enabled = valid && !busy && !uncertain;
    return wrap([
      Heading(t.stockCreate),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(item!.name),
      if (!valid) Text(t.conflictFailure),
      LabelledInput(
        label: t.stockLabel,
        controller: label,
        enabled: enabled,
        error: invalid == 'label' ? error : null,
      ),
      if (productLabel != null) ...[
        Text(t.productSourceHelp),
        ProductComponentEditor(
          data: productEditor,
          enabled: enabled,
          error: error == t.productIngredientInvalid ? error : null,
          onChanged: () => setState(() {}),
        ),
      ],
      if (productLabel == null)
        SettingsToggleRow(
          label: t.vialMixed,
          description: t.vialMixedHelp,
          value: mixed,
          enabled: enabled,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          onChanged: (v) => setState(() {
            mixed = v;
            if (v) unit = 'ml';
            entryChanged();
          }),
        ),
      if (productLabel == null && mixed)
        VialPreparationEditor(
          data: preparationEditor,
          enabled: enabled,
          onChanged: () => setState(() {}),
        ),
      if (productLabel == null && !mixed)
        LabelledInput(
          label: t.stockStrength,
          controller: strength,
          enabled: enabled,
        ),
      if (productLabel == null && !mixed)
        SettingsToggleRow(
          label: t.stockKnownStrength,
          description: t.stockKnownStrengthHelp,
          value: knownStrength,
          enabled: enabled,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          onChanged: (v) => setState(() {
            knownStrength = v;
            entryChanged();
          }),
        ),
      if (productLabel == null && knownStrength && !mixed) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final each in [false, true])
              Semantics(
                selected: strengthPerCount == each,
                inMutuallyExclusiveGroup: true,
                child: VitalButton.secondary(
                  onPressed: enabled
                      ? () => setState(() {
                          strengthPerCount = each;
                          entryChanged();
                        })
                      : null,
                  child: Text(
                    each ? t.substanceStrengthEach : t.substanceStrengthMl,
                  ),
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mass in ['mg', 'mcg'])
              Semantics(
                selected: strengthMassUnit == mass,
                inMutuallyExclusiveGroup: true,
                child: VitalButton.secondary(
                  onPressed: enabled
                      ? () => setState(() {
                          strengthMassUnit = mass;
                          entryChanged();
                        })
                      : null,
                  child: Text(mass == 'mcg' ? t.substanceMicrograms : mass),
                ),
              ),
          ],
        ),
        LabelledInput(
          label: strengthPerCount
              ? t.substanceStrengthEach
              : t.substanceStrengthMl,
          controller: concentration,
          helper: t.stockDecimalHelp,
          enabled: enabled,
          error: invalid == 'concentration' ? error : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
      Text(t.unitLabel),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final u in ['mg', 'ml', 'count'])
            Semantics(
              selected: unit == u,
              child: VitalButton.secondary(
                multiline: true,
                onPressed: enabled && productLabel == null && !mixed
                    ? () => setState(() {
                        unit = u;
                        entryChanged();
                      })
                    : null,
                child: Text(u),
              ),
            ),
        ],
      ),
      SettingsToggleRow(
        label: t.stockKnownOpening,
        description: t.stockOpeningHelp,
        value: knownOpening,
        enabled: enabled,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        onChanged: (v) => setState(() {
          knownOpening = v;
          entryChanged();
        }),
      ),
      if (knownOpening)
        LabelledInput(
          label: t.stockOpening,
          controller: opening,
          helper: t.stockDecimalHelp,
          enabled: enabled,
          error: invalid == 'opening' ? error : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      const SizedBox(height: 8),
      VitalDisclosure(
        title: t.featureStockDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.featureStockDetailsHelp),
            const SizedBox(height: 12),
            LabelledInput(
              label: t.featureStockLot,
              controller: lot,
              helper: t.featureStockLotHelp,
              enabled: enabled,
              error: invalid == 'lot' ? error : null,
            ),
            LabelledInput(
              label: t.featureStockExpiry,
              controller: expiry,
              helper: t.featureStockExpiryHelp,
              enabled: enabled,
              error: invalid == 'expiry' ? error : null,
            ),
            LabelledInput(
              label: t.featureStockCapacity,
              controller: capacity,
              helper: t.featureStockCapacityHelp(unit),
              enabled: enabled,
              error: invalid == 'capacity' ? error : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      LabelledInput(
        label: t.stockThreshold,
        controller: threshold,
        helper: t.stockThresholdHelp,
        enabled: enabled,
        error: invalid == 'threshold' ? error : null,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
      SettingsToggleRow(
        label: t.stockRefill,
        description: t.stockRefillHelp,
        value: refill,
        enabled: enabled,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        onChanged: (v) => setState(() {
          refill = v;
          entryChanged();
        }),
      ),
      Text(t.stockLocalNoticeHelp),
      ?failure(),
      VitalButton(
        onPressed: !busy && (uncertain || (valid && !conflict)) ? save : null,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.create,
        ),
      ),
    ]);
  }
}

class StockAdjustmentForm extends ConsumerStatefulWidget {
  const StockAdjustmentForm({
    super.key,
    required this.personId,
    required this.containerId,
    this.notices = false,
    this.details = false,
    this.restock = false,
  });
  final String personId, containerId;
  final bool notices, details, restock;
  @override
  ConsumerState<StockAdjustmentForm> createState() =>
      _StockAdjustmentFormState();
}

class _StockAdjustmentFormState extends DurableFormState<StockAdjustmentForm> {
  final amount = TextEditingController(),
      reason = TextEditingController(),
      lot = TextEditingController(),
      expiry = TextEditingController(),
      capacity = TextEditingController();
  StockMovementKind? kind;
  bool restoredMovement = false;
  bool unknown = false,
      noticesMode = false,
      detailsMode = false,
      initialised = false,
      clearThreshold = false;
  AdultProfile? owner;
  StoredStockContainer? container;
  @override
  DraftKind get entryKind => DraftKind.stockAdjustment;
  @override
  String? get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => owner?.revision;

  /// Notices configure a different stock command than quantity adjustments, so
  /// each surface keeps its own durable draft for the same container. The
  /// notices surface carries a stable variant; the quantity surface keeps the
  /// legacy key so existing movement drafts still restore untouched.
  @override
  String? get entryTarget => widget.containerId;
  @override
  String? get entryDraftVariant => detailsMode
      ? 'details'
      : noticesMode
      ? 'notices'
      : null;
  @override
  Future<OrdinaryDraft?> adoptEntryDraft(
    RecordStore store,
    OrdinaryDraft? draft,
  ) async {
    if (noticesMode) {
      if (draft != null) return draft;
      // Adopt a pre-variant notices entry still stored at the shared quantity
      // key; movement drafts there belong to the quantity surface untouched.
      final legacy = await store.draftById(entryBaseDraftId);
      if (legacy == null || legacy.fields['kind'] != 'notices') return null;
      return store.relocateLegacyStockNoticesDraft(
        legacyId: legacy.id,
        destinationId: '$entryBaseDraftId:notices',
        personId: widget.personId,
        targetId: widget.containerId,
      );
    }
    if (draft == null || draft.fields['kind'] != 'notices') return draft;
    // The quantity key still holds a pre-variant notices intent. Free it for
    // this surface without restoring or discarding its content.
    await store.relocateLegacyStockNoticesDraft(
      legacyId: draft.id,
      destinationId: '$entryBaseDraftId:notices',
      personId: widget.personId,
      targetId: widget.containerId,
    );
    return null;
  }

  @override
  int? get entryTargetRevision => container?.revision;
  @override
  Map<String, String> captureEntry() => {
    'kind': detailsMode
        ? 'details'
        : noticesMode
        ? 'notices'
        : kind?.name ?? '',
    'amount': amount.text,
    'unknown': '$unknown',
    'reason': reason.text,
    'clearThreshold': '$clearThreshold',
    'lot': lot.text,
    'expiry': expiry.text,
    'capacity': capacity.text,
  };
  @override
  void restoreEntry(Map<String, String> f) {
    // The route decides the surface. A draft written for another command of
    // the same container must never leak its fields into this editor.
    if ((f['kind'] ?? '') == 'details') {
      if (!detailsMode) return;
      lot.text = f['lot'] ?? '';
      expiry.text = f['expiry'] ?? '';
      capacity.text = f['capacity'] ?? '';
      return;
    }
    if ((f['kind'] ?? '') == 'notices') {
      if (!noticesMode) return;
      amount.text = f['amount'] ?? '';
      clearThreshold = f['clearThreshold'] == 'true';
      reason.text = f['reason'] ?? '';
      unknown = f['unknown'] == 'true';
      return;
    }
    if (detailsMode || noticesMode) {
      conflict = true;
      error = conflictMessage;
      return;
    }
    kind = StockMovementKind.values
        .where((v) => v.name == f['kind'])
        .firstOrNull;
    restoredMovement = kind != null;
    amount.text = f['amount'] ?? '';
    reason.text = f['reason'] ?? '';
    unknown = f['unknown'] == 'true';
    clearThreshold = f['clearThreshold'] == 'true';
  }

  @override
  void initState() {
    super.initState();
    // Existing movement drafts restore their own kind and values afterwards.
    if (widget.restock) kind = StockMovementKind.restock;
    amount.addListener(entryChanged);
    reason.addListener(entryChanged);
    lot.addListener(entryChanged);
    expiry.addListener(entryChanged);
    capacity.addListener(entryChanged);
  }

  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    lot.dispose();
    expiry.dispose();
    capacity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (detailsMode) {
      CivilDate? packExpiry;
      ExactAmount? packCapacity;
      if (expiry.text.trim().isNotEmpty) {
        try {
          packExpiry = CivilDate.parse(expiry.text.trim());
        } catch (_) {
          setState(() => error = t.featureStockExpiryInvalid);
          return;
        }
      }
      try {
        if (capacity.text.trim().isNotEmpty) {
          final originalCapacity = container!.capacity;
          packCapacity =
              originalCapacity != null &&
                  capacity.text == stockExactAmountEntry(originalCapacity)
              ? originalCapacity
              : stockCapacityEntry(capacity.text);
        }
      } catch (_) {
        setState(() => error = t.featureStockCapacityInvalid);
        return;
      }
      final packLot = lot.text.trim().isEmpty ? null : lot.text.trim();
      if (packLot != null && packLot.length > 200) {
        setState(() => error = t.featureStockLotInvalid);
        return;
      }
      await commit((command) async {
        final store = await ref.read(recordStoreProvider.future);
        await store.updateStockMetadata(
          commandId: command,
          personId: widget.personId,
          expectedPersonRevision: capturedPersonRevision!,
          expectedGeneration: capturedGeneration!,
          containerId: widget.containerId,
          expectedContainerRevision: capturedTargetRevision!,
          lot: packLot,
          expiryDate: packExpiry,
          capacity: packCapacity,
        );
      }, successPath: '/stock/${widget.personId}?item=${container!.itemId}');
      return;
    }
    if (noticesMode) {
      ExactAmount? low;
      try {
        low = amount.text.trim().isEmpty
            ? (clearThreshold ? null : container!.lowThreshold)
            : stockMeasurement(amount.text);
      } catch (_) {
        setState(() => error = t.stockMeasurementInvalid);
        return;
      }
      await commit((command) async {
        final store = await ref.read(recordStoreProvider.future);
        await store.configureStockNotices(
          commandId: command,
          personId: widget.personId,
          expectedPersonRevision: capturedPersonRevision!,
          expectedGeneration: capturedGeneration!,
          containerId: widget.containerId,
          expectedContainerRevision: capturedTargetRevision!,
          lowThreshold: low,
          refillEnabled: container!.refillEnabled,
        );
      }, successPath: '/stock/${widget.personId}?item=${container!.itemId}');
      return;
    }
    if (kind == null) {
      setState(() => error = t.stockChooseKind);
      return;
    }
    EnteredStockAmount? entered;
    ExactAmount? measured;
    try {
      if (kind == StockMovementKind.reconciliation) {
        if (!unknown) measured = stockMeasurement(amount.text);
      } else {
        entered = EnteredStockAmount(
          stockDecimal(amount.text),
          container!.unit,
        );
      }
    } catch (_) {
      setState(
        () => error = kind == StockMovementKind.reconciliation
            ? t.stockMeasurementInvalid
            : t.stockAmountInvalid,
      );
      return;
    }
    await commit((command) async {
      final store = await ref.read(recordStoreProvider.future);
      await store.addStockMovement(
        commandId: command,
        personId: widget.personId,
        expectedGeneration: capturedGeneration!,
        expectedPersonRevision: capturedPersonRevision!,
        containerId: widget.containerId,
        expectedContainerRevision: capturedTargetRevision!,
        kind: kind!,
        amount: entered,
        measured: measured,
        reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
      );
    }, successPath: '/stock/${widget.personId}?item=${container!.itemId}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider),
        result = ref.watch(
          stockContainerProvider((
            personId: widget.personId,
            containerId: widget.containerId,
          )),
        );
    if (people.hasError || result.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(
                stockContainerProvider((
                  personId: widget.personId,
                  containerId: widget.containerId,
                )),
              );
            },
          ),
        ],
      );
    }
    if (!people.hasValue || !result.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final live = people.value!
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    if (live == null || result.value == null) {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    owner ??= live;
    container ??= result.value;
    if (!initialised) {
      initialised = true;
      noticesMode = widget.notices;
      detailsMode = widget.details;
      if (detailsMode) {
        lot.text = container!.lot ?? '';
        expiry.text = container!.expiryDate?.toString() ?? '';
        if (container!.capacity case final savedCapacity?) {
          capacity.text = stockExactAmountEntry(savedCapacity);
        }
      }
      if (noticesMode) amount.text = '';
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        !live.isArchived &&
        live.revision == capturedPersonRevision &&
        result.value!.revision == capturedTargetRevision;
    final enabled = valid && !busy && !uncertain && !conflict;
    return wrap([
      Heading(
        noticesMode
            ? t.stockNotices
            : detailsMode
            ? t.featureStockDetails
            : t.stockAdjust,
      ),
      if (widget.restock && restoredMovement)
        Text(t.directRestockRestored, style: StitchType.caption),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(container!.label),
      if (container!.productLabel != null)
        ProductLabelView(label: container!.productLabel!)
      else
        Text(t.stockStrengthValue(container!.strength.label)),
      StockBalanceText(container: result.value!),
      if (!valid) Text(t.conflictFailure),
      if (detailsMode) ...[
        Text(t.featureStockDetailsHelp),
        StockPackFacts(container: result.value!, detailed: true),
        LabelledInput(
          label: t.featureStockLot,
          controller: lot,
          helper: t.featureStockLotHelp,
          enabled: enabled,
          error: error == t.featureStockLotInvalid ? error : null,
        ),
        LabelledInput(
          label: t.featureStockExpiry,
          controller: expiry,
          helper: t.featureStockExpiryHelp,
          enabled: enabled,
          error: error == t.featureStockExpiryInvalid ? error : null,
        ),
        LabelledInput(
          label: t.featureStockCapacity,
          controller: capacity,
          helper: t.featureStockCapacityHelp(result.value!.unit),
          enabled: enabled,
          error: error == t.featureStockCapacityInvalid ? error : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        VitalDisclosure(
          title: t.featureStockMetadataHistory,
          child: StockMetadataHistory(
            personId: widget.personId,
            containerId: widget.containerId,
            unit: container!.unit,
          ),
        ),
      ],
      if (noticesMode && container!.lowThreshold != null)
        Text(
          t.stockThresholdValue(
            stockAmountText(t, container!.lowThreshold!, container!.unit),
          ),
        ),
      if (noticesMode)
        LabelledInput(
          label: t.stockThreshold,
          controller: amount,
          helper: clearThreshold
              ? t.stockThresholdCleared
              : t.stockThresholdEditHelp,
          enabled: enabled,
          error: error == t.stockMeasurementInvalid ? error : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      if (noticesMode)
        VitalButton.secondary(
          onPressed: enabled
              ? () => setState(() {
                  clearThreshold = true;
                  amount.clear();
                  entryChanged();
                })
              : null,
          child: Text(t.catalogueClear),
        ),
      if (!noticesMode && !detailsMode)
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (k, name) in [
              (StockMovementKind.restock, t.stockRestock),
              (StockMovementKind.waste, t.stockWaste),
              (StockMovementKind.reconciliation, t.stockMeasure),
            ])
              Semantics(
                selected: kind == k,
                child: VitalButton.secondary(
                  multiline: true,
                  onPressed: enabled
                      ? () => setState(() {
                          kind = k;
                          entryChanged();
                        })
                      : null,
                  child: Text(name),
                ),
              ),
          ],
        ),
      if (!noticesMode && !detailsMode && kind != null) ...[
        Text(
          kind == StockMovementKind.restock
              ? t.stockRestockHelp
              : kind == StockMovementKind.waste
              ? t.stockWasteHelp
              : t.stockMeasureHelp,
        ),
        if (kind == StockMovementKind.reconciliation)
          SettingsToggleRow(
            label: t.stockUnknownMeasure,
            description: t.stockUnknownMeasureHelp,
            value: unknown,
            enabled: enabled,
            reduceMotion: MediaQuery.disableAnimationsOf(context),
            onChanged: (v) => setState(() {
              unknown = v;
              entryChanged();
            }),
          ),
        if (kind != StockMovementKind.reconciliation || !unknown) ...[
          LabelledInput(
            label: t.amountLabel,
            controller: amount,
            helper: t.stockDecimalHelp,
            enabled: enabled,
            error:
                error == t.stockMeasurementInvalid ||
                    error == t.stockAmountInvalid
                ? error
                : null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          Text(container!.unit),
        ],
        LabelledInput(
          label: t.stockReason,
          controller: reason,
          enabled: enabled,
        ),
      ],
      ?failure(),
      VitalButton(
        onPressed: !busy && (uncertain || (valid && !conflict)) ? save : null,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.save,
        ),
      ),
      const SizedBox(height: 24),
      StockMovementHistory(
        personId: widget.personId,
        containerId: widget.containerId,
        unit: container!.unit,
      ),
    ]);
  }
}

/// Saved pack-detail revisions. Movement revisions do not create metadata
/// rows, so the version numbers honestly identify metadata edits only.
class StockMetadataHistory extends ConsumerStatefulWidget {
  const StockMetadataHistory({
    super.key,
    required this.personId,
    required this.containerId,
    required this.unit,
  });
  final String personId, containerId, unit;
  @override
  ConsumerState<StockMetadataHistory> createState() =>
      _StockMetadataHistoryState();
}

class _StockMetadataHistoryState extends ConsumerState<StockMetadataHistory> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final query = (
      personId: widget.personId,
      containerId: widget.containerId,
      offset: offset,
    );
    return ref
        .watch(stockMetadataHistoryProvider(query))
        .when(
          loading: () => Text(t.loadingRecords),
          error: (_, _) => LoadFailure(
            onRetry: () => ref.invalidate(stockMetadataHistoryProvider(query)),
          ),
          data: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rows.isEmpty) Text(t.featureStockMetadataEmpty),
              for (final row in rows.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        row.source == 'migrated'
                            ? t.featureStockMetadataUndated(row.revision)
                            : t.featureStockMetadataEntry(
                                row.source == 'created'
                                    ? t.featureStockMetadataCreated
                                    : t.featureStockMetadataEdited,
                                row.revision,
                                displayStamp(context, ref, row.recordedAt),
                              ),
                      ),
                      if (row.lot case final lot?)
                        Text(t.featureStockLotValue(lot)),
                      if (row.expiryDate case final expiry?)
                        Text(t.featureStockExpiryValue(expiry.toString())),
                      if (row.capacity case final capacity?)
                        Text(
                          t.featureStockCapacityValue(
                            t.stockQuantity(
                              stockExactAmountEntry(capacity),
                              widget.unit,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (offset > 0)
                    VitalButton.secondary(
                      onPressed: () => setState(() => offset -= 20),
                      child: Text(t.previous),
                    ),
                  if (rows.length > 20)
                    VitalButton.secondary(
                      onPressed: () => setState(() => offset += 20),
                      child: Text(t.more),
                    ),
                ],
              ),
            ],
          ),
        );
  }
}

class StockNoticeSettings extends ConsumerStatefulWidget {
  const StockNoticeSettings({
    super.key,
    required this.container,
    required this.personRevision,
  });
  final StoredStockContainer container;
  final int personRevision;
  @override
  ConsumerState<StockNoticeSettings> createState() =>
      _StockNoticeSettingsState();
}

class _StockNoticeSettingsState extends ConsumerState<StockNoticeSettings> {
  bool busy = false;
  String? error;
  ({
    String command,
    String personId,
    String containerId,
    int revision,
    int personRevision,
    bool refill,
    String generation,
    ExactAmount? threshold,
  })?
  pending;
  Future<void> save(bool refill) async {
    if (busy) return;
    final t = AppLocalizations.of(context);
    pending ??= (
      command: newCommandId(),
      personId: widget.container.personId,
      containerId: widget.container.id,
      revision: widget.container.revision,
      personRevision: widget.personRevision,
      refill: refill,
      generation: ref.read(recordStoreProvider).requireValue.generation,
      threshold: widget.container.lowThreshold,
    );
    final action = pending!;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      await store.configureStockNotices(
        commandId: action.command,
        personId: action.personId,
        expectedPersonRevision: action.personRevision,
        containerId: action.containerId,
        expectedContainerRevision: action.revision,
        expectedGeneration: action.generation,
        lowThreshold: action.threshold,
        refillEnabled: action.refill,
      );
      pending = null;
    } catch (e) {
      if (e is CommandConflict) pending = null;
      if (mounted) {
        setState(
          () => error = e is CommandConflict
              ? t.conflictFailure
              : t.stockNoticeFailure,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsToggleRow(
          label: t.stockRefill,
          description: t.stockRefillHelp,
          value: widget.container.refillEnabled,
          enabled: !busy && pending == null,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          onChanged: save,
        ),
        if (widget.container.lowThreshold != null) ...[
          const SizedBox(height: 10),
          Text(
            t.stockThresholdValue(
              stockAmountText(
                t,
                widget.container.lowThreshold!,
                widget.container.unit,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: VitalButton.secondary(
            onPressed: busy || pending != null
                ? null
                : () => context.push(
                    '/stock/${widget.container.personId}/adjust/${widget.container.id}?notices=true',
                  ),
            child: Text(t.edit),
          ),
        ),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        if (pending != null)
          VitalButton.secondary(
            onPressed: busy ? null : () => save(pending!.refill),
            child: Text(t.retry),
          ),
      ],
    );
  }
}
