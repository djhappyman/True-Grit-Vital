import 'records.dart';
import 'products/products.dart';
import 'reminders/reminders.dart';
import 'scheduling/stored_daily.dart';
import 'scheduling/daily_plan.dart';
import 'stock/stored_stock.dart';

/// A bounded recording action, not a recipe or a compatibility judgement.
const maxCombinedSources = 16;

void _identity(String value) {
  if (value.isEmpty || value.length > 256) {
    throw const FormatException('combined_identity');
  }
}

void _site(String? label) {
  if (label != null && (label.trim().isEmpty || label.length > 500)) {
    throw const FormatException('combined_site');
  }
}

/// Independent physical source. An occurrence link applies only to this source.
final class CombinedUseComponent {
  CombinedUseComponent({
    required this.itemId,
    required this.expectedItemRevision,
    required this.enteredAmount,
    this.stockUse,
    this.productUse,
    this.intendedRow,
    this.intervalClockSample,
    this.siteLabel,
  }) {
    _identity(itemId);
    ExactQuantity.parse(enteredAmount);
    _site(siteLabel);
    if (expectedItemRevision < 1 || stockUse != null && productUse != null) {
      throw const FormatException('combined_source');
    }
    final entered = stockUse?.entered ?? productUse?.enteredVolume;
    if (entered != null && entered.originalText != enteredAmount) {
      throw const FormatException('combined_amount');
    }
    final container = stockUse?.containerId ?? productUse?.containerId;
    final revision =
        stockUse?.expectedContainerRevision ??
        productUse?.expectedContainerRevision;
    if (container != null) {
      _identity(container);
      if ((revision ?? 0) < 1) {
        throw const FormatException('combined_container');
      }
    } else if (revision != null) {
      throw const FormatException('combined_container');
    }
  }
  final String itemId, enteredAmount;
  final int expectedItemRevision;
  final StockUseInput? stockUse;
  final ProductUseInput? productUse;
  final String? siteLabel;
  final DailyRow? intendedRow;
  final ReminderClockSample? intervalClockSample;
  String? get containerId => stockUse?.containerId ?? productUse?.containerId;
}

final class CombinedUseCommand {
  CombinedUseCommand({
    required this.commandId,
    required this.expectedGeneration,
    required this.personId,
    required this.expectedPersonRevision,
    required this.actualAt,
    required Iterable<CombinedUseComponent> components,
  }) : components = List.unmodifiable(components) {
    for (final id in [commandId, expectedGeneration, personId]) {
      _identity(id);
    }
    if (expectedPersonRevision < 1 ||
        this.components.length < 2 ||
        this.components.length > maxCombinedSources ||
        actualAt.year < 1 ||
        actualAt.year > 9999) {
      throw const FormatException('combined_command');
    }
    final buckets = <DailyIdentity>{};
    for (final component in this.components) {
      final row = component.intendedRow;
      if (row != null && !buckets.add(row.expectation.identity)) {
        throw const FormatException('combined_duplicate_occurrence');
      }
      if (row != null &&
          (row.generation != expectedGeneration ||
              row.personRevision != expectedPersonRevision ||
              row.expectation.identity.personId != personId ||
              row.expectation.itemId != component.itemId ||
              row.itemRevision != component.expectedItemRevision)) {
        throw const CommandConflict('combined_occurrence');
      }
      if (component.stockUse case final stock?) {
        if (stock.expectedGeneration != expectedGeneration) {
          throw const CommandConflict('generation');
        }
      }
      if (component.productUse case final product?) {
        if (product.expectedGeneration != expectedGeneration) {
          throw const CommandConflict('generation');
        }
        if (product.label.personId != personId ||
            product.label.itemId != component.itemId ||
            product.sourceLabel != null &&
                (product.sourceLabel!.personId != personId ||
                    product.sourceLabel!.itemId != component.itemId)) {
          throw const CommandConflict('ownership');
        }
        if (product.expectedItemRevision != null &&
            product.expectedItemRevision != component.expectedItemRevision) {
          throw const CommandConflict('item_revision');
        }
      }
    }
  }
  final String commandId, expectedGeneration, personId;
  final int expectedPersonRevision;
  final DateTime actualAt;
  final List<CombinedUseComponent> components;
}

