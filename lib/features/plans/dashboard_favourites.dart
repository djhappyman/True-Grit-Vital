import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import 'dashboard_week.dart';
import 'plan_providers.dart';
import 'today_hero.dart';

/// Persisted quick-record choices. Only plan identities are stored: names,
/// amounts and pause state always come from the live plan so a changed plan
/// cannot keep showing a stale shortcut.
class DashboardFavourites {
  const DashboardFavourites({
    this.planIds = const [],
    this.loaded = false,
    this.busy = false,
    this.failed = false,
  });
  final List<String> planIds;
  final bool loaded, busy, failed;
}

/// Decodes the closed settings record. A malformed record is a load failure,
/// not an empty selection: silently replacing it would lose saved choices.
List<String> decodeDashboardFavouriteIds(String raw) {
  final data = jsonDecode(raw);
  if (data is! Map<String, dynamic>) {
    throw const FormatException('dashboard_favourites');
  }
  final ids = data['planIds'];
  if (ids is! List) throw const FormatException('dashboard_favourites');
  final seen = <String>{};
  final result = <String>[];
  for (final id in ids) {
    if (id is! String || id.isEmpty) {
      throw const FormatException('dashboard_favourites');
    }
    if (seen.add(id)) result.add(id);
  }
  return List.unmodifiable(result);
}

final dashboardFavouritesProvider =
    NotifierProvider<DashboardFavouritesController, DashboardFavourites>(
      DashboardFavouritesController.new,
    );

/// Writes through an exact captured record store and the commit fence supplied
/// by the controller, so a delayed queued write cannot land in a restored
/// dataset or publish across a lock cycle.
typedef DashboardFavouritesWriter = Future<void> Function(
  RecordStore store,
  String value,
  bool Function() canCommit,
);

final dashboardFavouritesWriterProvider = Provider<DashboardFavouritesWriter>(
  (ref) =>
      (store, value, canCommit) => store.writeSetting(
        'dashboard_favourites',
        value,
        canCommit: canCommit,
      ),
);

class DashboardFavouritesController extends Notifier<DashboardFavourites> {
  // The notifier survives a record-store replacement (restore). Delayed reads
  // and writes from a replaced dataset are fenced by epoch, and saves serialise
  // on this shared notifier, mirroring DisplayPreferencesController. The lock
  // epoch additionally retires a write that spans a lock/unlock cycle.
  int _epoch = 0, _lockEpoch = 0;
  bool _saving = false;
  Completer<void>? _saveSettled;

  @override
  DashboardFavourites build() {
    ref.listen(appLockProvider.select((state) => state.locked), (
      previous,
      next,
    ) {
      if (previous != next) _lockEpoch++;
    });
    final record = ref.watch(recordStoreProvider);
    final store = (record.isLoading || record.hasError) ? null : record.value;
    final epoch = ++_epoch;
    if (store != null) {
      scheduleMicrotask(() async {
        try {
          // A read issued while a publication is in flight would return the
          // value that write is about to replace; wait, then read freshly.
          while (_saving && ref.mounted && epoch == _epoch) {
            final settled = _saveSettled;
            if (settled == null) break;
            await settled.future;
          }
          if (!ref.mounted || epoch != _epoch) return;
          final raw = await store.readSetting('dashboard_favourites');
          if (!ref.mounted || epoch != _epoch) return;
          state = DashboardFavourites(
            planIds: raw == null ? const [] : decodeDashboardFavouriteIds(raw),
            loaded: true,
          );
        } catch (_) {
          if (ref.mounted && epoch == _epoch) {
            state = const DashboardFavourites(loaded: true, failed: true);
          }
        }
      });
    }
    return DashboardFavourites(busy: _saving);
  }

