import 'package:flutter/services.dart' show TextInputAction;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart' show LoadFailure;
import '../../ui/vital_ui.dart';
import '../catalogue/item_types.dart' show itemTypeProvider;
import 'substance_summary.dart';

/// One page key of the bounded Substances list. The 51st row of a page only
/// reveals the next page; search and the type filter run over the whole stored
/// collection at the store, not over a loaded subset.
typedef SubstancesPageQuery = ({
  FeedScope scope,
  String search,
  String typeId,
  int offset,
});

final substancesPageProvider = StreamProvider.autoDispose
    .family<List<SubstanceItem>, SubstancesPageQuery>(retry: (_, _) => null, (
      ref,
      query,
    ) async* {
      yield* (await ref.watch(recordStoreProvider.future)).watchItems(
        scope: query.scope,
        search: query.search,
        typeId: query.typeId.isEmpty ? null : query.typeId,
        limit: 51,
        offset: query.offset,
      );
    });

typedef SubstancesTypeQuery = ({FeedScope scope, String search});

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
  // Fallback name while the selected type's live lookup loads. The separate
  // lookup keeps renames visible even when search-constrained counts omit it.
  String? _typeName;
  int _pages = 1;

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
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _search.clear();
      _typeId = '';
      _typeName = null;
      _pages = 1;
    });
  }

  void _selectType(String typeId, String typeName) => setState(() {
    _typeId = typeId;
    _typeName = typeId.isEmpty ? null : typeName;
    _pages = 1;
  });

  void _retry() {
    ref.invalidate(substancesPageProvider);
    ref.invalidate(substanceTypesProvider);
    setState(() => _pages = 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final search = _search.text.trim();
    final pages = [
      for (var page = 0; page < _pages; page++)
        ref.watch(
          substancesPageProvider((
            scope: widget.scope,
            search: search,
            typeId: _typeId,
            offset: page * 50,
          )),
        ),
    ];
    final summaries = ref.watch(
      substanceTypesProvider((scope: widget.scope, search: search)),
    );
    final personId = widget.scope.personId;
    final selectedType = _typeId.isEmpty || personId == null
        ? null
        : ref.watch(itemTypeProvider((personId: personId, typeId: _typeId)));
    final filtered = search.isNotEmpty || _typeId.isNotEmpty;
    // Search and the active type filter stay visible while data fails, so a
    // failure never removes the user's controls or hides why results are
    // absent; the retry sits with the result area below the tools.
    final failed = pages.any((p) => p.hasError) || summaries.hasError;
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
        VitalField(
          label: t.designSubstancesSearchLabel,
          child: TextField(
            controller: _search,
            placeholder: Text(t.designSubstancesSearchHint),
            textInputAction: TextInputAction.search,
          ),
        ),
        const SizedBox(height: 16),
        SubstanceTypeFilters(
          summaries: summaries.value ?? const [],
          selectedTypeId: _typeId,
          selectedTypeName: selectedType?.value?.name ?? _typeName,
          countsKnown:
              summaries.hasValue && !summaries.isLoading && !summaries.hasError,
          onSelected: _selectType,
        ),
        const SizedBox(height: 16),
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
      return '$name (${t.designSubstancesItemCount(count)})';
    }

    return VitalSegments<String>(
      values: ['', ...pills.map((pill) => pill.typeId!)],
      selected: selectedTypeId,
      onChanged: (typeId) =>
          onSelected(typeId, typeId.isEmpty ? '' : names[typeId]!),
      label: label,
    );
  }
}

/// Compact identity card. The whole identity row opens the substance's
/// existing detail/history URL, the current primary destination; lead
/// integration repoints it to /substance/:id when the D04 overview returns.
/// Record, combined, schedule, stock and history actions stay reachable.
class SubstanceIdentityCard extends StatelessWidget {
  const SubstanceIdentityCard({super.key, required this.item});
  final SubstanceItem item;

  void _open(BuildContext context) => context.push('/item/${item.id}');

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: VitalSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VitalCompactRow(
              title: item.name,
              subtitle: t.itemDetails(item.form, item.type, item.unit),
              trailing: const Icon(LucideIcons.chevronRight),
              icon: LucideIcons.pill,
              onPressed: () => _open(context),
            ),
            const SizedBox(height: 12),
            SubstanceSummary(item: item),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                VitalButton(
                  onPressed: () => context.push('/record/${item.id}'),
                  child: Text(t.record),
                ),
                VitalButton.secondary(
                  onPressed: () => context.push(
                    '/combined/${item.personId}?item=${item.id}',
                  ),
                  child: Text(t.combinedAction),
                ),
                VitalButton.secondary(
                  onPressed: () => context.push('/schedule/${item.id}'),
                  child: Text(t.schedule),
                ),
                VitalButton.secondary(
                  onPressed: () =>
                      context.push('/stock/${item.personId}?item=${item.id}'),
                  child: Text(t.stock),
                ),
                VitalButton.secondary(
                  onPressed: () => context.push('/item/${item.id}'),
                  child: Text(t.history),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
