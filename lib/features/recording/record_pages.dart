import '../supporting/supporting_pages.dart';
import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'dart:async';
import 'dart:convert';

import '../catalogue/catalogue_picker.dart';
import '../attachments/attachment_pages.dart';
import '../catalogue/item_types.dart';
import '../stock/stock_providers.dart';
import '../stock/stock_widgets.dart';
import '../products/product_widgets.dart';
import '../products/product_pages.dart';
import '../../app/settings_toggle_row.dart';

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/material.dart' show showDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../app/app_lock.dart';
import 'actual_time.dart';
import '../plans/daily_feed.dart';
import '../plans/interval_review.dart';
import '../plans/interval_clock.dart';
import '../profiles/profile_pages.dart';

import '../../app/vital_app.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/storage_bootstrap.dart';

final actualTimeResolverProvider = Provider<List<DateTime> Function(DateTime)>(
  (ref) => actualTimeCandidates,
);
typedef RecordInput = ({
  String commandId,
  String itemId,
  String amount,
  DateTime actualAt,
  String personId,
  int? expectedPersonRevision,
});
final recordWriterProvider = Provider<Future<UseRecord> Function(RecordInput)>(
  (ref) => (input) async {
    final store = await ref.read(recordStoreProvider.future);
    return store.record(
      commandId: input.commandId,
      itemId: input.itemId,
      amount: input.amount,
      actualAt: input.actualAt,
      personId: input.personId,
      expectedPersonRevision: input.expectedPersonRevision,
    );
  },
);
typedef VoidInput = ({
  String commandId,
  String recordId,
  int expectedRevision,
  String personId,
  int? expectedPersonRevision,
});
final voidWriterProvider = Provider<Future<UseRecord> Function(VoidInput)>(
  (ref) =>
      (input) async => (await ref.read(recordStoreProvider.future)).voidRecord(
        commandId: input.commandId,
        recordId: input.recordId,
        expectedRevision: input.expectedRevision,
        personId: input.personId,
        expectedPersonRevision: input.expectedPersonRevision,
      ),
);
final savedRecordProvider = NotifierProvider<SavedRecordNotice, UseRecord?>(
  SavedRecordNotice.new,
);

class SavedRecordNotice extends Notifier<UseRecord?> {
  @override
  UseRecord? build() => null;
  void set(UseRecord record) => state = record;
}

typedef RecordQuery = ({
  String? itemId,
  DateTime? actualFrom,
  DateTime? actualBefore,
  int limit,
  int offset,
  FeedScope? scope,
});
final pagedRecordsProvider = StreamProvider.autoDispose
    .family<List<UseRecord>, RecordQuery>(retry: (_, _) => null, (
      ref,
      query,
    ) async* {
      final store = await ref.watch(recordStoreProvider.future);
      yield* store.watchRecords(
        itemId: query.itemId,
        scope: query.scope,
        actualFrom: query.actualFrom,
        actualBefore: query.actualBefore,
        limit: query.limit,
        offset: query.offset,
      );
    });
typedef OwnedRecord = ({String recordId, String personId});
final recordLookupProvider = StreamProvider.autoDispose
    .family<UseRecord?, OwnedRecord>(retry: (_, _) => null, (
      ref,
      target,
    ) async* {
      yield* (await ref.watch(recordStoreProvider.future))
          .watchRecordById(target.recordId, target.personId);
    });

class StorageGate extends ConsumerWidget {
  const StorageGate({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppLocalizations.of(context);
    return ref
        .watch(recordStoreProvider)
        .when(
          data: (_) {
            if (child is ProfileForm || ref.watch(setupReadyProvider)) {
              return child;
            }
            return ref
                .watch(profilesProvider)
                .when(
                  skipLoadingOnRefresh: false,
                  data: (people) {
                    final me = people.where((p) => p.isMe).firstOrNull;
                    if (me != null && !me.adultConfirmed) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) context.go('/profile');
                      });
                      return Scaffold(
                        child: PageContent(
                          children: [Text(text.loadingRecords)],
                        ),
                      );
                    }
                    return child;
                  },
                  error: (_, _) => Scaffold(
                    child: PageContent(
                      children: [
                        LoadFailure(
                          onRetry: () => ref.invalidate(profilesProvider),
                        ),
                      ],
                    ),
                  ),
                  loading: () => Scaffold(
                    child: PageContent(children: [Text(text.loadingRecords)]),
                  ),
                );
          },
          loading: () => Scaffold(
            child: PageContent(children: [Text(text.loadingRecords)]),
          ),
          error: (error, _) => Scaffold(
            child: PageContent(
              children: [
                Heading(
                  error is StorageBootstrapException &&
                          error.code == 'linux_keyring_unavailable'
                      ? text.keyringTitle
                      : text.recoveryTitle,
                ),
                Text(
                  error is StorageBootstrapException &&
                          error.code == 'unsupported_host'
                      ? text.unsupportedBody
                      : error is StorageBootstrapException &&
                            error.code == 'linux_keyring_unavailable'
                      ? text.keyringBody
                      : error is StateError &&
                            error.message == 'single_user_required'
                      ? text.singleUserRequired
                      : text.recoveryBody,
                ),
                const SizedBox(height: 20),
                VitalButton(
                  onPressed: () => ref.invalidate(recordStoreProvider),
                  child: Text(text.retry),
                ),
              ],
            ),
          ),
        );
  }
}

/// Compatibility entry point for existing feature imports.
class Heading extends StatelessWidget {
  const Heading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 16),
    child: Semantics(header: true, child: Text(text, style: VitalType.section)),
  );
}

class EntryPage extends StatelessWidget {
  const EntryPage({
    super.key,
    required this.children,
    this.onBack,
    this.panelled = true,
  });
  final List<Widget> children;
  final VoidCallback? onBack;
  final bool panelled;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final titleIndex = children.indexWhere((child) => child is Heading);
    return VitalPage(
      title: titleIndex < 0 ? null : (children[titleIndex] as Heading).text,
      panelled: panelled,
      leading: VitalButton.secondary(
        leading: const Icon(LucideIcons.arrowLeft),
        onPressed:
            onBack ??
            () => context.canPop() ? context.pop() : context.go('/today'),
        child: Text(t.back),
      ),
      headerActions: [
        VitalButton.secondary(
          leading: const Icon(LucideIcons.sunMoon),
          onPressed: () => context.push('/appearance'),
          child: Text(t.appearance),
        ),
      ],
      children: [
        for (var i = 0; i < children.length; i++)
          if (i != titleIndex) children[i],
      ],
    );
  }
}

class RecordCollection extends ConsumerStatefulWidget {
  const RecordCollection({super.key, required this.destination});
  final Destination destination;
  @override
  ConsumerState<RecordCollection> createState() => _RecordCollectionState();
}

class _RecordCollectionState extends ConsumerState<RecordCollection> {
  Destination get destination => widget.destination;
  int itemPages = 1;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final notice = ref.watch(savedRecordProvider);
    final people = ref.watch(profilesProvider);
    if (!people.hasValue) {
      return PageContent(
        children: [
          if (people.hasError)
            LoadFailure(
              onRetry: () {
                ref.invalidate(profilesProvider);
              },
            )
          else
            Text(t.loadingRecords),
        ],
      );
    }
    const scope = FeedScope.me();
    final itemResults = [
      for (var page = 0; page < itemPages; page++)
        ref.watch(scopedItemsPageProvider((scope: scope, offset: page * 50))),
    ];
    final AsyncValue<List<SubstanceItem>> items =
        itemResults.any((p) => p.hasError)
        ? AsyncError(Object(), StackTrace.current)
        : itemResults.any((p) => !p.hasValue)
        ? const AsyncLoading()
        : AsyncData([
            for (final page in itemResults) ...page.requireValue.take(50),
          ]);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final query = (
      itemId: null,
      scope: scope,
      actualFrom: destination == Destination.today ? day : null,
      actualBefore: destination == Destination.today
          ? DateTime(now.year, now.month, now.day + 1)
          : null,
      limit: 51,
      offset: 0,
    );

