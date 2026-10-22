import '../stock/exact_amount.dart';
import 'report_selection.dart' show ReportSelectionFailure;

/// Strength captured with the actual dose, never a current substance default.
/// Optional preparation facts are projected out unless stock details are chosen.
final class ReportDoseStrength {
  ReportDoseStrength({
    this.mgPerMl,
    this.mgPerCount,
    this.preparation,
    this.equivalentAvailable = true,
  }) {
    if ((mgPerMl != null && mgPerMl! <= ExactAmount.zero) ||
        (mgPerCount != null && mgPerCount! <= ExactAmount.zero) ||
        (mgPerMl != null && mgPerCount != null) ||
        (preparation != null && preparation!.mgPerMl != mgPerMl)) {
      throw const ReportSelectionFailure('report_strength');
    }
  }
  final ExactAmount? mgPerMl, mgPerCount;
  final VialPreparation? preparation;
  final bool equivalentAvailable;

  static ReportDoseStrength? capture(
    LabelledStrength? strength, {
    required bool includePreparation,
    bool equivalentAvailable = true,
  }) => strength == null
      ? null
      : ReportDoseStrength(
          mgPerMl: strength.mgPerMl,
          mgPerCount: strength.mgPerCount,
          preparation: includePreparation ? strength.preparation : null,
          equivalentAvailable: equivalentAvailable,
        );

  ExactAmount? equivalent(ExactAmount amount, String from, String to) {
    if (!equivalentAvailable) return null;
    if (from == 'mg' && to == 'ml' && mgPerMl != null) return amount / mgPerMl!;
    if (from == 'ml' && to == 'mg' && mgPerMl != null) return amount * mgPerMl!;
    if (from == 'mg' && to == 'count' && mgPerCount != null) {
      return amount / mgPerCount!;
    }
    if (from == 'count' && to == 'mg' && mgPerCount != null) {
      return amount * mgPerCount!;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'mgPerMl': mgPerMl?.toString(),
    'mgPerCount': mgPerCount?.toString(),
    if (!equivalentAvailable) 'equivalentAvailable': false,
    if (preparation != null) 'preparation': preparation!.toJson(),
  };
}
