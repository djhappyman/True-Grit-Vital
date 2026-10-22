import '../../app/app_lock.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/supporting.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'supporting_form_model.dart';
import 'supporting_input.dart';
import 'supporting_widgets.dart';

class SupportingForm extends ConsumerStatefulWidget {
  const SupportingForm({
    super.key,
    required this.personId,
    this.id,
    this.observation = false,
    this.itemId,
    this.eventId,
    this.returnLocation,
  });
  final String personId;
  final String? id, itemId, eventId, returnLocation;
  final bool observation;
  @override
  ConsumerState<SupportingForm> createState() => _SupportingFormState();
}

class _SupportingFormState extends DurableFormState<SupportingForm> {
  SupportingFormModel? model;
  SupportingRevision? original;
  final controllers = <String, TextEditingController>{};
  String? frozen;
  bool details = false;
  final openMetrics = <String>{};
  int page = 0, metricOffset = 0;
  final metricSearch = TextEditingController();
  final sourceCandidates = <AttachmentRecord>[];
  AttachmentPageCursor? sourceCursor;
  bool sourceHasMore = false, sourceLoading = false, sourceLoaded = false;
  bool sourceFailed = false;
  String? sourceGeneration;
  int _sourceRequest = 0;
  static const pageSize = 10;
  SupportingFormModel get form => model!;
  bool get observation =>
      original?.kind == SupportingRecordKind.observation || widget.observation;
  @override
  DraftKind get entryKind =>
      observation ? DraftKind.supportingObservation : DraftKind.labPanel;
  @override
  String get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => ref
      .read(profilesProvider)
      .value
      ?.where((p) => p.id == widget.personId)
      .firstOrNull
      ?.revision;
  @override
  String? get entryTarget => widget.id;
  @override
  String get entryFallback => form.get('_return').isNotEmpty
      ? form.get('_return')
      : '/supporting?person=${widget.personId}';
  @override
  int? get entryTargetRevision => original?.revision;
  @override
  String get conflictMessage => AppLocalizations.of(context).supportingConflict;
  @override
  String get draftUnavailableMessage =>
      AppLocalizations.of(context).supportingDraftUnavailable;
  @override
  String get draftFailureMessage =>
      AppLocalizations.of(context).supportingDraftFailure;
  @override
  String get draftSavedMessage =>
      AppLocalizations.of(context).supportingDraftSaved;
  @override
  String get saveFailureMessage =>
      AppLocalizations.of(context).supportingSaveFailure;
  @override
  Map<String, String> captureEntry() => {
    'payload': form.encode(),
    'frozen': frozen ?? '',
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    form.restore(
      Map<String, dynamic>.from(jsonDecode(fields['payload']!) as Map),
    );
    frozen = supportingOptional(fields['frozen'] ?? '');
    for (final c in controllers.values) {
      c.dispose();
    }
    controllers.clear();
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    metricSearch.dispose();
    super.dispose();
  }

