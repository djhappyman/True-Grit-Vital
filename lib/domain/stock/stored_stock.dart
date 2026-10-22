import 'exact_amount.dart';
import '../products/products.dart';
import '../scheduling/daily_plan.dart' show CivilDate;
import 'stock_ledger.dart';
export 'exact_amount.dart';
export 'stock_ledger.dart';
export '../scheduling/daily_plan.dart' show CivilDate;

enum StockNoticeState { none, low, refill, unknown, limitReached }

/// A civil expiry date compared with the person's current local day.
enum StockExpiryState { none, expired, today, future }

final class StockReplacement {
  const StockReplacement({
    required this.oldStrength,
    required this.newStrength,
    required this.keep,
  });
  final LabelledStrength oldStrength, newStrength;
  final FixedReplacementAmount keep;
}

final class StockUseInput {
  const StockUseInput({
    this.containerId,
    this.expectedContainerRevision,
    required this.expectedGeneration,
    required this.entered,
    this.replacement,
    this.strength,
  });
  final String expectedGeneration;
  final String? containerId;
  final int? expectedContainerRevision;
  final LabelledStrength? strength;
  final EnteredStockAmount entered;
  final StockReplacement? replacement;
}

final class StoredStockContainer {
  const StoredStockContainer({
    required this.id,
    required this.personId,
    required this.itemId,
    required this.label,
    required this.unit,
    required this.strength,
    required this.revision,
    required this.balance,
    required this.sequence,
    this.productLabel,
    this.lowThreshold,
    this.lot,
    this.expiryDate,
    this.capacity,
    required this.refillEnabled,
    this.alreadyCommitted = false,
  });
  final ProductLabelSnapshot? productLabel;
  final String id, personId, itemId, label, unit;
  final LabelledStrength strength;
  final int revision, sequence;
  final StockBalance balance;
  final ExactAmount? lowThreshold;

  /// Optional user-entered pack facts. Older rows read all three as null.
  /// They are descriptive: neither limits a recorded balance nor blocks use.
  final String? lot;
  final CivilDate? expiryDate;
  final ExactAmount? capacity;

  final bool refillEnabled, alreadyCommitted;

  StockExpiryState expiryState(CivilDate today) {
    final expiry = expiryDate;
    if (expiry == null) return StockExpiryState.none;
    final order = expiry.compareTo(today);
    return order < 0
        ? StockExpiryState.expired
        : order == 0
        ? StockExpiryState.today
        : StockExpiryState.future;
  }

  StockNoticeState get notice {
    if (balance.limitReached) return StockNoticeState.limitReached;
    final value = balance.value;
    if (value == null) return StockNoticeState.unknown;
    if (refillEnabled && value <= ExactAmount.zero) {
      return StockNoticeState.refill;
    }
    if (lowThreshold != null && value <= lowThreshold!) {
      return StockNoticeState.low;
    }
    return StockNoticeState.none;
  }

  bool get isLow => notice == StockNoticeState.low;
  bool get needsRefill => notice == StockNoticeState.refill;
}

/// A bounded visual proportion of exact values. The ratio is computed with
/// integers before one conversion to double, so large exact pairs cannot
/// overflow or become NaN. Values below zero show empty; values at or above
/// capacity show full. The full exact text remains the accessible value.
double stockCapacityFraction(ExactAmount balance, ExactAmount capacity) {
  if (capacity <= ExactAmount.zero) {
    throw ArgumentError('capacity_must_be_positive');
  }
  if (balance <= ExactAmount.zero) return 0;
  if (balance.compareTo(capacity) >= 0) return 1;
  final scaled =
      (balance.numerator * capacity.denominator * BigInt.from(1000000)) ~/
      (balance.denominator * capacity.numerator);
  return scaled.toDouble() / 1000000;
}

final class StoredStockMovement {
  const StoredStockMovement({
    required this.id,
    required this.personId,
    required this.containerId,
    required this.sequence,
    required this.kind,
    required this.amount,
    required this.strength,
    required this.recordedAt,
    this.recordId,
    this.enteredText,
    this.enteredUnit,
    this.reversesId,
    this.physicalCorrection,
    this.reviewedCorrection,
    this.replacement,
    this.reason,
  });
  final String id, personId, containerId;
  final int sequence;
  final StockMovementKind kind;
  final ExactAmount? amount;
  final LabelledStrength strength;
  final DateTime recordedAt;
  final String? recordId, enteredText, enteredUnit, reversesId, reason;
  final PhysicalCorrection? physicalCorrection, reviewedCorrection;
  final StockReplacement? replacement;
}

