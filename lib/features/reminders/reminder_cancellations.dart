import 'package:flutter/foundation.dart';

import '../../app/reminder_health.dart';

/// The only reminder-cancellation claim the health surface may render.
///
/// Both counts come from the last bounded repair pass and describe different
/// observations, not a partition: an obsolete reminder can be retried because
/// the device has not stopped it and also be reported as unconfirmed. Never
/// add the two numbers together or present them as one total.
@immutable
final class ReminderCancellationNotice {
  const ReminderCancellationNotice._({
    required this.pending,
    required this.unconfirmed,
    required this.checkedAt,
    required this.visible,
  });

  factory ReminderCancellationNotice.of(ReminderHealthSummary health) {
    final pending = health.pendingCancellations;
    final unconfirmed = health.unconfirmedCancellations;
    return ReminderCancellationNotice._(
      pending: pending,
      unconfirmed: unconfirmed,
      checkedAt: health.checkedAt,
      // A count is only evidence after a completed pass reported it. Before
      // the first pass (a new install or a replaced dataset) and after a pass
      // that failed without reporting, nothing is claimed. Zero is never
      // rendered as a confirmed stop.
      visible:
          health.attempted &&
          !health.failed &&
          (pending > 0 || unconfirmed > 0),
    );
  }

  /// Reminders the device has not yet confirmed as stopped. Vital asks again
  /// on the next pass.
  final int pending;

  /// Reminders whose cancellation receipt did not confirm a stop.
  final int unconfirmed;

  /// When the reporting pass checked the device, or null when it is unknown.
  final DateTime? checkedAt;

  /// Whether a completed pass supports showing the cancellation details.
  final bool visible;

  bool get hasPending => pending > 0;
  bool get hasUnconfirmed => unconfirmed > 0;
}
