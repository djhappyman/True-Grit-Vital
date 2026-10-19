import '../../app/app_lock.dart';

import 'package:flutter/material.dart' show showDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/settings_toggle_row.dart';
import '../../app/storage.dart';
import '../../app/supporting.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'supporting_widgets.dart';

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

class SupportingRecordsPage extends ConsumerStatefulWidget {
  const SupportingRecordsPage({super.key, required this.location});
  final String location;
  @override
  ConsumerState<SupportingRecordsPage> createState() => _SupportingPageState();
}

class _SupportingPageState extends ConsumerState<SupportingRecordsPage> {
  late final seed = Uri.parse(widget.location).queryParameters;
  String get person => seed['person'] ?? meId;
  late SupportingRecordKind kind = seed['kind'] == 'observation'
      ? SupportingRecordKind.observation
      : SupportingRecordKind.labPanel;
  late SupportingDateBasis basis =
      SupportingDateBasis.values
          .where((v) => v.name == seed['basis'])
          .firstOrNull ??
      SupportingDateBasis.collection;
  bool filters = false;
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
      ...seed,
      'kind': kind.name,
      'basis': basis.name,
      'unknown': unknown.toString(),
      'voided': voided.toString(),
      'from': appliedFrom?.toString(),
      'before': appliedBefore?.toString(),
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