  /// Persists [planIds] in order. Returns true only when this dataset and lock
  /// generation accepted the write; a lock, a replaced dataset or a storage
  /// failure returns false and restores the last committed selection.
  Future<bool> save(List<String> planIds) async {
    if (_saving || ref.read(appLockProvider).locked) return false;
    final record = ref.read(recordStoreProvider);
    final store = (record.isLoading || record.hasError) ? null : record.value;
    if (store == null) return false;
    final previous = state.planIds, epoch = ++_epoch, lockEpoch = _lockEpoch;
    final settled = _saveSettled = Completer<void>();
    _saving = true;
    state = DashboardFavourites(
      planIds: List.unmodifiable(planIds),
      loaded: true,
      busy: true,
    );
    bool current() =>
        ref.mounted &&
        epoch == _epoch &&
        lockEpoch == _lockEpoch &&
        !ref.read(appLockProvider).locked;
    var saved = false;
    try {
      await ref.read(dashboardFavouritesWriterProvider)(
        store,
        jsonEncode({'planIds': planIds}),
        current,
      );
      if (current()) {
        state = DashboardFavourites(
          planIds: List.unmodifiable(planIds),
          loaded: true,
        );
        saved = true;
      }
    } catch (_) {
      if (ref.mounted && epoch == _epoch) {
        state = DashboardFavourites(
          planIds: previous,
          loaded: true,
          failed: true,
        );
      }
    } finally {
      _saving = false;
      _saveSettled = null;
      if (ref.mounted && state.busy) {
        state = DashboardFavourites(
          planIds: state.planIds,
          loaded: state.loaded,
          failed: state.failed,
        );
      }
      settled.complete();
    }
    return saved;
  }
}

