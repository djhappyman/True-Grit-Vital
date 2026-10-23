import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../domain/substance_profile.dart';
import '../../domain/stock/exact_amount.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../stock/stock_providers.dart' show stockDecimal;
import 'substance_profile_editor.dart';

/// One grouped form choice sets the canonical unit; no guessed concentration.
class MedicineFormFields extends StatelessWidget {
  const MedicineFormFields({
    super.key,
    required this.data,
    required this.enabled,
    required this.onChanged,
    this.categoryField,
  });
  final SubstanceProfileEditorData data;
  final bool enabled;
  final VoidCallback onChanged;
  final Widget? categoryField;
  static const options = [
    SubstanceForm.tablet,
    SubstanceForm.caplet,
    SubstanceForm.capsule,
    SubstanceForm.liquid,
    SubstanceForm.powder,
    SubstanceForm.oil,
    SubstanceForm.water,
    SubstanceForm.powderToMix,
  ];
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final formField = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.quickMedicineForm, style: VitalType.label),
        const SizedBox(height: 4),
        Text(
          t.quickMedicineFormHelp,
          style: VitalType.metadata.copyWith(color: VitalColors(context).muted),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: VitalSelect<String>(
            label: t.quickMedicineForm,
            value: data.form?.name ?? '',
            values: options.map((f) => f.name).toList(),
            labelOf: (key) => key.isEmpty
                ? t.quickMedicineChooseForm
                : substanceFormLabel(t, SubstanceForm.values.byName(key)),
            groupOf: (key) => _injectable(SubstanceForm.values.byName(key))
                ? t.substanceInjectable
                : t.substanceOral,
            subtitleOf: (key) => switch (SubstanceForm.values.byName(key)) {
              SubstanceForm.tablet => t.quickMedicineTabletHint,
              SubstanceForm.caplet => t.quickMedicineCapletHint,
              SubstanceForm.capsule => t.quickMedicineCapsuleHint,
              SubstanceForm.liquid => t.quickMedicineLiquidHint,
              SubstanceForm.powder => t.quickMedicinePowderHint,
              SubstanceForm.oil => t.quickMedicineOilHint,
              SubstanceForm.water => t.quickMedicineWaterHint,
              SubstanceForm.powderToMix => t.quickMedicineMixedHint,
              SubstanceForm.other => t.substanceOther,
            },
            enabled: enabled,
            onChanged: (key) {
              final form = SubstanceForm.values.byName(key);
              if (form == data.form) return;
              data.route = _injectable(form)
                  ? SubstanceRoute.injectable
                  : SubstanceRoute.oral;
              data.form = form;
              data.strength.clear();
              data.strengthBasis.text = form == SubstanceForm.powderToMix
                  ? ''
                  : '1';
              data.changed();
              onChanged();
            },
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (categoryField == null)
          formField
        else
          VitalFormRow(first: formField, second: categoryField!),
        const SizedBox(height: 16),
        if (data.form != null &&
            data.form != SubstanceForm.other &&
            data.form != SubstanceForm.powder)
          MedicineStrengthFields(
            data: data,
            enabled: enabled,
            onChanged: onChanged,
          ),
        if (data.form == SubstanceForm.powder)
          Text(t.quickMedicinePowderHelp, style: VitalType.metadata),
      ],
    );
  }

  static bool _injectable(SubstanceForm f) => const {
    SubstanceForm.oil,
    SubstanceForm.water,
    SubstanceForm.powderToMix,
  }.contains(f);
}

/// Main entry retains the label amount and quantity. The per-one equivalent is
/// display-only; its rounded preview is never parsed back into data.
class MedicineStrengthFields extends ConsumerWidget {
  const MedicineStrengthFields({
    super.key,
    required this.data,
    required this.enabled,
    required this.onChanged,
  });
  final SubstanceProfileEditorData data;
  final bool enabled;
  final VoidCallback onChanged;

  String _unit(AppLocalizations t, {bool plural = false}) =>
      switch (data.form) {
        SubstanceForm.tablet =>
          plural ? t.quickMedicineTablets : t.quickMedicineTablet,
        SubstanceForm.caplet =>
          plural ? t.quickMedicineCaplets : t.quickMedicineCapletUnit,
        SubstanceForm.capsule =>
          plural ? t.quickMedicineCapsules : t.quickMedicineCapsule,
        _ => 'ml',
      };

