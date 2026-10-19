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

/// Known mg per ml for one exact ingredient identity; null means unknown.
final class LabelledStrength {
  LabelledStrength({
    required this.ingredientId,
    required this.label,
    this.mgPerMl,
  }) {
    if (ingredientId.isEmpty ||
        label.isEmpty ||
        (mgPerMl != null && mgPerMl! <= ExactAmount.zero)) {
      throw ArgumentError('invalid_strength');
    }
  }
  final String ingredientId, label;
  final ExactAmount? mgPerMl;
  ExactAmount? equivalent(
    ExactAmount amount, {
    required String from,
    required String to,
  }) {
    if (from == to && const {'mg', 'ml', 'count'}.contains(from)) return amount;
    final strength = mgPerMl;
    if (strength == null) return null;
    if (from == 'mg' && to == 'ml') return amount / strength;
    if (from == 'ml' && to == 'mg') return amount * strength;
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
