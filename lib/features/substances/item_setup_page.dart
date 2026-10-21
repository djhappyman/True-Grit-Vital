import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import '../stock/stock_providers.dart';
import 'substance_detail_providers.dart';
import 'substance_overview.dart' show overviewPlansProvider;

/// Resumable, optional steps after identity creation.
///
/// The identity is already committed. Schedule and opening stock open the
/// existing editors, including their previews, drafts and save guards. An
/// explicit skip only records that choice; it never creates a plan or a stock
/// container. Details stay user-authored and private.
class ItemSetupPage extends ConsumerStatefulWidget {
  const ItemSetupPage({super.key, required this.itemId});
  final String itemId;
  @override
  ConsumerState<ItemSetupPage> createState() => _ItemSetupPageState();
}

class _ItemSetupPageState extends ConsumerState<ItemSetupPage> {
  bool busy = false;
  String? error;
  String? capturedGeneration;

  Future<void> _update({
    bool skipSchedule = false,
    bool skipStock = false,
    bool skipDetails = false,
    bool complete = false,
    required AdultProfile owner,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      if (capturedGeneration == null ||
          capturedGeneration != store.generation) {
        throw const CommandConflict('generation');
      }
      await store.updateItemSetup(
        commandId: newCommandId(),
        expectedGeneration: capturedGeneration,
        itemId: widget.itemId,
        expectedPersonRevision: owner.revision,
        skipSchedule: skipSchedule,
        skipStock: skipStock,
        skipDetails: skipDetails,
        complete: complete,
      );
      if (complete && mounted) {
        context.go('/substance/${widget.itemId}');
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = AppLocalizations.of(context).saveFailure);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _step({
    required String title,
    required IconData icon,
    required String help,
    required bool ready,
    required bool skipped,
    required String addedLabel,
    required String skippedLabel,
    required VoidCallback? onAdd,
    required VoidCallback? onSkip,
  }) {
    final t = AppLocalizations.of(context);
    return VitalPanel(
      title: title,
      icon: icon,
      action: ready
          ? VitalBadge(
              skipped && addedLabel.isEmpty ? skippedLabel : addedLabel,
              tone: skipped ? VitalTone.neutral : VitalTone.positive,
            )
          : null,
      children: [
        Text(
          help,
          style: VitalType.metadata.copyWith(
            color: Theme.of(context).colorScheme.mutedForeground,
          ),
        ),
        if (!ready)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VitalButton(onPressed: busy ? null : onAdd, child: Text(t.add)),
              VitalButton.secondary(
                onPressed: busy ? null : onSkip,
                child: Text(t.featureSetupSkip),
              ),
            ],
          )
        else if (onAdd != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VitalButton.secondary(
              onPressed: busy ? null : onAdd,
              child: Text(t.edit),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final people = ref.watch(profilesProvider);
    final item = ref.watch(itemLookupProvider(widget.itemId));
    final setup = ref.watch(itemSetupProvider(widget.itemId));
    final plans = ref.watch(
      overviewPlansProvider((
        itemId: widget.itemId,
        scope: FeedScope.person(meId),
      )),
    );
    final stock = ref.watch(
      stockContainersProvider((
        personId: meId,
        itemId: widget.itemId,
        offset: 0,
      )),
    );
    final detail = ref.watch(itemDetailProvider(widget.itemId));
    if (people.hasError ||
        item.hasError ||
        setup.hasError ||
        plans.hasError ||
        stock.hasError ||
        detail.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(itemLookupProvider(widget.itemId));
              ref.invalidate(itemSetupProvider(widget.itemId));
              ref.invalidate(overviewPlansProvider);
              ref.invalidate(stockContainersProvider);
              ref.invalidate(itemDetailProvider(widget.itemId));
            },
          ),
        ],
      );
    }
    if (!people.hasValue ||
        !item.hasValue ||
        !setup.hasValue ||
        !plans.hasValue ||
        !stock.hasValue ||
        !detail.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final owner = people.value!
        .where((person) => person.id == meId)
        .firstOrNull;
    final saved = item.value;
    if (owner == null || saved == null || saved.personId != meId) {
      return EntryPage(children: [Text(t.noItem)]);
    }
    final state = setup.value;
    final generation = ref.watch(recordStoreProvider).value?.generation;
    capturedGeneration ??= generation;
    if (generation == null ||
        capturedGeneration != generation ||
        owner.isArchived) {
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    final planAdded = plans.value!.isNotEmpty;
    final stockAdded = stock.value!.isNotEmpty;
    final detailsAdded = detail.value?.isEmpty == false;
    final scheduleSkipped = state?.scheduleSkipped ?? false;
    final stockSkipped = state?.stockSkipped ?? false;
    final detailsSkipped = state?.detailsSkipped ?? false;
    final scheduleReady = planAdded || scheduleSkipped;
    final stockReady = stockAdded || stockSkipped;
    final detailsReady = detailsAdded || detailsSkipped;
    final complete = scheduleReady && stockReady && detailsReady;
    return EntryPage(
      children: [
        Heading(t.featureSetupTitle),
        Text(saved.name, style: VitalType.record),
        Text(
          t.featureSetupIdentitySaved(
            saved.form.isEmpty ? saved.unit : '${saved.form} · ${saved.unit}',
          ),
        ),
        Text(
          t.featureSetupIdentityHelp,
          style: VitalType.metadata.copyWith(
            color: Theme.of(context).colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 20),
        _step(
          title: t.schedule,
          icon: LucideIcons.calendarClock,
          help: t.featureSetupScheduleHelp,
          ready: scheduleReady,
          skipped: scheduleSkipped && !planAdded,
          addedLabel: planAdded ? t.featureSetupAdded : '',
          skippedLabel: t.featureSetupSkipped,
          onAdd: () => context.push('/schedule/${saved.id}?setup=true'),
          onSkip: () => _update(skipSchedule: true, owner: owner),
        ),
        const SizedBox(height: 12),
        _step(
          title: t.stock,
          icon: LucideIcons.package,
          help: t.featureSetupStockHelp,
          ready: stockReady,
          skipped: stockSkipped && !stockAdded,
          addedLabel: stockAdded ? t.featureSetupAdded : '',
          skippedLabel: t.featureSetupSkipped,
          onAdd: () => context.push(
            '/stock/${saved.personId}/create?item=${saved.id}&setup=true',
          ),
          onSkip: () => _update(skipStock: true, owner: owner),
        ),
        const SizedBox(height: 12),
        _step(
          title: t.featureSetupDetails,
          icon: LucideIcons.notebookPen,
          help: t.featureSetupDetailsHelp,
          ready: detailsReady,
          skipped: detailsSkipped && !detailsAdded,
          addedLabel: detailsAdded ? t.featureSetupAdded : '',
          skippedLabel: t.featureSetupSkipped,
          onAdd: () =>
              context.push('/substance/${saved.id}/details?setup=true'),
          onSkip: () => _update(skipDetails: true, owner: owner),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(error!)),
        ],
        const SizedBox(height: 20),
        VitalButton(
          onPressed: busy
              ? null
              : complete
              ? () => _update(complete: true, owner: owner)
              : null,
          child: Text(t.featureSetupFinish),
        ),
        const SizedBox(height: 8),
        VitalButton.secondary(
          onPressed: busy ? null : () => context.go('/substance/${saved.id}'),
          child: Text(t.cancel),
        ),
      ],
    );
  }
}
