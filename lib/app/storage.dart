import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import '../platform/linux_storage_bootstrap.dart';
import '../platform/storage_bootstrap.dart';

/// Tests override this boundary with an explicitly keyed temporary database.
final storeLoaderProvider = Provider<Future<RecordStore> Function()>(
  (ref) => () async {
    final StorageBootstrap bootstrap;
    if (Platform.isAndroid) {
      bootstrap = const AndroidStorageBootstrap();
    } else if (Platform.isLinux) {
      bootstrap = LinuxStorageBootstrap();
    } else {
      throw const StorageBootstrapException('unsupported_host');
    }
    final location = await bootstrap.prepare();
    final store = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: location.isNew,
    );
    try {
      await bootstrap.activate(location);
      return store;
    } catch (_) {
      await store.close();
      rethrow;
    }
  },
);
final recordStoreProvider = FutureProvider<RecordStore>(retry: (_, _) => null, (
  ref,
) async {
  final store = await ref.watch(storeLoaderProvider)();
  ref.onDispose(store.close);
  return store;
});
final itemsProvider = StreamProvider<List<SubstanceItem>>(
  retry: (_, _) => null,
  (ref) async* {
    final store = await ref.watch(recordStoreProvider.future);
    yield* store.watchItems();
  },
);
final recordsProvider = StreamProvider<List<UseRecord>>(retry: (_, _) => null, (
  ref,
) async* {
  final store = await ref.watch(recordStoreProvider.future);
  yield* store.watchRecords();
});

final itemLookupProvider = StreamProvider.autoDispose
    .family<SubstanceItem?, String>(retry: (_, _) => null, (ref, id) async* {
      yield* (await ref.watch(recordStoreProvider.future)).watchItemById(id);
    });

final scopedItemsPageProvider = StreamProvider.autoDispose
    .family<List<SubstanceItem>, ({FeedScope scope, int offset})>(
      retry: (_, _) => null,
      (ref, query) async* {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchItems(scope: query.scope, limit: 51, offset: query.offset);
      },
    );
