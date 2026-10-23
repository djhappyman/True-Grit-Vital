import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/substance_profile.dart';
import 'medicine_strength_fields.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart' show LabelledInput, Heading;

String substanceRouteLabel(AppLocalizations t, SubstanceRoute route) =>
    switch (route) {
      SubstanceRoute.injectable => t.substanceInjectable,
      SubstanceRoute.oral => t.substanceOral,
      SubstanceRoute.other => t.substanceOther,
    };
String substanceFormLabel(AppLocalizations t, SubstanceForm form) =>
    switch (form) {
      SubstanceForm.oil => t.substanceOil,
      SubstanceForm.water => t.substanceWater,
      SubstanceForm.powderToMix => t.substanceMix,
      SubstanceForm.tablet => t.tablet,
      SubstanceForm.capsule => t.screenCreateFormCapsule,
      SubstanceForm.caplet => t.quickMedicineCaplet,
      SubstanceForm.liquid => t.liquid,
      SubstanceForm.powder => t.screenCreateFormPowder,
      SubstanceForm.other => t.substanceOther,
    };

class HalfLifeEditorData {
  HalfLifeEditorData(this.changed) {
    for (final c in controls) {
      c.addListener(changed);
    }
  }
  final VoidCallback changed;
  final value = TextEditingController(),
      context = TextEditingController(),
      source = TextEditingController();
  String unit = 'hours';
  Iterable<TextEditingController> get controls => [value, context, source];
  Map<String, Object?> capture() => {
    'value': value.text,
    'unit': unit,
    'context': context.text,
    'source': source.text,
  };
  void restore(Map<String, dynamic> m) {
    value.text = m['value'] as String? ?? '';
    unit = m['unit'] as String? ?? 'hours';
    context.text = m['context'] as String? ?? '';
    source.text = m['source'] as String? ?? '';
  }

  HalfLife? read() {
    if (controls.every((c) => c.text.trim().isEmpty)) return null;
    return HalfLife(
      value: value.text.trim().replaceAll(',', '.'),
      unit: unit,
      context: context.text.trim(),
      source: source.text.trim(),
    );
  }

  void dispose() {
    for (final c in controls) {
      c.dispose();
    }
  }
}

