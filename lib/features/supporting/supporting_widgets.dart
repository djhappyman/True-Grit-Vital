import 'package:flutter/material.dart' show MaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../domain/supporting/supporting.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';

String supportingDateLabel(
  BuildContext context,
  WidgetRef ref,
  SupportingDate date,
) {
  final t = AppLocalizations.of(context);
  return switch (date.precision) {
    SupportingDatePrecision.unknown =>
      date.originalText ?? t.supportingUnknownDate,
    SupportingDatePrecision.partial =>
      date.originalText ?? t.supportingUnknownDate,
    // A saved civil day stays that day. No clock time, zone or midnight is
    // invented for it.
    SupportingDatePrecision.day => MaterialLocalizations.of(
      context,
    ).formatMediumDate(date.civilDate!.calendarValue),
    SupportingDatePrecision.exact => displayStamp(
      context,
      ref,
      date.instant!,
      includeSeconds: true,
    ),
  };
}

/// The saved source date and zone stay separate from the display projection.
String? supportingDateSourceLabel(
  BuildContext context,
  WidgetRef ref,
  SupportingDate date,
) {
  final t = AppLocalizations.of(context);
  final source = switch (date.precision) {
    SupportingDatePrecision.exact => [
      if (date.originalText != null && date.originalText!.isNotEmpty)
        date.originalText!,
      if (date.zoneId != null) date.zoneId!,
      if (date.utcOffsetMinutes != null) _offset(date.utcOffsetMinutes!),
    ],
    SupportingDatePrecision.day => [
      if (date.originalText != null &&
          date.originalText != date.civilDate.toString())
        date.originalText!,
      if (date.zoneId != null) date.zoneId!,
    ],
    SupportingDatePrecision.partial ||
    SupportingDatePrecision.unknown => const <String>[],
  };
  if (source.isEmpty) return null;
  return t.supportingSavedSource(source.join(', '));
}

String _offset(int value) =>
    'UTC${value < 0 ? '-' : '+'}${(value.abs() ~/ 60).toString().padLeft(2, '0')}:${(value.abs() % 60).toString().padLeft(2, '0')}';

String _qualifier(SupportingQualifier qualifier) => switch (qualifier) {
  SupportingQualifier.exact => '',
  SupportingQualifier.lessThan => '<',
  SupportingQualifier.lessOrEqual => '≤',
  SupportingQualifier.greaterThan => '>',
  SupportingQualifier.greaterOrEqual => '≥',
};

/// The entered value and source words only. A supplied unit is appended for
/// display by [supportingValueLabel]; a missing unit stays a separate visible
/// state so a bare number never implies one.
String supportingEnteredValue(AppLocalizations t, LabResultSnapshot result) {
  final value = result.value;
  final original = value.originalText;
  if (value.kind == SupportingValueKind.missing) {
    return original ?? t.supportingResultMissing;
  }
  final text = original ?? t.supportingResultMissing;
  if (value.kind != SupportingValueKind.numeric ||
      text.startsWith(RegExp(r'[<>≤≥]'))) {
    return text;
  }
  return '${_qualifier(value.qualifier)}$text';
}

/// Plot bounds need the full displayed value; exact-table rows show the unit
/// separately so a missing unit is visible rather than silently omitted.
String supportingValueLabel(AppLocalizations t, LabResultSnapshot result) {
  final value = supportingEnteredValue(t, result);
  return result.unit == null ? value : '$value ${result.unit}';
}

String _resultSemantics(AppLocalizations t, LabResultSnapshot result) =>
    t.supportingResultSemantics(
      result.originalMarkerText,
      supportingEnteredValue(t, result),
      result.unit ?? t.supportingUnitMissing,
      result.referenceRange?.originalText ?? t.supportingRangeMissing,
    );

class SupportingResultView extends StatelessWidget {
  const SupportingResultView({super.key, required this.result, this.action});
  final LabResultSnapshot result;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), p = result.provenance;
    final range = result.referenceRange,
        missing = result.value.kind == SupportingValueKind.missing,
        original = result.value.originalText;
    return VitalSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: _resultSemantics(t, result),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    result.originalMarkerText,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (result.markerName != result.originalMarkerText)
                    Text(
                      t.supportingDateLabel(
                        t.supportingMarker,
                        result.markerName,
                      ),
                    ),
                  if (missing) ...[
                    Text(t.supportingResultMissing),
                    if (original != null) Text(supportingValueLabel(t, result)),
                  ] else
                    Text(supportingValueLabel(t, result)),
                  if (result.unit == null)
                    Text(t.supportingUnitMissing)
                  else if (missing && original == null)
                    Text(t.supportingDateLabel(t.supportingUnit, result.unit!)),
                  Text(
                    range == null
                        ? t.supportingRangeMissing
                        : t.supportingDateLabel(
                            t.supportingRange,
                            range.originalText,
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (result.sourceFlag case final flag?)
            Text(t.supportingDateLabel(t.supportingFlag, flag)),
          if (p != null) SupportingProvenanceView(provenance: p),
          ?action,
        ],
      ),
    );
  }
}

