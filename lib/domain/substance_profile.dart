import 'dart:convert';

import 'stock/exact_amount.dart';

enum SubstanceRoute { injectable, oral, other }

enum SubstanceForm {
  oil,
  water,
  powderToMix,
  tablet,
  capsule,
  caplet,
  liquid,
  powder,
  other,
}

/// User-entered reference information, never a pharmacokinetic prediction.
final class HalfLife {
  HalfLife({
    required this.value,
    required this.unit,
    this.context = '',
    this.source = '',
  }) {
    ExactAmount.parseEntry(value);
    if (!const {'hours', 'days'}.contains(unit) ||
        context.length > 500 ||
        source.length > 2000) {
      throw const FormatException('half_life');
    }
  }
  final String value, unit, context, source;
  Map<String, Object?> toJson() => {
    'value': value,
    'unit': unit,
    'context': context,
    'source': source,
  };
  factory HalfLife.fromJson(Map<String, dynamic> m) => HalfLife(
    value: m['value'] as String,
    unit: m['unit'] as String,
    context: m['context'] as String? ?? '',
    source: m['source'] as String? ?? '',
  );
}

/// Descriptive choices, separate from an item's original labelled form/type.
final class SubstanceProfile {
  SubstanceProfile({
    required this.route,
    required this.form,
    this.otherForm = '',
    this.strengthText,
    this.strengthBasisText = '1',
    this.massUnit = 'mg',
    this.halfLife,
  }) {
    final valid = switch (route) {
      SubstanceRoute.injectable => const {
        SubstanceForm.oil,
        SubstanceForm.water,
        SubstanceForm.powderToMix,
        SubstanceForm.other,
      },
      SubstanceRoute.oral => const {
        SubstanceForm.tablet,
        SubstanceForm.capsule,
        SubstanceForm.caplet,
        SubstanceForm.liquid,
        SubstanceForm.powder,
        SubstanceForm.other,
      },
      SubstanceRoute.other => const {SubstanceForm.other},
    };
    if (!valid.contains(form) ||
        otherForm.length > 500 ||
        (form == SubstanceForm.other && otherForm.trim().isEmpty) ||
        !const {'mg', 'mcg'}.contains(massUnit)) {
      throw const FormatException('substance_profile');
    }
    ExactAmount.parseEntry(strengthBasisText);
    if (strengthText != null) {
      ExactAmount.parseEntry(strengthText!);
      if (!isCount && !isLiquid) {
        throw const FormatException('profile_strength');
      }
    }
    if (jsonEncode(toJson()).length > 8000) {
      throw const FormatException('profile_bound');
    }
  }
  final SubstanceRoute route;
  final SubstanceForm form;
  final String otherForm, massUnit;

  /// Quantity of the selected form containing strengthText. Old profiles use one.
  final String strengthBasisText;
  final String? strengthText;
  final HalfLife? halfLife;
  bool get isCount => const {
    SubstanceForm.tablet,
    SubstanceForm.capsule,
    SubstanceForm.caplet,
  }.contains(form);
  bool get isLiquid => const {
    SubstanceForm.oil,
    SubstanceForm.water,
    SubstanceForm.liquid,
    SubstanceForm.powderToMix,
  }.contains(form);
  static String unitFor(SubstanceForm form) => switch (form) {
    SubstanceForm.tablet ||
    SubstanceForm.capsule ||
    SubstanceForm.caplet => 'count',
    SubstanceForm.oil ||
    SubstanceForm.water ||
    SubstanceForm.liquid ||
    SubstanceForm.powderToMix => 'ml',
    _ => 'mg',
  };
  String get doseUnit => unitFor(form);
  ExactAmount? get strengthMg => strengthText == null
      ? null
      : ExactAmount.parseEntry(strengthText!) /
            ExactAmount(BigInt.from(massUnit == 'mcg' ? 1000 : 1)) /
            ExactAmount.parseEntry(strengthBasisText);
  String? get perUnitStrengthText {
    final mg = strengthMg;
    if (mg == null) return null;
    final value = mg * ExactAmount(BigInt.from(massUnit == 'mcg' ? 1000 : 1));
    if (value > ExactAmount.maxEntered ||
        (value * ExactAmount(BigInt.from(1000000))).denominator != BigInt.one) {
      return null;
    }
    return value.compactDecimal(places: 6);
  }

  LabelledStrength? labelledStrength(String itemId, String label) =>
      strengthMg == null
      ? null
      : LabelledStrength(
          ingredientId: itemId,
          label: label,
          mgPerMl: isLiquid ? strengthMg : null,
          mgPerCount: isCount ? strengthMg : null,
          preparation: form == SubstanceForm.powderToMix
              ? VialPreparation(
                  powderAmount: strengthText!,
                  massUnit: massUnit,
                  finalVolumeMl: strengthBasisText,
                )
              : null,
        );
  Map<String, Object?> toJson() => {
    'route': route.name,
    'form': form.name,
    'otherForm': otherForm,
    'strengthText': strengthText,
    if (strengthBasisText != '1') 'strengthBasisText': strengthBasisText,
    'massUnit': massUnit,
    'halfLife': halfLife?.toJson(),
  };
  factory SubstanceProfile.fromJson(Map<String, dynamic> m) => SubstanceProfile(
    route: SubstanceRoute.values.byName(m['route'] as String),
    form: SubstanceForm.values.byName(m['form'] as String),
    otherForm: m['otherForm'] as String? ?? '',
    strengthText: m['strengthText'] as String?,
    strengthBasisText: m['strengthBasisText'] as String? ?? '1',
    massUnit: m['massUnit'] as String? ?? 'mg',
    halfLife: m['halfLife'] == null
        ? null
        : HalfLife.fromJson(Map<String, dynamic>.from(m['halfLife'] as Map)),
  );
}
