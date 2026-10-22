import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/stock/exact_amount.dart';
import '../../l10n/app_localizations.dart';
import 'stock_providers.dart' show stockDecimal;
import 'stock_widgets.dart' show stockAmountText;
import 'vial_preparation_editor.dart';

class StrengthEquivalent extends StatelessWidget {
  const StrengthEquivalent({
    super.key,
    required this.strength,
    required this.amount,
    required this.unit,
    this.showPreparation = true,
  });
  final LabelledStrength strength;
  final String amount, unit;
  final bool showPreparation;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    ExactAmount? a;
    try {
      a = ExactAmount.parseEntry(stockDecimal(amount));
    } catch (_) {
      /* The entry field owns validation. */
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!showPreparation || strength.preparation == null)
          if ((strength.mgPerMl ?? strength.mgPerCount) case final s?)
            Text(
              t.substanceStrengthSummary(
                s.compactDecimal(),
                'mg',
                strength.mgPerCount != null ? t.substanceEach : 'ml',
              ),
            ),
        if (showPreparation)
          if (strength.preparation case final p?)
            VialPreparationSummary(preparation: p),
        if (a != null)
          for (final target in [
            'mg',
            if (strength.mgPerMl != null) 'ml',
            if (strength.mgPerCount != null) 'count',
          ])
            if (target != unit)
              if (strength.equivalent(a, from: unit, to: target) case final v?)
                Text(
                  target == 'count'
                      ? t.substanceCountEquivalent(v.compactDecimal())
                      : t.stockNewEquivalent(stockAmountText(t, v, target)),
                ),
      ],
    );
  }
}
