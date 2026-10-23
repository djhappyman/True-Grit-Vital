import '../stock/exact_amount.dart';

/// Captured display units for a schedule. The medicine is never edited here.
final class PlanDoseDisplay {
  PlanDoseDisplay({required this.unit, this.strength}) {
    if (unit.trim().isEmpty || unit.length > 100) {
      throw const FormatException('schedule_unit');
    }
  }
  final String unit;
  final LabelledStrength? strength;
  Map<String, Object?> toJson() => {
    'unit': unit,
    if (strength != null) 'strength': strength!.toJson(),
  };
  factory PlanDoseDisplay.fromJson(Map<String, dynamic> value) =>
      PlanDoseDisplay(
        unit: value['unit'] as String,
        strength: value['strength'] == null
            ? null
            : LabelledStrength.fromJson(
                Map<String, dynamic>.from(value['strength'] as Map),
              ),
      );
}

ExactAmount? convertScheduleAmount(
  ExactAmount amount,
  String from,
  String to,
  LabelledStrength? strength,
) {
  if (from == to) return amount;
  final thousand = ExactAmount(BigInt.from(1000));
  final source = from == 'mcg' ? amount / thousand : amount;
  final sourceUnit = from == 'mcg' ? 'mg' : from;
  final targetUnit = to == 'mcg' ? 'mg' : to;
  final converted = sourceUnit == targetUnit
      ? source
      : strength?.equivalent(source, from: sourceUnit, to: targetUnit);
  return converted == null
      ? null
      : to == 'mcg'
      ? converted * thousand
      : converted;
}

/// A positive decimal accepted by the existing six-place scheduling engine.
/// Refuses a rounded equivalent rather than silently changing the dose.
String exactScheduleEntry(ExactAmount amount) {
  final scaled = amount * ExactAmount(BigInt.from(1000000));
  if (scaled.denominator != BigInt.one ||
      amount <= ExactAmount.zero ||
      amount > ExactAmount.maxEntered) {
    throw const FormatException('schedule_conversion_precision');
  }
  return amount
      .roundedDecimal(places: 6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// A person-chosen end rule. Dates remain the ordinary version bounds.
final class PlanStopCondition {
  PlanStopCondition({
    required this.from,
    required this.zone,
    this.total,
    this.unit,
    this.containerId,
    this.strength,
  }) {
    if (!from.isUtc ||
        zone.isEmpty ||
        (total != null) == (containerId != null) ||
        total != null &&
            (total! <= ExactAmount.zero || unit == null || unit!.isEmpty) ||
        containerId != null &&
            (containerId!.isEmpty || containerId!.length > 256)) {
      throw const FormatException('schedule_end_rule');
    }
  }
  final DateTime from;
  final String zone;
  final ExactAmount? total;
  final String? unit, containerId;
  final LabelledStrength? strength;
  Map<String, Object?> toJson() => {
    'from': from.microsecondsSinceEpoch,
    'zone': zone,
    if (total != null) ...{
      'total': [total!.numerator.toString(), total!.denominator.toString()],
      'unit': unit,
    },
    if (containerId != null) 'container': containerId,
    if (strength != null) 'strength': strength!.toJson(),
  };
  factory PlanStopCondition.fromJson(Map<String, dynamic> v) =>
      PlanStopCondition(
        from: DateTime.fromMicrosecondsSinceEpoch(
          v['from'] as int,
          isUtc: true,
        ),
        zone: v['zone'] as String,
        total: v['total'] == null
            ? null
            : ExactAmount.fromStorage(
                v['total'][0] as String,
                v['total'][1] as String,
              ),
        unit: v['unit'] as String?,
        containerId: v['container'] as String?,
        strength: v['strength'] == null
            ? null
            : LabelledStrength.fromJson(
                Map<String, dynamic>.from(v['strength'] as Map),
              ),
      );
}
