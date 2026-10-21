import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/dashboard_favourites.dart';

class _Lock extends AppLockController {
  _Lock(this.locked);
  bool locked;
  @override
  AppLockState build() =>
      AppLockState(ready: true, locked: locked, enabled: false);
  void set(bool value) {
    locked = value;
    state = state.copy(locked: value);
  }
}

Future<RecordStore> openStore(Directory directory, {bool isNew = true}) =>
    RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (index) => index + 1),
      isNew: isNew,
    );

Future<DashboardFavourites> waitLoaded(ProviderContainer container) async {
  for (var attempt = 0; attempt < 250; attempt++) {
    final state = container.read(dashboardFavouritesProvider);
    if (state.loaded) return state;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('favourites did not load');
}

void main() {
  test('decodes order, drops duplicates and rejects malformed records', () {
    expect(decodeDashboardFavouriteIds('{"planIds":["b","a","b"]}'), [
      'b',
      'a',
    ]);
    expect(
      () => decodeDashboardFavouriteIds('not json'),
      throwsFormatException,
    );
    expect(
      () => decodeDashboardFavouriteIds('{"planIds":[1]}'),
      throwsFormatException,
    );
    expect(
      () => decodeDashboardFavouriteIds('{"other":[]}'),
      throwsFormatException,
    );
  });

  test(
    'saves order, reloads it and keeps it through a store restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vital-favourites-',
      );
      var store = await openStore(directory);
      await store.writeSetting(
        'dashboard_favourites',
        jsonEncode({
          'planIds': ['b', 'a'],
        }),
      );
      var container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(() => _Lock(false)),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await store.close();
        await directory.delete(recursive: true);
      });
      expect((await waitLoaded(container)).planIds, ['b', 'a']);
      expect(
        await container.read(dashboardFavouritesProvider.notifier).save([
          'c',
          'a',
        ]),
        isTrue,
      );
      expect(
        decodeDashboardFavouriteIds(
          (await store.readSetting('dashboard_favourites'))!,
        ),
        ['c', 'a'],
      );

      // Reopen the encrypted dataset with a fresh provider tree.
      container.dispose();
      await store.close();
      store = await openStore(directory, isNew: false);
      container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(() => _Lock(false)),
        ],
      );
      expect((await waitLoaded(container)).planIds, ['c', 'a']);
    },
  );

  test(
    'a failed write restores the committed order and reports failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vital-favourites-',
      );
      final store = await openStore(directory);
      await store.writeSetting(
        'dashboard_favourites',
        jsonEncode({
          'planIds': ['a'],
        }),
      );
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(() => _Lock(false)),
          dashboardFavouritesWriterProvider.overrideWithValue(
            (store, value, canCommit) async =>
                throw StateError('injected_failure'),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await store.close();
        await directory.delete(recursive: true);
      });
      await waitLoaded(container);
      expect(
        await container.read(dashboardFavouritesProvider.notifier).save(['b']),
        isFalse,
      );
      final state = container.read(dashboardFavouritesProvider);
      expect(state.planIds, ['a']);
      expect(state.failed, isTrue);
      expect(
        decodeDashboardFavouriteIds(
          (await store.readSetting('dashboard_favourites'))!,
        ),
        ['a'],
      );
    },
  );

  test('a locked dataset writes nothing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vital-favourites-',
    );
    final store = await openStore(directory);
    await store.writeSetting(
      'dashboard_favourites',
      jsonEncode({
        'planIds': ['a'],
      }),
    );
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => store),
        appLockProvider.overrideWith(() => _Lock(true)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await store.close();
      await directory.delete(recursive: true);
    });
    await waitLoaded(container);
    expect(
      await container.read(dashboardFavouritesProvider.notifier).save(['b']),
      isFalse,
    );
    expect(container.read(dashboardFavouritesProvider).planIds, ['a']);
    expect(
      decodeDashboardFavouriteIds(
        (await store.readSetting('dashboard_favourites'))!,
      ),
      ['a'],
    );
  });

  test('a replaced store wins over an in-flight old-store write', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vital-favourites-',
    );
    final storeA = await openStore(directory);
    await storeA.writeSetting(
      'dashboard_favourites',
      jsonEncode({
        'planIds': ['a'],
      }),
    );
    final storeB = await RecordStore.open(
      path: '${directory.path}/replacement.db',
      key: List.generate(32, (index) => index + 1),
      isNew: true,
    );
    await storeB.writeSetting(
      'dashboard_favourites',
      jsonEncode({
        'planIds': ['b'],
      }),
    );
    var current = storeA;
    final gate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => current),
        appLockProvider.overrideWith(() => _Lock(false)),
        dashboardFavouritesWriterProvider.overrideWithValue((
          store,
          value,
          canCommit,
        ) async {
          await gate.future;
          throw StateError('old_store_write');
        }),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await storeA.close();
      await storeB.close();
      await directory.delete(recursive: true);
    });
    await waitLoaded(container);
    final saving = container.read(dashboardFavouritesProvider.notifier).save([
      'x',
    ]);
    await Future<void>.delayed(Duration.zero);
    current = storeB;
    container.invalidate(recordStoreProvider);
    await container.read(recordStoreProvider.future);
    gate.complete();
    expect(await saving, isFalse);
    for (var attempt = 0; attempt < 250; attempt++) {
      final state = container.read(dashboardFavouritesProvider);
      if (state.loaded && !state.busy && state.planIds.isNotEmpty) {
        expect(state.planIds, ['b']);
        expect(state.failed, isFalse);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    fail('replacement store choices did not load');
  });

  test('a delayed write across a lock cycle cannot publish', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vital-favourites-',
    );
    final store = await openStore(directory);
    await store.writeSetting(
      'dashboard_favourites',
      jsonEncode({
        'planIds': ['a'],
      }),
    );
    final gate = Completer<void>();
    final lock = _Lock(false);
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => store),
        appLockProvider.overrideWith(() => lock),
        dashboardFavouritesWriterProvider.overrideWithValue((
          store,
          value,
          canCommit,
        ) async {
          await gate.future;
          await store.writeSetting(
            'dashboard_favourites',
            value,
            canCommit: canCommit,
          );
        }),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await store.close();
      await directory.delete(recursive: true);
    });
    await waitLoaded(container);
    final saving = container.read(dashboardFavouritesProvider.notifier).save([
      'z',
    ]);
    await Future<void>.delayed(Duration.zero);
    lock.set(true);
    await Future<void>.delayed(Duration.zero);
    lock.set(false);
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    expect(await saving, isFalse);
    final state = container.read(dashboardFavouritesProvider);
    expect(state.planIds, ['a']);
    expect(state.failed, isTrue);
    expect(
      decodeDashboardFavouriteIds(
        (await store.readSetting('dashboard_favourites'))!,
      ),
      ['a'],
    );
  });
}