/// The dashboard quick-record row and its real configuration entry point.
///
/// Saved choices keep their order. Deleted, changed or no-longer-as-needed
/// plans are reported rather than silently replaced. Recording always opens
/// the existing record route, so review and stock/strength checks stay intact.
class DashboardQuickRecord extends ConsumerWidget {
  const DashboardQuickRecord({super.key, required this.scope});
  final FeedScope scope;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final plans = ref.watch(allScopePlansProvider(scope));
    final saved = ref.watch(dashboardFavouritesProvider);
    final collection = plans.value;
    final prn = collection?.asNeeded ?? const <SavedDailyPlan>[];
    final selection = dashboardFavouriteSelection(saved.planIds, prn);
    final showEveryPlan = saved.planIds.isEmpty;
    final shown = showEveryPlan ? prn : selection.plans;
    final now = ref.watch(todayNowProvider)();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.planAsNeeded,
                style: StitchType.small.copyWith(
                  color: StitchColors(context).muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            StitchButton(
              quiet: true,
              compact: true,
              onPressed: collection == null
                  ? null
                  : () => showDashboardFavouritesDialog(context, collection),
              child: Text(
                t.stitchConfigure,
                style: StitchType.small.copyWith(
                  color: StitchColors(context).accent,
                ),
              ),
            ),
          ],
        ),
        if (plans.hasError || saved.failed) ...[
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: Text(
              plans.hasError
                  ? t.featureWeekPlansLoadFailure
                  : t.featureWeekFavouriteLoadFailure,
              style: StitchType.caption.copyWith(
                color: StitchColors(context).amber,
              ),
            ),
          ),
          StitchButton(
            quiet: true,
            compact: true,
            onPressed: () {
              if (plans.hasError) {
                ref.invalidate(allScopePlansProvider(scope));
              } else {
                ref.invalidate(dashboardFavouritesProvider);
              }
            },
            child: Text(t.retry),
          ),
        ],
        const SizedBox(height: 4),
        if (collection == null)
          plans.isLoading
              ? Text(
                  t.loadingRecords,
                  style: StitchType.caption.copyWith(
                    color: StitchColors(context).muted,
                  ),
                )
              : const SizedBox.shrink()
        else if (shown.isEmpty)
          Text(
            prn.isEmpty
                ? t.featureWeekNoAsNeeded
                : t.featureWeekFavouriteUnavailable(selection.unavailable),
            style: StitchType.caption.copyWith(
              color: StitchColors(context).muted,
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in shown)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _QuickRecordChip(entry: entry, now: now),
                  ),
                const _ObservationChip(),
              ],
            ),
          ),
        if (shown.isEmpty) ...[
          const SizedBox(height: 4),
          const _ObservationChip(),
        ],
        if (!showEveryPlan &&
            selection.unavailable > 0 &&
            shown.isNotEmpty) ...[
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: Text(
              t.featureWeekFavouriteUnavailable(selection.unavailable),
              style: StitchType.caption.copyWith(
                color: StitchColors(context).amber,
              ),
            ),
          ),
        ],
        if (collection != null && !collection.complete) ...[
          const SizedBox(height: 4),
          Text(
            t.featureWeekFavouriteListIncomplete,
            style: StitchType.caption.copyWith(
              color: StitchColors(context).amber,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickRecordChip extends ConsumerWidget {
  const _QuickRecordChip({required this.entry, required this.now});
  final SavedDailyPlan entry;
  final DateTime now;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final item = ref.watch(itemLookupProvider(entry.plan.itemId)).value;
    final paused = entry.plan.pauses.any((pause) => pause.contains(now));
    final label = item?.name ?? t.record;
    return Semantics(
      button: true,
      label: paused ? '$label. ${t.pauseState}' : label,
      onTap: () => context.push('/record/${entry.plan.itemId}'),
      child: ExcludeSemantics(
        child: StitchButton(
          icon: LucideIcons.plus,
          compact: true,
          onPressed: () => context.push('/record/${entry.plan.itemId}'),
          child: Text(paused ? '$label · ${t.pauseState}' : label),
        ),
      ),
    );
  }
}

class _ObservationChip extends StatelessWidget {
  const _ObservationChip();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StitchButton(
      icon: LucideIcons.activity,
      compact: true,
      onPressed: () => context.push('/supporting'),
      child: Text(t.stitchObservation),
    );
  }
}

Future<void> showDashboardFavouritesDialog(
  BuildContext context,
  DashboardPlanCollection collection,
) => showVitalDialog<void>(
  context: context,
  builder: (context) => DashboardFavouritesDialog(collection: collection),
);

/// Chooses a saved subset and order from the complete as-needed collection.
/// The dialog writes nothing until Save; a failed write keeps the dialog open
/// with the last committed selection untouched.
class DashboardFavouritesDialog extends ConsumerStatefulWidget {
  const DashboardFavouritesDialog({super.key, required this.collection});
  final DashboardPlanCollection collection;
  @override
  ConsumerState<DashboardFavouritesDialog> createState() =>
      _DashboardFavouritesDialogState();
}

class _DashboardFavouritesDialogState
    extends ConsumerState<DashboardFavouritesDialog> {
  late List<String> selected;
  late int unavailable;
  bool saving = false;
  bool failed = false;

  Map<String, SavedDailyPlan> get byId => {
    for (final plan in widget.collection.asNeeded) plan.plan.planId: plan,
  };

  @override
  void initState() {
    super.initState();
    final saved = ref.read(dashboardFavouritesProvider).planIds;
    final selection = dashboardFavouriteSelection(
      saved,
      widget.collection.asNeeded,
    );
    selected = [for (final plan in selection.plans) plan.plan.planId];
    unavailable = selection.unavailable;
  }

  void toggle(String id) {
    setState(() {
      failed = false;
      if (selected.contains(id)) {
        selected.remove(id);
      } else {
        selected.add(id);
      }
    });
  }

  void move(String id, int delta) {
    final from = selected.indexOf(id), to = from + delta;
    if (from < 0 || to < 0 || to >= selected.length) return;
    setState(() {
      failed = false;
      final moved = selected.removeAt(from);
      selected.insert(to, moved);
    });
  }

  Future<void> save() async {
    if (saving || !widget.collection.complete) return;
    setState(() {
      saving = true;
      failed = false;
    });
    final ok = await ref
        .read(dashboardFavouritesProvider.notifier)
        .save(selected);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        saving = false;
        failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final plans = widget.collection.asNeeded;
    final chosen = selected.toSet();
    final ordered = [
      for (final id in selected) ?byId[id],
      for (final plan in plans)
        if (!chosen.contains(plan.plan.planId)) plan,
    ];
    return VitalDialog(
      title: Text(t.featureWeekQuickRecord),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.featureWeekFavouritesHelp),
          const SizedBox(height: 4),
          Text(
            t.featureWeekFavouritesEmptyHelp,
            style: StitchType.caption.copyWith(
              color: StitchColors(context).muted,
            ),
          ),
          if (unavailable > 0) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                t.featureWeekFavouritesStale(unavailable),
                style: StitchType.caption.copyWith(
                  color: StitchColors(context).amber,
                ),
              ),
            ),
            Text(
              t.featureWeekFavouritesStaleHelp,
              style: StitchType.caption.copyWith(
                color: StitchColors(context).muted,
              ),
            ),
          ],
          if (!widget.collection.complete) ...[
            const SizedBox(height: 8),
            Text(
              t.featureWeekFavouriteListIncomplete,
              style: StitchType.caption.copyWith(
                color: StitchColors(context).amber,
              ),
            ),
          ],
          if (failed) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                t.featureWeekFavouriteSaveFailure,
                style: StitchType.caption.copyWith(
                  color: StitchColors(context).danger,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (plans.isEmpty)
            Text(
              t.featureWeekNoAsNeeded,
              style: StitchType.body.copyWith(
                color: StitchColors(context).muted,
              ),
            ),
          for (final plan in ordered)
            _FavouriteRow(
              key: ValueKey(plan.plan.planId),
              plan: plan,
              chosen: chosen.contains(plan.plan.planId),
              first: selected.firstOrNull == plan.plan.planId,
              last: selected.lastOrNull == plan.plan.planId,
              enabled: !saving,
              onToggle: () => toggle(plan.plan.planId),
              onUp: () => move(plan.plan.planId, -1),
              onDown: () => move(plan.plan.planId, 1),
            ),
        ],
      ),
      actions: [
        VitalButton.secondary(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        VitalButton.secondary(
          onPressed: saving || selected.isEmpty
              ? null
              : () => setState(() {
                  failed = false;
                  selected.clear();
                }),
          child: Text(t.clear),
        ),
        VitalButton(
          onPressed: saving || !widget.collection.complete ? null : save,
          child: Text(t.save),
        ),
      ],
    );
  }
}

