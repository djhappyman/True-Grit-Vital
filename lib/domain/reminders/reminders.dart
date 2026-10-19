import '../scheduling/stored_daily.dart';

enum ReminderActionKind { open, taken, snooze, skip }

enum ReminderKind { ordinary, snooze }

enum ReminderTrigger { wall, elapsed }

enum ReminderReceipt {
  accepted,
  consumed,
  cancelled,
  postUncertain,
  failed,
  unknown,
}

enum ReminderRepairState {
  pending,
  prepared,
  consumed,
  cancelled,
  postUncertain,
  failed,
  unknown,
  capacity,
  interrupted,
  expired,
  review,
}

final class ReminderClockSample {
  const ReminderClockSample({
    required this.utcMilliseconds,
    required this.elapsedMilliseconds,
    required this.bootId,
  });
  final int utcMilliseconds, elapsedMilliseconds;
  final String bootId;
  DateTime get utc =>
      DateTime.fromMillisecondsSinceEpoch(utcMilliseconds, isUtc: true);
}

final class ReminderDeadline {
  const ReminderDeadline(this.elapsedMilliseconds, this.projectedUtc);
  final int elapsedMilliseconds;
  final DateTime projectedUtc;
}

/// Checked against both signed native milliseconds and Dart's instant range.
ReminderDeadline snoozeDeadline(ReminderClockSample sample, int delayMinutes) {
  const nativeMax = 9223372036854775807;
  const instantMax = 8640000000000000;
  if (delayMinutes <= 0 ||
      sample.bootId.isEmpty ||
      sample.bootId.length > 256 ||
      sample.elapsedMilliseconds < 0 ||
      sample.elapsedMilliseconds > nativeMax ||
      sample.utcMilliseconds < -instantMax ||
      sample.utcMilliseconds > instantMax) {
    throw const FormatException('snooze_input');
  }
  final delay = BigInt.from(delayMinutes) * BigInt.from(60000);
  final elapsed = BigInt.from(sample.elapsedMilliseconds) + delay;
  final utc = BigInt.from(sample.utcMilliseconds) + delay;
  if (elapsed > BigInt.from(nativeMax) || utc > BigInt.from(instantMax)) {
    throw const FormatException('snooze_overflow');
  }
  return ReminderDeadline(
    elapsed.toInt(),
    DateTime.fromMillisecondsSinceEpoch(utc.toInt(), isUtc: true),
  );
}

ReminderRepairState snoozeClockState({
  required ReminderClockSample saved,
  required int deadlineMilliseconds,
  required ReminderClockSample? current,
}) {
  if (current == null) return ReminderRepairState.review;
  if (saved.bootId != current.bootId) return ReminderRepairState.interrupted;
  if (current.elapsedMilliseconds >= deadlineMilliseconds) {
    return ReminderRepairState.expired;
  }
  return ReminderRepairState.pending;
}

final class ReminderTarget {
  const ReminderTarget({
    required this.row,
    required this.snoozeRevision,
    this.configRevision = 0,
  });
  final DailyRow row;
  final int snoozeRevision, configRevision;
  int get reminderRevision => row.reminderRevision;
}

final class SnoozeCommand {
  const SnoozeCommand({
    required this.commandId,
    required this.target,
    required this.delayMinutes,
    required this.sample,
    required this.observedZone,
  });
  final String commandId;
  final ReminderTarget target;
  final int delayMinutes;
  final ReminderClockSample sample;
  final String? observedZone;
}

final class DesiredReminder {
  const DesiredReminder({
    required this.requestToken,
    required this.takenToken,
    required this.snoozeToken,
    required this.skipToken,
    required this.generation,
    required this.namespace,
    required this.target,
    required this.kind,
    required this.trigger,
    required this.deadlineMilliseconds,
    required this.intentRevision,
    required this.repairState,
    this.bootId,
    this.reason,
    this.adapterFingerprint,
    this.sample,
    this.delayMinutes,
  });
  final String requestToken,
      takenToken,
      snoozeToken,
      skipToken,
      generation,
      namespace;
  final ReminderTarget target;
  final ReminderKind kind;
  final ReminderTrigger trigger;
  final int deadlineMilliseconds, intentRevision;
  final ReminderRepairState repairState;
  final String? bootId, reason, adapterFingerprint;
  final ReminderClockSample? sample;
  final int? delayMinutes;
  DateTime get projectedUtc => kind == ReminderKind.ordinary
      ? (trigger == ReminderTrigger.elapsed
            ? target.row.expectation.instant!
            : DateTime.fromMillisecondsSinceEpoch(
                deadlineMilliseconds,
                isUtc: true,
              ))
      : snoozeDeadline(sample!, delayMinutes!).projectedUtc;
}

