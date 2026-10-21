import '../../app/app_lock.dart';

import 'package:flutter/material.dart' show showDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../app/supporting.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'screen_labs_collection.dart';
import 'screen_panel_widgets.dart';
import 'supporting_widgets.dart';

/// Runs one durably saved supporting void or restore intent. Overridable in
/// widget tests so a commit failure or a lost reply can be exercised without a
/// second command engine.
typedef SupportingVoidRun = Future<SupportingRevision> Function(
  OrdinaryDraft draft,
);
final supportingVoidWriterProvider = Provider<SupportingVoidRun>(
  (ref) =>
      (draft) async =>
          (await ref.read(recordStoreProvider.future))
              .resumeSupportingVoidDraft(draft),
);

String supportingLocation(
  String person, {
  String? item,
  String? event,
  String? back,
}) => Uri(
  path: '/supporting',
  queryParameters: {
    'person': person,
    'item': ?item,
    'event': ?event,
    'return': ?back,
  },
).toString();

/// The canonical `/supporting` collection. Its labs composition lives in the
/// screen-specific file; the panel detail below keeps its own existing chrome.
class SupportingRecordsPage extends StatelessWidget {
  const SupportingRecordsPage({super.key, required this.location});
  final String location;
  @override
  Widget build(BuildContext context) =>
      ScreenLabsCollectionPage(location: location);
}

class SupportingDetailPage extends ConsumerStatefulWidget {
  const SupportingDetailPage({
    super.key,
    required this.personId,
    required this.id,
    this.revision,
    this.returnLocation,
  });
  final String personId, id;
  final int? revision;
  final String? returnLocation;
  @override
  ConsumerState<SupportingDetailPage> createState() =>
      _SupportingDetailPageState();
}

class _SupportingDetailPageState extends ConsumerState<SupportingDetailPage> {
  int resultPage = 0;
  ScreenPanelResultFilter resultFilter = ScreenPanelResultFilter.all;
  bool revisions = false, busy = false;
  int? beforeRevision;
  String? error, feedback;
  final backFocus = FocusNode();
  @override
  void dispose() {
    backFocus.dispose();
    super.dispose();
  }

  OrdinaryDraft? _pendingDraft(List<OrdinaryDraft> drafts) => drafts
      .where(
        (draft) =>
            draft.kind == DraftKind.supportingVoid &&
            draft.personId == widget.personId &&
            draft.targetId == widget.id,
      )
      .firstOrNull;

  void _reload() {
    ref.invalidate(supportingLookupProvider);
    ref.invalidate(supportingRevisionsProvider);
    ref.invalidate(ordinaryDraftsProvider);
  }

  Future<void> _openFiles() async {
    await context.push('/files/${widget.personId}/supporting/${widget.id}');
    if (mounted) backFocus.requestFocus();
  }

  Future<bool> _committed(RecordStore store, String operation) async {
    try {
      return await store.operationCommitted(operation);
    } catch (_) {
      return false;
    }
  }

