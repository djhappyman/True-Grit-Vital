import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/stock/stored_stock.dart';
import 'package:true_grit_vital/features/stock/stock_metadata_diff.dart';

StoredStockMetadataRevision revision(
  int number, {
  String source = 'edited',
  String containerId = 'container',
  String? lot,
  CivilDate? expiry,
  ExactAmount? capacity,
}) => StoredStockMetadataRevision(
  containerId: containerId,
  revision: number,
  recordedAt: DateTime.utc(2026, 10, 22),
  source: source,
  lot: lot,
  expiryDate: expiry,
  capacity: capacity,
);

void main() {
  group('stock metadata revision diff', () {
    test('reports added, cleared, changed and unchanged fields', () {
      final diff = stockMetadataRevisionDiff(
        revision(
          2,
          lot: 'LOT-B',
          capacity: ExactAmount(BigInt.one, BigInt.from(3)),
        ),
        revision(
          1,
          lot: 'LOT-A',
          expiry: CivilDate(2027, 1, 31),
          capacity: ExactAmount(BigInt.one, BigInt.from(3)),
        ),
      );
      expect(diff.comparison, StockMetadataComparison.compared);
      expect(diff.changes.map((field) => field.field), [
        StockMetadataField.lot,
        StockMetadataField.expiry,
      ]);
      expect(
        diff.fields
            .singleWhere((f) => f.field == StockMetadataField.lot)
            .change,
        StockMetadataChange.changed,
      );
      expect(
        diff.fields
            .singleWhere((f) => f.field == StockMetadataField.lot)
            .before,
        'LOT-A',
      );
      expect(
        diff.fields.singleWhere((f) => f.field == StockMetadataField.lot).after,
        'LOT-B',
      );
      expect(
        diff.fields
            .singleWhere((f) => f.field == StockMetadataField.expiry)
            .change,
        StockMetadataChange.cleared,
      );
      expect(
        diff.fields
            .singleWhere((f) => f.field == StockMetadataField.capacity)
            .change,
        StockMetadataChange.unchanged,
      );
    });

    test('compares exact capacity fractions without rounding', () {
      final diff = stockMetadataRevisionDiff(
        revision(2, capacity: ExactAmount(BigInt.from(2), BigInt.from(6))),
        revision(1, capacity: ExactAmount(BigInt.one, BigInt.from(3))),
      );
      expect(
        diff.fields
            .singleWhere((f) => f.field == StockMetadataField.capacity)
            .change,
        StockMetadataChange.unchanged,
      );

      final changed = stockMetadataRevisionDiff(
        revision(3, capacity: ExactAmount(BigInt.one, BigInt.from(2))),
        revision(2, capacity: ExactAmount(BigInt.one, BigInt.from(3))),
      );
      final capacity = changed.fields.singleWhere(
        (f) => f.field == StockMetadataField.capacity,
      );
      expect(capacity.change, StockMetadataChange.changed);
      expect(capacity.before, ExactAmount(BigInt.one, BigInt.from(3)));
      expect(capacity.after, ExactAmount(BigInt.one, BigInt.from(2)));
    });

    test('adds a first value and keeps two absent values unchanged', () {
      final added = stockMetadataRevisionDiff(
        revision(2, lot: 'LOT-1'),
        revision(1),
      );
      expect(
        added.fields
            .singleWhere((f) => f.field == StockMetadataField.lot)
            .change,
        StockMetadataChange.added,
      );
      expect(
        added.fields
            .singleWhere((f) => f.field == StockMetadataField.expiry)
            .change,
        StockMetadataChange.unchanged,
      );

      final noChanges = stockMetadataRevisionDiff(revision(3), revision(2));
      expect(noChanges.changes, isEmpty);
    });

    test('does not compare a different container with adjacent numbering', () {
      final diff = stockMetadataRevisionDiff(
        revision(2, lot: 'NEW'),
        revision(1, containerId: 'other', lot: 'OLD'),
      );
      expect(diff.comparison, StockMetadataComparison.unavailable);
      expect(diff.changes, isEmpty);
    });

    test('does not infer an old value across a revision gap', () {
      final diff = stockMetadataRevisionDiff(
        revision(6, lot: 'LOT-6'),
        revision(4, lot: 'LOT-4'),
      );
      expect(diff.comparison, StockMetadataComparison.unavailable);
      expect(diff.predecessor, isNull);
      expect(diff.changes, isEmpty);
    });

    test('does not infer an old value without a loaded predecessor', () {
      final diff = stockMetadataRevisionDiff(revision(4, lot: 'LOT-4'), null);
      expect(diff.comparison, StockMetadataComparison.unavailable);
      expect(diff.changes, isEmpty);
    });

    test('treats the first authored version as having no comparison', () {
      final diff = stockMetadataRevisionDiff(
        revision(1, source: 'created', lot: 'LOT-1'),
        revision(1, source: 'migrated'),
      );
      expect(diff.comparison, StockMetadataComparison.first);
      expect(diff.predecessor, isNull);
      expect(diff.changes, isEmpty);
    });

    test('never calls a migrated version an authored edit', () {
      final diff = stockMetadataRevisionDiff(
        revision(1, source: 'migrated'),
        null,
      );
      expect(diff.comparison, StockMetadataComparison.carriedForward);
      expect(diff.changes, isEmpty);
      expect(diff.predecessorCarriedForward, isFalse);
    });

    test(
      'marks a carried-forward predecessor and still reports new values',
      () {
        final diff = stockMetadataRevisionDiff(
          revision(2, lot: 'LOT-NEW', capacity: ExactAmount(BigInt.one)),
          revision(1, source: 'migrated'),
        );
        expect(diff.comparison, StockMetadataComparison.compared);
        expect(diff.predecessor, isNotNull);
        expect(diff.predecessorCarriedForward, isTrue);
        final lot = diff.fields.singleWhere(
          (f) => f.field == StockMetadataField.lot,
        );
        expect(lot.change, StockMetadataChange.unknown);
        expect(lot.before, isNull);
        expect(lot.after, 'LOT-NEW');
      },
    );

    test('keeps a carried-forward predecessor unknown, not unchanged', () {
      final diff = stockMetadataRevisionDiff(
        revision(2),
        revision(1, source: 'migrated'),
      );
      expect(diff.predecessorCarriedForward, isTrue);
      expect(
        diff.fields.map((field) => field.change),
        everyElement(StockMetadataChange.unknown),
      );
      expect(diff.fields.map((field) => field.before), everyElement(isNull));
    });
  });
}
