import '../scheduling/stored_daily.dart';
import '../stock/stored_stock.dart' show ExactAmount, StockNoticeState;

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
    Iterable<StockNoticeReminder> stockNotices = const [],
    Iterable<StockNoticeReminder> stockNoticeAttention = const [],
    Iterable<ReminderExclusion> exclusions = const [],
    Iterable<DesiredReminder> attention = const [],
  }) : eventEnds = List.unmodifiable(eventEnds),
       eventEndAttention = List.unmodifiable(eventEndAttention),
       stockNotices = List.unmodifiable(stockNotices),
       stockNoticeAttention = List.unmodifiable(stockNoticeAttention),
       desired = List.unmodifiable(desired),
       obsoleteTokens = List.unmodifiable(obsoleteTokens),
       coverage = List.unmodifiable(coverage),
       exclusions = List.unmodifiable(exclusions),
       attention = List.unmodifiable(attention);
  final String generation, namespace;
  final int sequence;
  final List<DesiredReminder> desired;
  final List<EventEndReminder> eventEnds, eventEndAttention;
  final List<StockNoticeReminder> stockNotices, stockNoticeAttention;
  final List<String> obsoleteTokens;
  final bool complete;
  final List<ReminderCoverage> coverage;
  final List<ReminderExclusion> exclusions;
  final List<DesiredReminder> attention;
}

/// Finite native capacity. Snoozes and event notices keep reserved pools, so a
/// dense ordinary queue cannot evict a deferred alert or an end review.
abstract final class ReminderCapacity {
  static const int ordinary = 232;
  static const int snoozes = 16;
  static const int eventEnds = 8;

  /// Reserved refill/low notices. A dense dose queue never displaces a stock
  /// notice, and a stock backlog never delays or evicts dose or event work.
  static const int stockNotices = 8;

  /// The Android adapter accepts at most 248 ordinary-purpose requests, eight
  /// event reviews and eight stock notices in one snapshot. These totals must
  /// stay in step with it.
  static const int nativeOrdinaryPurpose = ordinary + snoozes;
  static const int nativeTotal =
      nativeOrdinaryPurpose + eventEnds + stockNotices;
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
    List.unmodifiable([
      ...ordinary.take(ReminderCapacity.ordinary),
      ...snoozes.take(ReminderCapacity.snoozes),
    ]),
    List.unmodifiable([
      ...ordinary.skip(ReminderCapacity.ordinary),
      ...snoozes.skip(ReminderCapacity.snoozes),
    ]),
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
  return EventEndAllocation(
    ordered.take(ReminderCapacity.eventEnds),
    ordered.skip(ReminderCapacity.eventEnds),
  );
}

/// One known low or refill condition for a configured stock container.
///
/// A deficit is represented by the same condition as the in-app notice:
/// [StockNoticeState.refill] when only the refill rule applies, otherwise
/// [StockNoticeState.low]. Unknown and aggregate-limited balances never enter
/// this lane, so the native notice never claims a quantity nobody measured.
final class StockNoticeReminder {
  const StockNoticeReminder({
    required this.requestToken,
    required this.takenToken,
    required this.snoozeToken,
    required this.skipToken,
    required this.generation,
    required this.namespace,
    required this.containerId,
    required this.personId,
    required this.itemId,
    required this.itemName,
    required this.label,
    required this.unit,
    required this.condition,
    required this.deadlineMilliseconds,
    required this.intentRevision,
    required this.repairState,
    this.balance,
    this.threshold,
    this.refillEnabled = false,
    this.reason,
    this.adapterFingerprint,
    this.opened = false,
  });
  final String requestToken,
      takenToken,
      snoozeToken,
      skipToken,
      generation,
      namespace,
      containerId,
      personId,
      itemId,
      itemName,
      label,
      unit;
  final StockNoticeState condition;
  final ExactAmount? balance, threshold;
  final bool refillEnabled;

  /// Set once an Open action was captured. A captured notice is never offered
  /// again, even before its terminal receipt arrives.
  final bool opened;
  final int deadlineMilliseconds, intentRevision;
  final ReminderRepairState repairState;
  final String? reason, adapterFingerprint;
  DateTime get projectedUtc =>
      DateTime.fromMillisecondsSinceEpoch(deadlineMilliseconds, isUtc: true);

  StockNoticeReminder copyWith({
    ReminderRepairState? repairState,
    String? reason,
    bool? opened,
    String? itemName,
    String? label,
    String? unit,
    StockNoticeState? condition,
    ExactAmount? balance,
    ExactAmount? threshold,
    bool? refillEnabled,
    int? deadlineMilliseconds,
  }) => StockNoticeReminder(
    requestToken: requestToken,
    takenToken: takenToken,
    snoozeToken: snoozeToken,
    skipToken: skipToken,
    generation: generation,
    namespace: namespace,
    containerId: containerId,
    personId: personId,
    itemId: itemId,
    itemName: itemName ?? this.itemName,
    label: label ?? this.label,
    unit: unit ?? this.unit,
    condition: condition ?? this.condition,
    balance: balance ?? this.balance,
    threshold: threshold ?? this.threshold,
    refillEnabled: refillEnabled ?? this.refillEnabled,
    deadlineMilliseconds: deadlineMilliseconds ?? this.deadlineMilliseconds,
    intentRevision: intentRevision,
    repairState: repairState ?? this.repairState,
    reason: reason ?? this.reason,
    adapterFingerprint: adapterFingerprint,
    opened: opened ?? this.opened,
  );
}

final class StockNoticeAllocation {
  StockNoticeAllocation(
    Iterable<StockNoticeReminder> selected,
    Iterable<StockNoticeReminder> excluded,
  ) : selected = List.unmodifiable(selected),
      excluded = List.unmodifiable(excluded);
  final List<StockNoticeReminder> selected, excluded;
}

/// Eight reserved refill/low notices. Missing-capability, uncertain and
/// capacity states stay visible; none of them is a delivery claim.
StockNoticeAllocation allocateStockNotices(
  Iterable<StockNoticeReminder> requests,
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
          var c = a.condition.index.compareTo(b.condition.index);
          if (c != 0) return c;
          c = a.personId.compareTo(b.personId);
          if (c != 0) return c;
          c = a.itemName.compareTo(b.itemName);
          if (c != 0) return c;
          c = a.label.compareTo(b.label);
          if (c != 0) return c;
          c = a.containerId.compareTo(b.containerId);
          return c != 0 ? c : a.requestToken.compareTo(b.requestToken);
        });
  return StockNoticeAllocation(
    ordered.take(ReminderCapacity.stockNotices),
    ordered.skip(ReminderCapacity.stockNotices),
  );
}

/// Review-only destination for an Open stock notice. No action kind here can
/// record an administration, move stock or alter a plan.
final class StockNoticeOpen {
  const StockNoticeOpen({
    required this.envelopeId,
    required this.personId,
    required this.itemId,
    required this.containerId,
  });
  final String envelopeId, personId, itemId, containerId;
}