    return PageContent(
      children: [
        VitalPageHeader(
          title: destination.label(t),
          icon: destination.icon,
          actions: destination == Destination.substances
              ? [
                  VitalButton(
                    leading: const Icon(LucideIcons.plus),
                    onPressed: () => context.push('/create'),
                    child: Text(t.create),
                  ),
                ]
              : const [],
        ),
        if (destination == Destination.today) const DraftList(),
        if (destination == Destination.today) const AttachmentJobs(),
        if (notice != null &&
            destination == Destination.history &&
            (scope.isEveryone
                ? people.requireValue.any(
                    (p) => p.id == notice.personId && !p.isArchived,
                  )
                : scope.personId == notice.personId))
          Semantics(
            liveRegion: true,
            child: Text(
              notice.isVoided
                  ? t.voidedContext(
                      ownerLabel(ref, t, notice.personId),
                      notice.name,
                      stockRecordAmountNumber(t, notice),
                      notice.actualUnit,
                    )
                  : t.savedContext(
                      ownerLabel(ref, t, notice.personId),
                      notice.name,
                      stockRecordAmountNumber(t, notice),
                      notice.actualUnit,
                    ),
            ),
          ),
        const SizedBox(height: 16),
        if (destination == Destination.today) StockNotices(scope: scope),
        if (destination == Destination.today) DailyFeed(scope: scope),
        if (destination == Destination.history)
          PlannedHistory(key: ValueKey((scope, 'planned')), scope: scope),
        if (destination == Destination.events)
          Text(t.eventsBody)
        else if (destination == Destination.substances) ...[
          items.when(
            data: (items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (items.isEmpty)
                  VitalEmptyState(
                    title: t.substances,
                    description: t.substancesReady,
                    icon: LucideIcons.pill,
                  ),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: VitalSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          VitalRecordHeader(
                            title: item.name,
                            subtitle: t.itemDetails(
                              item.form,
                              item.type,
                              item.unit,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              VitalButton(
                                onPressed: () =>
                                    context.push('/record/${item.id}'),
                                child: Text(t.record),
                              ),
                              VitalButton.secondary(
                                onPressed: () => context.push(
                                  '/combined/${item.personId}?item=${item.id}',
                                ),
                                child: Text(t.combinedAction),
                              ),
                              VitalButton.secondary(
                                onPressed: () =>
                                    context.push('/schedule/${item.id}'),
                                child: Text(t.schedule),
                              ),
                              VitalButton.secondary(
                                onPressed: () => context.push(
                                  '/stock/${item.personId}?item=${item.id}',
                                ),
                                child: Text(t.stock),
                              ),
                              VitalButton.secondary(
                                onPressed: () =>
                                    context.push('/item/${item.id}'),
                                child: Text(t.history),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            error: (_, _) => LoadFailure(
              onRetry: () => ref.invalidate(scopedItemsPageProvider),
            ),
            loading: () => Text(t.loadingRecords),
          ),
          if ((itemResults.last.value?.length ?? 0) > 50)
            VitalButton.secondary(
              onPressed: () => setState(() => itemPages++),
              child: Text(t.more),
            ),
        ] else if (destination == Destination.today)
          VitalSection(
            title: Text(t.statusRecorded),
            children: [
              PagedRecordList(
                key: ValueKey(scope),
                query: query,
                emptyBody: t.todayReady,
              ),
            ],
          )
        else
          PagedRecordList(
            key: ValueKey(scope),
            query: query,
            emptyBody: t.historyReady,
          ),
      ],
    );
  }
}

class PagedRecordList extends ConsumerStatefulWidget {
  const PagedRecordList({
    super.key,
    required this.query,
    required this.emptyBody,
  });
  final RecordQuery query;
  final String emptyBody;
  @override
  ConsumerState<PagedRecordList> createState() => _PagedRecordListState();
}

class _PagedRecordListState extends ConsumerState<PagedRecordList> {
  int pageCount = 1;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final visited = <String>{};
    final queries = [
      for (var page = 0; page < pageCount; page++)
        (
          itemId: widget.query.itemId,
          scope: widget.query.scope,
          actualFrom: widget.query.actualFrom,
          actualBefore: widget.query.actualBefore,
          limit: 51,
          offset: page * 50,
        ),
    ];
    final pages = [
      for (final query in queries) ref.watch(pagedRecordsProvider(query)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var page = 0; page < pages.length; page++)
          pages[page].when(
            data: (rows) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page == 0 && rows.isEmpty) ...[
                  VitalEmptyState(
                    title: t.noRecords,
                    description: widget.emptyBody,
                  ),
                ],
                for (final record in rows.take(50))
                  if (visited.add(record.id))
                    RecordCard(key: ValueKey(record.id), record: record),
              ],
            ),
            error: (_, _) => LoadFailure(
              onRetry: () =>
                  ref.invalidate(pagedRecordsProvider(queries[page])),
            ),
            loading: () => Text(t.loadingRecords),
          ),
        if ((pages.last.value?.length ?? 0) > 50)
          VitalButton.secondary(
            onPressed: () => setState(() => pageCount++),
            child: Text(t.more),
          ),
      ],
    );
  }
}

class LoadFailure extends StatelessWidget {
  const LoadFailure({super.key, required this.onRetry, this.message});
  final VoidCallback onRetry;
  final String? message;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return VitalNotice(
      tone: VitalTone.danger,
      icon: LucideIcons.circleAlert,
      action: Align(
        alignment: AlignmentDirectional.centerStart,
        child: VitalButton.secondary(onPressed: onRetry, child: Text(t.retry)),
      ),
      child: Text(message ?? t.historyUnavailable),
    );
  }
}