  Widget input(
    String key,
    String label, {
    Map<String, String>? row,
    String? helper,
    int maxLines = 1,
  }) {
    final values = row ?? form.fields;
    final path = row == null ? key : '${row['id']}:$key';
    final controller = controllers.putIfAbsent(path, () {
      final c = TextEditingController(text: values[key] ?? '');
      c.addListener(() {
        values[key] = c.text;
        if (row != null && key == 'value') {
          // A typed limit is the source value. It wins over the qualifier
          // control instead of failing a contradictory second entry.
          final prefix = _valuePrefix(c.text);
          if (prefix != null && row['qualifier'] != 'exact') {
            row['qualifier'] = 'exact';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
        }
        entryChanged();
      });
      return c;
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LabelledInput(
        label: label,
        controller: controller,
        helper: helper,
        maxLines: maxLines,
        enabled: !busy && !uncertain && !conflict,
      ),
    );
  }

  String? _valuePrefix(String text) {
    final value = text.trimLeft();
    for (final prefix in ['<=', '>=', '≤', '≥', '<', '>']) {
      if (value.startsWith(prefix)) return prefix;
    }
    return null;
  }

  bool _sourceAttached(AttachmentRecord record) => form.sourceReferences.any(
    (source) =>
        source.id == record.id &&
        source.version == record.revision &&
        source.contentVersionId == record.versionId,
  );

  void attachSource(AttachmentRecord record) {
    if (_sourceAttached(record) || form.sourceReferences.length >= 100) {
      return;
    }
    setState(() {
      form.sourceReferences.add(
        SupportingSourceReference(
          id: record.id,
          personId: record.personId,
          version: record.revision,
          kind: SupportingSourceKind.attachment,
          originalText: record.name,
          contentVersionId: record.versionId,
        ),
      );
      entryChanged();
    });
  }

  void removeSource(int index) {
    setState(() {
      form.sourceReferences.removeAt(index);
      entryChanged();
    });
  }

  String _sourceLabel(AppLocalizations t, SupportingSourceReference source) =>
      source.originalText ?? t.supportingSavedSourceReference(source.version);

  /// Reads one bounded page of saved files. Only the latest request may
  /// update the list, so a closed section, an app lock or a replaced dataset
  /// cannot let an older page appear later.
  Future<void> loadSourceCandidates() async {
    if (sourceLoading) return;
    final request = ++_sourceRequest;
    setState(() {
      sourceLoading = true;
      sourceFailed = false;
    });
    try {
      final page = await ref.read(
        supportingSourceCandidatesProvider(
          SupportingSourceRequest(
            personId: widget.personId,
            cursor: sourceCursor,
          ),
        ).future,
      );
      if (!mounted || request != _sourceRequest) return;
      final generation = ref.read(recordStoreProvider).value?.generation;
      if (ref.read(appLockProvider).locked) {
        setState(() => sourceLoading = false);
        return;
      }
      if (page.generation == null || page.generation != generation) {
        // A replaced dataset must not be offered. Do not auto-retry: the
        // visible retry stays a deliberate choice.
        setState(() {
          sourceLoading = false;
          sourceFailed = true;
        });
        return;
      }
      final merged = mergeSupportingSourcePage(sourceCandidates, page.records);
      setState(() {
        sourceCandidates
          ..clear()
          ..addAll(merged);
        sourceCursor = page.nextCursor;
        sourceHasMore = page.hasMore;
        sourceGeneration = page.generation;
        sourceLoaded = true;
        sourceLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _sourceRequest) return;
      setState(() {
        sourceLoading = false;
        sourceFailed = true;
      });
    }
  }

  void resetSourceCandidates() {
    _sourceRequest++;
    setState(() {
      sourceCandidates.clear();
      sourceCursor = null;
      sourceHasMore = false;
      sourceLoaded = false;
      sourceLoading = false;
      sourceFailed = false;
      sourceGeneration = null;
    });
  }

  void toggleDetails() {
    if (details) {
      setState(() {
        details = false;
        if (sourceLoading) {
          // Discard the page in flight; reopening loads from the same cursor.
          _sourceRequest++;
          sourceLoading = false;
        }
      });
      return;
    }
    setState(() => details = true);
    if (!sourceLoaded && !sourceFailed) unawaited(loadSourceCandidates());
  }

  Widget sourceReferences(bool enabled, AppLocalizations t) {
    final generation = ref.watch(
      recordStoreProvider.select((s) => s.value?.generation),
    );
    if (sourceLoaded &&
        sourceGeneration != null &&
        generation != null &&
        generation != sourceGeneration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && sourceGeneration != generation) {
          resetSourceCandidates();
        }
      });
    } else if (details && !sourceLoaded && !sourceLoading && !sourceFailed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            details &&
            !sourceLoaded &&
            !sourceLoading &&
            !sourceFailed) {
          unawaited(loadSourceCandidates());
        }
      });
    }
    final visible = generation == null
        ? const <AttachmentRecord>[]
        : [
            for (final record in sourceCandidates)
              if (supportingSourceEligible(
                record,
                personId: widget.personId,
                generation: generation,
              ))
                record,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (form.sourceReferences.isNotEmpty) ...[
          Text(t.supportingSourceReferences),
          for (var i = 0; i < form.sourceReferences.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_sourceLabel(t, form.sourceReferences[i])),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Semantics(
                      label: t.supportingRemoveSource(
                        _sourceLabel(t, form.sourceReferences[i]),
                      ),
                      child: VitalButton.secondary(
                        onPressed: enabled ? () => removeSource(i) : null,
                        child: Text(t.remove),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 12),
        Text(t.supportingSourceFiles),
        Text(t.supportingSourceFilesHelp),
        if (sourceFailed)
          LoadFailure(
            message: t.supportingLoadFailure,
            onRetry: () => unawaited(loadSourceCandidates()),
          )
        else if (!sourceLoaded)
          Text(t.loadingRecords),
        if (sourceLoaded) ...[
          if (visible.isEmpty && !sourceHasMore)
            Text(t.supportingNoSourceFiles),
          for (final record in visible)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(record.name),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Semantics(
                      label: t.supportingAttachSource(record.name),
                      child: VitalButton.secondary(
                        onPressed:
                            enabled &&
                                form.sourceReferences.length < 100 &&
                                !_sourceAttached(record)
                            ? () => attachSource(record)
                            : null,
                        child: Text(
                          _sourceAttached(record)
                              ? t.supportingAttached
                              : t.supportingAttach,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (sourceLoading)
            Text(t.loadingRecords)
          else if (sourceHasMore && !sourceFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: VitalButton.secondary(
                  onPressed: () => unawaited(loadSourceCandidates()),
                  child: Text(t.more),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget date(String prefix, String label) {
    final t = AppLocalizations.of(context);
    final enabled = !busy && !uncertain && !conflict;
    final precision = form.get('${prefix}Precision').isEmpty
        ? 'unknown'
        : form.get('${prefix}Precision');
    return VitalSection(
      title: Text(label),
      children: [
        VitalSegments<String>(
          values: const ['unknown', 'day', 'exact', 'partial'],
          selected: precision,
          onChanged: (v) {
            if (enabled) {
              setState(() {
                form.fields['${prefix}Precision'] = v;
                entryChanged();
              });
            }
          },
          label: (v) => switch (v) {
            'day' => t.supportingDay,
            'exact' => t.supportingExact,
            'partial' => t.supportingPartial,
            _ => t.supportingUnknown,
          },
        ),
        input(
          '${prefix}Text',
          t.supportingDateText,
          helper: precision == 'exact'
              ? t.supportingExactDateHelp
              : t.supportingDateHelp,
        ),
        if (precision == 'exact')
          input(
            '${prefix}Zone',
            t.supportingZone,
            helper: t.supportingZoneHelp,
          ),
      ],
    );
  }

  void addResult() {
    if (form.rows.length >= SupportingLimits.maxResults) return;
    setState(() {
      form.rows.add({
        'id': newCommandId(),
        'metricId': newCommandId(),
        'kind': 'numeric',
        'qualifier': 'exact',
      });
      page = (form.rows.length - 1) ~/ pageSize;
      entryChanged();
    });
  }

  Future<void> save() async {
    if (observation &&
        form.rows.isEmpty &&
        supportingOptional(form.get('notes')) == null) {
      setState(
        () =>
            error = AppLocalizations.of(context).supportingObservationRequired,
      );
      return;
    }
    if (frozen == null) {
      try {
        frozen = jsonEncode(form.snapshot().toJson());
      } catch (_) {
        setState(() => error = AppLocalizations.of(context).supportingInvalid);
        return;
      }
    }
    final snapshot = SupportingSnapshot.fromJson(
      Map<String, dynamic>.from(jsonDecode(frozen!) as Map),
    );
    await commit(
      (command) async {
        await ref.read(supportingWriterProvider)((
          commandId: command,
          generation: capturedGeneration!,
          personRevision: capturedPersonRevision!,
          targetRevision: capturedTargetRevision,
          snapshot: snapshot,
        ));
        ref.invalidate(supportingLookupProvider);
        ref.invalidate(supportingRevisionsProvider);
      },
      successPath: Uri(
        path: '/supporting/${widget.personId}/${snapshot.id.id}',
        queryParameters: {'return': entryFallback},
      ).toString(),
    );
  }

  @override
  String? recoverableCommandFailure(Object error) {
    if (error is ArgumentError ||
        error is FormatException ||
        error is SupportingLimitException) {
      frozen = null;
      return AppLocalizations.of(context).supportingInvalid;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(appLockProvider.select((s) => s.locked))) {
      return EntryPage(
        children: [Text(AppLocalizations.of(context).supportingLocked)],
      );
    }
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider);
    final owner = people.value
        ?.where((p) => p.id == widget.personId)
        .firstOrNull;
    if (people.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            message: t.supportingLoadFailure,
            onRetry: () => ref.invalidate(profilesProvider),
          ),
        ],
      );
    }
    if (!people.hasValue) return EntryPage(children: [Text(t.loadingRecords)]);
    if (owner == null) {
      return EntryPage(children: [Text(t.supportingUnavailable)]);
    }
    if (model == null) {
      if (widget.id != null) {
        final saved = ref.watch(
          supportingLookupProvider((
            personId: widget.personId,
            id: widget.id!,
            revision: null,
          )),
        );
        if (saved.hasError) {
          return EntryPage(
            children: [
              LoadFailure(
                message: t.supportingLoadFailure,
                onRetry: () => ref.invalidate(supportingLookupProvider),
              ),
            ],
          );
        }
        if (!saved.hasValue) {
          return EntryPage(children: [Text(t.loadingRecords)]);
        }
        original = saved.value;
        if (original == null || original!.isVoided) {
          return EntryPage(children: [Text(t.supportingUnavailable)]);
        }
      }
      model = SupportingFormModel(
        id: widget.id ?? newCommandId(),
        personId: widget.personId,
        observation: observation,
        numberFormat: supportingNumberFormat(context),
      );
      form.fields['_return'] =
          widget.returnLocation ?? '/supporting?person=${widget.personId}';
      if (original != null) {
        form.load(original!.snapshot);
      } else {
        if (widget.itemId != null) {
          form.contextLinks.add(
            SupportingContextLink(
              id: widget.itemId!,
              personId: widget.personId,
              kind: SupportingContextKind.item,
            ),
          );
        }
        if (widget.eventId != null) {
          form.contextLinks.add(
            SupportingContextLink(
              id: widget.eventId!,
              personId: widget.personId,
              kind: SupportingContextKind.event,
            ),
          );
        }
      }
    }
    if (!prepareDraft()) return wrap([Text(t.loadingRecords)]);
    final enabled = !busy && !uncertain && !conflict && !owner.isArchived;
    return wrap([
      Heading(
        observation
            ? (widget.id == null
                  ? t.supportingAddObservation
                  : t.supportingEditObservation)
            : (widget.id == null
                  ? t.supportingAddPanel
                  : t.supportingEditPanel),
      ),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(observation ? t.supportingObservationManual : t.supportingManual),
      if (owner.isArchived) Text(t.archivedHelp),
      input('title', t.supportingTitleLabel),
      date(
        'collection',
        observation ? t.supportingMeasured : t.supportingCollection,
      ),
      if (!observation) date('report', t.supportingReport),
      VitalSection(
        title: Text(observation ? t.supportingValues : t.supportingResults),
        action: VitalButton.secondary(
          onPressed: enabled && form.rows.length < SupportingLimits.maxResults
              ? addResult
              : null,
          child: Text(t.supportingAdd),
        ),
        children: [
          if (form.rows.isEmpty)
            Text(
              observation
                  ? t.supportingNoValuesObservation
                  : t.supportingNoValues,
            ),
          for (
            var index = page * pageSize;
            index < form.rows.length && index < (page + 1) * pageSize;
            index++
          )
            result(index, enabled),
          if (form.rows.length > pageSize)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                VitalButton.secondary(
                  onPressed: page > 0 ? () => setState(() => page--) : null,
                  child: Text(t.supportingPrevious),
                ),
                VitalButton.secondary(
                  onPressed: (page + 1) * pageSize < form.rows.length
                      ? () => setState(() => page++)
                      : null,
                  child: Text(t.supportingNext),
                ),
              ],
            ),
        ],
      ),
      SupportingDisclosure(
        label: observation ? t.supportingDetails : t.supportingSource,
        open: details,
        onPressed: toggleDetails,
      ),
      if (details)
        VitalSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!observation) ...[
                input('lab', t.supportingLab),
                input('labId', t.supportingLabIdentity),
                input('method', t.supportingMethod),
                input('methodId', t.supportingMethodIdentity),
                input('specimen', t.supportingSpecimen),
                input('specimenId', t.supportingSpecimenIdentity),
                input('accession', t.supportingAccession),
                input('reportId', t.supportingReportId),
              ],
              input('source', t.supportingSourceText, maxLines: 3),
              sourceReferences(enabled, t),
              input('by', t.supportingRecordedBy),
              input('notes', t.supportingNotes, maxLines: 5),
            ],
          ),
        ),
      if (form.contextLinks.isNotEmpty) ...[
        Text(t.supportingContext),
        Text(t.supportingContextHint),
        for (final c in form.contextLinks) Text(c.id),
      ],
      ?failure(),
      VitalButton(
        isLoading: busy,
        onPressed: enabled || uncertain && !busy && !conflict ? save : null,
        child: Text(uncertain ? t.retry : t.save),
      ),
    ]);
  }

  Widget result(int index, bool enabled) {
    final t = AppLocalizations.of(context), row = form.rows[index];
    final id = row['id']!;
    final open = openMetrics.contains(id);
    final numeric = (row['kind'] ?? 'numeric') == 'numeric';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: VitalSurface(
        key: ValueKey(id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.supportingResultPosition(index + 1, form.rows.length)),
            input(
              'marker',
              observation ? t.supportingComponent : t.supportingMarker,
              row: row,
              maxLines: 2,
            ),
            SupportingDisclosure(
              label: t.supportingMetrics,
              semanticLabel: t.supportingMarkerDisclosure(index + 1),
              open: open,
              onPressed: () => setState(() {
                if (open) {
                  openMetrics.remove(id);
                } else {
                  openMetrics.add(id);
                }
              }),
            ),
            if (open) metricPicker(row, enabled),
            if (!observation)
              input(
                'originalMarker',
                t.supportingOriginalMarker,
                row: row,
                maxLines: 2,
              ),
            if (!observation)
              input(
                'category',
                t.screenLabsCategory,
                row: row,
                helper: t.screenLabsCategoryHelp,
                maxLines: 2,
              ),
            VitalSegments<String>(
              values: const ['numeric', 'qualitative', 'missing'],
              selected: row['kind'] ?? 'numeric',
              onChanged: (v) {
                if (enabled) {
                  setState(() {
                    row['kind'] = v;
                    entryChanged();
                  });
                }
              },
              label: (v) => switch (v) {
                'qualitative' => t.supportingQualitative,
                'missing' => t.supportingMissing,
                _ => t.supportingNumeric,
              },
            ),
            input(
              'value',
              t.supportingValue,
              row: row,
              helper: numeric ? t.supportingValueHint : null,
              maxLines: 2,
            ),
            if (numeric)
              VitalSegments<String>(
                values: const [
                  'exact',
                  'lessThan',
                  'lessOrEqual',
                  'greaterThan',
                  'greaterOrEqual',
                ],
                selected: row['qualifier'] ?? 'exact',
                onChanged: (v) {
                  if (!enabled) return;
                  final controller = controllers['${row['id']}:value'];
                  final text = controller?.text ?? '';
                  final prefix = _valuePrefix(text);
                  if (prefix != null) {
                    // Choosing a qualifier here keeps one source of truth:
                    // the selected control replaces a typed prefix.
                    controller?.text = text
                        .trimLeft()
                        .substring(prefix.length)
                        .trimLeft();
                  }
                  setState(() {
                    row['qualifier'] = v;
                    entryChanged();
                  });
                },
                label: (v) => switch (v) {
                  'lessThan' => '<',
                  'lessOrEqual' => '≤',
                  'greaterThan' => '>',
                  'greaterOrEqual' => '≥',
                  _ => '=',
                },
              ),
            input('unit', t.supportingUnit, row: row),
            if (!observation)
              input(
                'range',
                t.supportingRange,
                row: row,
                helper: t.supportingRangeHint,
                maxLines: 2,
              ),
            if (!observation) input('flag', t.supportingFlag, row: row),
            VitalButton.secondary(
              onPressed: enabled
                  ? () => setState(() {
                      form.rows.removeAt(index);
                      openMetrics.remove(id);
                      if (page * pageSize >= form.rows.length && page > 0) {
                        page--;
                      }
                      entryChanged();
                    })
                  : null,
              child: Text(t.supportingRemove),
            ),
          ],
        ),
      ),
    );
  }

  Widget metricPicker(Map<String, String> row, bool enabled) {
    final t = AppLocalizations.of(context);
    final request = (
      personId: widget.personId,
      kind: observation
          ? SupportingMetricKind.observation
          : SupportingMetricKind.lab,
      search: metricSearch.text,
      offset: metricOffset,
    );
    final found = ref.watch(supportingMetricsProvider(request));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.supportingChooseMetric),
        LabelledInput(
          label: t.supportingSearchMarkers,
          controller: metricSearch,
        ),
        VitalButton.secondary(
          onPressed: () => setState(() => metricOffset = 0),
          child: Text(t.supportingApply),
        ),
        if (found.hasError)
          LoadFailure(
            message: t.supportingLoadFailure,
            onRetry: () => ref.invalidate(supportingMetricsProvider(request)),
          ),
        for (final metric in found.value ?? <SupportingMetric>[])
          VitalButton.secondary(
            multiline: true,
            onPressed: enabled
                ? () => setState(() {
                    row['metricId'] = metric.id;
                    row['marker'] = metric.name;
                    controllers['${row['id']}:marker']?.text = metric.name;
                    entryChanged();
                  })
                : null,
            child: Text(metric.name),
          ),
        Text(row['marker'] ?? t.supportingNewMetric),
        VitalButton.secondary(
          onPressed: enabled
              ? () => setState(() {
                  row['metricId'] = newCommandId();
                  entryChanged();
                })
              : null,
          child: Text(t.create),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            VitalButton.secondary(
              onPressed: metricOffset > 0
                  ? () => setState(() => metricOffset -= 50)
                  : null,
              child: Text(t.supportingPrevious),
            ),
            VitalButton.secondary(
              onPressed: found.value?.length == 50
                  ? () => setState(() => metricOffset += 50)
                  : null,
              child: Text(t.supportingNext),
            ),
          ],
        ),
      ],
    );
  }
}