/// Explicit physical policy remains separate from correcting the record.
/// A null site clears the previous snapshot; callers preserve untouched sites.
final class CombinedCorrectionComponent {
  CombinedCorrectionComponent({
    required this.recordId,
    required this.expectedRevision,
    required this.physicalCorrection,
    this.enteredAmount,
    this.siteLabel,
    Iterable<IntervalChangeReview> intervalReviews = const [],
  }) : intervalReviews = List.unmodifiable(intervalReviews) {
    _identity(recordId);
    _site(siteLabel);
    if (expectedRevision < 1) {
      throw const FormatException('combined_revision');
    }
    if (enteredAmount != null) ExactQuantity.parse(enteredAmount!);
  }
  final String recordId;
  final int expectedRevision;
  final String? enteredAmount, siteLabel;
  final PhysicalCorrection? physicalCorrection;
  final List<IntervalChangeReview> intervalReviews;
}

/// The store must verify that these are exactly the current group's members.
final class CombinedCorrectionCommand {
  CombinedCorrectionCommand({
    required this.commandId,
    required this.actionId,
    required this.personId,
    required this.expectedPersonRevision,
    required this.expectedGeneration,
    required Iterable<CombinedCorrectionComponent> components,
    this.actualAt,
    this.voided = false,
  }) : components = List.unmodifiable(components) {
    for (final id in [commandId, actionId, personId, expectedGeneration]) {
      _identity(id);
    }
    if (expectedPersonRevision < 1 ||
        this.components.length < 2 ||
        this.components.length > maxCombinedSources ||
        this.components.map((c) => c.recordId).toSet().length !=
            this.components.length ||
        actualAt != null && (actualAt!.year < 1 || actualAt!.year > 9999) ||
        voided &&
            (actualAt != null ||
                this.components.any((c) => c.enteredAmount != null))) {
      throw const FormatException('combined_correction');
    }
  }
  final String commandId, actionId, personId, expectedGeneration;
  final int expectedPersonRevision;
  final List<CombinedCorrectionComponent> components;
  final DateTime? actualAt;
  final bool voided;
}

final class CombinedUseResult {
  CombinedUseResult({
    required this.actionId,
    required this.personId,
    required Iterable<UseRecord> records,
    this.alreadyCommitted = false,
  }) : records = List.unmodifiable(records);
  final String actionId, personId;
  final List<UseRecord> records;
  final bool alreadyCommitted;
}

/// A reviewed physical outflow, counted once per component, never per ingredient.
final class CombinedStockOutflow {
  const CombinedStockOutflow({
    required this.containerId,
    required this.personId,
    required this.itemId,
    required this.unit,
    required this.expectedRevision,
    required this.amount,
  });
  final String containerId, personId, itemId, unit;
  final int expectedRevision;
  final ExactAmount? amount;
}

/// Fold same-container draws exactly; unknown conversion keeps the total unknown.
/// A negative resulting balance represents a mismatch, not a rejected actual.
List<CombinedStockOutflow> combineStockOutflows(
  Iterable<CombinedStockOutflow> outflows,
) {
  final result = <String, CombinedStockOutflow>{};
  var count = 0;
  for (final next in outflows) {
    if (++count > maxCombinedSources ||
        next.expectedRevision < 1 ||
        next.amount != null && next.amount! < ExactAmount.zero) {
      throw const FormatException('combined_outflow');
    }
    final old = result[next.containerId];
    if (old != null &&
        (old.personId != next.personId ||
            old.itemId != next.itemId ||
            old.unit != next.unit ||
            old.expectedRevision != next.expectedRevision)) {
      throw const CommandConflict('combined_container_snapshot');
    }
    result[next.containerId] = CombinedStockOutflow(
      containerId: next.containerId,
      personId: next.personId,
      itemId: next.itemId,
      unit: next.unit,
      expectedRevision: next.expectedRevision,
      amount: old == null
          ? next.amount
          : old.amount == null || next.amount == null
          ? null
          : old.amount! + next.amount!,
    );
  }
  return List.unmodifiable(result.values);
}
