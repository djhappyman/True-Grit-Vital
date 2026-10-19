import 'exact_amount.dart';

/// One person's particular physical source. Strength changes require a new ID.
final class StockOwner {
  StockOwner({
    required this.personId,
    required this.containerId,
    required this.unit,
  }) {
    if (personId.isEmpty ||
        containerId.isEmpty ||
        !const {'mg', 'ml', 'count'}.contains(unit)) {
      throw ArgumentError('invalid_stock_owner');
    }
  }
  final String personId, containerId, unit;
  @override
  bool operator ==(Object other) =>
      other is StockOwner &&
      personId == other.personId &&
      containerId == other.containerId &&
      unit == other.unit;
  @override
  int get hashCode => Object.hash(personId, containerId, unit);
}

enum StockMovementKind { restock, actualUse, waste, reconciliation, correction }

enum PhysicalCorrection { reverseRecordedEffect, retainPhysicalEffect }

/// An immutable physical ledger fact. Unknown outflow is represented by null.
final class StockMovement {
  StockMovement._(this.id, this.owner, this.kind, this.amount, this.reversesId);
  factory StockMovement.restock(
    String id,
    StockOwner owner,
    ExactAmount amount,
  ) => StockMovement._(
    id,
    owner,
    StockMovementKind.restock,
    _positive(amount),
    null,
  );
  factory StockMovement.use(String id, StockOwner owner, ExactAmount? amount) =>
      StockMovement._(
        id,
        owner,
        StockMovementKind.actualUse,
        amount == null ? null : -_positive(amount),
        null,
      );
  factory StockMovement.waste(
    String id,
    StockOwner owner,
    ExactAmount amount,
  ) => StockMovement._(
    id,
    owner,
    StockMovementKind.waste,
    -_positive(amount),
    null,
  );

  /// Absolute measured balance. null explicitly re-establishes unknown stock.
  factory StockMovement.reconcile(
    String id,
    StockOwner owner,
    ExactAmount? measured,
  ) {
    if (measured != null && measured < ExactAmount.zero) {
      throw ArgumentError('negative_measurement');
    }
    return StockMovement._(
      id,
      owner,
      StockMovementKind.reconciliation,
      measured,
      null,
    );
  }

  /// Correcting history needs a physical-effect choice; void alone does nothing.
  factory StockMovement.correct(
    String id,
    StockMovement original,
    PhysicalCorrection choice,
  ) {
    if (original.kind != StockMovementKind.actualUse &&
        original.kind != StockMovementKind.waste) {
      throw ArgumentError('not_correctable_outflow');
    }
    return StockMovement._(
      id,
      original.owner,
      StockMovementKind.correction,
      choice == PhysicalCorrection.retainPhysicalEffect
          ? ExactAmount.zero
          : original.amount == null
          ? null
          : -original.amount!,
      original.id,
    );
  }
  static ExactAmount _positive(ExactAmount amount) {
    if (amount <= ExactAmount.zero) {
      throw ArgumentError('positive_movement_required');
    }
    return amount;
  }

  final String id;
  final StockOwner owner;
  final StockMovementKind kind;

  /// Signed delta, except reconciliation is an absolute quantity.
  final ExactAmount? amount;
  final String? reversesId;
}

/// Explicitly distinguishes unknown balance from an aggregate resource limit.
final class StockBalance {
  const StockBalance(this.value, {this.limitReached = false});
  final ExactAmount? value;
  final bool limitReached;
  bool get isDeficit => value != null && value! < ExactAmount.zero;
}

/// Replay in persisted sequence order from an optional exact checkpoint.
/// SQL selects TEXT pairs; SQL SUM/TOTAL/CAST must never calculate quantities.
StockBalance foldStock(
  StockOwner owner,
  Iterable<StockMovement> movements, {
  ExactAmount? opening,
  int maxMovements = 100000,
  int maxBits = 65536,
}) {
  if (maxMovements < 1 || maxBits < 64) throw ArgumentError('aggregate_budget');
  bool exceedsBudget(ExactAmount? amount) =>
      amount != null &&
      (amount.numerator.bitLength > maxBits ||
          amount.denominator.bitLength > maxBits);
  if (exceedsBudget(opening)) {
    return const StockBalance(null, limitReached: true);
  }
  var balance = opening;
  final seen = <String, StockMovement>{};
  final epochs = <String, int>{};
  final corrected = <String>{};
  var measurementEpoch = 0;
  var count = 0;
  for (final movement in movements) {
    if (++count > maxMovements) {
      return const StockBalance(null, limitReached: true);
    }
    if (movement.owner != owner) throw ArgumentError('stock_owner_mismatch');
    if (movement.id.isEmpty || seen.containsKey(movement.id)) {
      throw ArgumentError('duplicate_movement');
    }
    if (exceedsBudget(movement.amount)) {
      return const StockBalance(null, limitReached: true);
    }
    final target = movement.reversesId;
    if (target != null) {
      final original = seen[target];
      if (original == null ||
          !corrected.add(target) ||
          (original.kind != StockMovementKind.actualUse &&
              original.kind != StockMovementKind.waste) ||
          (movement.amount != ExactAmount.zero &&
              movement.amount !=
                  (original.amount == null ? null : -original.amount!))) {
        throw ArgumentError('invalid_correction');
      }
    }
    seen[movement.id] = movement;
    if (movement.kind == StockMovementKind.reconciliation) measurementEpoch++;
    epochs[movement.id] = measurementEpoch;
    // A later physical measurement supersedes every earlier estimated effect.
    // Preserve the correction in history without inventing a physical return.
    if (target != null && epochs[target] != measurementEpoch) continue;
    balance = movement.kind == StockMovementKind.reconciliation
        ? movement.amount
        : balance == null || movement.amount == null
        ? null
        : balance + movement.amount!;
    if (exceedsBudget(balance)) {
      return const StockBalance(null, limitReached: true);
    }
  }
  return StockBalance(balance);
}
