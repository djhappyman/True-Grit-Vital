import '../../domain/stock/stored_stock.dart';

/// One optional pack-detail field saved in a container metadata revision.
enum StockMetadataField { lot, expiry, capacity }

/// How one field differs from an immediately preceding saved revision.
///
/// Two absent values in authored revisions are [unchanged]: absence is not an
/// inferred edit. A carried-forward predecessor has no recorded values, so its
/// fields are [unknown] rather than unchanged or cleared.
enum StockMetadataChange { unchanged, added, cleared, changed, unknown }

/// The comparison available for one saved revision.
enum StockMetadataComparison {
  /// Revision 1 was authored directly. No earlier version exists.
  first,

  /// The immediately preceding full revision is loaded and comparable.
  compared,

  /// This revision was inserted by the schema migration, not authored by a
  /// person.
  carriedForward,

  /// A later revision has no exact predecessor in the available page. No old
  /// value is inferred across that boundary.
  unavailable,
}

/// The factual difference for one field, using the saved typed values.
final class StockMetadataFieldDiff {
  const StockMetadataFieldDiff({
    required this.field,
    required this.change,
    this.before,
    this.after,
  });

  final StockMetadataField field;
  final StockMetadataChange change;

  /// Saved value in the previous revision when it was comparable.
  final Object? before;

  /// Saved value in this revision. Null means the field has no saved value.
  final Object? after;
}

/// One revision and the exact comparison that its saved values support.
final class StockMetadataRevisionDiff {
  const StockMetadataRevisionDiff({
    required this.revision,
    required this.comparison,
    required this.fields,
    this.predecessor,
  });

  final StoredStockMetadataRevision revision;
  final StockMetadataComparison comparison;
  final List<StockMetadataFieldDiff> fields;

  /// The exact immediately preceding revision, only when [comparison] is
  /// [StockMetadataComparison.compared].
  final StoredStockMetadataRevision? predecessor;

  /// The previous version came from the schema migration, so its absence of
  /// details is not a person's clearing action.
  bool get predecessorCarriedForward =>
      comparison == StockMetadataComparison.compared &&
      predecessor?.source == 'migrated';

  /// Fields that are not unchanged, in lot, expiry, capacity order. This
  /// includes unknown fields after a carried-forward predecessor.
  Iterable<StockMetadataFieldDiff> get changes =>
      fields.where((field) => field.change != StockMetadataChange.unchanged);
}

/// Compares one full saved revision with its exact predecessor.
///
/// [predecessor] may be null. It is only used when its revision number is one
/// lower than [revision]; a missing page row or a revision gap therefore yields
/// [StockMetadataComparison.unavailable] instead of guessing an older value.
StockMetadataRevisionDiff stockMetadataRevisionDiff(
  StoredStockMetadataRevision revision,
  StoredStockMetadataRevision? predecessor,
) {
  if (revision.source == 'migrated') {
    return StockMetadataRevisionDiff(
      revision: revision,
      comparison: StockMetadataComparison.carriedForward,
      fields: const [],
    );
  }
  if (revision.revision == 1) {
    return StockMetadataRevisionDiff(
      revision: revision,
      comparison: StockMetadataComparison.first,
      fields: const [],
    );
  }
  if (predecessor == null ||
      predecessor.containerId != revision.containerId ||
      predecessor.revision != revision.revision - 1) {
    return StockMetadataRevisionDiff(
      revision: revision,
      comparison: StockMetadataComparison.unavailable,
      fields: const [],
    );
  }
  return StockMetadataRevisionDiff(
    revision: revision,
    comparison: StockMetadataComparison.compared,
    predecessor: predecessor,
    fields: [
      _field(
        StockMetadataField.lot,
        predecessor.lot,
        revision.lot,
        predecessorCarriedForward: predecessor.source == 'migrated',
      ),
      _field(
        StockMetadataField.expiry,
        predecessor.expiryDate,
        revision.expiryDate,
        predecessorCarriedForward: predecessor.source == 'migrated',
      ),
      _field(
        StockMetadataField.capacity,
        predecessor.capacity,
        revision.capacity,
        predecessorCarriedForward: predecessor.source == 'migrated',
      ),
    ],
  );
}

StockMetadataFieldDiff _field<T>(
  StockMetadataField field,
  T? before,
  T? after, {
  required bool predecessorCarriedForward,
}) {
  if (predecessorCarriedForward) {
    return StockMetadataFieldDiff(
      field: field,
      change: StockMetadataChange.unknown,
      after: after,
    );
  }
  final change = before == after
      ? StockMetadataChange.unchanged
      : before == null
      ? StockMetadataChange.added
      : after == null
      ? StockMetadataChange.cleared
      : StockMetadataChange.changed;
  return StockMetadataFieldDiff(
    field: field,
    change: change,
    before: before,
    after: after,
  );
}
