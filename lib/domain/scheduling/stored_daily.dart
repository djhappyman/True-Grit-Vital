import 'phase_plan.dart';
import 'daily_plan.dart';
import '../reminders/reminders.dart';
import '../products/products.dart';
import 'daily_resolver.dart';

final class SavedDailyPlan {
  const SavedDailyPlan({
    required this.plan,
    required this.revision,
    this.alreadyCommitted = false,
  });
  final DailyPlanVersion plan;
  final int revision;
  final bool alreadyCommitted;
}

enum DailyActionKind { taken, skip }

final class DailyAction {
  const DailyAction({
    required this.id,
    required this.kind,
    required this.revision,
    required this.isUndone,
    required this.sequence,
    required this.recordedAt,
    this.recordId,
    this.recordRevision,
    this.reason,
    this.alreadyCommitted = false,
  });
  final String id;
  final DailyActionKind kind;
  final int revision, sequence;
  final DateTime recordedAt;
  final bool isUndone, alreadyCommitted;
  final String? recordId;
  final int? recordRevision;
  final String? reason;
}

/// A captured action context. Every revision is rechecked inside the write lock.
final class DailyRow {
  DailyRow({
    required this.generation,
    required this.personRevision,
    required this.planRevision,
    required this.expectation,
    required this.personName,
    required this.itemName,
    required this.revision,
    required Iterable<DailyAction> actions,
    required this.takenCount,
    required this.skippedCount,
    this.productLabel,
    this.itemRevision = 1,
    this.actionsComplete = true,
    this.reminderRevision = 0,
  }) : actions = List.unmodifiable(actions);
  final ProductLabelSnapshot? productLabel;
  final String generation, personName, itemName;
  final int personRevision,
      planRevision,
      revision,
      reminderRevision,
      itemRevision;
  final DailyExpectation expectation;
  final List<DailyAction> actions;
  final int takenCount, skippedCount;
  final bool actionsComplete;
  int get plannedCount => expectation.plannedCount ?? 1;
  bool get isResolved => takenCount + skippedCount >= plannedCount;
}

final class DailyRows {
  DailyRows({
    required Iterable<DailyRow> rows,
    required this.complete,
    this.issue,
  }) : rows = List.unmodifiable(rows);
  final List<DailyRow> rows;
  final bool complete;
  final DailyCalculationIssue? issue;
}

final class DailyPlanNextRow {
  const DailyPlanNextRow({required this.plan, required this.result});
  final DailyPlanVersion plan;
  final DailyNext result;
}

final class DailyPlanNextRows {
  DailyPlanNextRows({
    required Iterable<DailyPlanNextRow> rows,
    required this.complete,
  }) : rows = List.unmodifiable(rows);
  final List<DailyPlanNextRow> rows;
  final bool complete;
}

/// A review of one explicit anchor change with a durable source-set guard.
final class IntervalChangeReview {
  const IntervalChangeReview({
    required this.plan,
    required this.recordId,
    required this.expectedRecordRevision,
    required this.sourceGuard,
    required this.generation,
    required this.personRevision,
    required this.now,
    required this.observedZone,
    this.before,
    this.after,
    this.actualAt,
    this.qualifies,
    this.voided = false,
    this.intervalClockSample,
  });
  final SavedDailyPlan plan;
  final String recordId, sourceGuard, generation, observedZone;
  final int expectedRecordRevision, personRevision;
  final DateTime now;
  final ReminderClockSample? intervalClockSample;
  final DateTime? actualAt;
  final bool? qualifies;
  final bool voided;
  final DailyExpectation? before, after;
}

/// Explicit review of a new clock basis and the first retained future result.
final class IntervalClockReview {
  const IntervalClockReview({
    required this.plan,
    required this.personRevision,
    required this.generation,
    required this.sample,
    required this.reviewedFrom,
    required this.sourceGuard,
    required this.observedZone,
    this.next,
  });
  final SavedDailyPlan plan;
  final int personRevision;
  final String generation, sourceGuard, observedZone;
  final ReminderClockSample sample;
  final CivilDate reviewedFrom;
  final DailyExpectation? next;
}

/// A read-only proposed pause, resume or repeating-break change.
final class PauseChangeReview {
  const PauseChangeReview({
    required this.plan,
    required this.proposed,
    required this.personRevision,
    required this.generation,
    required this.sourceGuard,
    required this.now,
    required this.observedZone,
    this.before,
    this.after,
    this.beforeDate,
    this.afterDate,
    this.restartAt,
  });
  final SavedDailyPlan plan;
  final DailyPlanVersion proposed;
  final int personRevision;
  final String generation, sourceGuard, observedZone;
  final DateTime now;
  final DateTime? restartAt;
  final DailyExpectation? before, after;
  final CivilDate? beforeDate, afterDate;
}

/// Frozen, revision-checked review of a complete phase definition.
final class PhaseChangeReview {
  const PhaseChangeReview({
    required this.plan,
    required this.proposed,
    required this.personRevision,
    required this.generation,
    required this.sourceGuard,
    required this.now,
    required this.observedZone,
    this.before,
    this.after,
    this.beforeIssue,
    this.afterIssue,
  });
  final SavedDailyPlan plan;
  final PhasePlan proposed;
  final int personRevision;
  final String generation, sourceGuard, observedZone;
  final DateTime now;
  final DailyExpectation? before, after;
  final DailyCalculationIssue? beforeIssue, afterIssue;
}
