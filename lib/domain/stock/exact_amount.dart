/// Exact rational arithmetic. No floating-point values enter bookkeeping.
final class ExactAmount implements Comparable<ExactAmount> {
  factory ExactAmount(BigInt numerator, [BigInt? denominator]) {
    final d = denominator ?? BigInt.one;
    if (d == BigInt.zero) throw ArgumentError('zero_denominator');
    final divisor = numerator.gcd(d);
    final sign = d.isNegative ? -BigInt.one : BigInt.one;
    return ExactAmount._(numerator ~/ divisor * sign, d ~/ divisor * sign);
  }
  const ExactAmount._(this.numerator, this.denominator);
  final BigInt numerator, denominator;
  static final zero = ExactAmount(BigInt.zero);
  static final maxEntered = ExactAmount(BigInt.from(9000000000));

  /// Canonical decimal entry, positive, at most six places and 9e9 units.
  factory ExactAmount.parseEntry(String text) {
    if (text.length > 32 || !RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(text)) {
      throw const FormatException('quantity_format');
    }
    final parts = text.split('.');
    final scale = parts.length == 1 ? 0 : parts[1].length;
    final value = ExactAmount(
      BigInt.parse(parts.join()),
      BigInt.from(10).pow(scale),
    );
    if (value <= zero || value > maxEntered) throw RangeError('quantity_range');
    return value;
  }

  /// Reads canonical storage pairs without passing through SQLite numbers.
  factory ExactAmount.fromStorage(String numerator, String denominator) {
    if (numerator.length > 20000 ||
        denominator.length > 20000 ||
        !RegExp(r'^-?(0|[1-9]\d*)$').hasMatch(numerator) ||
        !RegExp(r'^[1-9]\d*$').hasMatch(denominator)) {
      throw const FormatException('rational_storage');
    }
    final value = ExactAmount(
      BigInt.parse(numerator),
      BigInt.parse(denominator),
    );
    if (value.numerator.toString() != numerator ||
        value.denominator.toString() != denominator) {
      throw const FormatException('noncanonical_rational');
    }
    return value;
  }
  ExactAmount operator +(ExactAmount other) => ExactAmount(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );
  ExactAmount operator -(ExactAmount other) => this + -other;
  ExactAmount operator -() => ExactAmount(-numerator, denominator);
  ExactAmount operator *(ExactAmount other) =>
      ExactAmount(numerator * other.numerator, denominator * other.denominator);
  ExactAmount operator /(ExactAmount other) =>
      ExactAmount(numerator * other.denominator, denominator * other.numerator);
  bool operator <(ExactAmount other) => compareTo(other) < 0;
  bool operator <=(ExactAmount other) => compareTo(other) <= 0;
  bool operator >(ExactAmount other) => compareTo(other) > 0;
  @override
  int compareTo(ExactAmount other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);
  @override
  bool operator ==(Object other) =>
      other is ExactAmount &&
      numerator == other.numerator &&
      denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  @override
  String toString() => '$numerator/$denominator';

  /// Compact output only. Never parse the rounded display back into storage.
  String compactDecimal({int places = 9}) {
    final value = roundedDecimal(places: places);
    return places == 0
        ? value
        : value
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }

  /// Output only: round half away from zero. Never parse this back for storage.
  String roundedDecimal({int places = 6}) {
    if (places < 0 || places > 12) throw RangeError.range(places, 0, 12);
    final scale = BigInt.from(10).pow(places);
    final scaled = numerator.abs() * scale;
    var coefficient = scaled ~/ denominator;
    if ((scaled % denominator) * BigInt.two >= denominator) {
      coefficient += BigInt.one;
    }
    final whole = coefficient ~/ scale;
    final fraction = places == 0
        ? ''
        : '.${(coefficient % scale).toString().padLeft(places, '0')}';
    return '${numerator.isNegative && coefficient != BigInt.zero ? '-' : ''}$whole$fraction';
  }
}

/// Retains the entry lexeme separately from the exact numeric value.
final class EnteredStockAmount {
  EnteredStockAmount(String text, this.unit)
    : originalText = text,
      value = ExactAmount.parseEntry(text) {
    if (!const {'mg', 'ml', 'count'}.contains(unit)) {
      throw ArgumentError('unsupported_unit');
    }
  }
  final String originalText, unit;
  final ExactAmount value;
}