  Future<void> _convert(BuildContext context, WidgetRef ref) async {
    if (!enabled || ref.read(appLockProvider).locked) return;
    final lock = ref.read(appLockProvider),
        generation = ref.read(recordStoreProvider).value?.generation;
    final oldForm = data.form,
        oldStrength = data.strength.text,
        oldBasis = data.strengthBasis.text,
        oldUnit = data.massUnit;
    final result =
        await showVitalDialog<({String basis, String amount, String unit})>(
          context: context,
          builder: (context) => _LabelStrengthDialog(
            basis: oldBasis,
            amount: oldStrength,
            unit: oldUnit,
            quantityUnit: _unit(AppLocalizations.of(context), plural: true),
          ),
        );
    if (!context.mounted ||
        result == null ||
        !enabled ||
        data.form != oldForm ||
        data.strength.text != oldStrength ||
        data.strengthBasis.text != oldBasis ||
        data.massUnit != oldUnit ||
        !identical(ref.read(appLockProvider), lock) ||
        ref.read(appLockProvider).locked ||
        ref.read(recordStoreProvider).value?.generation != generation) {
      return;
    }
    if (result.amount.isEmpty) {
      data.strength.clear();
      data.strengthBasis.text = '1';
      data.changed();
      onChanged();
      return;
    }
    data.massUnit = result.unit;
    // Keep the label relationship, even when its per-one value terminates.
    // The field and live preview derive that equivalent without replacing it.
    data.strengthBasis.text = result.basis;
    data.strength.text = result.amount;
    data.changed();
    onChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context), c = VitalColors(context);
    final mixed = data.form == SubstanceForm.powderToMix;
    return ListenableBuilder(
      listenable: Listenable.merge([data.strength, data.strengthBasis]),
      builder: (context, _) {
        SubstanceProfile? profile;
        ExactAmount? basis;
        try {
          profile = data.read();
        } catch (_) {
          /* The parent owns saved-value validation. */
        }
        try {
          basis = ExactAmount.parseEntry(
            data.strengthBasis.text.replaceAll(',', '.'),
          );
        } catch (_) {
          /* Incomplete volume entry has no calculated preview. */
        }
        final basisIsOne = basis == ExactAmount(BigInt.one);
        final mass = profile?.strengthMg;
        final shownMass = mass == null
            ? null
            : mass *
                  ExactAmount(BigInt.from(data.massUnit == 'mcg' ? 1000 : 1));
        final approximate =
            shownMass != null &&
            (shownMass * ExactAmount(BigInt.from(1000000))).denominator !=
                BigInt.one;
        Widget massRow() => _QuantityPair(
          label: mixed ? t.quickMedicinePowderAmount : t.quickMedicineStrength,
          helper: mixed ? null : t.quickMedicineStrengthHelp,
          suffix: mixed
              ? null
              : t.quickMedicinePer(
                  data.strengthBasis.text,
                  _unit(t, plural: !basisIsOne),
                ),
          compactUnit: true,
          number: TextField(
            controller: data.strength,
            enabled: enabled,
            placeholder: Text(t.amountLabel),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          unit: VitalSelect<String>(
            label: t.quickMedicineMassUnit,
            value: data.massUnit,
            values: const ['mg', 'mcg'],
            labelOf: (u) => u == 'mcg' ? t.substanceMicrograms : u,
            selectedLabelOf: (u) => u,
            enabled: enabled,
            onChanged: (unit) {
              data.massUnit = unit;
              data.changed();
              onChanged();
            },
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (mixed) ...[
              massRow(),
              const SizedBox(height: 12),
              _QuantityPair(
                label: t.quickMedicineFinalVolume,
                number: TextField(
                  controller: data.strengthBasis,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                unit: const _FixedUnit('ml'),
              ),
              const SizedBox(height: 6),
              Text(
                t.quickMedicineFinalHelp,
                style: VitalType.metadata.copyWith(color: c.muted),
              ),
            ] else
              massRow(),
            const SizedBox(height: 8),
            if (shownMass != null && !basisIsOne)
              Text(
                approximate
                    ? t.quickMedicineEquivalentApprox(
                        _unit(t),
                        shownMass.compactDecimal(places: 6),
                        data.massUnit,
                      )
                    : t.quickMedicineEquivalent(
                        _unit(t),
                        shownMass.compactDecimal(places: 6),
                        data.massUnit,
                      ),
                style: VitalType.control.copyWith(
                  color: c.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (!mixed)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: VitalControlStyle(
                  quiet: true,
                  child: Button(
                    style: ButtonVariance.ghost,
                    onPressed: enabled ? () => _convert(context, ref) : null,
                    child: Text(t.quickMedicineConvert),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuantityPair extends StatelessWidget {
  const _QuantityPair({
    required this.label,
    required this.number,
    required this.unit,
    this.suffix,
    this.helper,
    this.compactUnit = false,
  });
  final String label;
  final String? suffix, helper;
  final bool compactUnit;
  final Widget number, unit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: VitalType.label),
      if (helper != null) ...[
        const SizedBox(height: 4),
        Text(
          helper!,
          style: VitalType.metadata.copyWith(color: VitalColors(context).muted),
        ),
      ],
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final scaler = MediaQuery.textScalerOf(context);
          final scale = scaler.scale(14) / 14;
          final unitWidth = 96 * scale;
          final numberWidth = 112 * scale;
          final referenceStyle = VitalType.control.copyWith(
            color: VitalColors(context).accent,
            fontWeight: FontWeight.w700,
          );
          final painter = TextPainter(
            text: TextSpan(text: suffix ?? '', style: referenceStyle),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          final referenceWidth = painter.width;
          painter.dispose();
          final inline =
              suffix != null &&
              constraints.maxWidth >=
                  numberWidth + unitWidth + referenceWidth + 24;
          final stackInputs =
              compactUnit &&
              constraints.maxWidth < numberWidth + unitWidth + 12;
          final reference = suffix == null
              ? null
              : Text(suffix!, style: referenceStyle);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stackInputs) ...[
                Semantics(label: label, child: number),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: unitWidth.clamp(0, constraints.maxWidth),
                    child: unit,
                  ),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: Semantics(label: label, child: number),
                    ),
                    const SizedBox(width: 12),
                    if (compactUnit)
                      SizedBox(width: unitWidth, child: unit)
                    else
                      Expanded(child: unit),
                    if (inline) ...[const SizedBox(width: 12), reference!],
                  ],
                ),
              if (reference != null && !inline) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: reference,
                ),
              ],
            ],
          );
        },
      ),
    ],
  );
}

