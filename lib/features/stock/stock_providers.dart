import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';

export '../../domain/stock/exact_amount.dart';
export '../../domain/stock/stock_ledger.dart';
export '../../domain/stock/stored_stock.dart';

typedef StockQuery = ({String personId, String? itemId, int offset});
final stockContainersProvider = StreamProvider.autoDispose
    .family<List<StoredStockContainer>, StockQuery>(retry: (_, _) => null, (
      ref,
      q,
    ) async* {
      yield* (await ref.watch(recordStoreProvider.future)).watchStockContainers(
        personId: q.personId,
        itemId: q.itemId,
        limit: 51,
        offset: q.offset,
      );
    });
typedef OwnedContainer = ({String personId, String containerId});
final stockContainerProvider = StreamProvider.autoDispose
    .family<StoredStockContainer?, OwnedContainer>(retry: (_, _) => null, (
      ref,
      q,
    ) async* {
      yield* (await ref.watch(recordStoreProvider.future))
          .watchStockContainerById(
            personId: q.personId,
            containerId: q.containerId,
          );
    });
typedef StockRecordQuery = ({String personId, String recordId});
final stockUseProvider = StreamProvider.autoDispose
    .family<StoredStockMovement?, StockRecordQuery>(retry: (_, _) => null, (
      ref,
      q,
    ) async* {
      yield* (await ref.watch(recordStoreProvider.future))
          .watchStockUseForRecord(personId: q.personId, recordId: q.recordId);
    });

/// Explicit decimal separator policy. Grouping and mixed separators are rejected.
String stockDecimal(String input) {
  final text = input.trim();
  if (text.contains(',') && text.contains('.')) {
    throw const FormatException('mixed_separator');
  }
  return text.replaceAll(',', '.');
}

ExactAmount stockMeasurement(String input) {
  final text = stockDecimal(input);
  if (RegExp(r'^0(?:\.0{1,6})?$').hasMatch(text)) return ExactAmount.zero;
  return ExactAmount.parseEntry(text);
}

final stockMovementsProvider = FutureProvider.autoDispose
    .family<
      List<StoredStockMovement>,
      ({String personId, String containerId, int offset})
    >(retry: (_, _) => null, (ref, q) async {
      await ref.watch(
        stockContainerProvider((
          personId: q.personId,
          containerId: q.containerId,
        )).future,
      );
      return (await ref.watch(recordStoreProvider.future)).stockMovements(
        personId: q.personId,
        containerId: q.containerId,
        limit: 51,
        offset: q.offset,
      );
    });

bool sameStockStrength(LabelledStrength first, LabelledStrength second) {
  if (first.ingredientId != second.ingredientId) return false;
  if (first.mgPerMl != null && second.mgPerMl != null) {
    return first.mgPerMl == second.mgPerMl;
  }
  return first.mgPerMl == second.mgPerMl && first.label == second.label;
}

final stockNoticeProvider = StreamProvider.autoDispose
    .family<StockNoticePage, ({FeedScope scope, int offset})>(
      retry: (_, _) => null,
      (ref, q) async* {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchStockNotices(scope: q.scope, limit: 50, offset: q.offset);
      },
    );