class HalfLifeEditor extends StatelessWidget {
  const HalfLifeEditor({
    super.key,
    required this.data,
    required this.enabled,
    required this.onChanged,
  });
  final HalfLifeEditorData data;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return VitalDisclosure(
      title: t.substanceHalfLife,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.substanceHalfLifeHelp),
          LabelledInput(
            label: t.substanceHalfLifeValue,
            controller: data.value,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          _Choices(
            values: const ['hours', 'days'],
            selected: data.unit,
            enabled: enabled,
            label: (v) => v == 'hours' ? t.substanceHours : t.substanceDays,
            onChanged: (v) {
              data.unit = v;
              data.changed();
              onChanged();
            },
          ),
          LabelledInput(
            label: t.substanceFormulation,
            controller: data.context,
            enabled: enabled,
            helper: t.substanceFormulationHelp,
          ),
          LabelledInput(
            label: t.substanceSource,
            controller: data.source,
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}

class SubstanceProfileEditorData {
  SubstanceProfileEditorData(this.changed) {
    other.addListener(changed);
    strength.addListener(changed);
    strengthBasis.addListener(changed);
    halfLife = HalfLifeEditorData(changed);
  }
  final VoidCallback changed;
  SubstanceRoute? route;
  SubstanceForm? form;
  String massUnit = 'mg';
  final other = TextEditingController(), strength = TextEditingController();
  final strengthBasis = TextEditingController(text: '1');
  late final HalfLifeEditorData halfLife;
  String encode() => jsonEncode({
    'route': route?.name,
    'form': form?.name,
    'otherForm': other.text,
    'strengthText': strength.text,
    'strengthBasisText': strengthBasis.text,
    'massUnit': massUnit,
    'halfLife': halfLife.capture(),
  });
  void restore(String encoded) {
    final m = jsonDecode(encoded) as Map<String, dynamic>;
    route = m['route'] == null
        ? null
        : SubstanceRoute.values.byName(m['route'] as String);
    form = m['form'] == null
        ? null
        : SubstanceForm.values.byName(m['form'] as String);
    other.text = m['otherForm'] as String? ?? '';
    strength.text = m['strengthText'] as String? ?? '';
    strengthBasis.text =
        m['strengthBasisText'] as String? ??
        (form == SubstanceForm.powderToMix ? '' : '1');
    massUnit = m['massUnit'] as String? ?? 'mg';
    halfLife.restore(Map<String, dynamic>.from(m['halfLife'] as Map? ?? {}));
  }

  void initialise(SubstanceProfile? p) {
    if (p != null) restore(jsonEncode(p.toJson()));
  }

  SubstanceProfile? read({bool blend = false}) {
    if (route == null) return null;
    if (form == null) throw const FormatException('choose_form');
    return SubstanceProfile(
      route: route!,
      form: form!,
      otherForm: other.text.trim(),
      massUnit: massUnit,
      strengthBasisText: blend || strength.text.trim().isEmpty
          ? '1'
          : strengthBasis.text.trim().replaceAll(',', '.'),
      strengthText: blend || strength.text.trim().isEmpty
          ? null
          : strength.text.trim().replaceAll(',', '.'),
      halfLife: blend ? null : halfLife.read(),
    );
  }

  void dispose() {
    other.dispose();
    strength.dispose();
    strengthBasis.dispose();
    halfLife.dispose();
  }
}

class SubstanceProfileEditor extends StatelessWidget {
  const SubstanceProfileEditor({
    super.key,
    required this.data,
    required this.enabled,
    required this.onChanged,
    this.blend = false,
  });
  final SubstanceProfileEditorData data;
  final bool enabled, blend;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final forms = switch (data.route) {
      SubstanceRoute.injectable => const [
        SubstanceForm.oil,
        SubstanceForm.water,
        SubstanceForm.powderToMix,
        SubstanceForm.other,
      ],
      SubstanceRoute.oral => const [
        SubstanceForm.tablet,
        SubstanceForm.capsule,
        SubstanceForm.caplet,
        SubstanceForm.liquid,
        SubstanceForm.powder,
        SubstanceForm.other,
      ],
      SubstanceRoute.other => const [SubstanceForm.other],
      null => const <SubstanceForm>[],
    };
    final isCount = const {
      SubstanceForm.tablet,
      SubstanceForm.capsule,
      SubstanceForm.caplet,
    }.contains(data.form);
    final isLiquid = const {
      SubstanceForm.oil,
      SubstanceForm.water,
      SubstanceForm.liquid,
      SubstanceForm.powderToMix,
    }.contains(data.form);
    void changed() {
      data.changed();
      onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.substanceTakenAs),
        _Choices(
          values: SubstanceRoute.values,
          selected: data.route,
          enabled: enabled,
          label: (r) => substanceRouteLabel(t, r),
          onChanged: (r) {
            if (data.route == r) return;
            data.route = r;
            data.form = r == SubstanceRoute.other ? SubstanceForm.other : null;
            data.strength.clear();
            data.strengthBasis.text = data.form == SubstanceForm.powderToMix
                ? ''
                : '1';
            changed();
          },
        ),
        if (data.route != null) ...[
          const SizedBox(height: 12),
          Text(t.formLabel),
          _Choices(
            values: forms,
            selected: data.form,
            enabled: enabled,
            label: (f) => substanceFormLabel(t, f),
            onChanged: (f) {
              if (data.form == f) return;
              data.form = f;
              data.strength.clear();
              changed();
            },
          ),
          if (data.form == SubstanceForm.other)
            LabelledInput(
              label: t.substanceOtherForm,
              controller: data.other,
              enabled: enabled,
            ),
          if (!blend && (isCount || isLiquid))
            MedicineStrengthFields(
              data: data,
              enabled: enabled,
              onChanged: onChanged,
            ),
          if (!blend) ...[
            const SizedBox(height: 12),
            HalfLifeEditor(
              data: data.halfLife,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ],
        ],
      ],
    );
  }
}

class SubstanceProfileSummary extends StatelessWidget {
  const SubstanceProfileSummary({super.key, required this.profile});
  final SubstanceProfile profile;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), h = profile.halfLife;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.substanceFormSummary(
            substanceRouteLabel(t, profile.route),
            profile.form == SubstanceForm.other
                ? profile.otherForm
                : substanceFormLabel(t, profile.form),
          ),
        ),
        if (profile.strengthText != null)
          Text(
            t.substanceStrengthSummary(
              profile.strengthText!,
              profile.massUnit == 'mcg' ? t.substanceMicrograms : 'mg',
              profile.strengthBasisText == '1'
                  ? profile.isCount
                        ? t.substanceEach
                        : 'ml'
                  : '${profile.strengthBasisText} ${profile.isCount ? t.dashboardUnitCount : 'ml'}',
            ),
          ),
        if (h != null) ...[
          Text(
            t.substanceHalfLifeSummary(
              h.value,
              h.unit == 'days' ? t.substanceDays : t.substanceHours,
            ),
          ),
          if (h.context.isNotEmpty) Text(h.context),
          if (h.source.isNotEmpty) Text(t.substanceSourceValue(h.source)),
        ],
      ],
    );
  }
}

class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.enabled,
    required this.label,
    required this.onChanged,
  });
  final List<T> values;
  final T? selected;
  final bool enabled;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in values)
        Semantics(
          selected: selected == v,
          inMutuallyExclusiveGroup: true,
          child: selected == v
              ? VitalButton(
                  onPressed: enabled ? () => onChanged(v) : null,
                  multiline: true,
                  child: Text(label(v)),
                )
              : VitalButton.secondary(
                  onPressed: enabled ? () => onChanged(v) : null,
                  multiline: true,
                  child: Text(label(v)),
                ),
        ),
    ],
  );
}
