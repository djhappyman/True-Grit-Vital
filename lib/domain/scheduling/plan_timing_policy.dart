/// Optional user-defined presentation and follow-up choices. Neither value
/// defines a medically safe time or changes the planned dose.
final class PlanTimingPolicy {
  PlanTimingPolicy({this.allowanceMinutes, this.followUpMinutes}) {
    if (allowanceMinutes == null && followUpMinutes == null) {
      throw const FormatException('empty_timing_policy');
    }
    for (final value in [allowanceMinutes, followUpMinutes]) {
      if (value != null && (value < 0 || value > maxMinutes)) {
        throw const FormatException('timing_policy_range');
      }
    }
    if (followUpMinutes == 0) {
      throw const FormatException('follow_up_positive');
    }
  }

  // Matches the bounded seven-day native preparation horizon. This is an
  // implementation limit, not a suggested or clinically meaningful interval.
  static const maxMinutes = 7 * 24 * 60;
  final int? allowanceMinutes, followUpMinutes;

  Map<String, Object> toJson() => {
    'allowance': ?allowanceMinutes,
    'followUp': ?followUpMinutes,
  };

  factory PlanTimingPolicy.fromJson(Map<String, dynamic> value) {
    if (value.keys.any((key) => !{'allowance', 'followUp'}.contains(key))) {
      throw const FormatException('timing_policy_fields');
    }
    return PlanTimingPolicy(
      allowanceMinutes: value['allowance'] as int?,
      followUpMinutes: value['followUp'] as int?,
    );
  }
}

enum DoseTimingLabel { earlier, withinWindow, later }

/// Compares the captured planned instant with the reported actual instant.
/// Date-only, uncertain and voided entries deliberately receive no label.
DoseTimingLabel? doseTimingLabel({
  required PlanTimingPolicy? policy,
  required DateTime? planned,
  required DateTime actual,
  bool dateOnly = false,
  bool timeNeedsReview = false,
  bool voided = false,
}) {
  final allowance = policy?.allowanceMinutes;
  if (allowance == null ||
      planned == null ||
      dateOnly ||
      timeNeedsReview ||
      voided) {
    return null;
  }
  final difference = actual.toUtc().difference(planned.toUtc()).inMicroseconds;
  final window = allowance * Duration.microsecondsPerMinute;
  return difference < -window
      ? DoseTimingLabel.earlier
      : difference > window
      ? DoseTimingLabel.later
      : DoseTimingLabel.withinWindow;
}

/// A single follow-up deadline, or null when disabled/unrepresentable.
DateTime? planFollowUpInstant(PlanTimingPolicy? policy, DateTime? planned) {
  final minutes = policy?.followUpMinutes;
  if (minutes == null || planned == null) return null;
  try {
    final result = planned.toUtc().add(Duration(minutes: minutes));
    return result.year >= 1 && result.year <= 9999 ? result : null;
  } on ArgumentError {
    return null;
  }
}
