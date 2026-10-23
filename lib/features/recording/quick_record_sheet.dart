import '../stock/stock_widgets.dart' show stockRecordAmountNumber;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import '../substances/substance_collection.dart';
import 'barcode_scan_panel.dart';
import 'quick_entry_context.dart';
import 'record_pages.dart';

/// One task route: searchable identity choice, minimal creation or the existing
/// durable dose editor. Changing steps never stacks task sheets.
class QuickRecordSheet extends ConsumerStatefulWidget {
  const QuickRecordSheet({super.key, required this.location});
  final String location;
  @override
  ConsumerState<QuickRecordSheet> createState() => _QuickRecordSheetState();
}

class _QuickRecordSheetState extends ConsumerState<QuickRecordSheet> {
  final search = TextEditingController();
  late QuickEntryContext entry;
  int offset = 0;
  String? acceptedLocation;
  String? storeGeneration;
  bool navigating = false, seeding = false, stale = false, scanning = false;

  @override
  void initState() {
    super.initState();
    entry = QuickEntryContext.parse(widget.location);
    storeGeneration = ref.read(recordStoreProvider).value?.generation;
    _seed();
    search.addListener(_searchChanged);
  }

  @override
  void didUpdateWidget(QuickRecordSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location == widget.location) return;
    entry = QuickEntryContext.parse(widget.location);
    acceptedLocation = null;
    navigating = false;
    stale = false;
    scanning = false;
    _seed();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _seed() {
    final uri = Uri.tryParse(widget.location);
    final seed = uri == null ? (query: '', offset: 0) : quickEntryListSeed(uri);
    seeding = true;
    search.text = seed.query;
    seeding = false;
    offset = seed.offset;
  }

  void _searchChanged() {
    if (seeding) return;
    setState(() {
      offset = 0;
      stale = false;
    });
  }