class RecordCard extends ConsumerStatefulWidget {
  const RecordCard({super.key, required this.record, this.showActions = true});
  final UseRecord record;
  final bool showActions;
  @override
  ConsumerState<RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends ConsumerState<RecordCard> {
  String? command;
  UseRecord? undoTarget;
  bool busy = false;
  String? error;
  int? undoOwnerRevision;
  PhysicalCorrection? physicalChoice;
  List<IntervalChangeReview>? intervalReviews;
  Future<void> undo(int ownerRevision) async {
    if (busy) return;
    undoOwnerRevision ??= ownerRevision;
    final t = AppLocalizations.of(context),
        target = undoTarget ??= widget.record;
    command ??= newCommandId();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      if (!mounted) return;
      intervalReviews ??= await reviewIntervalMutation(
        context,
        ref,
        target,
        voided: true,
      );
      if (intervalReviews == null || !mounted) return;
      final linked = await store.stockUseForRecord(
        personId: target.personId,
        recordId: target.id,
      );
      if (!mounted) return;
      if (linked != null && physicalChoice == null) {
        final container = await store.stockContainerById(
          personId: target.personId,
          containerId: linked.containerId,
        );
        if (!mounted) return;
        physicalChoice = await choosePhysicalCorrection(
          context,
          linked,
          personName: ownerLabel(ref, t, target.personId),
          itemName: target.name,
          quantity: stockAmountText(t, target.actualAmount, target.actualUnit),
          containerLabel: container?.label ?? t.stockUnavailable,
        );
        if (physicalChoice == null || !mounted) return;
      }
      final result = physicalChoice == null && intervalReviews!.isEmpty
          ? await ref.read(voidWriterProvider)((
              commandId: command!,
              recordId: target.id,
              expectedRevision: target.revision,
              personId: target.personId,
              expectedPersonRevision: undoOwnerRevision,
            ))
          : await store.voidRecord(
              commandId: command!,
              recordId: target.id,
              expectedRevision: target.revision,
              personId: target.personId,
              expectedPersonRevision: undoOwnerRevision,
              stockCorrection: physicalChoice,
              intervalReviews: intervalReviews,
            );
      ref.read(savedRecordProvider.notifier).set(result);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error = e is CommandConflict ? t.conflictFailure : t.undoFailure,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final t = AppLocalizations.of(context);
    final profile = ref
        .watch(profilesProvider)
        .value
        ?.where((p) => p.id == r.personId)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: VitalSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VitalRecordHeader(
              title: r.name,
              icon: r.isVoided ? LucideIcons.history : LucideIcons.circleCheck,
            ),
            if (!r.isVoided && widget.showActions)
              IntervalRecordChoices(record: r),
            Text(
              t.ownerAmount(
                ownerLabel(ref, t, r.personId),
                stockRecordAmountNumber(t, r),
                r.actualUnit,
              ),
            ),
            Text(switch (r.source) {
              RecordSource.unspecified => t.legacySource,
              RecordSource.selfReported => t.selfSource,
              RecordSource.recordedOnBehalf => t.onBehalf(
                ownerLabel(ref, t, r.personId),
              ),
            }),
            if (ref
                    .watch(profilesProvider)
                    .value
                    ?.any((p) => p.id == r.personId && p.isArchived) ??
                false) ...[
              Text(t.archivedHelp),
              VitalButton.secondary(
                onPressed: () => context.push('/profile'),
                child: Text(t.profile),
              ),
            ],
            Text(t.itemDetails(r.form, r.type, r.actualUnit)),
            Text(
              t.stockEntryProvenance(
                r.originalEntry ?? r.enteredAmount,
                r.originalUnit ?? r.unit,
              ),
            ),
            if (r.labelledStrength != null) ...[
              Text(t.stockStrengthValue(r.labelledStrength!.label)),
              if (r.actualUnit == 'mg' &&
                  r.labelledStrength!.equivalent(
                        r.actualAmount,
                        from: 'mg',
                        to: 'ml',
                      ) !=
                      null)
                Text(
                  t.stockNewEquivalent(
                    stockAmountText(
                      t,
                      r.labelledStrength!.equivalent(
                        r.actualAmount,
                        from: 'mg',
                        to: 'ml',
                      )!,
                      'ml',
                    ),
                  ),
                ),
              if (r.actualUnit == 'ml' &&
                  r.labelledStrength!.equivalent(
                        r.actualAmount,
                        from: 'ml',
                        to: 'mg',
                      ) !=
                      null)
                Text(
                  t.stockNewEquivalent(
                    stockAmountText(
                      t,
                      r.labelledStrength!.equivalent(
                        r.actualAmount,
                        from: 'ml',
                        to: 'mg',
                      )!,
                      'mg',
                    ),
                  ),
                ),
            ],
            if (r.replacement != null) ...[
              Text(t.stockReplacementFrom(r.replacement!.oldStrength.label)),
              Text(
                r.replacement!.keep == FixedReplacementAmount.milligrams
                    ? t.stockKeepMg
                    : t.stockKeepMl,
              ),
            ],
            if (r.combinedActionId != null) Text(t.combinedHistoryHelp),
            if (r.siteLabel != null) Text(t.combinedSiteValue(r.siteLabel!)),
            if (widget.showActions)
              VitalButton.secondary(
                onPressed: () => context.push('/site/${r.personId}/${r.id}'),
                child: Text(t.combinedSiteAction),
              ),
            if (widget.showActions)
              VitalButton.secondary(
                onPressed: () =>
                    context.push('/files/${r.personId}/record/${r.id}'),
                child: Text(t.attachments),
              ),
            ProductRecordDetails(record: r),
            StockRecordEffect(record: r),
            if (r.catalogueSnapshot != null)
              CatalogueSource(snapshot: r.catalogueSnapshot!),
            Text(t.actualStamp(displayStamp(context, ref, r.actualAt))),
            Text(t.entryStamp(displayStamp(context, ref, r.enteredAt))),
            Text(t.revisionStamp(r.revision)),
            if (r.isVoided) Text(t.voided),
            if (error != null) Semantics(liveRegion: true, child: Text(error!)),
            if (widget.showActions &&
                !r.isVoided &&
                profile != null &&
                !profile.isArchived) ...[
              const SizedBox(height: 12),
              Text(t.undoHelp),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  VitalButton.secondary(
                    onPressed: busy
                        ? null
                        : () => context.push(
                            r.combinedActionId == null
                                ? '/correct/${r.id}?person=${r.personId}'
                                : '/combined/${r.personId}/edit/${r.combinedActionId}',
                          ),
                    child: Text(t.correct),
                  ),

                  VitalButton.secondary(
                    onPressed: busy
                        ? null
                        : r.combinedActionId == null
                        ? () => undo(profile.revision)
                        : () => context.push(
                            '/combined/${r.personId}/edit/${r.combinedActionId}?undo=true',
                          ),
                    child: Text(busy ? t.saving : t.undo),
                  ),
                ],
              ),
            ],
            if (widget.showActions) ...[
              const SizedBox(height: 12),
              VitalButton.secondary(
                onPressed: () =>
                    context.push('/revisions/${r.id}?person=${r.personId}'),
                child: Text(t.history),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Immediate review after logging, with the same correction and Undo controls
/// as the recorded section of Today. The full timeline remains in History.
class RecordedDosesPage extends ConsumerWidget {
  const RecordedDosesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final notice = ref.watch(savedRecordProvider);
    return EntryPage(
      children: [
        Heading(t.history),
        if (notice != null && notice.personId == meId)
          Semantics(
            liveRegion: true,
            child: Text(
              notice.isVoided
                  ? t.voidedContext(
                      ownerLabel(ref, t, meId),
                      notice.name,
                      stockRecordAmountNumber(t, notice),
                      notice.actualUnit,
                    )
                  : t.savedContext(
                      ownerLabel(ref, t, meId),
                      notice.name,
                      stockRecordAmountNumber(t, notice),
                      notice.actualUnit,
                    ),
            ),
          ),
        PagedRecordList(
          query: (
            itemId: null,
            actualFrom: null,
            actualBefore: null,
            limit: 51,
            offset: 0,
            scope: const FeedScope.me(),
          ),
          emptyBody: t.historyReady,
        ),
      ],
    );
  }
}

class ItemHistory extends ConsumerStatefulWidget {
  const ItemHistory({super.key, required this.itemId});
  final String itemId;
  @override
  ConsumerState<ItemHistory> createState() => _ItemHistoryState();
}

class _ItemHistoryState extends ConsumerState<ItemHistory> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final notice = ref.watch(savedRecordProvider);
    return ref
        .watch(itemLookupProvider(widget.itemId))
        .when(
          data: (item) => EntryPage(
            children: [
              Heading(t.history),
              if (item == null)
                Text(t.noItem)
              else ...[
                if (notice != null && notice.itemId == item.id)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      notice.isVoided
                          ? t.voidedContext(
                              ownerLabel(ref, t, meId),
                              notice.name,
                              stockRecordAmountNumber(t, notice),
                              notice.actualUnit,
                            )
                          : t.savedContext(
                              ownerLabel(ref, t, meId),
                              notice.name,
                              stockRecordAmountNumber(t, notice),
                              notice.actualUnit,
                            ),
                    ),
                  ),
                Text(item.name),
                ProductLabelPanel(item: item),
                VitalButton.secondary(
                  onPressed: () => context.push(
                    supportingLocation(
                      item.personId,
                      item: item.id,
                      back: '/item/${item.id}',
                    ),
                  ),
                  child: Text(t.supportingTitle),
                ),
                VitalButton.secondary(
                  onPressed: () =>
                      context.push('/files/${item.personId}/item/${item.id}'),
                  child: Text(t.attachments),
                ),
                VitalButton.secondary(
                  multiline: true,
                  onPressed: () =>
                      context.push('/use/${item.personId}/${item.id}'),
                  child: Text(t.useHistory),
                ),
                VitalButton.secondary(
                  onPressed: () =>
                      context.push('/stock/${item.personId}?item=${item.id}'),
                  child: Text(t.stock),
                ),
                if (item.catalogueSnapshot != null)
                  CatalogueSource(snapshot: item.catalogueSnapshot!),
                Text(t.profileOwner(ownerLabel(ref, t, item.personId))),
                const SizedBox(height: 16),
                PagedRecordList(
                  query: (
                    itemId: item.id,
                    actualFrom: null,
                    actualBefore: null,
                    limit: 51,
                    offset: 0,
                    scope: FeedScope.person(item.personId),
                  ),
                  emptyBody: t.historyReady,
                ),
              ],
            ],
          ),
          error: (_, _) => EntryPage(
            children: [
              LoadFailure(
                onRetry: () =>
                    ref.invalidate(itemLookupProvider(widget.itemId)),
              ),
            ],
          ),
          loading: () => EntryPage(children: [Text(t.loadingRecords)]),
        );
  }
}

