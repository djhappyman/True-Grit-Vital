/// A food label the person explicitly chose for one immutable plan version.
///
/// These are literal labels, not inferred meal times, dose intervals or proof
/// of compliance.
enum FoodRequirement {
  beforeFood,
  withFood,
  afterFood,
  emptyStomach;

  /// Stable English wording for non-localized report and export text.
  ///
  /// The app interface localizes the same choices separately.
  String get reportLabel => switch (this) {
    FoodRequirement.beforeFood => 'Before food',
    FoodRequirement.withFood => 'With food',
    FoodRequirement.afterFood => 'After food',
    FoodRequirement.emptyStomach => 'Empty stomach',
  };
}

/// Optional authored food and bedtime labels for one plan version.
///
/// Every field is unspecified by default. A value only exists because the
/// person chose it explicitly; nothing here schedules, validates or infers a
/// meal time or compliance.
final class ScheduleRequirement {
  const ScheduleRequirement({this.food, this.atBedtime = false});

  final FoodRequirement? food;
  final bool atBedtime;

  bool get isEmpty => food == null && !atBedtime;
  bool get isNotEmpty => !isEmpty;

  ScheduleRequirement withFood(FoodRequirement? value) =>
      ScheduleRequirement(food: value, atBedtime: atBedtime);

  ScheduleRequirement withBedtime(bool value) =>
      ScheduleRequirement(food: food, atBedtime: value);

  /// Stable English summary for non-localized report text.
  String get reportSummary => [
    if (food case final value?) value.reportLabel,
    if (atBedtime) 'At bedtime',
  ].join(' · ');

  /// Additive JSON. Omitted keys mean the person did not choose that label.
  Map<String, Object?> toJson() => {
    if (food != null) 'food': food!.name,
    if (atBedtime) 'bedtime': true,
  };

  /// Reads an optional saved object. Missing or empty content is unspecified.
  ///
  /// An unknown food name is rejected so a newer label is never silently
  /// dropped or treated as a different choice.
  static ScheduleRequirement? fromJson(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) throw const FormatException('plan_requirements');
    final foodValue = raw['food'];
    final bedtimeValue = raw['bedtime'];
    final validFood = foodValue == null || foodValue is String;
    final validBedtime = bedtimeValue == null || bedtimeValue is bool;
    if (!validFood || !validBedtime) {
      throw const FormatException('plan_requirements');
    }
    final value = ScheduleRequirement(
      food: switch (foodValue) {
        null => null,
        final String name =>
          FoodRequirement.values.asNameMap()[name] ??
              (throw const FormatException('plan_requirement_food')),
        _ => throw const FormatException('plan_requirement_food'),
      },
      atBedtime: bedtimeValue as bool? ?? false,
    );
    return value.isEmpty ? null : value;
  }

  @override
  bool operator ==(Object other) =>
      other is ScheduleRequirement &&
      food == other.food &&
      atBedtime == other.atBedtime;

  @override
  int get hashCode => Object.hash(food, atBedtime);
}