/// One prepared vial. Both original mass and confirmed final volume are kept.
/// Added liquid is descriptive and never substitutes for final volume.
final class VialPreparation {
  VialPreparation({
    required this.powderAmount,
    required this.massUnit,
    required this.finalVolumeMl,
    this.liquid = '',
    this.addedVolumeMl,
    this.preparedOn,
  }) {
    ExactAmount.parseEntry(powderAmount);
    ExactAmount.parseEntry(finalVolumeMl);
    if (!const {'mg', 'mcg'}.contains(massUnit) || liquid.length > 500) {
      throw const FormatException('preparation');
    }
    if (addedVolumeMl != null) ExactAmount.parseEntry(addedVolumeMl!);
    if (preparedOn != null) {
      final date = DateTime.tryParse(preparedOn!);
      if (date == null ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(preparedOn!) ||
          date.toIso8601String().substring(0, 10) != preparedOn) {
        throw const FormatException('preparation_date');
      }
    }
  }
  final String powderAmount, massUnit, finalVolumeMl, liquid;
  final String? addedVolumeMl, preparedOn;
  ExactAmount get mgPerMl =>
      ExactAmount.parseEntry(powderAmount) /
      ExactAmount(BigInt.from(massUnit == 'mcg' ? 1000 : 1)) /
      ExactAmount.parseEntry(finalVolumeMl);
  Map<String, Object?> toJson() => {
    'powderAmount': powderAmount,
    'massUnit': massUnit,
    'finalVolumeMl': finalVolumeMl,
    'liquid': liquid,
    'addedVolumeMl': addedVolumeMl,
    'preparedOn': preparedOn,
  };
  factory VialPreparation.fromJson(Map<String, dynamic> m) => VialPreparation(
    powderAmount: m['powderAmount'] as String,
    massUnit: m['massUnit'] as String,
    finalVolumeMl: m['finalVolumeMl'] as String,
    liquid: m['liquid'] as String? ?? '',
    addedVolumeMl: m['addedVolumeMl'] as String?,
    preparedOn: m['preparedOn'] as String?,
  );
}

/// Exact known strength for one ingredient. Null values remain unknown.
final class LabelledStrength {
  LabelledStrength({
    required this.ingredientId,
    required this.label,
    this.mgPerMl,
    this.mgPerCount,
    this.preparation,
  }) {
    if (ingredientId.isEmpty ||
        label.isEmpty ||
        (mgPerMl != null && mgPerMl! <= ExactAmount.zero) ||
        (mgPerCount != null && mgPerCount! <= ExactAmount.zero) ||
        (mgPerMl != null && mgPerCount != null) ||
        (preparation != null && mgPerMl != preparation!.mgPerMl)) {
      throw ArgumentError('invalid_strength');
    }
  }
  final String ingredientId, label;
  final ExactAmount? mgPerMl;
  final ExactAmount? mgPerCount;
  final VialPreparation? preparation;
  Map<String, Object?> toJson() => {
    'ingredient': ingredientId,
    'label': label,
    'pair': mgPerMl == null
        ? null
        : [mgPerMl!.numerator.toString(), mgPerMl!.denominator.toString()],
    if (mgPerCount != null)
      'countPair': [
        mgPerCount!.numerator.toString(),
        mgPerCount!.denominator.toString(),
      ],
    if (preparation != null) 'preparation': preparation!.toJson(),
  };
  factory LabelledStrength.fromJson(Map<String, dynamic> m) {
    ExactAmount? pair(String key) {
      final p = m[key] as List?;
      return p == null
          ? null
          : ExactAmount.fromStorage(p[0] as String, p[1] as String);
    }

    return LabelledStrength(
      ingredientId: m['ingredient'] as String,
      label: m['label'] as String,
      mgPerMl: pair('pair'),
      mgPerCount: pair('countPair'),
      preparation: m['preparation'] == null
          ? null
          : VialPreparation.fromJson(
              Map<String, dynamic>.from(m['preparation'] as Map),
            ),
    );
  }
  ExactAmount? equivalent(
    ExactAmount amount, {
    required String from,
    required String to,
  }) {
    if (from == to && const {'mg', 'ml', 'count'}.contains(from)) return amount;
    if (from == 'mg' && to == 'count' && mgPerCount != null) {
      return amount / mgPerCount!;
    }
    if (from == 'count' && to == 'mg' && mgPerCount != null) {
      return amount * mgPerCount!;
    }
    final strength = mgPerMl;
    if (strength != null && from == 'mg' && to == 'ml') {
      return amount / strength;
    }
    if (strength != null && from == 'ml' && to == 'mg') {
      return amount * strength;
    }
    return null;
  }
}

enum FixedReplacementAmount { milligrams, millilitres }

final class ReplacementAmounts {
  const ReplacementAmounts._(this.milligrams, this.millilitres);
  final ExactAmount milligrams, millilitres;

  /// A required policy prevents silent defaults. Does not mutate any plan.
  static ReplacementAmounts? calculate({
    required EnteredStockAmount entered,
    required LabelledStrength oldStrength,
    required LabelledStrength newStrength,
    required FixedReplacementAmount keep,
  }) {
    if (oldStrength.ingredientId != newStrength.ingredientId) return null;
    final fixedUnit = keep == FixedReplacementAmount.milligrams ? 'mg' : 'ml';
    final fixed = oldStrength.equivalent(
      entered.value,
      from: entered.unit,
      to: fixedUnit,
    );
    if (fixed == null) return null;
    final otherUnit = fixedUnit == 'mg' ? 'ml' : 'mg';
    final other = newStrength.equivalent(fixed, from: fixedUnit, to: otherUnit);
    if (other == null) return null;
    return fixedUnit == 'mg'
        ? ReplacementAmounts._(fixed, other)
        : ReplacementAmounts._(other, fixed);
  }
}
