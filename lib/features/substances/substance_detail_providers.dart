import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';

/// One substance's authored details, kept live after save, restore or deletion.
final itemDetailProvider = StreamProvider.autoDispose
    .family<SubstanceDetail?, String>((ref, itemId) async* {
      yield* (await ref.watch(recordStoreProvider.future))
          .watchItemDetail(itemId);
    });

/// Durable optional-step progress for a newly created substance.
final itemSetupProvider = StreamProvider.autoDispose
    .family<ItemSetupState?, String>((ref, itemId) async* {
      yield* (await ref.watch(recordStoreProvider.future))
          .watchItemSetup(itemId);
    });
