import '../stock/exact_amount.dart';

enum SupportingValueKind { numeric, qualitative, missing }

enum SupportingQualifier {
  exact,
  lessThan,
  lessOrEqual,
  greaterThan,
  greaterOrEqual,
}

/// Original source text survives even when its exact rational normalises zero
/// or trailing decimal places. Qualifiers never become measured boundary points.
final class SupportingValue {
  factory SupportingValue.numeric(
    String originalText, {
    SupportingQualifier qualifier = SupportingQualifier.exact,
  }) {
    if (originalText.length > 128) {
      throw const FormatException('supporting_number_length');
    }
    var number = originalText.trim();
    for (final prefix in ['<=', '>=', '≤', '≥', '<', '>']) {
      if (!number.startsWith(prefix)) continue;
      final sourceQualifier = switch (prefix) {
        '<=' || '≤' => SupportingQualifier.lessOrEqual,
        '>=' || '≥' => SupportingQualifier.greaterOrEqual,
        '<' => SupportingQualifier.lessThan,
        _ => SupportingQualifier.greaterThan,
      };
      if (qualifier != SupportingQualifier.exact &&
          qualifier != sourceQualifier) {
        throw const FormatException('supporting_qualifier_conflict');
      }
      qualifier = sourceQualifier;
      number = number.substring(prefix.length).trim();
      break;
    }
    final parsed = parseSupportingNumber(number);
    return SupportingValue._(
      SupportingValueKind.numeric,
      originalText,
      qualifier,
      parsed,
    );
  }
  factory SupportingValue.qualitative(String originalText) {
    supportingText(originalText, 'value_text', max: 8192);
    return SupportingValue._(
      SupportingValueKind.qualitative,
      originalText,
      SupportingQualifier.exact,
      null,
    );
  }
  factory SupportingValue.missing({String? originalText}) {
    if (originalText != null) {
      supportingText(originalText, 'value_text', max: 8192);
    }
    return SupportingValue._(
      SupportingValueKind.missing,
      originalText,
      SupportingQualifier.exact,
      null,
    );
  }
  const SupportingValue._(
    this.kind,
    this.originalText,
    this.qualifier,
    this.exactAmount,
  );
  final SupportingValueKind kind;
  final String? originalText;
  final SupportingQualifier qualifier;
  final ExactAmount? exactAmount;
  bool get isExactNumeric =>
      kind == SupportingValueKind.numeric &&
      qualifier == SupportingQualifier.exact;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'originalText': originalText,
    'qualifier': qualifier.name,
    'numerator': exactAmount?.numerator.toString(),
    'denominator': exactAmount?.denominator.toString(),
  };
  factory SupportingValue.fromJson(Map<String, dynamic> json) {
    final kind = SupportingValueKind.values.byName(json['kind'] as String);
    final value = switch (kind) {
      SupportingValueKind.numeric => SupportingValue.numeric(
        json['originalText'] as String,
        qualifier: SupportingQualifier.values.byName(
          json['qualifier'] as String,
        ),
      ),
      SupportingValueKind.qualitative => SupportingValue.qualitative(
        json['originalText'] as String,
      ),
      SupportingValueKind.missing => SupportingValue.missing(
        originalText: json['originalText'] as String?,
      ),
    };
    if (value.exactAmount?.numerator.toString() != json['numerator'] ||
        value.exactAmount?.denominator.toString() != json['denominator']) {
      throw const FormatException('supporting_value_pair');
    }
    return value;
  }
}

/// Mechanical envelope only: 128 source characters, 64 coefficient digits,
/// exponent magnitude <=308. No clinical plausibility rule or dose parser.
ExactAmount parseSupportingNumber(String source) {
  if (source.length > 128) {
    throw const FormatException('supporting_number_length');
  }
  final text = source.trim();
  final match = RegExp(
    r'^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$',
  ).firstMatch(text);
  if (match == null) throw const FormatException('supporting_number');
  final whole = match[2] ?? '', fraction = match[3] ?? match[4] ?? '';
  if (whole.length + fraction.length > 64) {
    throw const FormatException('supporting_number_digits');
  }
  final exponent = int.tryParse(match[5] ?? '0');
  if (exponent == null || exponent.abs() > 308) {
    throw const FormatException('supporting_number_exponent');
  }
  var coefficient = BigInt.parse('$whole$fraction');
  if (match[1] == '-') coefficient = -coefficient;
  final scale = fraction.length - exponent;
  return scale >= 0
      ? ExactAmount(coefficient, BigInt.from(10).pow(scale))
      : ExactAmount(coefficient * BigInt.from(10).pow(-scale));
}

void supportingText(String value, String code, {int max = 512}) {
  if (value.trim().isEmpty || value.length > max) throw ArgumentError(code);
}

void supportingOptionalText(String? value, String code, {int max = 8192}) {
  if (value != null) supportingText(value, code, max: max);
}

final class SupportingRangeBound {
  SupportingRangeBound({required this.value, this.inclusive = true});
  final ExactAmount value;
  final bool inclusive;
  Map<String, Object?> toJson() => {
    'numerator': value.numerator.toString(),
    'denominator': value.denominator.toString(),
    'inclusive': inclusive,
  };
  factory SupportingRangeBound.fromJson(Map<String, dynamic> json) =>
      SupportingRangeBound(
        value: ExactAmount.fromStorage(
          json['numerator'] as String,
          json['denominator'] as String,
        ),
        inclusive: json['inclusive'] as bool,
      );
}

/// Source-supplied bounds only. Unparseable text remains useful, never guessed.
final class SourceReferenceRange {
  SourceReferenceRange({
    required this.originalText,
    this.lower,
    this.upper,
    this.unit,
    this.applicabilityText,
  }) {
    supportingText(originalText, 'range_text', max: 8192);
    supportingOptionalText(unit, 'range_unit');
    supportingOptionalText(applicabilityText, 'range_applicability');
    if (lower != null &&
        upper != null &&
        (lower!.value > upper!.value ||
            lower!.value == upper!.value &&
                (!lower!.inclusive || !upper!.inclusive))) {
      throw ArgumentError('range_bounds');
    }
  }
  final String originalText;
  final SupportingRangeBound? lower, upper;
  final String? unit, applicabilityText;
  Map<String, Object?> toJson() => {
    'originalText': originalText,
    'lower': lower?.toJson(),
    'upper': upper?.toJson(),
    'unit': unit,
    'applicabilityText': applicabilityText,
  };
  factory SourceReferenceRange.fromJson(Map<String, dynamic> json) =>
      SourceReferenceRange(
        originalText: json['originalText'] as String,
        lower: json['lower'] == null
            ? null
            : SupportingRangeBound.fromJson(
                Map<String, dynamic>.from(json['lower'] as Map),
              ),
        upper: json['upper'] == null
            ? null
            : SupportingRangeBound.fromJson(
                Map<String, dynamic>.from(json['upper'] as Map),
              ),
        unit: json['unit'] as String?,
        applicabilityText: json['applicabilityText'] as String?,
      );
}