class _FixedUnit extends StatelessWidget {
  const _FixedUnit(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 56),
    child: Center(
      child: Text(label, style: VitalType.control, textAlign: TextAlign.center),
    ),
  );
}

class _LabelStrengthDialog extends ConsumerStatefulWidget {
  const _LabelStrengthDialog({
    required this.basis,
    required this.amount,
    required this.unit,
    required this.quantityUnit,
  });
  final String basis, amount, unit, quantityUnit;
  @override
  ConsumerState<_LabelStrengthDialog> createState() =>
      _LabelStrengthDialogState();
}

class _LabelStrengthDialogState extends ConsumerState<_LabelStrengthDialog> {
  late final basis = TextEditingController(text: widget.basis),
      amount = TextEditingController(text: widget.amount);
  late String unit = widget.unit;
  late final lock = ref.read(appLockProvider);
  late final generation = ref.read(recordStoreProvider).value?.generation;
  @override
  void initState() {
    super.initState();
    lock;
    generation;
  }

  void _dismiss() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  String? error;
  @override
  void dispose() {
    basis.dispose();
    amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (ref.read(appLockProvider).locked ||
        !identical(ref.read(appLockProvider), lock) ||
        ref.read(recordStoreProvider).value?.generation != generation) {
      Navigator.of(context).pop();
      return;
    }
    try {
      final b = stockDecimal(basis.text), a = stockDecimal(amount.text);
      ExactAmount.parseEntry(b);
      ExactAmount.parseEntry(a);
      Navigator.of(context).pop((basis: b, amount: a, unit: unit));
    } catch (_) {
      setState(
        () => error = AppLocalizations.of(context).quickMedicineAmountsInvalid,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    ref.listen(appLockProvider, (before, after) {
      if (after.locked && before?.locked != true) _dismiss();
    });
    ref.listen(recordStoreProvider.select((s) => s.value?.generation), (
      before,
      after,
    ) {
      if (before != null && before != after) _dismiss();
    });
    return VitalDialog(
      title: Text(t.quickMedicineLabelTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.quickMedicineLabelHelp, style: VitalType.metadata),
          const SizedBox(height: 16),
          _QuantityPair(
            label: t.quickMedicineFor,
            number: TextField(
              controller: basis,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            unit: _FixedUnit(widget.quantityUnit),
          ),
          const SizedBox(height: 12),
          _QuantityPair(
            label: t.quickMedicineContains,
            number: TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            unit: VitalSelect<String>(
              label: t.quickMedicineMassUnit,
              value: unit,
              values: const ['mg', 'mcg'],
              labelOf: (u) => u == 'mcg' ? t.substanceMicrograms : u,
              onChanged: (value) => setState(() => unit = value),
            ),
          ),
          if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        ],
      ),
      actions: [
        if (widget.amount.isNotEmpty)
          VitalButton.secondary(
            onPressed: () =>
                Navigator.of(context).pop((basis: '1', amount: '', unit: unit)),
            child: Text(t.clear),
          ),
        VitalButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        VitalButton(onPressed: _submit, child: Text(t.done)),
      ],
    );
  }
}
