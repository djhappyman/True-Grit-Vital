import '../../app/app_lock.dart';

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/supporting.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'supporting_form_model.dart';
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
  bool details = false, metrics = false;
  int page = 0, metricOffset = 0;
  final metricSearch = TextEditingController();
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
  }) {
    final values = row ?? form.fields;
    final path = row == null ? key : '${row['id']}:$key';
    final controller = controllers.putIfAbsent(path, () {
      final c = TextEditingController(text: values[key] ?? '');
      c.addListener(() {
        values[key] = c.text;
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
        enabled: !busy && !uncertain && !conflict,
      ),
    );
  }

  Widget date(String prefix, String label) {
    final t = AppLocalizations.of(context);
    final enabled = !busy && !uncertain && !conflict;
    return VitalSection(
      title: Text(label),
      children: [
        VitalSegments<String>(
          values: const ['unknown', 'day', 'exact', 'partial'],
          selected: form.get('${prefix}Precision').isEmpty
              ? 'unknown'
              : form.get('${prefix}Precision'),
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
          helper: t.supportingDateHint,
        ),
        if (form.get('${prefix}Precision') == 'exact' ||
            form.get('${prefix}Precision') == 'day')
          input('${prefix}Zone', t.supportingZone),
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
          LoadFailure(onRetry: () => ref.invalidate(profilesProvider)),
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
        title: Text(t.supportingResults),
        action: VitalButton.secondary(
          onPressed: enabled && form.rows.length < SupportingLimits.maxResults
              ? addResult
              : null,
          child: Text(t.supportingAdd),
        ),
        children: [
          if (form.rows.isEmpty) Text(t.supportingNoResults),
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
        label: t.supportingSource,
        open: details,
        onPressed: () => setState(() => details = !details),
      ),
      if (details)
        VitalSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              input('lab', t.supportingLab),
              input('labId', t.supportingLabIdentity),
              input('method', t.supportingMethod),
              input('methodId', t.supportingMethodIdentity),
              input('specimen', t.supportingSpecimen),
              input('specimenId', t.supportingSpecimenIdentity),
              input('source', t.supportingSourceText),
              input('by', t.supportingRecordedBy),
              input('notes', t.supportingNotes),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: VitalSurface(
        key: ValueKey(row['id']),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.supportingResultPosition(index + 1, form.rows.length)),
            input('marker', t.supportingMarker, row: row),
            SupportingDisclosure(
              label: t.supportingMetrics,
              open: metrics,
              onPressed: () => setState(() => metrics = !metrics),
            ),
            if (metrics) metricPicker(row, enabled),
            input('originalMarker', t.supportingOriginalMarker, row: row),
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
            input('value', t.supportingValue, row: row),
            if (row['kind'] == 'numeric')
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
                  if (enabled) {
                    setState(() {
                      row['qualifier'] = v;
                      entryChanged();
                    });
                  }
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
            input(
              'range',
              t.supportingRange,
              row: row,
              helper: t.supportingRangeHint,
            ),
            input('flag', t.supportingFlag, row: row),
            VitalButton.secondary(
              onPressed: enabled
                  ? () => setState(() {
                      form.rows.removeAt(index);
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
        LabelledInput(label: t.supportingMarker, controller: metricSearch),
        VitalButton.secondary(
          onPressed: () => setState(() => metricOffset = 0),
          child: Text(t.supportingApply),
        ),
        if (found.hasError)
          LoadFailure(
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