final class SnoozeResult {
  const SnoozeResult({required this.desired, this.alreadyCommitted = false});
  final DesiredReminder desired;
  final bool alreadyCommitted;
}

final class PendingReminderAction {
  const PendingReminderAction({
    required this.envelopeId,
    required this.commandId,
    required this.draftId,
    required this.target,
    required this.action,
    required this.submitted,
    this.delayMinutes,
    this.delayText,
    this.observedZone,
    this.sample,
    this.actualAt,
  });
  final String envelopeId, commandId, draftId;
  final ReminderTarget target;
  final ReminderActionKind action;
  final bool submitted;
  final String? delayText, observedZone;
  final int? delayMinutes;
  final ReminderClockSample? sample;
  final DateTime? actualAt;
}

final class ReminderCoverage {
  const ReminderCoverage({
    required this.scope,
    required this.generation,
    required this.basis,
    required this.adapterFingerprint,
    required this.checkedAt,
    required this.complete,
    this.preparedThrough,
    this.reason,
  });
  final String scope, generation, basis, adapterFingerprint;
  final DateTime checkedAt;
  final DateTime? preparedThrough;
  final bool complete;
  final String? reason;
}

final class ReminderExclusion {
  const ReminderExclusion({
    required this.scope,
    required this.reason,
    required this.count,
  });
  final String scope, reason;
  final int count;
}

final class ReminderProjection {
  ReminderProjection({
    required this.generation,
    required this.namespace,
    required this.sequence,
    required Iterable<DesiredReminder> desired,
    required Iterable<String> obsoleteTokens,
    required this.complete,
    required Iterable<ReminderCoverage> coverage,
    Iterable<EventEndReminder> eventEnds = const [],
    Iterable<EventEndReminder> eventEndAttention = const [],
    Iterable<ReminderExclusion> exclusions = const [],
    Iterable<DesiredReminder> attention = const [],
  }) : eventEnds = List.unmodifiable(eventEnds),
       eventEndAttention = List.unmodifiable(eventEndAttention),
       desired = List.unmodifiable(desired),
       obsoleteTokens = List.unmodifiable(obsoleteTokens),
       coverage = List.unmodifiable(coverage),
       exclusions = List.unmodifiable(exclusions),
       attention = List.unmodifiable(attention);
  final String generation, namespace;
  final int sequence;
  final List<DesiredReminder> desired;
  final List<EventEndReminder> eventEnds, eventEndAttention;
  final List<String> obsoleteTokens;
  final bool complete;
  final List<ReminderCoverage> coverage;
  final List<ReminderExclusion> exclusions;
  final List<DesiredReminder> attention;
}

final class ReminderAllocation {
  ReminderAllocation(this.selected, this.excluded);
  final List<DesiredReminder> selected, excluded;
}