  /// Writes the exact confirmed request before running it. The draft row is the
  /// only pending record, so a restart shows the same action; the `_command`
  /// transaction removes the row on commit or idempotent replay.
  Future<void> changeVoid(SupportingRevision record, int ownerRevision) async {
    final t = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => VitalDialog(
        title: Text(record.isVoided ? t.supportingRestore : t.supportingVoid),
        content: Text(
          record.isVoided ? t.supportingRestoreBody : t.supportingVoidBody,
        ),
        actions: [
          VitalButton.secondary(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          VitalButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              record.isVoided ? t.supportingRestore : t.supportingVoid,
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final store = await ref.read(recordStoreProvider.future);
    final operation = newCommandId();
    final draft = OrdinaryDraft.supportingVoid(
      id: operation,
      operationId: operation,
      generation: store.generation,
      personId: widget.personId,
      personRevision: ownerRevision,
      recordId: widget.id,
      recordRevision: record.revision,
      isVoided: !record.isVoided,
    );
    setState(() {
      busy = true;
      error = null;
      feedback = null;
    });
    try {
      await store.saveDraft(draft);
    } catch (_) {
      // Nothing was executed and no record changed.
      if (mounted) {
        setState(() {
          busy = false;
          error = t.supportingVoidNotSaved;
        });
      }
      return;
    }
    if (mounted) await _runVoid(draft);
  }

  Future<void> _runVoid(OrdinaryDraft draft) async {
    final t = AppLocalizations.of(context);
    final store = await ref.read(recordStoreProvider.future);
    if (mounted) {
      setState(() {
        busy = true;
        error = null;
        feedback = null;
      });
    }
    try {
      await ref.read(supportingVoidWriterProvider)(draft);
      if (!mounted) return;
      _voidSaved(t, draft);
    } catch (failure) {
      // Resolve a possibly lost reply before reporting failure: the captured
      // revision may now be stale only because this exact operation committed.
      final committed = await _committed(store, draft.operationId);
      if (!mounted) return;
      if (committed) {
        _voidSaved(t, draft);
      } else {
        setState(() {
          error =
              failure is CommandConflict &&
                  {
                    'person_context',
                    'supporting_revision',
                  }.contains(failure.code)
              ? t.supportingVoidChanged
              : t.supportingVoidUncertain;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _voidSaved(AppLocalizations t, OrdinaryDraft draft) {
    _reload();
    setState(
      () => feedback = draft.fields['isVoided'] == 'true'
          ? t.supportingVoidSaved
          : t.supportingRestoreSaved,
    );
  }

  Future<void> discardPending(OrdinaryDraft draft) async {
    final t = AppLocalizations.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await (await ref.read(recordStoreProvider.future)).discardDraft(draft.id);
      if (!mounted) return;
      _reload();
      setState(() => feedback = t.supportingVoidDiscarded);
    } catch (_) {
      if (mounted) setState(() => error = t.draftDiscardFailure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// The saved action stays visible and explicitly discardable even when its
  /// owner is archived or its record is no longer available.
  Widget _pendingCard(
    AppLocalizations t,
    OrdinaryDraft draft, {
    required bool canResume,
    String? explanation,
  }) => VitalSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          draft.fields['isVoided'] == 'true'
              ? t.supportingVoidPending
              : t.supportingRestorePending,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(explanation ?? t.supportingVoidPendingBody),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            VitalButton(
              isLoading: busy,
              onPressed: busy || !canResume ? null : () => _runVoid(draft),
              child: Text(t.resume),
            ),
            VitalButton.secondary(
              onPressed: busy ? null : () => discardPending(draft),
              child: Text(t.discard),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (ref.watch(appLockProvider.select((s) => s.locked))) {
      return EntryPage(
        children: [Text(AppLocalizations.of(context).supportingLocked)],
      );
    }
    final t = AppLocalizations.of(context),
        request = (
          personId: widget.personId,
          id: widget.id,
          revision: widget.revision,
        );
    final pending = widget.revision == null
        ? _pendingDraft(
            ref.watch(ordinaryDraftsProvider).value ?? const <OrdinaryDraft>[],
          )
        : null;
    final record = ref.watch(supportingLookupProvider(request));
    if (record.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            message: t.supportingLoadFailure,
            onRetry: () => ref.invalidate(supportingLookupProvider(request)),
          ),
        ],
      );
    }
    if (!record.hasValue) return EntryPage(children: [Text(t.loadingRecords)]);
    final saved = record.value;
    if (saved == null) {
      return EntryPage(
        children: [
          Text(t.supportingUnavailable),
          if (pending != null)
            _pendingCard(
              t,
              pending,
              canResume: false,
              explanation: t.supportingVoidMissing,
            ),
          if (error != null) Semantics(liveRegion: true, child: Text(error!)),
          if (feedback != null)
            Semantics(liveRegion: true, child: Text(feedback!)),
        ],
      );
    }
    final s = saved.snapshot,
        owner = ref
            .watch(profilesProvider)
            .value
            ?.where((p) => p.id == widget.personId)
            .firstOrNull;
    final mutable =
        widget.revision == null && !busy && owner != null && !owner.isArchived;
    final audit = revisions
        ? ref.watch(
            supportingRevisionsProvider((
              personId: widget.personId,
              id: widget.id,
              before: beforeRevision,
            )),
          )
        : null;
    final collectionLabel = supportingDateLabel(context, ref, s.collectionDate);
    final collectionSource = supportingDateSourceLabel(
      context,
      ref,
      s.collectionDate,
    );
    final reportLabel = s.kind == SupportingRecordKind.labPanel
        ? supportingDateLabel(context, ref, s.reportDate)
        : null;
    final reportSource = s.kind == SupportingRecordKind.labPanel
        ? supportingDateSourceLabel(context, ref, s.reportDate)
        : null;
    final laboratory = s.provenance.laboratoryName ?? s.provenance.laboratoryId;
    final withRange = s.results
        .where((result) => result.referenceRange != null)
        .toList(growable: false);
    final withoutRange = s.results
        .where((result) => result.referenceRange == null)
        .toList(growable: false);
    final filtered = switch (resultFilter) {
      ScreenPanelResultFilter.all => s.results,
      ScreenPanelResultFilter.withRange => withRange,
      ScreenPanelResultFilter.withoutRange => withoutRange,
    };
    final lastPage = filtered.isEmpty ? 0 : (filtered.length - 1) ~/ 25;
    final shownPage = resultPage.clamp(0, lastPage);
    final visible = filtered.skip(shownPage * 25).take(25);
    void openTrends(LabResultSnapshot result) => context.push(
      Uri(
        path: '/supporting/${widget.personId}/trends',
        queryParameters: {'metric': result.metricId, 'kind': s.kind.name},
      ).toString(),
    );
    return EntryPage(
      panelled: false,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(
            widget.returnLocation ?? supportingLocation(widget.personId),
          );
        }
      },
      children: [
        Heading(
          s.kind == SupportingRecordKind.labPanel
              ? t.screenPanelPanelDetail
              : t.screenPanelObservationDetail,
        ),
        ScreenPanelHero(
          title: s.title,
          kindLabel: s.kind == SupportingRecordKind.labPanel
              ? t.supportingPanel
              : t.supportingObservation,
          laboratory: laboratory,
          dateLabel: s.kind == SupportingRecordKind.labPanel
              ? t.supportingCollection
              : t.supportingMeasured,
          collectionLabel: collectionLabel,
          reportLabel: reportLabel,
          dateSource: collectionSource,
          revision: saved.revision,
          resultCount: s.results.length,
          voided: saved.isVoided,
        ),
        if (pending != null && owner != null) ...[
          const SizedBox(height: 16),
          _pendingCard(
            t,
            pending,
            canResume: !owner.isArchived,
            explanation: owner.isArchived ? t.supportingVoidArchived : null,
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!saved.isVoided)
              StitchButton(
                icon: LucideIcons.pencil,
                primary: true,
                onPressed: mutable
                    ? () => context.push(
                        Uri(
                          path:
                              '/supporting/${widget.personId}/${widget.id}/edit',
                          queryParameters: {
                            'return':
                                widget.returnLocation ??
                                supportingLocation(widget.personId),
                          },
                        ).toString(),
                      )
                    : null,
                child: Text(t.edit),
              ),
            if (pending == null)
              VitalButton.secondary(
                isLoading: busy,
                onPressed: mutable
                    ? () => changeVoid(saved, owner.revision)
                    : null,
                child: Text(
                  saved.isVoided ? t.supportingRestore : t.supportingVoid,
                ),
              ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          VitalNotice(
            tone: VitalTone.danger,
            icon: LucideIcons.circleAlert,
            child: Semantics(liveRegion: true, child: Text(error!)),
          ),
        ],
        if (feedback != null) ...[
          const SizedBox(height: 16),
          VitalNotice(
            icon: LucideIcons.check,
            child: Semantics(liveRegion: true, child: Text(feedback!)),
          ),
        ],
        if (s.contextLinks.isNotEmpty) ...[
          const SizedBox(height: 24),
          VitalSection(
            title: Text(t.supportingContext),
            children: [
              Text(t.supportingContextHint),
              for (final link in s.contextLinks)
                ScreenPanelLinkedRecord(
                  key: ValueKey('${link.kind.name}-${link.id}'),
                  link: link,
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        VitalSection(
          title: Text(t.supportingResults),
          children: [
            ScreenPanelFilters(
              selected: resultFilter,
              onChanged: (filter) => setState(() {
                resultFilter = filter;
                resultPage = 0;
              }),
              allLabel: t.screenPanelFilterAll(s.results.length),
              rangeLabel: t.screenPanelFilterRange(withRange.length),
              noRangeLabel: t.screenPanelFilterNoRange(withoutRange.length),
            ),
            if (filtered.isEmpty)
              Text(
                s.results.isEmpty
                    ? t.supportingNoResults
                    : t.screenPanelNoFilteredResults,
              )
            else
              for (final result in visible)
                ScreenPanelResultCard(
                  key: ValueKey(result.id),
                  result: result,
                  onTrends: () => openTrends(result),
                ),
            if (filtered.length > 25)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StitchButton(
                    onPressed: shownPage > 0
                        ? () => setState(() => resultPage = shownPage - 1)
                        : null,
                    child: Text(t.supportingPrevious),
                  ),
                  StitchButton(
                    onPressed: (shownPage + 1) * 25 < filtered.length
                        ? () => setState(() => resultPage = shownPage + 1)
                        : null,
                    child: Text(t.supportingNext),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 24),
        VitalPanel(
          title: t.supportingProvenance,
          icon: LucideIcons.flaskConical,
          children: [
            Text(
              t.supportingDateLabel(
                s.kind == SupportingRecordKind.labPanel
                    ? t.supportingCollection
                    : t.supportingMeasured,
                collectionLabel,
              ),
            ),
            if (collectionSource != null) Text(collectionSource),
            if (reportLabel != null)
              Text(t.supportingDateLabel(t.supportingReport, reportLabel)),
            if (reportSource != null) Text(reportSource),
            SupportingProvenanceView(provenance: s.provenance),
            if (s.notes != null) Text(t.supportingNotes),
            if (s.notes != null) Text(s.notes!),
            Text(
              t.supportingDateLabel(
                t.supportingEntry,
                displayStamp(
                  context,
                  ref,
                  saved.enteredAt,
                  zoneId: 'UTC',
                  includeSeconds: true,
                ),
              ),
            ),
            if (saved.correctedAt != null)
              Text(
                t.supportingDateLabel(
                  t.screenPanelRevised,
                  displayStamp(
                    context,
                    ref,
                    saved.revisionEnteredAt,
                    zoneId: 'UTC',
                    includeSeconds: true,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SupportingDisclosure(
          label: t.supportingRevisions,
          open: revisions,
          onPressed: () => setState(() => revisions = !revisions),
        ),
        if (revisions) ...[
          if (audit!.hasError) ...[
            const SizedBox(height: 12),
            LoadFailure(
              message: t.supportingLoadFailure,
              onRetry: () => ref.invalidate(supportingRevisionsProvider),
            ),
          ],
          for (final old in audit.value ?? <SupportingRevision>[]) ...[
            const SizedBox(height: 8),
            StitchButton(
              onPressed: () => context.push(
                '/supporting/${widget.personId}/${widget.id}?revision=${old.revision}',
              ),
              child: Text(
                '${t.supportingRevisionLabel(old.revision)} · ${displayStamp(context, ref, old.revisionEnteredAt, zoneId: 'UTC', includeSeconds: true)}',
              ),
            ),
          ],
          if (beforeRevision != null) ...[
            const SizedBox(height: 8),
            StitchButton(
              onPressed: () => setState(() => beforeRevision = null),
              child: Text(t.supportingPrevious),
            ),
          ],
          if (audit.value?.length == 25) ...[
            const SizedBox(height: 8),
            StitchButton(
              onPressed: () =>
                  setState(() => beforeRevision = audit.value!.last.revision),
              child: Text(t.supportingNext),
            ),
          ],
        ],
        if (widget.revision == null) ...[
          const SizedBox(height: 24),
          ScreenPanelFiles(
            personId: widget.personId,
            id: widget.id,
            enabled: true,
            filesFocusNode: backFocus,
            onOpenFiles: _openFiles,
            onExport: () => context.push('/exports?content=supporting'),
          ),
        ],
      ],
    );
  }
}
