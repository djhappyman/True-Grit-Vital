import 'package:flutter/widgets.dart';

import '../../domain/scheduling/schedule_requirement.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';

/// Localized labels for the optional food and bedtime choices.
List<String> planRequirementLabels(
  AppLocalizations t,
  ScheduleRequirement? requirements,
) => [
  if (requirements?.food case final food?)
    switch (food) {
      FoodRequirement.beforeFood => t.finishR01FoodBefore,
      FoodRequirement.withFood => t.finishR01FoodWith,
      FoodRequirement.afterFood => t.finishR01FoodAfter,
      FoodRequirement.emptyStomach => t.finishR01FoodEmptyStomach,
    },
  if (requirements?.atBedtime == true) t.finishR01AtBedtime,
];

/// Compact badges for saved optional requirements.
///
/// These restate the person's exact choices. They never imply a meal time,
/// dose interval or compliance.
class PlanRequirementBadges extends StatelessWidget {
  const PlanRequirementBadges({
    super.key,
    required this.requirements,
    this.empty,
  });

  final ScheduleRequirement? requirements;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final labels = planRequirementLabels(
      AppLocalizations.of(context),
      requirements,
    );
    if (labels.isEmpty) return empty ?? const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final label in labels) VitalBadge(label)],
    );
  }
}
