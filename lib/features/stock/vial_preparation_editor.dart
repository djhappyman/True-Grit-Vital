import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/stock/exact_amount.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart' show LabelledInput, Heading;

class VialPreparationEditorData {
  VialPreparationEditorData(this.changed) {
    for (final c in controls) {
      c.addListener(changed);
    }
  }
  final VoidCallback changed;
  final powder = TextEditingController(),
      finalVolume = TextEditingController(),
      liquid = TextEditingController(),
      added = TextEditingController(),
      date = TextEditingController();
  String massUnit = 'mg';
  Iterable<TextEditingController> get controls => [
    powder,
    finalVolume,
    liquid,
    added,
    date,
  ];
  String encode() => jsonEncode({
    'powder': powder.text,
    'finalVolume': finalVolume.text,
    'liquid': liquid.text,
    'added': added.text,
    'date': date.text,
    'massUnit': massUnit,
  });
  void restore(String encoded) {
    final m = jsonDecode(encoded) as Map<String, dynamic>;
    powder.text = m['powder'] as String? ?? '';
    finalVolume.text = m['finalVolume'] as String? ?? '';
    liquid.text = m['liquid'] as String? ?? '';
    added.text = m['added'] as String? ?? '';
    date.text = m['date'] as String? ?? '';
    massUnit = m['massUnit'] as String? ?? 'mg';
  }

  VialPreparation read() => VialPreparation(
    powderAmount: powder.text.trim().replaceAll(',', '.'),
    massUnit: massUnit,
    finalVolumeMl: finalVolume.text.trim().replaceAll(',', '.'),
    liquid: liquid.text.trim(),
    addedVolumeMl: added.text.trim().isEmpty
        ? null
        : added.text.trim().replaceAll(',', '.'),
    preparedOn: date.text.trim().isEmpty ? null : date.text.trim(),
  );
  void dispose() {
    for (final c in controls) {
      c.dispose();
    }
  }
}

class VialPreparationEditor extends StatelessWidget {
  const VialPreparationEditor({
    super.key,
    required this.data,
    required this.enabled,
    required this.onChanged,
  });
  final VialPreparationEditorData data;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(data.controls.toList()),
      builder: (context, _) {
        VialPreparation? preview;
        try {
          preview = data.read();
        } catch (_) {
          /* Field validation is shown on Save. */
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Heading(t.vialMixed),
            Text(t.vialMixedHelp),
            LabelledInput(
              label: t.vialAmount,
              controller: data.powder,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final u in ['mg', 'mcg'])
                  Semantics(
                    selected: data.massUnit == u,
                    inMutuallyExclusiveGroup: true,
                    child: VitalButton.secondary(
                      onPressed: enabled
                          ? () {
                              data.massUnit = u;
                              data.changed();
                              onChanged();
                            }
                          : null,
                      child: Text(u == 'mcg' ? t.substanceMicrograms : u),
                    ),
                  ),
              ],
            ),
            LabelledInput(
              label: t.vialFinalVolume,
              controller: data.finalVolume,
              helper: t.vialFinalHelp,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            if (preview != null)
              Text(
                t.vialEquivalent(preview.mgPerMl.compactDecimal()),
                key: const ValueKey('vial-strength-preview'),
              ),
            VitalDisclosure(
              title: t.vialDetails,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabelledInput(
                    label: t.vialLiquid,
                    controller: data.liquid,
                    enabled: enabled,
                  ),
                  LabelledInput(
                    label: t.vialAdded,
                    controller: data.added,
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  LabelledInput(
                    picker: VitalPickerKind.date,
                    label: t.vialDate,
                    controller: data.date,
                    enabled: enabled,
                    helper: t.vialDateHelp,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class VialPreparationSummary extends StatelessWidget {
  const VialPreparationSummary({super.key, required this.preparation});
  final VialPreparation preparation;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), p = preparation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.vialFacts(
            p.powderAmount,
            p.massUnit == 'mcg' ? t.substanceMicrograms : 'mg',
            p.finalVolumeMl,
          ),
        ),
        Text(t.vialEquivalent(p.mgPerMl.compactDecimal())),
        if (p.liquid.isNotEmpty) Text(p.liquid),
        if (p.addedVolumeMl != null) Text(t.vialAddedValue(p.addedVolumeMl!)),
        if (p.preparedOn != null) Text(t.vialDateValue(p.preparedOn!)),
      ],
    );
  }
}
