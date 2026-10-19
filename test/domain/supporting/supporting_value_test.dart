import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'supporting_test_data.dart';

void main() {
  for (final pair in {
    '0': '0/1',
    '-0.000': '0/1',
    '+0': '0/1',
    '-12.3400': '-617/50',
    '.5': '1/2',
    '1.': '1/1',
    '1.234567890123456789': '1234567890123456789/1000000000000000000',
    '-2.5e-3': '-1/400',
    '1E+3': '1000/1',
  }.entries) {
    test('exact source ${pair.key} retains its lexeme', () {
      final value = SupportingValue.numeric(pair.key);
      expect(value.exactAmount.toString(), pair.value);
      expect(value.originalText, pair.key);
      expect(
        SupportingValue.fromJson(
          jsonDecode(jsonEncode(value.toJson())) as Map<String, dynamic>,
        ).toJson(),
        value.toJson(),
      );
    });
  }
  for (final text in [
    'NaN',
    'Infinity',
    '1,000',
    '0x10',
    '1e309',
    '1e-309',
    '1e99999999999999999999999',
    '1/3',
    '--1',
    '',
    List.filled(65, '1').join(),
    List.filled(129, '0').join(),
  ]) {
    test('unsupported number rejects rather than becomes zero: $text', () {
      expect(() => SupportingValue.numeric(text), throwsFormatException);
      final fallback = SupportingValue.qualitative(
        text.isEmpty ? 'Unreported source' : text,
      );
      expect(fallback.exactAmount, isNull);
    });
  }
  for (final pair in {
    '<0.1': SupportingQualifier.lessThan,
    '≤ -0.1': SupportingQualifier.lessOrEqual,
    '>=0': SupportingQualifier.greaterOrEqual,
    '>1e2': SupportingQualifier.greaterThan,
  }.entries) {
    test('qualified ${pair.key} never supplies a point', () {
      final value = SupportingValue.numeric(pair.key);
      expect(value.qualifier, pair.value);
      expect(value.isExactNumeric, isFalse);
      expect(value.originalText, pair.key);
      expect(SupportingValue.fromJson(value.toJson()).toJson(), value.toJson());
    });
  }
  test('conflicting qualifier rejects', () {
    expect(
      () => SupportingValue.numeric(
        '<1',
        qualifier: SupportingQualifier.greaterThan,
      ),
      throwsFormatException,
    );
  });
  test('qualitative, missing and exact zero stay distinct', () {
    final values = [
      SupportingValue.qualitative('Not detected'),
      SupportingValue.missing(),
      SupportingValue.numeric('0'),
    ];
    expect(values.map((v) => v.kind).toSet(), hasLength(3));
    expect(values[0].exactAmount, isNull);
    expect(values[1].exactAmount, isNull);
    expect(values[2].exactAmount, ExactAmount.zero);
  });
  test('range text survives failed parse and one-sided source bounds', () {
    final range = SourceReferenceRange(
      originalText: '< 5, method dependent',
      upper: SupportingRangeBound(
        value: parseSupportingNumber('5'),
        inclusive: false,
      ),
      unit: 'source unit',
      applicabilityText: 'Source population only',
    );
    expect(
      SourceReferenceRange.fromJson(range.toJson()).toJson(),
      range.toJson(),
    );
    expect(
      SourceReferenceRange(originalText: 'See source report').lower,
      isNull,
    );
    expect(
      () => SourceReferenceRange(
        originalText: 'invalid parsed bounds',
        lower: SupportingRangeBound(value: parseSupportingNumber('5')),
        upper: SupportingRangeBound(value: parseSupportingNumber('4')),
      ),
      throwsArgumentError,
    );
  });
  test('numeric codec rejects a mismatched exact storage pair', () {
    final json = SupportingValue.numeric('0').toJson();
    json['numerator'] = '1';
    expect(() => SupportingValue.fromJson(json), throwsFormatException);
  });
  test('scientific envelope keeps maximum exponent exact', () {
    expect(parseSupportingNumber('1e308').numerator.toString(), hasLength(309));
    expect(
      parseSupportingNumber('1e-308').denominator.toString(),
      hasLength(309),
    );
  });
}