final class StockNoticeRow {
  const StockNoticeRow({
    required this.container,
    required this.personName,
    required this.itemName,
  });
  final StoredStockContainer container;
  final String personName, itemName;
}

final class StockNoticePage {
  StockNoticePage({
    required Iterable<StockNoticeRow> rows,
    required this.hasMore,
  }) : rows = List.unmodifiable(rows);
  final List<StockNoticeRow> rows;
  final bool hasMore;
}

/// One saved container metadata revision. The source says whether the row was
/// created, edited or carried forward by the schema 24 migration.
final class StoredStockMetadataRevision {
  const StoredStockMetadataRevision({
    required this.containerId,
    required this.revision,
    required this.recordedAt,
    required this.source,
    this.lot,
    this.expiryDate,
    this.capacity,
  });
  final String containerId;
  final int revision;
  final DateTime recordedAt;
  final String source;
  final String? lot;
  final CivilDate? expiryDate;
  final ExactAmount? capacity;
}

/// Balance-based inventory state. A known zero or deficit is Low, never
/// Adequate; an unknown or aggregate-limited balance stays its own state.
enum StockInventoryBalance { low, adequate, unknown }

/// Whole-collection inventory filters. Paused is plan-based and expiry is
/// pack-date based, so either may overlap a balance state; the popover states
/// that overlap rather than hiding it.
enum StockInventoryFilter { all, low, adequate, paused, unknown, expired, today }

/// The item's current plan shape, kept separate from its stock balance.
enum StockInventoryPlanState {
  active,
  paused,
  mixed,
  asNeeded,
  unscheduled,
  unresolved,
}

final class StockInventoryCounts {
  const StockInventoryCounts({
    required this.all,
    required this.low,
    required this.adequate,
    required this.paused,
    required this.unknown,
    required this.unresolved,
    this.expired,
    this.today,
  });
  const StockInventoryCounts.empty()
    : all = 0,
      low = 0,
      adequate = 0,
      paused = 0,
      unknown = 0,
      unresolved = 0,
      expired = null,
      today = null;
  final int all, low, adequate, paused, unknown, unresolved;

  /// Expiry counts are null when no observed local civil day was available.
  /// They are never reported as zero from an unknown date or time zone.
  final int? expired, today;

  bool get expiryKnown => expired != null && today != null;

  int? count(StockInventoryFilter filter) => switch (filter) {
    StockInventoryFilter.all => all,
    StockInventoryFilter.low => low,
    StockInventoryFilter.adequate => adequate,
    StockInventoryFilter.paused => paused,
    StockInventoryFilter.unknown => unknown,
    StockInventoryFilter.expired => expired,
    StockInventoryFilter.today => today,
  };
}

/// One whole-collection inventory read under one search and clock snapshot.
/// [containers] is the filtered list before the UI's page slice.
final class StockInventorySnapshot {
  StockInventorySnapshot({
    required Iterable<StoredStockContainer> containers,
    required Map<String, StockInventoryBalance> balances,
    required Map<String, StockInventoryPlanState> planStates,
    required this.counts,
    required this.complete,
    this.expiryDay,
  }) : containers = List.unmodifiable(containers),
       balances = Map.unmodifiable(balances),
       planStates = Map.unmodifiable(planStates);
  StockInventorySnapshot.empty()
    : containers = const [],
      balances = const {},
      planStates = const {},
      counts = const StockInventoryCounts.empty(),
      complete = true,
      expiryDay = null;
  final List<StoredStockContainer> containers;
  final Map<String, StockInventoryBalance> balances;
  final Map<String, StockInventoryPlanState> planStates;
  final StockInventoryCounts counts;

  /// The observed local civil day used for expiry comparison. Null means no
  /// valid date and zone were available, so expiry counts and filters stay
  /// unavailable instead of falling back to UTC or claiming zero.
  final CivilDate? expiryDay;

  /// False when the bounded whole-collection read hit its row bound. Counts
  /// and filters then stay visibly incomplete rather than claiming a total.
  final bool complete;

  StockInventoryBalance balanceFor(String containerId) =>
      balances[containerId] ?? StockInventoryBalance.unknown;
  StockInventoryPlanState planStateFor(String containerId) =>
      planStates[containerId] ?? StockInventoryPlanState.unscheduled;
}