/// Earliest first; equal instants round-robin stable person/plan queues.
ReminderAllocation allocateReminders(Iterable<DesiredReminder> requests) {
  List<DesiredReminder> order(Iterable<DesiredReminder> values) {
    final byTime = <int, Map<String, List<DesiredReminder>>>{};
    for (final r in values) {
      final key =
          '${r.target.row.expectation.identity.personId}/${r.target.row.expectation.identity.planId}';
      (byTime
              .putIfAbsent(r.projectedUtc.millisecondsSinceEpoch, () => {})
              .putIfAbsent(key, () => []))
          .add(r);
    }
    final result = <DesiredReminder>[];
    for (final time in byTime.keys.toList()..sort()) {
      final queues = byTime[time]!;
      final keys = queues.keys.toList()..sort();
      for (final q in queues.values) {
        q.sort((a, b) {
          final ai = a.target.row.expectation.identity;
          final bi = b.target.row.expectation.identity;
          final date = ai.originalDate.compareTo(bi.originalDate);
          return date != 0
              ? date
              : (ai.slotId ?? '').compareTo(bi.slotId ?? '');
        });
      }
      while (queues.values.any((q) => q.isNotEmpty)) {
        for (final key in keys) {
          if (queues[key]!.isNotEmpty) result.add(queues[key]!.removeAt(0));
        }
      }
    }
    return result;
  }

  final schedulable = requests.where(
    (r) => ![
      ReminderRepairState.consumed,
      ReminderRepairState.postUncertain,
      ReminderRepairState.cancelled,
      ReminderRepairState.interrupted,
      ReminderRepairState.expired,
      ReminderRepairState.review,
    ].contains(r.repairState),
  );
  final ordinary = order(
    schedulable.where((r) => r.kind == ReminderKind.ordinary),
  );
  final snoozes = order(
    schedulable.where((r) => r.kind == ReminderKind.snooze),
  );
  // Existing accepted snoozes cannot be silently evicted by later requests.
  final originalOrder = {
    for (var i = 0; i < snoozes.length; i++) snoozes[i].requestToken: i,
  };
  snoozes.sort((a, b) {
    final aAccepted = a.repairState == ReminderRepairState.prepared;
    final bAccepted = b.repairState == ReminderRepairState.prepared;
    return aAccepted == bAccepted
        ? originalOrder[a.requestToken]!.compareTo(
            originalOrder[b.requestToken]!,
          )
        : (aAccepted ? -1 : 1);
  });
  return ReminderAllocation(
    List.unmodifiable([...ordinary.take(232), ...snoozes.take(16)]),
    List.unmodifiable([...ordinary.skip(232), ...snoozes.skip(16)]),
  );
}

/// Review-only event prompt. Tokens never authorise administration or stock writes.
final class EventEndReminder {
  const EventEndReminder({
    required this.requestToken,
    required this.takenToken,
    required this.snoozeToken,
    required this.skipToken,
    required this.generation,
    required this.namespace,
    required this.eventId,
    required this.personId,
    required this.eventRevision,
    required this.personRevision,
    required this.deadlineMilliseconds,
    required this.repairState,
    this.reason,
    this.adapterFingerprint,
  });
  final String requestToken,
      takenToken,
      snoozeToken,
      skipToken,
      generation,
      namespace,
      eventId,
      personId;
  final int eventRevision, personRevision, deadlineMilliseconds;
  final ReminderRepairState repairState;
  final String? reason, adapterFingerprint;
  DateTime get projectedUtc =>
      DateTime.fromMillisecondsSinceEpoch(deadlineMilliseconds, isUtc: true);
}

final class EventEndAllocation {
  EventEndAllocation(
    Iterable<EventEndReminder> selected,
    Iterable<EventEndReminder> excluded,
  ) : selected = List.unmodifiable(selected),
      excluded = List.unmodifiable(excluded);
  final List<EventEndReminder> selected, excluded;
}

/// Eight recovery/end-review slots remain separate from 232 ordinary/16 Snooze.
EventEndAllocation allocateEventEndReminders(
  Iterable<EventEndReminder> requests,
) {
  final ordered =
      requests
          .where(
            (r) => [
              ReminderRepairState.pending,
              ReminderRepairState.prepared,
              ReminderRepairState.failed,
              ReminderRepairState.unknown,
              ReminderRepairState.capacity,
            ].contains(r.repairState),
          )
          .toList()
        ..sort((a, b) {
          var c = a.deadlineMilliseconds.compareTo(b.deadlineMilliseconds);
          if (c != 0) return c;
          c = a.personId.compareTo(b.personId);
          if (c != 0) return c;
          c = a.eventId.compareTo(b.eventId);
          return c != 0 ? c : a.requestToken.compareTo(b.requestToken);
        });
  return EventEndAllocation(ordered.take(8), ordered.skip(8));
}