class SupportingProvenanceView extends StatefulWidget {
  const SupportingProvenanceView({super.key, required this.provenance});
  final SupportingProvenance provenance;
  @override
  State<SupportingProvenanceView> createState() =>
      _SupportingProvenanceViewState();
}

class _SupportingProvenanceViewState extends State<SupportingProvenanceView> {
  bool identifiers = false;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), p = widget.provenance;
    final laboratory =
        p.laboratoryName ?? p.laboratoryId ?? t.supportingUnknown;
    final method = p.methodText ?? p.methodId ?? t.supportingUnknown;
    final specimen = p.specimenText ?? p.specimenId ?? t.supportingUnknown;
    final identityRows = <String, String?>{
      t.supportingLabIdentity: p.laboratoryId,
      t.supportingMethodIdentity: p.methodId,
      t.supportingSpecimenIdentity: p.specimenId,
    };
    final hasIdentities = identityRows.values.any((value) => value != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Laboratory, method and specimen belong to a transcribed report. An
        // observation keeps only the source words that actually apply.
        if (p.mode == SupportingProvenanceMode.manualTranscription) ...[
          Text(t.supportingDateLabel(t.supportingLab, laboratory)),
          Text(t.supportingDateLabel(t.supportingMethod, method)),
          Text(t.supportingDateLabel(t.supportingSpecimen, specimen)),
          if (hasIdentities)
            SupportingDisclosure(
              label: t.supportingIdentifiers,
              semanticLabel: t.supportingIdentifiers,
              open: identifiers,
              onPressed: () => setState(() => identifiers = !identifiers),
            ),
          if (identifiers)
            for (final row in identityRows.entries)
              if (row.value != null)
                Text(t.supportingDateLabel(row.key, row.value!)),
        ],
        if (p.sourceText case final source?)
          Text(t.supportingDateLabel(t.supportingSourceText, source)),
        if (p.recordedBy case final recordedBy?)
          Text(t.supportingDateLabel(t.supportingRecordedBy, recordedBy)),
        if (p.sourceReferences.isNotEmpty) ...[
          Text(t.supportingSourceReferences),
          for (final source in p.sourceReferences)
            _SupportingSourceReferenceView(source: source),
        ],
      ],
    );
  }
}

class _SupportingSourceReferenceView extends StatelessWidget {
  const _SupportingSourceReferenceView({required this.source});
  final SupportingSourceReference source;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final label =
        source.originalText ?? t.supportingSavedSourceReference(source.version);
    final route = supportingSourceRoute(source);
    final opens = route != null;
    final textOnly = source.kind == SupportingSourceKind.report;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label),
          if (textOnly)
            Text(t.supportingSourceTextOnly)
          else if (!opens)
            Text(t.supportingSourceUnavailable)
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                label: t.supportingOpenSourceVersion(source.version),
                child: VitalButton.secondary(
                  onPressed: () => context.push(route),
                  child: Text(t.supportingOpen),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Only a live, exact attachment version can be opened as its saved source.
String? supportingSourceRoute(SupportingSourceReference source) {
  if (source.kind != SupportingSourceKind.attachment ||
      source.contentVersionId == null) {
    return null;
  }
  return Uri(
    path: '/supporting-source/${source.personId}/${source.id}',
    queryParameters: {
      'revision': source.version.toString(),
      'version': source.contentVersionId!,
    },
  ).toString();
}

class SupportingDisclosure extends StatelessWidget {
  const SupportingDisclosure({
    super.key,
    required this.label,
    required this.open,
    required this.onPressed,
    this.semanticLabel,
  });
  final String label;
  final bool open;
  final VoidCallback onPressed;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: semanticLabel,
      expanded: open,
      child: VitalButton.secondary(onPressed: onPressed, child: Text(label)),
    ),
  );
}