class _FavouriteRow extends ConsumerWidget {
  const _FavouriteRow({
    super.key,
    required this.plan,
    required this.chosen,
    required this.first,
    required this.last,
    required this.enabled,
    required this.onToggle,
    required this.onUp,
    required this.onDown,
  });
  final SavedDailyPlan plan;
  final bool chosen, first, last, enabled;
  final VoidCallback onToggle, onUp, onDown;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final item = ref.watch(itemLookupProvider(plan.plan.itemId)).value;
    final name = item?.name ?? t.record;
    final now = ref.watch(todayNowProvider)();
    final paused = plan.plan.pauses.any((pause) => pause.contains(now));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: VitalLayout.target,
            height: VitalLayout.target,
            child: Center(
              child: Semantics(
                label: t.featureWeekInclude(name),
                child: Checkbox(
                  state: chosen
                      ? CheckboxState.checked
                      : CheckboxState.unchecked,
                  onChanged: enabled ? (_) => onToggle() : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: StitchType.name),
                if (item != null && item.form.isNotEmpty)
                  Text(
                    item.form,
                    style: StitchType.caption.copyWith(
                      color: StitchColors(context).muted,
                    ),
                  ),
                if (paused)
                  Text(
                    t.pauseState,
                    style: StitchType.caption.copyWith(
                      color: StitchColors(context).amber,
                    ),
                  ),
              ],
            ),
          ),
          if (chosen)
            Column(
              children: [
                _OrderButton(
                  icon: LucideIcons.chevronUp,
                  label: t.featureWeekMoveUp,
                  onPressed: enabled && !first ? onUp : null,
                ),
                _OrderButton(
                  icon: LucideIcons.chevronDown,
                  label: t.featureWeekMoveDown,
                  onPressed: enabled && !last ? onDown : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _OrderButton extends StatelessWidget {
  const _OrderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    child: ExcludeSemantics(
      child: StitchButton(
        quiet: true,
        compact: true,
        onPressed: onPressed,
        child: Icon(icon, size: 18),
      ),
    ),
  );
}
