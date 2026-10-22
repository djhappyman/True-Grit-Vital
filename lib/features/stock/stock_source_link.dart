import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/storage.dart';
import '../../domain/history/timeline_entry.dart';

/// Immutable owner and saved-dose record named by one stock movement.
typedef StockSourceKey = ({String personId, String recordId});

/// Canonical History entry identity for a saved dose.
///
/// A combined dose keeps its group identity, so inspection opens the same
/// combined source the person would reach from History. A separate single
/// dose keeps its record identity. A stock movement's `reversesId` is a
/// movement identity and is never used here.
typedef StockSourceTarget = ({TimelineEntryKind kind, String value});

/// The saved single-dose identity. Used while the grouped identity is still
/// being resolved and when the source no longer resolves at all.
StockSourceTarget singleStockSourceTarget(String recordId) =>
    (kind: TimelineEntryKind.record, value: recordId);

final stockSourceTargetProvider = FutureProvider.autoDispose
    .family<StockSourceTarget, StockSourceKey>((ref, key) async {
      final record = await (await ref.watch(recordStoreProvider.future))
          .recordById(key.recordId, personId: key.personId);
      final actionId = record?.combinedActionId;
      return actionId == null
          ? singleStockSourceTarget(key.recordId)
          : (kind: TimelineEntryKind.combined, value: actionId);
    });

/// The canonical read-only source route for one saved dose.
///
/// Path segments and query values are encoded by [Uri] rather than joined as
/// raw text, so an identity containing a separator cannot change the route.
String stockSourceLocation(
  StockSourceTarget target, {
  required String personId,
  required String returnLocation,
}) => Uri(
  path:
      '/history-source/${Uri.encodeComponent(target.kind.name)}/'
      '${Uri.encodeComponent(target.value)}',
  queryParameters: {
    'person': personId,
    if (returnLocation.isNotEmpty) 'return': returnLocation,
  },
).toString();
