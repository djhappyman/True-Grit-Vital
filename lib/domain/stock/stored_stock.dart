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
