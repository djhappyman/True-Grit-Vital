import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/scheduling/daily_plan.dart';
import '../../domain/scheduling/daily_resolver.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';

/// Completeness of the displayed seven-day preview interval.
enum PlanPreviewTotalsStatus { complete, incomplete, asNeeded }

/// One exact planned quantity for a single unit in the seven-day interval.
///
/// The amount stays in [ExactQuantity]'s integer scale. Different units are
/// never added together, and no ingredient or product count is rewritten as a
/// dose of another substance.
final class PlanPreviewUnitTotal {
  const PlanPreviewUnitTotal({required this.unit, required this.scaled});

  final String unit;
  final BigInt scaled;

  String get exact => formatPlanPreviewQuantity(scaled);
}

/// Factual planned totals for the seven dates shown by the preview.
///
/// [doses] counts planned dose entries, including each dose represented by an
/// untimed daily count. [units] holds one exact total per actual unit. The
/// totals describe the plan only; they are not recorded use or adherence.
final class PlanPreviewTotals {
  const PlanPreviewTotals._({
    required this.status,
    this.doses = 0,
    this.units = const [],
  });

  final PlanPreviewTotalsStatus status;
  final int doses;
  final List<PlanPreviewUnitTotal> units;
}

/// Expands exactly the displayed seven dates before any display row limit.
///
/// The wider 370-day preview is deliberately not used: its count is not a
/// seven-day count, and its row or date limit may be reached beyond this
/// interval. Only a complete seven-day expansion produces definite totals.
PlanPreviewTotals planPreviewTotals(
  DailyPlanVersion plan, {
  required CivilDate from,
  required String observedZone,
  DateTime? now,
  int maxRows = 20000,
}) {
  if (plan.timing is AsNeeded) {
    return const PlanPreviewTotals._(status: PlanPreviewTotalsStatus.asNeeded);
  }
  final resolver = DailyResolver();
  resolver.clock.validateZone(plan.zoneBasis.zoneFor(observedZone));
  final toExclusive = from.addDays(7);
  final expansion = resolver.expand(
    plan,
    from: from,
    toExclusive: toExclusive,
    observedZone: observedZone,
    maxDates: 7,
    maxRows: maxRows,
    now: now,
  );
  if (!expansion.complete) {
    return const PlanPreviewTotals._(
      status: PlanPreviewTotalsStatus.incomplete,
    );
  }
  var doses = 0;
  final units = <String, BigInt>{};
  for (final row in expansion.rows) {
    if (row.identity.originalDate.compareTo(from) < 0 ||
        row.identity.originalDate.compareTo(toExclusive) >= 0) {
      continue;
    }
    final count = row.plannedCount ?? 1;
    doses += count;
    final scaled = BigInt.from(row.amount.quantity.scaled) * BigInt.from(count);
    units.update(
      row.amount.unit,
      (total) => total + scaled,
      ifAbsent: () => scaled,
    );
  }
  return PlanPreviewTotals._(
    status: PlanPreviewTotalsStatus.complete,
    doses: doses,
    units: List.unmodifiable([
      for (final entry in units.entries)
        PlanPreviewUnitTotal(unit: entry.key, scaled: entry.value),
    ]),
  );
}

const _quantityScale = 1000000;
final _quantityScaleBigInt = BigInt.from(_quantityScale);
final _trailingZeroes = RegExp(r'0+$');

/// Canonical exact decimal for a scaled quantity, without rounding.
String formatPlanPreviewQuantity(BigInt scaled) {
  if (scaled.isNegative) throw ArgumentError('negative_planned_quantity');
  final whole = scaled ~/ _quantityScaleBigInt;
  final fraction = (scaled % _quantityScaleBigInt)
      .toString()
      .padLeft(6, '0')
      .replaceFirst(_trailingZeroes, '');
  return '$whole${fraction.isEmpty ? '' : '.$fraction'}';
}

/// Compact planned totals for the seven dates displayed above.
///
/// The block states an explicit unavailable, as-needed or empty result instead
/// of showing a partial or invented amount.
class PlanPreviewTotalsSummary extends StatelessWidget {
  const PlanPreviewTotalsSummary({super.key, required this.totals});

  final PlanPreviewTotals totals;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              t.batch15T11PlanPreviewTotalsHeading,
              style: VitalType.record,
            ),
          ),
          const SizedBox(height: 4),
          if (totals.status == PlanPreviewTotalsStatus.asNeeded)
            Text(t.batch15T11PlanPreviewTotalsPrn)
          else if (totals.status == PlanPreviewTotalsStatus.incomplete)
            Text(t.batch15T11PlanPreviewTotalsIncomplete)
          else if (totals.doses == 0)
            Text(t.batch15T11PlanPreviewTotalsNone)
          else ...[
            Text(
              t.batch15T11PlanPreviewTotalsDoses(totals.doses),
              key: const ValueKey('plan-preview-total-doses'),
              style: VitalType.body,
            ),
            for (final unit in totals.units)
              Text(
                t.batch15T11PlanPreviewTotalsQuantity(unit.exact, unit.unit),
                key: ValueKey('plan-preview-total-unit-${unit.unit}'),
                style: VitalType.body,
              ),
            const SizedBox(height: 4),
            Text(
              t.batch15T11PlanPreviewTotalsHelp,
              style: VitalType.metadata.copyWith(color: colors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}
