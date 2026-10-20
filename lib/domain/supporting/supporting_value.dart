import '../stock/exact_amount.dart';

enum SupportingValueKind { numeric, qualitative, missing }

enum SupportingQualifier {
  exact,
  lessThan,
  lessOrEqual,
  greaterThan,
  greaterOrEqual,
}

/// The decimal and grouping marks this locale uses for exact numeric entry.
///
/// The saved [SupportingValue.originalText] is never rewritten. Only the text
/// given to the exact parser is normalised, and that parse text is retained in
/// JSON so a reopened record does not depend on the current device locale.
final class SupportingNumberFormat {
  const SupportingNumberFormat({
    this.decimalSeparator = '.',
    this.groupSeparator = ',',
  });
  final String decimalSeparator, groupSeparator;
}

/// Normalises a locale-formatted exact number without inventing a value.
///
/// A locale group mark is accepted only in valid three-digit groups. A comma in
/// a dot-decimal locale such as `1,5` is rejected rather than silently read as
/// fifteen. Plain whitespace is accepted as a group mark because source reports
/// commonly use it.
String normalizeSupportingNumberText(
  String source, {
  SupportingNumberFormat format = const SupportingNumberFormat(),
}) {
  var text = source.trim();
  if (text.isEmpty) return text;
  final sign = text.startsWith('-') || text.startsWith('+') ? text[0] : '';
  if (sign.isNotEmpty) text = text.substring(1);
  var exponent = '';
  final exponentIndex = text.toLowerCase().indexOf('e');
  if (exponentIndex >= 0) {
    exponent = text.substring(exponentIndex);
    text = text.substring(0, exponentIndex);
  }
  final decimal = format.decimalSeparator.isEmpty
      ? '.'
      : format.decimalSeparator;
  final group = format.groupSeparator.isEmpty ? ',' : format.groupSeparator;
  String whole = text;
  String? fraction;
  if (text.contains(decimal)) {
    if (text.indexOf(decimal) != text.lastIndexOf(decimal)) {
      throw const FormatException('supporting_number');
    }
    final parts = text.split(decimal);
    whole = parts[0];
    fraction = parts[1];
    if (fraction.contains(group)) {
      throw const FormatException('supporting_number');
    }
  } else if (decimal != '.' && text.contains('.')) {
    // A dot is a group mark in a comma-decimal locale. Treat it as a decimal
    // point unless the final group has exactly three digits.
    final last = text.lastIndexOf('.');
    final tail = text.substring(last + 1);
    if ('.'.allMatches(text).length == 1 && tail.length != 3) {
      whole = text.substring(0, last);
      fraction = tail;
    }
  }
  final digits = whole.isEmpty && fraction != null && fraction.isNotEmpty
      ? '0'
      : _supportingGroupedDigits(whole, group);
  if (fraction != null && !RegExp(r'^\d*$').hasMatch(fraction)) {
    throw const FormatException('supporting_number');
  }
  return '$sign$digits${fraction == null ? '' : '.$fraction'}$exponent';
}

String _supportingGroupedDigits(String whole, String group) {
  if (RegExp(r'^\d+$').hasMatch(whole)) return whole;
  final marks = <String>{group, ' ', '\u00A0', '\u202F'}..remove('');
  final alternation = marks.map(RegExp.escape).join('|');
  if (!RegExp('^\\d{1,3}(?:($alternation)\\d{3})+\$').hasMatch(whole)) {
    throw const FormatException('supporting_number');
  }
  return whole.replaceAll(RegExp('(?:$alternation)'), '');
}

/// Original source text survives even when its exact rational normalises zero
/// or trailing decimal places. Qualifiers never become measured boundary points.
final class SupportingValue {
  factory SupportingValue.numeric(
    String originalText, {
    SupportingQualifier qualifier = SupportingQualifier.exact,
    String? parseText,
    SupportingNumberFormat? numberFormat,
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
    final source = parseText ?? number;
    final parsedText = numberFormat == null
        ? source
        : normalizeSupportingNumberText(source, format: numberFormat);
    final parsed = parseSupportingNumber(parsedText);
    return SupportingValue._(
      SupportingValueKind.numeric,
      originalText,
      qualifier,
      parsed,
      parsedText,
    );
  }
  factory SupportingValue.qualitative(String originalText) {
    supportingText(originalText, 'value_text', max: 8192);
    return SupportingValue._(
      SupportingValueKind.qualitative,
      originalText,
      SupportingQualifier.exact,
      null,
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
      null,
    );
  }
  const SupportingValue._(
    this.kind,
    this.originalText,
    this.qualifier,
    this.exactAmount,
    this.parseText,
  );
  final SupportingValueKind kind;
  final String? originalText;
  final SupportingQualifier qualifier;
  final ExactAmount? exactAmount;

  /// The ASCII-normalised text used for exact parsing. It preserves the
  /// original lexeme separately and keeps a localised record reopenable.
  final String? parseText;
  bool get isExactNumeric =>
      kind == SupportingValueKind.numeric &&
      qualifier == SupportingQualifier.exact;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'originalText': originalText,
    'qualifier': qualifier.name,
    'parseText': parseText,
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
        parseText: json['parseText'] as String?,
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
