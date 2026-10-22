import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/storage.dart';
import '../../app/app_lock.dart';
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

/// Exact, editable text for a saved capacity. A rational that terminates
/// within six places becomes a decimal; any other exact value stays a
/// numerator/denominator fraction, never a rounded display value.
String stockExactAmountEntry(ExactAmount value) {
  var denominator = value.denominator;
  var twos = 0, fives = 0;
  while (denominator % BigInt.two == BigInt.zero) {
    denominator ~/= BigInt.two;
    twos++;
  }
  while (denominator % BigInt.from(5) == BigInt.zero) {
    denominator ~/= BigInt.from(5);
    fives++;
  }
  final places = twos > fives ? twos : fives;
  if (denominator == BigInt.one && places <= 6) {
    var text = value.roundedDecimal(places: places);
    if (text.contains('.')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }
  return '${value.numerator}/${value.denominator}';
}

/// Parses a positive capacity entered as an exact decimal or a fraction such
/// as 1/3. Fractions keep their exact value and are never rounded.
ExactAmount stockCapacityEntry(String input) {
  final text = input.trim();
  final fraction = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(text);
  if (fraction != null) {
    final numerator = BigInt.parse(fraction.group(1)!);
    final denominator = BigInt.parse(fraction.group(2)!);
    if (denominator == BigInt.zero) {
      throw const FormatException('capacity_fraction');
    }
    final value = ExactAmount(numerator, denominator);
    if (value <= ExactAmount.zero || value > ExactAmount.maxEntered) {
      throw RangeError('capacity_range');
    }
    return value;
  }
  return ExactAmount.parseEntry(stockDecimal(text));
}

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

typedef StockInventoryQuery = ({
  String personId,
  String? itemId,
  String search,
  StockInventoryFilter filter,
  DateTime asOf,
  String? zone,
});

/// Whole-collection inventory state, composed from one store-backed search,
/// item scope and clock snapshot. The loaded page is sliced by the page.
final stockInventoryProvider = StreamProvider.autoDispose
    .family<StockInventorySnapshot, StockInventoryQuery>(
      retry: (_, _) => null,
      (ref, q) async* {
        if (ref.watch(appLockProvider.select((state) => state.locked))) {
          yield StockInventorySnapshot.empty();
          return;
        }
        try {
          yield* (await ref.watch(recordStoreProvider.future))
              .watchStockInventory(
                personId: q.personId,
                itemId: q.itemId,
                search: q.search,
                filter: q.filter,
                now: q.asOf,
                observedZone: q.zone,
              );
        } on CommandConflict catch (error) {
          if (error.code != 'app_locked') rethrow;
        }
      },
    );

typedef StockForecastQuery = ({
  String personId,
  String containerId,
  DateTime asOf,
  String? zone,
});

final stockForecastProvider = StreamProvider.autoDispose
    .family<StockRunOutForecast?, StockForecastQuery>(retry: (_, _) => null, (
      ref,
      q,
    ) async* {
      if (ref.watch(appLockProvider.select((state) => state.locked))) {
        yield null;
        return;
      }
      try {
        yield* (await ref.watch(recordStoreProvider.future)).watchStockForecast(
          personId: q.personId,
          containerId: q.containerId,
          now: q.asOf,
          observedZone: q.zone,
        );
      } on CommandConflict catch (error) {
        if (error.code != 'app_locked') rethrow;
      }
    });

final stockMetadataHistoryProvider = StreamProvider.autoDispose
    .family<
      List<StoredStockMetadataRevision>,
      ({String personId, String containerId, int offset})
    >(retry: (_, _) => null, (ref, q) async* {
      if (ref.watch(appLockProvider.select((state) => state.locked))) {
        yield const <StoredStockMetadataRevision>[];
        return;
      }
      try {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchStockMetadataHistory(
              personId: q.personId,
              containerId: q.containerId,
              offset: q.offset,
              limit: 21,
            );
      } on CommandConflict catch (error) {
        if (error.code != 'app_locked') rethrow;
      }
    });