  void reset() => cursors
    ..clear()
    ..add(null);
  @override
  Widget build(BuildContext context) {
    if (ref.watch(appLockProvider.select((s) => s.locked))) {
      return EntryPage(
        children: [Text(AppLocalizations.of(context).supportingLocked)],
      );
    }
    final t = AppLocalizations.of(context);
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
      displayZone: ref.watch(displayZoneProvider),
    );
    final request = SupportingPageRequest(query, cursor: cursors.last);
    final records = ref.watch(supportingPageProvider(request));
    final page = records.value;
    return EntryPage(
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(seed['return'] ?? '/history');
        }
      },
      children: [
        Heading(t.supportingTitle),
        Text(t.profileOwner(ownerLabel(ref, t, person))),
        VitalSegments<SupportingRecordKind>(
          values: SupportingRecordKind.values,
          selected: kind,
          onChanged: (v) => setState(() {
            kind = v;
            reset();
          }),
          label: (v) => v == SupportingRecordKind.labPanel
              ? t.supportingPanels
              : t.supportingObservations,
        ),
        VitalButton(
          onPressed: () => context.push(
            Uri(
              path:
                  '/supporting/$person/${kind == SupportingRecordKind.labPanel ? 'add-panel' : 'add-observation'}',
              queryParameters: {
                'return': viewLocation(),
                if (seed['item'] != null) 'item': seed['item']!,
                if (seed['event'] != null) 'event': seed['event']!,
              },
            ).toString(),
          ),
          child: Text(t.supportingAdd),
        ),
        SupportingDisclosure(
          label: t.supportingFilters,
          open: filters,
          onPressed: () => setState(() => filters = !filters),
        ),
        if (filters)
          VitalSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.supportingDateBasis),
                VitalSegments<SupportingDateBasis>(
                  values: SupportingDateBasis.values,
                  selected: basis,
                  onChanged: (v) => setState(() {
                    basis = v;
                    reset();
                  }),
                  label: (v) => switch (v) {
                    SupportingDateBasis.collection =>
                      kind == SupportingRecordKind.observation
                          ? t.supportingMeasured
                          : t.supportingCollection,
                    SupportingDateBasis.report => t.supportingReportChoice,
                    SupportingDateBasis.entry => t.supportingEntryChoice,
                  },
                ),
                LabelledInput(label: t.supportingFrom, controller: from),
                LabelledInput(label: t.supportingBefore, controller: before),
                Text(t.chartRangeSummary(from.text, before.text)),
                SettingsToggleRow(
                  label: t.supportingIncludeUnknown,
                  description: t.supportingDateHint,
                  value: unknown,
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                  onChanged: (v) => setState(() {
                    unknown = v;
                    reset();
                  }),
                ),
                SettingsToggleRow(
                  label: t.supportingIncludeVoided,
                  description: t.supportingIncludeVoidedHint,
                  value: voided,
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                  onChanged: (v) => setState(() {
                    voided = v;
                    reset();
                  }),
                ),
                VitalButton.secondary(
                  onPressed: () {
                    try {
                      final start = from.text.isEmpty
                              ? null
                              : CivilDate.parse(from.text),
                          end = before.text.isEmpty
                              ? null
                              : CivilDate.parse(before.text);
                      if (start != null &&
                          end != null &&
                          end.compareTo(start) <= 0) {
                        throw const FormatException();
                      }
                      setState(() {
                        appliedFrom = start;
                        appliedBefore = end;
                        error = null;
                        reset();
                      });
                    } catch (_) {
                      setState(() => error = t.supportingInvalid);
                    }
                  },
                  child: Text(t.supportingApply),
                ),
              ],
            ),
          ),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        if (records.hasError)
          LoadFailure(
            onRetry: () {
              reset();
              ref.invalidate(supportingPageProvider);
              setState(() {});
            },
          ),
        if (records.isLoading) Text(t.loadingRecords),
        if (page != null && page.entries.isEmpty) Text(t.supportingEmpty),
        if (page != null)
          for (final record in page.entries)
            VitalSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    record.snapshot.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    t.supportingDateLabel(
                      kind == SupportingRecordKind.observation
                          ? t.supportingMeasured
                          : t.supportingCollection,
                      supportingDateLabel(
                        context,
                        ref,
                        record.snapshot.collectionDate,
                      ),
                    ),
                  ),
                  if (kind == SupportingRecordKind.labPanel)
                    Text(
                      t.supportingDateLabel(
                        t.supportingReport,
                        supportingDateLabel(
                          context,
                          ref,
                          record.snapshot.reportDate,
                        ),
                      ),
                    ),
                  if (record.isVoided) Text(t.supportingVoided),
                  VitalButton.secondary(
                    onPressed: () => context.push(
                      Uri(
                        path: '/supporting/$person/${record.id.id}',
                        queryParameters: {'return': viewLocation()},
                      ).toString(),
                    ),
                    child: Text(t.supportingSource),
                  ),
                ],
              ),
            ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            VitalButton.secondary(
              onPressed: cursors.length > 1
                  ? () => setState(() => cursors.removeLast())
                  : null,
              child: Text(t.supportingPrevious),
            ),
            VitalButton.secondary(
              onPressed: page?.next == null
                  ? null
                  : () => setState(() => cursors.add(page!.next)),
              child: Text(t.supportingNext),
            ),
          ],
        ),
      ],
    );
  }
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
  bool revisions = false, busy = false;
  int? beforeRevision;
  String? error;
  VoidSupportingRecordCommand? pending;
  final backFocus = FocusNode();
  @override
  void dispose() {
    backFocus.dispose();
    super.dispose();
  }

  Future<void> changeVoid(SupportingRevision record, int ownerRevision) async {
    final t = AppLocalizations.of(context);
    if (pending == null) {
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
      pending = VoidSupportingRecordCommand(
        commandId: newCommandId(),
        generation: ref.read(recordStoreProvider).requireValue.generation,
        personId: widget.personId,
        id: widget.id,
        expectedPersonRevision: ownerRevision,
        expectedRevision: record.revision,
        isVoided: !record.isVoided,
      );
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await (await ref.read(recordStoreProvider.future))
          .voidSupportingRecord(pending!);
      pending = null;
      ref.invalidate(supportingLookupProvider);
      ref.invalidate(supportingRevisionsProvider);
    } catch (_) {
      if (mounted) setState(() => error = t.saveFailure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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
    final record = ref.watch(supportingLookupProvider(request));
    if (record.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () => ref.invalidate(supportingLookupProvider(request)),
          ),
        ],
      );
    }
    if (!record.hasValue) return EntryPage(children: [Text(t.loadingRecords)]);
    final saved = record.value;
    if (saved == null) {
      return EntryPage(children: [Text(t.supportingUnavailable)]);
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
    return EntryPage(
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
              ? t.supportingPanel
              : t.supportingObservation,
        ),
        Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
        Text(
          s.title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        Text(t.supportingRevisionLabel(saved.revision)),
        if (saved.isVoided) Text(t.supportingVoided),
        Text(
          t.supportingDateLabel(
            s.kind == SupportingRecordKind.labPanel
                ? t.supportingCollection
                : t.supportingMeasured,
            supportingDateLabel(context, ref, s.collectionDate),
          ),
        ),
        if (s.kind == SupportingRecordKind.labPanel)
          Text(
            t.supportingDateLabel(
              t.supportingReport,
              supportingDateLabel(context, ref, s.reportDate),
            ),
          ),
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
              t.supportingRevisions,
              displayStamp(
                context,
                ref,
                saved.revisionEnteredAt,
                zoneId: 'UTC',
                includeSeconds: true,
              ),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (!saved.isVoided)
              VitalButton.secondary(
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
            VitalButton.secondary(
              focusNode: backFocus,
              onPressed: widget.revision == null
                  ? () async {
                      await context.push(
                        '/files/${widget.personId}/supporting/${widget.id}',
                      );
                      if (mounted) backFocus.requestFocus();
                    }
                  : null,
              child: Text(t.attachments),
            ),
            VitalButton.secondary(
              isLoading: busy,
              onPressed: mutable
                  ? () => changeVoid(saved, owner.revision)
                  : null,
              child: Text(
                pending != null
                    ? t.retry
                    : saved.isVoided
                    ? t.supportingRestore
                    : t.supportingVoid,
              ),
            ),
          ],
        ),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        VitalSection(
          title: Text(t.supportingResults),
          children: [
            if (s.results.isEmpty) Text(t.supportingNoResults),
            for (final result in s.results.skip(resultPage * 25).take(25))
              SupportingResultView(
                key: ValueKey(result.id),
                result: result,
                action: VitalButton.secondary(
                  onPressed: () => context.push(
                    Uri(
                      path: '/supporting/${widget.personId}/trends',
                      queryParameters: {
                        'metric': result.metricId,
                        'kind': s.kind.name,
                      },
                    ).toString(),
                  ),
                  child: Text(t.supportingTrends),
                ),
              ),
            if (s.results.length > 25)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  VitalButton.secondary(
                    onPressed: resultPage > 0
                        ? () => setState(() => resultPage--)
                        : null,
                    child: Text(t.supportingPrevious),
                  ),
                  VitalButton.secondary(
                    onPressed: (resultPage + 1) * 25 < s.results.length
                        ? () => setState(() => resultPage++)
                        : null,
                    child: Text(t.supportingNext),
                  ),
                ],
              ),
          ],
        ),
        VitalSection(
          title: Text(t.supportingProvenance),
          children: [
            SupportingProvenanceView(provenance: s.provenance),
            if (s.notes != null) Text(s.notes!),
          ],
        ),
        if (s.contextLinks.isNotEmpty)
          VitalSection(
            title: Text(t.supportingContext),
            children: [
              Text(t.supportingContextHint),
              for (final link in s.contextLinks)
                VitalButton.secondary(
                  multiline: true,
                  onPressed: () => context.push(
                    link.kind == SupportingContextKind.item
                        ? '/item/${link.id}'
                        : '/event/${link.id}',
                  ),
                  child: Text(link.id),
                ),
            ],
          ),
        SupportingDisclosure(
          label: t.supportingRevisions,
          open: revisions,
          onPressed: () => setState(() => revisions = !revisions),
        ),
        if (revisions) ...[
          if (audit!.hasError)
            LoadFailure(
              onRetry: () => ref.invalidate(supportingRevisionsProvider),
            ),
          for (final old in audit.value ?? <SupportingRevision>[])
            VitalButton.secondary(
              multiline: true,
              onPressed: () => context.push(
                '/supporting/${widget.personId}/${widget.id}?revision=${old.revision}',
              ),
              child: Text(
                '${t.supportingRevisionLabel(old.revision)} · ${displayStamp(context, ref, old.revisionEnteredAt, zoneId: 'UTC', includeSeconds: true)}',
              ),
            ),
          if (beforeRevision != null)
            VitalButton.secondary(
              onPressed: () => setState(() => beforeRevision = null),
              child: Text(t.supportingPrevious),
            ),
          if (audit.value?.length == 25)
            VitalButton.secondary(
              onPressed: () =>
                  setState(() => beforeRevision = audit.value!.last.revision),
              child: Text(t.supportingNext),
            ),
        ],
      ],
    );
  }
}
