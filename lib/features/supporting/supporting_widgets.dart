import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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
    SupportingDatePrecision.partial => date.originalText!,
    SupportingDatePrecision.day =>
      '${date.civilDate}${date.zoneId == null ? '' : ' (${date.zoneId})'}',
    SupportingDatePrecision.exact =>
      '${date.originalText ?? date.instant!.toIso8601String()} (${date.zoneId}, ${_offset(date.utcOffsetMinutes!)})',
  };
}

String _offset(int value) =>
    'UTC${value < 0 ? '-' : '+'}${(value.abs() ~/ 60).toString().padLeft(2, '0')}:${(value.abs() % 60).toString().padLeft(2, '0')}';
String supportingValueLabel(AppLocalizations t, LabResultSnapshot result) {
  final value = result.value;
  final original = value.originalText ?? t.supportingMissing;
  final qualifier = switch (value.qualifier) {
    SupportingQualifier.exact => '',
    SupportingQualifier.lessThan => '<',
    SupportingQualifier.lessOrEqual => '≤',
    SupportingQualifier.greaterThan => '>',
    SupportingQualifier.greaterOrEqual => '≥',
  };
  return '${original.startsWith(RegExp(r'[<>≤≥]')) ? '' : qualifier}$original${result.unit == null ? '' : ' ${result.unit}'}';
}

class SupportingResultView extends StatelessWidget {
  const SupportingResultView({super.key, required this.result, this.action});
  final LabResultSnapshot result;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), p = result.provenance;
    return VitalSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            result.originalMarkerText,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(supportingValueLabel(t, result)),
          if (result.referenceRange case final range?)
            Text(t.supportingDateLabel(t.supportingRange, range.originalText)),
          if (result.sourceFlag case final flag?)
            Text(t.supportingDateLabel(t.supportingFlag, flag)),
          if (p != null) SupportingProvenanceView(provenance: p),
          ?action,
        ],
      ),
    );
  }
}

class SupportingProvenanceView extends StatelessWidget {
  const SupportingProvenanceView({super.key, required this.provenance});
  final SupportingProvenance provenance;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), p = provenance;
    final values = <String, String?>{
      t.supportingLab: p.laboratoryName,
      t.supportingLabIdentity: p.laboratoryId,
      t.supportingMethod: p.methodText,
      t.supportingMethodIdentity: p.methodId,
      t.supportingSpecimen: p.specimenText,
      t.supportingSpecimenIdentity: p.specimenId,
      t.supportingSourceText: p.sourceText,
      t.supportingRecordedBy: p.recordedBy,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in values.entries)
          if (e.value != null) Text(t.supportingDateLabel(e.key, e.value!)),
        for (final source in p.sourceReferences)
          Text(
            t.supportingSourceVersion(
              source.version.toString(),
              source.contentVersionId ?? source.id,
            ),
          ),
      ],
    );
  }
}

class SupportingDisclosure extends StatelessWidget {
  const SupportingDisclosure({
    super.key,
    required this.label,
    required this.open,
    required this.onPressed,
  });
  final String label;
  final bool open;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      expanded: open,
      child: VitalButton.secondary(onPressed: onPressed, child: Text(label)),
    ),
  );
}