class LabelledInput extends StatelessWidget {
  const LabelledInput({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.helper,
    this.enabled = true,
    this.error,
    this.semanticLabel,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? helper;
  final bool enabled;
  final String? error, semanticLabel;
  final int maxLines;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: VitalType.label),
        const SizedBox(height: 8),
        Semantics(
          label: semanticLabel ?? label,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            maxLines: maxLines,
            minLines: maxLines > 1 ? 1 : null,
            textInputAction: maxLines > 1
                ? TextInputAction.newline
                : TextInputAction.next,
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              helper!,
              style: VitalType.metadata.copyWith(
                color: Theme.of(context).colorScheme.mutedForeground,
              ),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.destructive,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

final draftOperationStatusProvider = StreamProvider.autoDispose
    .family<DraftOperationStatus, String>(retry: (_, _) => null, (
      ref,
      id,
    ) async* {
      yield* (await ref.watch(recordStoreProvider.future))
          .watchDraftOperation(id);
    });

/// Bounded ordinary forms persist only their closed, reviewed field snapshots.
abstract class DurableFormState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  bool busy = false, uncertain = false, conflict = false, dirty = false;
  String? error, commandId;
  bool _draftStarted = false, draftReady = false, _restoring = false;
  bool draftFailed = false;
  String? _draftId, _generation, _completedPath;
  int? capturedPersonRevision, capturedTargetRevision;
  String? get capturedGeneration => _generation;
  Future<void> _draftQueue = Future.value();
  DraftCheckpoint? _pendingDraft;
  bool _draftWriting = false;
  DraftKind get entryKind;
  String? get entryPerson;
  int? get entryPersonRevision;
  String? get entryTarget;
  String get entryFallback => '/substances';
  int? get entryTargetRevision => null;

  /// Optional mode suffix of a form that hosts more than one command over the
  /// same [entryTarget]. It only namespaces this form's durable draft identity;
  /// the stored target identity stays [entryTarget]. Null keeps the legacy key.
  String? get entryDraftVariant => null;

  /// Legacy draft key without any [entryDraftVariant]. Forms that adopt a
  /// pre-variant draft use it to find and relocate the older row.
  String get entryBaseDraftId =>
      '${entryKind.name}:${entryPerson ?? "new"}:${entryTarget ?? "new"}';

  /// Optional hook between the durable lookup and the form restore. A form
  /// adopts or relocates a draft belonging to another of its surfaces here and
  /// returns it; returning null means nothing is applied. The default keeps
  /// the returned draft unchanged.
  Future<OrdinaryDraft?> adoptEntryDraft(
    RecordStore store,
    OrdinaryDraft? draft,
  ) => Future.value(draft);

  /// Feature-specific recovery wording. Existing forms keep the shared copy.
  String get conflictMessage => AppLocalizations.of(context).conflictFailure;
  String get draftUnavailableMessage =>
      AppLocalizations.of(context).draftUnavailable;
  String get draftFailureMessage => AppLocalizations.of(context).draftFailure;
  String get draftSavedMessage => AppLocalizations.of(context).draftSaved;
  String get saveFailureMessage => AppLocalizations.of(context).saveFailure;
  Map<String, String> captureEntry();
  void restoreEntry(Map<String, String> fields);

  bool prepareDraft() {
    if (_draftStarted) return draftReady;
    _draftStarted = true;
    capturedPersonRevision = entryPersonRevision;
    capturedTargetRevision = entryTargetRevision;
    _draftId = entryBaseDraftId;
    final variant = entryDraftVariant;
    if (variant != null) _draftId = '$_draftId:$variant';
    Future<void>(() async {
      try {
        final store = await ref.read(recordStoreProvider.future);
        _generation = store.generation;
        var draft = await store.draftById(_draftId!);
        draft = await adoptEntryDraft(store, draft);
        if (!mounted) return;
        if (draft != null) {
          commandId = draft.operationId;
          capturedPersonRevision = draft.personRevision;
          capturedTargetRevision = draft.targetRevision;
          if (await store.operationCommitted(draft.operationId)) {
            await store.discardDraft(draft.id);
            if (!mounted) return;
            conflict = true;
            error = draftSavedMessage;
          } else {
            _restoring = true;
            restoreEntry(draft.fields);
            _restoring = false;
            dirty = true;
            uncertain = draft.submitted;
          }
        }
        if (mounted) setState(() => draftReady = true);
      } catch (_) {
        if (mounted) {
          setState(() {
            draftFailed = true;
            draftReady = true;
          });
        }
      }
    });
    return false;
  }

  void entryChanged() {
    if (_restoring) return;
    dirty = true;
    if (draftReady && !busy && !uncertain) persistEntry();
  }

  OrdinaryDraft snapshot({bool submitted = false}) => OrdinaryDraft(
    id: _draftId!,
    generation: _generation!,
    operationId: commandId ??= newCommandId(),
    kind: entryKind,
    personId: entryPerson,
    personRevision: capturedPersonRevision,
    targetId: entryTarget,
    targetRevision: capturedTargetRevision,
    fields: captureEntry(),
    submitted: submitted,
  );
  void persistEntry() {
    if (_generation == null) return;
    final store = ref.read(recordStoreProvider).requireValue;
    try {
      _pendingDraft = store.captureDraftCheckpoint(snapshot());
    } catch (_) {
      if (mounted) setState(() => draftFailed = true);
      return;
    }
    if (_draftWriting) return;
    _draftWriting = true;
    _draftQueue = Future<void>(() async {
      try {
        while (_pendingDraft != null) {
          final draft = _pendingDraft!;
          _pendingDraft = null;
          await draft.persist();
        }
        if (mounted) setState(() => draftFailed = false);
      } catch (_) {
        if (mounted) setState(() => draftFailed = true);
      } finally {
        _draftWriting = false;
      }
    });
  }

  Future<void> leave() async {
    if (busy || uncertain && !conflict) {
      setState(() => error = AppLocalizations.of(context).pendingBody);
      return;
    }
    if (dirty) {
      final t = AppLocalizations.of(context);
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => VitalDialog(
          title: Text(t.unsavedHeading),
          content: Text(t.unsavedBody),
          actions: [
            VitalButton.secondary(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.keep),
            ),
            VitalButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.discard),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    try {
      await _draftQueue;
      if (_draftId != null) {
        await (await ref.read(recordStoreProvider.future))
            .discardDraft(_draftId!);
      }
    } catch (_) {
      if (mounted) setState(() => draftFailed = true);
      return;
    }
    if (mounted) {
      setState(() {
        dirty = false;
        uncertain = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(entryFallback);
        }
      });
    }
  }

  String? recoverableCommandFailure(Object error) => null;

  Future<void> commit(
    Future<void> Function(String command) save, {
    required String successPath,
  }) async {
    if (busy || conflict || !draftReady) return;
    commandId ??= newCommandId();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      if (_generation != store.generation) {
        throw const CommandConflict('generation');
      }
      await _draftQueue;
      // Check the durable result before any retry's stale-owner validation.
      if (!await store.operationCommitted(commandId!)) {
        await store.saveDraft(snapshot(submitted: true));
        await save(commandId!);
      }
      if (mounted) {
        dirty = false;
        uncertain = false;
        if (!store.writesSuspended) {
          context.go(successPath);
        } else {
          _completedPath = successPath;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final recovery = recoverableCommandFailure(e);
          uncertain = recovery == null && e is! CommandConflict;
          conflict =
              recovery == null &&
              e is CommandConflict &&
              e.code != 'app_locked';
          error = recovery ?? (conflict ? conflictMessage : saveFailureMessage);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget wrap(List<Widget> children) {
    final operation = commandId == null
        ? null
        : ref.watch(draftOperationStatusProvider(commandId!)).value;
    if (operation == DraftOperationStatus.invalidated) {
      dirty = false;
      conflict = true;
      return EntryPage(children: [Text(draftUnavailableMessage)]);
    }
    final currentGeneration = ref.watch(recordStoreProvider).value?.generation;
    if (_generation != null &&
        currentGeneration != null &&
        currentGeneration != _generation) {
      dirty = false;
      conflict = true;
      return EntryPage(children: [Text(draftUnavailableMessage)]);
    }
    ref.listen(appLockProvider, (previous, next) {
      if (!next.locked && _completedPath != null) {
        final path = _completedPath!;
        _completedPath = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go(path);
        });
      }
    });
    return PopScope(
      canPop: !dirty && !busy && !uncertain,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: EntryPage(
        onBack: leave,
        children: [
          if (draftFailed)
            Semantics(liveRegion: true, child: Text(draftFailureMessage)),
          if (draftFailed)
            VitalButton.secondary(
              onPressed: busy ? null : persistEntry,
              child: Text(AppLocalizations.of(context).retry),
            ),
          ...children,
        ],
      ),
    );
  }

  Widget? failure() =>
      error == null ||
          error == AppLocalizations.of(context).nameRequired ||
          error == AppLocalizations.of(context).amountInvalid ||
          error == AppLocalizations.of(context).timeInvalid ||
          error == AppLocalizations.of(context).ambiguousTime
      ? null
      : Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(error!),
          ),
        );
}

class ItemForm extends ConsumerStatefulWidget {
  const ItemForm({super.key});
  @override
  ConsumerState<ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends DurableFormState<ItemForm> {
  @override
  DraftKind get entryKind => DraftKind.item;
  @override
  String? get entryPerson => owner?.id;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => null;
  @override
  Map<String, String> captureEntry() => {
    'name': name.text,
    'form': form.text,
    'unit': unit.text,
    'type': type.text,
    'query': query.text,
    'typeId': selectedTypeId ?? '',
    'typeRevision': selectedTypeRevision?.toString() ?? '',
    'catalogue': selection == null ? '' : jsonEncode(selection!.toJson()),
    'productEnabled': '$productEnabled',
    'productComponents': productEditor.encode(),
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    productEnabled = fields['productEnabled'] == 'true';
    if (fields['productComponents'] case final encoded?) {
      productEditor.restore(encoded);
    }
    name.text = fields['name'] ?? '';
    form.text = fields['form'] ?? '';
    unit.text = fields['unit'] ?? '';
    type.text = fields['type'] ?? '';
    query.text = fields['query'] ?? '';
    selectedTypeId = fields['typeId']?.isEmpty == false
        ? fields['typeId']
        : null;
    selectedTypeRevision = int.tryParse(fields['typeRevision'] ?? '');
    selection = fields['catalogue']?.isNotEmpty == true
        ? CatalogueSnapshot.fromJson(
            jsonDecode(fields['catalogue']!) as Map<String, dynamic>,
          )
        : null;
  }

  bool productEnabled = false;
  late final productEditor = ProductEditorData(entryChanged);
  AdultProfile? owner;
  CatalogueSnapshot? selection;
  String? selectedTypeId;
  int? selectedTypeRevision;
  int typeOffset = 0;
  bool searching = false;
  final query = TextEditingController();
  final name = TextEditingController(),
      form = TextEditingController(),
      unit = TextEditingController(),
      type = TextEditingController();
  @override
  void initState() {
    super.initState();
    for (final c in [name, form, unit, type, query]) {
      c.addListener(entryChanged);
    }
  }

  @override
  void dispose() {
    productEditor.dispose();
    for (final c in [name, form, unit, type, query]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (name.text.trim().isEmpty) {
      setState(() => error = t.nameRequired);
      return;
    }
    if ([name, form, unit, type].any(
      (c) =>
          c.text.trim().isEmpty ||
          c.text.length >
              ((selection != null && (c == name || c == form)) ? 2048 : 500),
    )) {
      setState(() => error = t.detailsRequired);
      return;
    }
    List<ProductComponent>? components;
    if (productEnabled) {
      try {
        components = productEditor.components();
      } catch (_) {
        setState(() => error = t.productIngredientInvalid);
        return;
      }
    }
    await commit((command) async {
      await (await ref.read(recordStoreProvider.future)).createItem(
        commandId: command,
        personId: owner!.id,
        expectedPersonRevision: capturedPersonRevision,
        name: selection?.product.name ?? name.text.trim(),
        form: selection?.product.form.isNotEmpty == true
            ? selection!.product.form
            : form.text.trim(),
        unit: unit.text.trim(),
        type: type.text.trim(),
        typeId: selectedTypeId,
        expectedTypeRevision: selectedTypeRevision,
        catalogueSnapshot: selection,
        productComponents: components,
      );
    }, successPath: '/substances');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final people = ref.watch(profilesProvider);
    if (!people.hasValue) return EntryPage(children: [Text(t.loadingRecords)]);
    owner ??= people.value!.where((p) => p.id == meId).firstOrNull;
    if (owner == null || !people.value!.any((p) => p.id == owner!.id)) {
      dirty = false;
      return EntryPage(children: [Text(t.profileUnavailable)]);
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final ownerValid = people.value!.any(
      (p) =>
          p.id == owner!.id &&
          !p.isArchived &&
          p.revision == capturedPersonRevision,
    );
    return wrap([
      Heading(t.newSubstance),
      if (!ownerValid) Text(t.profileChanged),
      Text(t.profileOwner(ownerLabel(ref, t, owner!.id))),
      const SizedBox(height: 20),
      if (searching)
        CataloguePicker(
          query: query,
          enabled: !busy && !uncertain && ownerValid,
          onSelect: (value) => setState(() {
            selection = value;
            name.text = value.product.name;
            form.text = value.product.form;
            searching = false;
            entryChanged();
          }),
          onCustom: (value) => setState(() {
            selection = null;
            name.text = value;
            searching = false;
            entryChanged();
          }),
        )
      else ...[
        if (selection != null) ...[
          Heading(t.catalogueSelected),
          CatalogueSource(snapshot: selection!),
          Text(t.catalogueSelectedHelp),
          VitalButton.secondary(
            onPressed: busy || uncertain || !ownerValid
                ? null
                : () => setState(() {
                    selection = null;
                    entryChanged();
                  }),
            child: Text(t.catalogueClear),
          ),
        ],
        VitalButton.secondary(
          onPressed: busy || uncertain || !ownerValid
              ? null
              : () => setState(() => searching = true),
          child: Text(t.catalogueSearchAction),
        ),
        const SizedBox(height: 20),
      ],
      LabelledInput(
        label: t.nameLabel,
        controller: name,
        error: error == t.nameRequired ? error : null,
        enabled: !busy && !uncertain && ownerValid && selection == null,
      ),
      LabelledInput(
        label: t.formLabel,
        controller: form,
        enabled:
            !busy &&
            !uncertain &&
            ownerValid &&
            (selection == null || selection!.product.form.isEmpty),
      ),
      SettingsToggleRow(
        label: t.productToggle,
        description: t.productToggleHelp,
        value: productEnabled,
        enabled: !busy && !uncertain && ownerValid,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        onChanged: (value) => setState(() {
          productEnabled = value;
          if (value) {
            unit.text = 'ml';
            productEditor.initialise();
          }
          entryChanged();
        }),
      ),
      if (productEnabled)
        ProductComponentEditor(
          data: productEditor,
          enabled: !busy && !uncertain && ownerValid,
          error: error == t.productIngredientInvalid ? error : null,
          onChanged: () => setState(() {}),
        ),
      Text(t.unitLabel),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final value in ['mg', 'ml', 'count'])
            Semantics(
              selected: unit.text == value,
              child: VitalButton.secondary(
                multiline: true,
                onPressed: busy || uncertain || !ownerValid || productEnabled
                    ? null
                    : () => setState(() => unit.text = value),
                child: Text(value),
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      LabelledInput(
        label: t.typeLabel,
        controller: type,
        enabled: !busy && !uncertain && ownerValid && selectedTypeId == null,
      ),
      Text(t.itemTypesHelp),
      if (selectedTypeId != null) ...[
        Text(t.itemTypeCurrent(type.text)),
        VitalButton.secondary(
          onPressed: busy || uncertain || !ownerValid
              ? null
              : () => setState(() {
                  selectedTypeId = null;
                  selectedTypeRevision = null;
                  entryChanged();
                }),
          child: Text(t.catalogueClear),
        ),
      ],
      ref
          .watch(itemTypesProvider((personId: owner!.id, offset: typeOffset)))
          .when(
            loading: () => Text(t.loadingRecords),
            error: (_, _) => LoadFailure(
              onRetry: () => ref.invalidate(
                itemTypesProvider((personId: owner!.id, offset: typeOffset)),
              ),
            ),
            data: (types) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final value in types.take(50))
                  Semantics(
                    selected: value.id == selectedTypeId,
                    label: t.itemTypeChoice(value.name),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: VitalButton.secondary(
                        multiline: true,
                        onPressed: busy || uncertain || !ownerValid
                            ? null
                            : () => setState(() {
                                type.text = value.name;
                                selectedTypeId = value.id;
                                selectedTypeRevision = value.revision;
                                entryChanged();
                              }),
                        child: Text(value.name),
                      ),
                    ),
                  ),
                if (typeOffset > 0)
                  VitalButton.secondary(
                    onPressed: () => setState(() => typeOffset -= 50),
                    child: Text(t.previous),
                  ),
                if (types.length > 50)
                  VitalButton.secondary(
                    onPressed: () => setState(() => typeOffset += 50),
                    child: Text(t.next),
                  ),
              ],
            ),
          ),
      const SizedBox(height: 12),
      VitalButton.secondary(
        onPressed: busy || uncertain || !ownerValid
            ? null
            : () => context.push('/types/${owner!.id}'),
        child: Text(t.itemTypeManage),
      ),
      const SizedBox(height: 20),
      ?failure(),
      VitalButton(
        onPressed: busy || conflict || (!ownerValid && !uncertain)
            ? null
            : save,
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

class DoseForm extends ConsumerStatefulWidget {
  const DoseForm({
    super.key,
    this.itemId,
    this.recordId,
    this.personId = meId,
    this.returnLocation,
  });
  final String? itemId, recordId;
  final String? returnLocation;
  final String personId;
  @override
  ConsumerState<DoseForm> createState() => _DoseFormState();
}

class _DoseFormState extends DurableFormState<DoseForm> {
  @override
  DraftKind get entryKind =>
      widget.recordId == null ? DraftKind.dose : DraftKind.correction;
  @override
  String? get entryPerson => owner?.id;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.recordId ?? widget.itemId;
  @override
  int? get entryTargetRevision => original?.revision ?? item?.revision;
  @override
  Map<String, String> captureEntry() => {
    'site': site.text,
    'siteOpen': '$siteOpen',
    'amount': amount.text,
    'date': date.text,
    'time': time.text,
    'instant': chosenInstant?.microsecondsSinceEpoch.toString() ?? '',
    'container': selectedContainer?.id ?? sourceId ?? '',
    'containerRevision':
        selectedContainer?.revision.toString() ??
        sourceRevision?.toString() ??
        '',
    'baseContainer': baseContainer?.id ?? baseId ?? '',
    'baseRevision':
        baseContainer?.revision.toString() ?? baseRevision?.toString() ?? '',
    'keep': keep?.name ?? '',
    'stockCorrection': stockCorrection?.name ?? '',
    'labelOnly': '$labelOnly',
    'labelStrength': labelStrength.text,
    'labelConcentration': labelConcentration.text,
    'enteredUnit': enteredUnit ?? item?.unit ?? '',
    'amountEdited': '$amountEdited',
    'intervalClockSample': encodeIntervalClock(
      intervalReviews?.firstOrNull?.intervalClockSample ??
          frozenIntervalClockSample,
    ),
    'productLabel': productLabel == null
        ? ''
        : jsonEncode(productLabel!.toJson()),
    'productUse': frozenProductUse == null
        ? ''
        : jsonEncode(frozenProductUse!.toJson()),
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    site.text = fields['site'] ?? '';
    siteOpen = fields['siteOpen'] == 'true';
    frozenProductUse = fields['productUse']?.isNotEmpty == true
        ? ProductUseInput.fromJson(
            jsonDecode(fields['productUse']!) as Map<String, dynamic>,
          )
        : null;
    productLabel = fields['productLabel']?.isNotEmpty == true
        ? ProductLabelSnapshot.fromJson(
            jsonDecode(fields['productLabel']!) as Map<String, dynamic>,
          )
        : productLabel;
    amount.text = fields['amount'] ?? '';
    date.text = fields['date'] ?? '';
    time.text = fields['time'] ?? '';
    amountEdited = fields['amountEdited'] == 'true';
    enteredUnit = fields['enteredUnit']?.isNotEmpty == true
        ? fields['enteredUnit']
        : item?.unit;
    sourceId = fields['container'];
    sourceRevision = int.tryParse(fields['containerRevision'] ?? '');
    baseId = fields['baseContainer'];
    baseRevision = int.tryParse(fields['baseRevision'] ?? '');
    keep = FixedReplacementAmount.values
        .where((v) => v.name == fields['keep'])
        .firstOrNull;
    stockCorrection = PhysicalCorrection.values
        .where((v) => v.name == fields['stockCorrection'])
        .firstOrNull;
    labelOnly = fields['labelOnly'] == 'true';
    labelStrength.text = fields['labelStrength'] ?? '';
    labelConcentration.text = fields['labelConcentration'] ?? '';
    final instant = int.tryParse(fields['instant'] ?? '');
    chosenInstant = instant == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(instant, isUtc: true);
    frozenIntervalClockSample = decodeIntervalClock(
      fields['intervalClockSample'],
    );
  }

  bool siteOpen = false;
  final site = TextEditingController();
  final amount = TextEditingController(),
      date = TextEditingController(),
      time = TextEditingController();
  StoredStockContainer? selectedContainer, baseContainer;
  String? sourceId, baseId, enteredUnit;
  int? sourceRevision, baseRevision;
  FixedReplacementAmount? keep;
  PhysicalCorrection? stockCorrection;
  bool labelOnly = false, amountEdited = false;
  final labelStrength = TextEditingController(),
      labelConcentration = TextEditingController();
  ProductLabelSnapshot? productLabel;
  ProductUseInput? frozenProductUse;
  ReminderClockSample? frozenIntervalClockSample;
  List<IntervalChangeReview>? intervalReviews;
  UseRecord? original;
  SubstanceItem? item;
  bool initialised = false;
  AdultProfile? owner;
  DateTime? chosenInstant;
  List<DateTime> clockChoices = [];
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    date.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    time.text =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    amount.addListener(() {
      if (initialised && draftReady && mounted) amountEdited = true;
      intervalReviews = null;
      frozenIntervalClockSample = null;
      entryChanged();
      if (initialised && draftReady && mounted) setState(() {});
    });
    site.addListener(entryChanged);
    labelStrength.addListener(entryChanged);
    labelConcentration.addListener(entryChanged);
    for (final c in [date, time]) {
      c.addListener(() {
        chosenInstant = null;
        clockChoices = [];
        intervalReviews = null;
        frozenIntervalClockSample = null;
        entryChanged();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      amount,
      date,
      time,
      labelStrength,
      labelConcentration,
      site,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? actual() {
    if (chosenInstant != null) return chosenInstant;
    final day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$')
        .firstMatch(date.text.trim());
    final clock = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time.text.trim());
    if (day == null || clock == null) return null;
    final y = int.parse(day[1]!),
        m = int.parse(day[2]!),
        d = int.parse(day[3]!),
        h = int.parse(clock[1]!),
        n = int.parse(clock[2]!);
    final at = DateTime(y, m, d, h, n);
    if (at.year != y ||
        at.month != m ||
        at.day != d ||
        at.hour != h ||
        at.minute != n) {
      return null;
    }
    final choices = ref.read(actualTimeResolverProvider)(
      DateTime.utc(y, m, d, h, n),
    );
    if (choices.length > 1) {
      clockChoices = choices;
      return choices.where((c) => c == chosenInstant).firstOrNull;
    }
    clockChoices = [];
    return choices.firstOrNull;
  }

  ExactAmount? _productPreviewVolume(String text, UseRecord? original) {
    if (text.trim().isEmpty) return original?.product?.volume;
    try {
      return ExactAmount.parseEntry(stockDecimal(text));
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (site.text.length > 500) {
      setState(() => error = t.combinedSiteInvalid);
      return;
    }
    late final String entered;
    try {
      final sourceEntry =
          selectedContainer != null ||
          labelOnly ||
          original?.labelledStrength != null ||
          productLabel != null ||
          original?.product != null;
      entered = sourceEntry ? stockDecimal(amount.text) : amount.text.trim();
      if (!(original != null &&
          stockRecordHasDerivedAmount(original!) &&
          entered.isEmpty)) {
        ExactQuantity.parse(entered);
      }
    } catch (_) {
      setState(() => error = t.amountInvalid);
      return;
    }
    final at = actual();
    if (at == null) {
      setState(
        () => error = clockChoices.length > 1 ? t.ambiguousTime : t.timeInvalid,
      );
      return;
    }
    chosenInstant = at;
    StockUseInput? stockUse;
    if (original == null && labelOnly && labelStrength.text.trim().isEmpty) {
      setState(() => error = t.stockStrengthRequired);
      return;
    }
    if (original == null && productLabel == null) {
      try {
        final source = selectedContainer;
        StockReplacement? replacement;
        if (baseContainer != null &&
            source != null &&
            baseContainer!.id != source.id &&
            !sameStockStrength(baseContainer!.strength, source.strength)) {
          if (keep == null) {
            setState(() => error = t.stockKeepRequired);
            return;
          }
          replacement = StockReplacement(
            oldStrength: baseContainer!.strength,
            newStrength: source.strength,
            keep: keep!,
          );
        }
        if (source != null || labelOnly) {
          stockUse = StockUseInput(
            expectedGeneration: capturedGeneration!,
            containerId: source?.id,
            expectedContainerRevision: source?.revision,
            entered: EnteredStockAmount(entered, enteredUnit ?? item!.unit),
            strength: source == null
                ? LabelledStrength(
                    ingredientId: item!.id,
                    label: labelStrength.text.trim(),
                    mgPerMl: labelConcentration.text.trim().isEmpty
                        ? null
                        : ExactAmount.parseEntry(
                            stockDecimal(labelConcentration.text),
                          ),
                  )
                : null,
            replacement: replacement,
          );
        }
      } catch (_) {
        setState(() => error = t.stockAmountInvalid);
        return;
      }
    } else if (original != null) {
      final linked = ref.read(
        stockUseProvider((
          personId: original!.personId,
          recordId: original!.id,
        )),
      );
      if (!linked.hasValue) {
        setState(() => error = t.loadingRecords);
        return;
      }
      if (linked.value != null && stockCorrection == null) {
        setState(() => error = t.stockPhysicalRequired);
        return;
      }
    }
    if (original == null && productLabel != null) {
      frozenProductUse ??= ProductUseInput(
        expectedGeneration: capturedGeneration!,
        label: productLabel!,
        expectedItemRevision: capturedTargetRevision,
        enteredVolume: EnteredStockAmount(entered, 'ml'),
        containerId: selectedContainer?.id,
        expectedContainerRevision: selectedContainer?.revision,
        sourceLabel: selectedContainer?.productLabel,
      );
    }
    if (original != null && intervalReviews == null) {
      final store = await ref.read(recordStoreProvider.future);
      final alreadySaved =
          commandId != null && await store.operationCommitted(commandId!);
      if (!mounted) return;
      if (!alreadySaved) {
        intervalReviews = await reviewIntervalMutation(
          context,
          ref,
          original!,
          actualAt: at,
          proposedAmount: entered.isEmpty ? null : entered,
          intervalClockSample: frozenIntervalClockSample,
        );
      } else {
        intervalReviews = [];
      }
      if (intervalReviews == null || !mounted) return;
    }
    await commit((command) async {
      final store = await ref.read(recordStoreProvider.future);
      if (original case final r?) {
        final result = await store.correct(
          commandId: command,
          recordId: r.id,
          expectedRevision: capturedTargetRevision!,
          amount: !amountEdited || entered.isEmpty ? null : entered,
          actualAt: at,
          personId: r.personId,
          expectedPersonRevision: capturedPersonRevision,
          stockCorrection: stockCorrection,
          intervalReviews: intervalReviews,
        );
        ref.read(savedRecordProvider.notifier).set(result);
      } else {
        final result = productLabel != null
            ? await store.recordProduct(
                commandId: command,
                itemId: item!.id,
                actualAt: at,
                personId: item!.personId,
                expectedPersonRevision: capturedPersonRevision!,
                siteLabel: site.text.trim().isEmpty ? null : site.text,
                use: frozenProductUse!,
              )
            : stockUse != null
            ? await store.record(
                commandId: command,
                itemId: item!.id,
                amount: entered,
                actualAt: at,
                personId: item!.personId,
                expectedPersonRevision: capturedPersonRevision,
                siteLabel: site.text.trim().isEmpty ? null : site.text,
                stockUse: stockUse,
              )
            : site.text.trim().isNotEmpty
            ? await store.record(
                commandId: command,
                itemId: item!.id,
                amount: entered,
                actualAt: at,
                personId: item!.personId,
                expectedPersonRevision: capturedPersonRevision,
                siteLabel: site.text,
              )
            : await ref.read(recordWriterProvider)((
                commandId: command,
                itemId: item!.id,
                amount: entered,
                actualAt: at,
                personId: item!.personId,
                expectedPersonRevision: capturedPersonRevision,
              ));
        ref.read(savedRecordProvider.notifier).set(result);
      }
    }, successPath: widget.returnLocation ?? '/recorded');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lookupId = widget.itemId;
    final lookup = lookupId == null
        ? const AsyncData<SubstanceItem?>(null)
        : ref.watch(itemLookupProvider(lookupId));
    final people = ref.watch(profilesProvider);
    final records = widget.recordId == null
        ? const AsyncData<UseRecord?>(null)
        : ref.watch(
            recordLookupProvider((
              recordId: widget.recordId!,
              personId: widget.personId,
            )),
          );
    final currentProduct = lookup.value == null
        ? const AsyncData<ProductLabelSnapshot?>(null)
        : ref.watch(
            productLabelProvider((
              personId: lookup.value!.personId,
              itemId: lookup.value!.id,
            )),
          );
    if (lookup.isLoading ||
        records.isLoading ||
        people.isLoading ||
        currentProduct.isLoading) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    if (lookup.hasError ||
        records.hasError ||
        people.hasError ||
        currentProduct.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              if (lookupId != null) {
                ref.invalidate(itemLookupProvider(lookupId));
                ref.invalidate(productLabelProvider);
              }
              ref.invalidate(profilesProvider);
              if (widget.recordId != null) {
                ref.invalidate(
                  recordLookupProvider((
                    recordId: widget.recordId!,
                    personId: widget.personId,
                  )),
                );
              }
            },
          ),
        ],
      );
    }
    if (initialised &&
        ((widget.recordId != null && records.value == null) ||
            (lookupId != null && lookup.value == null) ||
            !people.value!.any((p) => p.id == owner!.id))) {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!initialised) {
      original = records.value;
      item = lookup.value;
      productLabel = records.value?.product?.label ?? currentProduct.value;
      if (original case final r?) {
        item = SubstanceItem(
          id: r.itemId,
          personId: r.personId,
          name: r.name,
          form: r.form,
          unit: r.unit,
          type: r.type,
        );
      }
      owner = people.value?.where((p) => p.id == item?.personId).firstOrNull;
      enteredUnit = original?.actualUnit ?? item?.unit;
      if (item == null ||
          owner == null ||
          widget.recordId != null && original == null) {
        return EntryPage(children: [Text(t.noItem)]);
      }
      if (original case final r?) {
        final d = r.actualAt.toLocal();
        amount.text = stockRecordHasDerivedAmount(r)
            ? ''
            : r.originalEntry ?? r.enteredAmount;
        date.text =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        time.text =
            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      }
      initialised = true;
      dirty = false;
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final productValid =
        original != null ||
        currentProduct.value?.revision == productLabel?.revision;
    final ownerValid =
        productValid &&
        people.value!.any(
          (p) =>
              p.id == owner!.id &&
              !p.isArchived &&
              p.revision == capturedPersonRevision,
        );
    if (original == null &&
        sourceId != null &&
        sourceId!.isNotEmpty &&
        selectedContainer == null &&
        !(uncertain && frozenProductUse != null)) {
      final source = ref.watch(
        stockContainerProvider((personId: owner!.id, containerId: sourceId!)),
      );
      if (!source.hasValue) {
        return EntryPage(children: [Text(t.loadingRecords)]);
      }
      if (source.value == null || source.value!.revision != sourceRevision) {
        conflict = true;
        return wrap([Text(t.conflictFailure)]);
      }
      selectedContainer = source.value;
    }
    if (original == null &&
        baseId != null &&
        baseId!.isNotEmpty &&
        baseContainer == null &&
        !(uncertain && frozenProductUse != null)) {
      final source = ref.watch(
        stockContainerProvider((personId: owner!.id, containerId: baseId!)),
      );
      if (!source.hasValue) {
        return EntryPage(children: [Text(t.loadingRecords)]);
      }
      if (source.value == null || source.value!.revision != baseRevision) {
        conflict = true;
        return wrap([Text(t.conflictFailure)]);
      }
      baseContainer = source.value;
    }
    final r = original;
    final name = r?.name ?? item!.name,
        unit = r?.actualUnit ?? enteredUnit ?? item!.unit;
    return wrap([
      Heading(r == null ? t.recordHeading : t.correctHeading),
      if (!ownerValid) ...[
        Text(t.conflictFailure),
        VitalButton.secondary(
          onPressed: () => context.push('/profile'),
          child: Text(t.profile),
        ),
      ],
      Text(
        r == null
            ? t.recordContext(ownerLabel(ref, t, owner!.id), name, unit)
            : t.correctionContext(ownerLabel(ref, t, owner!.id), name, unit),
      ),
      if (owner!.id != meId)
        Text(t.recordingOnBehalf(ownerLabel(ref, t, owner!.id))),
      const SizedBox(height: 20),
      LabelledInput(
        label: r != null && stockRecordHasDerivedAmount(r)
            ? t.stockCorrectionAmount
            : t.amountLabel,
        helper: productLabel != null
            ? t.productVolumeHelp
            : r != null && stockRecordHasDerivedAmount(r)
            ? t.stockCorrectionKeep
            : (selectedContainer != null ||
                  labelOnly ||
                  r?.labelledStrength != null)
            ? t.stockDecimalHelp
            : null,
        controller: amount,
        error: error == t.amountInvalid ? error : null,
        enabled: !busy && !uncertain && ownerValid,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
      Text(unit),
      if (r?.exactActualAmount != null)
        Text(
          t.stockNewEquivalent(
            stockAmountText(t, r!.actualAmount, r.actualUnit),
          ),
        ),
      const SizedBox(height: 16),
      if (productLabel != null) ...[
        Heading(t.productIngredients),
        if (selectedContainer != null ||
            frozenProductUse?.sourceLabel != null) ...[
          Text(t.productFixedVolume),
          Heading(t.productOldLabel),
          ProductLabelView(
            label: productLabel!,
            volume: _productPreviewVolume(amount.text, original),
          ),
          Heading(t.productNewLabel),
        ],
        ProductLabelView(
          label:
              frozenProductUse?.sourceLabel ??
              selectedContainer?.productLabel ??
              productLabel!,
          volume: _productPreviewVolume(amount.text, original),
        ),
      ],
      if (r == null) ...[
        StockSourcePicker(
          personId: owner!.id,
          itemId: item!.id,
          selectedId: selectedContainer?.id ?? sourceId,
          productOnly: productLabel != null,
          enabled: !busy && !uncertain && ownerValid,
          onSelected: (c) => setState(() {
            if (c == null) {
              selectedContainer = null;
              baseContainer = null;
              sourceId = null;
              baseId = null;
              keep = null;
              enteredUnit = item!.unit;
            } else {
              baseContainer ??= c;
              selectedContainer = c;
              sourceId = c.id;
              sourceRevision = c.revision;
              keep = null;
              labelOnly = false;
            }
            entryChanged();
          }),
        ),
        if (productLabel == null &&
            const {'mg', 'ml'}.contains(item!.unit) &&
            (selectedContainer != null || labelOnly)) ...[
          Text(t.unitLabel),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final u in ['mg', 'ml'])
                Semantics(
                  selected: unit == u,
                  child: VitalButton.secondary(
                    multiline: true,
                    onPressed: !busy && !uncertain && ownerValid
                        ? () => setState(() {
                            enteredUnit = u;
                            keep = null;
                            entryChanged();
                          })
                        : null,
                    child: Text(u),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (productLabel == null &&
            selectedContainer == null &&
            (sourceId == null || sourceId!.isEmpty)) ...[
          SettingsToggleRow(
            label: t.stockLabelOnly,
            description: t.stockLabelOnlyHelp,
            value: labelOnly,
            enabled: !busy && !uncertain && ownerValid,
            reduceMotion: MediaQuery.disableAnimationsOf(context),
            onChanged: (v) => setState(() {
              labelOnly = v;
              if (!v) enteredUnit = item!.unit;
              entryChanged();
            }),
          ),
          if (labelOnly) ...[
            LabelledInput(
              label: t.stockStrength,
              controller: labelStrength,
              error: error == t.stockStrengthRequired ? error : null,
              enabled: !busy && !uncertain && ownerValid,
            ),
            LabelledInput(
              label: t.stockConcentration,
              controller: labelConcentration,
              helper: t.stockConcentrationHelp,
              enabled: !busy && !uncertain && ownerValid,
            ),
          ],
        ],
        if (productLabel == null && selectedContainer != null)
          StockDosePreview(
            enteredText: amount.text,
            enteredUnit: unit,
            selected: selectedContainer!,
            base: baseContainer,
            keep: keep,
            enabled: !busy && !uncertain && ownerValid,
            onKeep: (v) => setState(() {
              keep = v;
              entryChanged();
            }),
            onActual: () => setState(() {
              baseContainer = selectedContainer;
              baseId = selectedContainer!.id;
              baseRevision = selectedContainer!.revision;
              keep = null;
              entryChanged();
            }),
          ),
      ] else ...[
        Text(t.stockCorrectionEntryHelp),
        ref
            .watch(stockUseProvider((personId: r.personId, recordId: r.id)))
            .when(
              loading: () => Text(t.loadingRecords),
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(
                  stockUseProvider((personId: r.personId, recordId: r.id)),
                ),
              ),
              data: (movement) => movement == null
                  ? const SizedBox.shrink()
                  : StockPhysicalChoice(
                      value: stockCorrection,
                      reviewed: movement.reviewedCorrection != null,
                      enabled: !busy && !uncertain && ownerValid,
                      onChanged: (v) => setState(() {
                        stockCorrection = v;
                        entryChanged();
                      }),
                    ),
            ),
      ],
      if (r == null) ...[
        VitalButton.secondary(
          onPressed: !busy && !uncertain && ownerValid
              ? () => setState(() {
                  siteOpen = !siteOpen;
                  entryChanged();
                })
              : null,
          child: Text(t.combinedSiteAction),
        ),
        if (siteOpen)
          LabelledInput(
            label: t.combinedSite,
            helper: t.combinedSiteHelp,
            controller: site,
            enabled: !busy && !uncertain && ownerValid,
          ),
        Text(t.intervalExtraHelp),
      ],
      LabelledInput(
        label: t.actualDateLabel,
        controller: date,
        helper: t.dateExample,
        error: error == t.timeInvalid ? error : null,
        enabled: !busy && !uncertain && ownerValid,
        keyboardType: TextInputType.datetime,
      ),
      LabelledInput(
        label: t.actualTimeLabel,
        controller: time,
        helper: t.timeExample,
        enabled: !busy && !uncertain && ownerValid,
        keyboardType: TextInputType.datetime,
      ),
      if (clockChoices.length > 1) ...[
        Text(t.ambiguousTime),
        const SizedBox(height: 8),
        for (var i = 0; i < clockChoices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.offsetChoice(
                    i == 0 ? t.earlier : t.later,
                    utcOffset(clockChoices[i].toLocal().timeZoneOffset),
                  ),
                ),
                Semantics(
                  selected: chosenInstant == clockChoices[i],
                  child: VitalButton.secondary(
                    multiline: true,
                    onPressed: busy || uncertain || !ownerValid
                        ? null
                        : () => setState(() {
                            chosenInstant = clockChoices[i];
                            entryChanged();
                          }),
                    child: Text(i == 0 ? t.earlier : t.later),
                  ),
                ),
              ],
            ),
          ),
      ],
      ?failure(),
      VitalButton(
        onPressed: busy || conflict || (!ownerValid && !uncertain)
            ? null
            : save,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.save,
        ),
      ),
    ]);
  }
}

final revisionHistoryProvider = FutureProvider.autoDispose
    .family<List<UseRecord>, OwnedRecord>(
      retry: (_, _) => null,
      (ref, target) async =>
          (await (await ref.watch(recordStoreProvider.future))
                  .history(target.recordId))
              .where((r) => r.personId == target.personId)
              .toList(),
    );

class RevisionHistory extends ConsumerWidget {
  const RevisionHistory({
    super.key,
    required this.recordId,
    this.personId = meId,
  });
  final String recordId;
  final String personId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return EntryPage(
      children: [
        Heading(t.recordHistory),
        ref
            .watch(
              revisionHistoryProvider((recordId: recordId, personId: personId)),
            )
            .when(
              data: (rows) => Column(
                children: [
                  for (final r in rows)
                    RecordCard(
                      key: ValueKey('${r.id}:${r.revision}'),
                      record: r,
                      showActions: false,
                    ),
                ],
              ),
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(
                  revisionHistoryProvider((
                    recordId: recordId,
                    personId: personId,
                  )),
                ),
              ),
              loading: () => Text(t.loadingRecords),
            ),
      ],
    );
  }
}

final ordinaryDraftsProvider = StreamProvider.autoDispose<List<OrdinaryDraft>>(
  retry: (_, _) => null,
  (ref) async* {
    final lock = ref.watch(appLockProvider);
    if (!lock.ready || lock.locked) {
      yield [];
      return;
    }
    yield* (await ref.watch(recordStoreProvider.future)).watchDrafts();
  },
);

class DraftList extends ConsumerStatefulWidget {
  const DraftList({super.key});
  @override
  ConsumerState<DraftList> createState() => _DraftListState();
}

class _DraftListState extends ConsumerState<DraftList> {
  bool failed = false;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final drafts = ref.watch(ordinaryDraftsProvider).value ?? [];
    if (drafts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.draftHeading),
        Text(t.draftBody),
        if (failed)
          Semantics(liveRegion: true, child: Text(t.draftDiscardFailure)),
        for (final draft in drafts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  draft.personId == null
                      ? t.addPerson
                      : t.profileOwner(ownerLabel(ref, t, draft.personId!)),
                ),
                Text(switch (draft.kind) {
                  DraftKind.supportingVoid =>
                    draft.fields['isVoided'] == 'true'
                        ? t.supportingVoid
                        : t.supportingRestore,
                  DraftKind.labPanel => t.supportingPanel,
                  DraftKind.supportingObservation => t.supportingObservation,
                  DraftKind.attachmentRename => t.attachmentRename,
                  DraftKind.event => t.events,
                  DraftKind.usePeriod => t.useHistory,
                  DraftKind.eventReview => t.eventEndReview,
                  DraftKind.item => t.newSubstance,
                  DraftKind.itemType => t.itemTypes,
                  DraftKind.productLabel => t.productLabelHeading,
                  DraftKind.stockContainer => t.stockCreate,
                  DraftKind.stockAdjustment => t.stockAdjust,
                  DraftKind.siteEdit => t.combinedSites,
                  DraftKind.combinedDose => t.combinedHeading,
                  DraftKind.combinedCorrection => t.combinedCorrection,
                  DraftKind.dose => t.recordHeading,
                  DraftKind.correction => t.correctHeading,
                  DraftKind.dailyPlan => t.schedule,
                  DraftKind.pausePlan => t.pauseHeading,
                  DraftKind.phasePlan => t.phaseHeading,
                  DraftKind.profile =>
                    draft.targetId == null ? t.addPerson : t.editPerson,
                }),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    VitalButton.secondary(
                      onPressed: () => context.push(draft.route),
                      child: Text(t.resume),
                    ),
                    VitalButton.secondary(
                      onPressed: () async {
                        await (await ref.read(recordStoreProvider.future))
                            .discardDraft(draft.id);
                      },
                      child: Text(t.discard),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