  /// One replacement navigation per tap. A locked, non-current or replaced
  /// dataset route never advances, and a double tap cannot queue a second task.
  bool _go(String location) {
    if (navigating || !mounted) return false;
    if (ref.read(appLockProvider).locked) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final generation = ref.read(recordStoreProvider).value?.generation;
    if (generation == null) return false;
    if (storeGeneration == null) {
      storeGeneration = generation;
    } else if (storeGeneration != generation) {
      setState(() {
        storeGeneration = generation;
        stale = true;
        offset = 0;
      });
      return false;
    }
    setState(() {
      navigating = true;
      stale = false;
    });
    context.replace(location);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => navigating = false);
    });
    return true;
  }

  VoidCallback _guardAction(VoidCallback action) {
    final store = ref.read(recordStoreProvider).value;
    final lock = ref.read(appLockProvider);
    return () {
      if (!mounted ||
          lock.locked ||
          !identical(ref.read(appLockProvider), lock) ||
          !identical(ref.read(recordStoreProvider).value, store) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      action();
    };
  }

  void _accept() {
    if (navigating) return;
    if (ref.read(appLockProvider).locked) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    setState(() => acceptedLocation = widget.location);
  }

  void _listenForStoreReplacement() {
    ref.listen(recordStoreProvider.select((value) => value.value?.generation), (
      previous,
      next,
    ) {
      if (next == null || previous == next) return;
      if (storeGeneration == null) {
        storeGeneration = next;
        return;
      }
      if (!mounted) return;
      setState(() {
        storeGeneration = next;
        stale = true;
        offset = 0;
      });
    });
  }

  String _issueText(AppLocalizations t, QuickEntryIssue issue) =>
      switch (issue) {
        QuickEntryIssue.invalidLocation => t.batch15T12LinkInvalid,
        QuickEntryIssue.duplicateDay ||
        QuickEntryIssue.duplicateTime ||
        QuickEntryIssue.duplicateItem => t.batch15T12DuplicateOption,
        QuickEntryIssue.invalidDay => t.batch15T12DayInvalid,
        QuickEntryIssue.invalidTime => t.batch15T12TimeInvalid,
        QuickEntryIssue.timeWithoutPlan => t.batch15T12TimeWithoutPlan,
        QuickEntryIssue.invalidItem =>
          entry.createNew || entry.plan
              ? t.batch15T12ItemInvalidTask
              : t.batch15T12ItemInvalid,
        QuickEntryIssue.invalidNewFlag ||
        QuickEntryIssue.invalidPlanFlag => t.batch15T12OptionInvalid,
        QuickEntryIssue.newAndItem => t.batch15T12ChoiceItemNew,
        QuickEntryIssue.planAndItem => t.batch15T12ChoiceItemPlan,
      };

  List<Widget> _issueMessages(AppLocalizations t) => [
    for (final issue in entry.issues)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(liveRegion: true, child: Text(_issueText(t, issue))),
      ),
  ];

  Widget _staleNotice(AppLocalizations t) => stale
      ? Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(liveRegion: true, child: Text(t.batch15T12Stale)),
        )
      : const SizedBox.shrink();

  Widget _issuePage(AppLocalizations t) => EntryPage(
    panelled: false,
    children: [
      Heading(t.batch15T12LinkHeading),
      ..._issueMessages(t),
      if (stale) _staleNotice(t),
      const SizedBox(height: 8),
      VitalButton(
        onPressed: navigating ? null : _guardAction(_accept),
        child: Text(t.batch15T12Continue),
      ),
    ],
  );

  Widget _choicePage(AppLocalizations t) {
    Widget action(String label, String location, {bool primary = false}) {
      final onPressed = _guardAction(() => _go(location));
      return primary
          ? VitalButton(onPressed: onPressed, child: Text(label))
          : VitalButton.secondary(onPressed: onPressed, child: Text(label));
    }

    return EntryPage(
      panelled: false,
      children: [
        Heading(t.batch15T12LinkHeading),
        ..._issueMessages(t),
        if (stale) _staleNotice(t),
        const SizedBox(height: 8),
        if (entry.createNew) ...[
          action(
            t.create,
            quickEntryCreateLocation(entry),
            primary: entry.createNew,
          ),
          const SizedBox(height: 8),
        ],
        if (entry.plan && entry.itemId != null) ...[
          action(
            t.batch15T12PlanAction,
            quickEntryPlanLocation(entry),
            primary: !entry.createNew,
          ),
          const SizedBox(height: 8),
        ],
        if (entry.itemId != null)
          action(
            t.record,
            quickEntryRecordLocation(entry),
            primary: !entry.createNew && !entry.plan,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (entry.hasIssues && acceptedLocation != widget.location) {
      return entry.needsChoice ? _choicePage(t) : _issuePage(t);
    }
    if (entry.createNew) {
      return ItemForm(
        key: ValueKey(widget.location),
        quick: true,
        day: entry.day,
        plan: entry.plan,
        initialTime: entry.time,
      );
    }
    if (entry.itemId case final id?) {
      return DoseForm(
        key: ValueKey(widget.location),
        itemId: id,
        initialDay: entry.day,
        returnLocation: '/today',
      );
    }
    _listenForStoreReplacement();
    if (scanning) {
      return EntryPage(
        panelled: false,
        children: [
          BarcodeScanPanel(
            onUse: (item) => _go(
              entry.plan
                  ? quickEntryPlanLocation(entry, itemId: item.id)
                  : quickEntryRecordLocation(entry, itemId: item.id),
            ),
            onClose: () {
              if (!mounted || ref.read(appLockProvider).locked) return;
              setState(() => scanning = false);
            },
          ),
        ],
      );
    }
    final query = SubstancesPageQuery(
      scope: const FeedScope.me(),
      search: search.text.trim(),
      typeId: '',
      offset: offset,
    );
    final items = ref.watch(substancesPageProvider(query));
    return EntryPage(
      panelled: false,
      children: [
        Heading(entry.plan ? t.dashboardPlanTitle : t.dashboardQuickTitle),
        Text(
          entry.plan ? t.dashboardPlanHelp : t.dashboardQuickHelp,
          style: StitchType.caption,
        ),
        if (stale) _staleNotice(t),
        const SizedBox(height: 16),
        LabelledInput(label: t.search, controller: search),
        const SizedBox(height: 8),
        VitalButton.secondary(
          leading: const Icon(LucideIcons.scanBarcode),
          onPressed: _guardAction(() => setState(() => scanning = true)),
          child: Text(t.finishR04Scan),
        ),
        const SizedBox(height: 8),
        VitalButton.secondary(
          leading: const Icon(LucideIcons.plus),
          onPressed: _guardAction(() => _go(quickEntryCreateLocation(entry))),
          child: Text(t.create),
        ),
        const SizedBox(height: 16),
        if (items.isLoading)
          Text(t.loadingRecords)
        else if (items.hasError)
          LoadFailure(
            onRetry: () => ref.invalidate(substancesPageProvider(query)),
          )
        else ...[
          for (final item in items.requireValue.take(quickEntryPageSize)) ...[
            VitalButton.secondary(
              multiline: true,
              onPressed: _guardAction(
                () => _go(
                  entry.plan
                      ? quickEntryPlanLocation(entry, itemId: item.id)
                      : quickEntryRecordLocation(entry, itemId: item.id),
                ),
              ),
              child: Text(item.name),
            ),
            const SizedBox(height: 8),
          ],
          if (items.requireValue.isEmpty)
            Text(t.historyNoOptions, style: StitchType.caption),
          if (items.requireValue.length > quickEntryPageSize)
            VitalButton.secondary(
              onPressed: () => setState(() => offset += quickEntryPageSize),
              child: Text(t.more),
            ),
          if (offset > 0)
            VitalButton.secondary(
              onPressed: () => setState(
                () => offset = (offset - quickEntryPageSize).clamp(0, offset),
              ),
              child: Text(t.back),
            ),
        ],
      ],
    );
  }
}

typedef UnplannedDay = ({CivilDate day, String zone, int limit});
final unplannedDayProvider = StreamProvider.autoDispose
    .family<List<UseRecord>, UnplannedDay>(retry: (_, _) => null, (
      ref,
      request,
    ) async* {
      final store = await ref.watch(recordStoreProvider.future);
      final bounds = DisplayTime().dayBounds(request.day, request.zone);
      yield* store.watchUnplannedUses(
        from: bounds.start,
        before: bounds.endExclusive,
        limit: request.limit,
      );
    });

class UnplannedMedication extends ConsumerStatefulWidget {
  const UnplannedMedication({
    super.key,
    required this.day,
    required this.today,
  });
  final CivilDate day, today;
  @override
  ConsumerState<UnplannedMedication> createState() =>
      _UnplannedMedicationState();
}

class _UnplannedMedicationState extends ConsumerState<UnplannedMedication> {
  int limit = 51;
  @override
  void didUpdateWidget(UnplannedMedication oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day != widget.day) limit = 51;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final query = (
      day: widget.day,
      zone: ref.watch(displayZoneProvider),
      limit: limit,
    );
    final records = ref.watch(unplannedDayProvider(query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StitchSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(t.dashboardUnplanned, style: StitchType.name),
                  ),
                  Semantics(
                    label: t.dashboardUnplannedHelp,
                    button: true,
                    child: StitchButton(
                      quiet: true,
                      compact: true,
                      onPressed: () => showVitalDialog<void>(
                        context: context,
                        builder: (context) => VitalDialog(
                          title: Text(t.dashboardUnplanned),
                          content: Text(t.dashboardUnplannedHelp),
                          actions: [
                            VitalButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(t.done),
                            ),
                          ],
                        ),
                      ),
                      child: const Icon(LucideIcons.info, size: 20),
                    ),
                  ),
                ],
              ),
              Text(
                t.dashboardUnplannedSubtitle,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
              const SizedBox(height: 8),
              if (records.isLoading)
                Text(t.loadingRecords, style: StitchType.caption)
              else if (records.hasError)
                LoadFailure(
                  onRetry: () => ref.invalidate(unplannedDayProvider(query)),
                )
              else if (records.requireValue.isEmpty)
                Text(
                  widget.day == widget.today
                      ? t.dashboardUnplannedEmptyToday
                      : t.dashboardUnplannedEmptyDay,
                  style: StitchType.caption.copyWith(color: c.muted),
                )
              else
                for (final record in records.requireValue.take(limit - 1)) ...[
                  StitchSurface(
                    inset: true,
                    padding: EdgeInsets.zero,
                    radius: VitalLayout.sectionRadius,
                    child: VitalCompactRow(
                      title: record.name,
                      subtitle:
                          '${stockRecordAmountNumber(t, record)} ${record.actualUnit}',
                      onPressed: () => context.push('/correct/${record.id}'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              if (records.hasValue &&
                  !records.isLoading &&
                  records.requireValue.length == limit)
                if (limit < 500)
                  VitalButton.secondary(
                    onPressed: () =>
                        setState(() => limit = (limit + 50).clamp(1, 500)),
                    child: Text(t.more),
                  )
                else
                  VitalButton.secondary(
                    onPressed: () => context.push('/history'),
                    child: Text(t.history),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StitchButton(
          outlined: true,
          icon: LucideIcons.plus,
          onPressed: () => context.push('/unplanned?day=${widget.day}'),
          child: Text(t.add),
        ),
      ],
    );
  }
}
