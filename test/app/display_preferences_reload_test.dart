import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';

/// Regression coverage for DisplayPreferencesController across dataset
/// replacement (restore re-invalidates `recordStoreProvider`).
///
/// Every fixture closes its container and its stores before the fixture root
/// is removed. Conditions are drawn from settled controller and store state,
/// never from timing calibration.
Future<void> main() async {
  final key = List.generate(32, (i) => i + 1);

  Future<RecordStore> openStore(
    Directory root,
    List<RecordStore> owned,
    String name,
  ) async {
    final directory = Directory('${root.path}/$name')..createSync();
    final store = await RecordStore.open(
      path: '${directory.path}/db',
      key: key,
      isNew: true,
    );
    owned.add(store);
    return store;
  }

  Future<void> disposeFixture(
    List<RecordStore> owned,
    Directory? root,
    ProviderContainer? container,
  ) async {
    try {
      try {
        container?.dispose();
      } finally {
        for (final store in owned) {
          await store.close();
        }
      }
    } finally {
      await root?.delete(recursive: true);
    }
  }

  Future<void> waitFor(
    Future<bool> Function() condition, {
    String? reason,
  }) async {
    for (var i = 0; i < 2000; i++) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await pumpEventQueue();
    }
    fail(reason ?? 'display preference fixture condition never held');
  }

  Future<void> nothingSurfaces(
    Future<bool> Function() forbidden, {
    String? reason,
  }) async {
    for (var i = 0; i < 250; i++) {
      expect(await forbidden(), isFalse, reason: reason);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await pumpEventQueue();
    }
  }

  Future<void> drain() => pumpEventQueue();

  ProviderContainer containerWith(Future<RecordStore> Function() loader) =>
      ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(loader),
          appLockProvider.overrideWith(DisplayReloadUnlock.new),
        ],
      );

  test('a pending record reload never reads the retired store into preference state', () async {
    final root = await Directory.systemTemp.createTemp('vital-time-swap-');
    final owned = <RecordStore>[];
    ProviderContainer? onDispose;
    try {
      final storeA = await openStore(root, owned, 'a');
      await storeA.writeSetting('display', '{"timeFormat":"h12"}');
      Future<RecordStore> Function() loader = () async => storeA;
      final container = containerWith(() => loader());
      onDispose = container;
      container.listen(
        displayPreferencesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final notifier = container.read(displayPreferencesProvider.notifier);
      await waitFor(
        () async =>
            container.read(displayPreferencesProvider).timeFormat ==
            TimeFormat.h12,
        reason: 'the first dataset data must settle first',
      );
      await drain();
      expect(
        (await storeA.readSetting('display'))!,
        contains('h12'),
        reason: 'the first dataset persisted its format',
      );

      // A manual invalidate is the dataset-swap path: while the pending
      // emission resolves, the record surface retains the retired storeA
      // in its value. The controller must not read it into state, and the
      // provider's own onDispose closes it as the swap retires it.
      loader = () => Completer<RecordStore>().future;
      container.invalidate(recordStoreProvider);
      await drain();
      await nothingSurfaces(
        () async {
          final current = container.read(displayPreferencesProvider);
          return current.timeFormat != TimeFormat.system ||
              current.busy ||
              current.failed;
        },
        reason:
            'a manual invalidate keeps the retired store in the pending '
            'value and the controller must not read it as settled state',
      );
      expect(container.read(displayPreferencesProvider).failed, isFalse);
      expect(notifier.state.busy, isFalse);
    } finally {
      await disposeFixture(owned, root, onDispose);
    }
  });

  test('a failed record swap never surfaces a preference failure from the retired store', () async {
    final root = await Directory.systemTemp.createTemp('vital-time-swap-');
    final owned = <RecordStore>[];
    ProviderContainer? onDispose;
    try {
      final storeA = await openStore(root, owned, 'a');
      Future<RecordStore> Function() loader = () async => storeA;
      final container = containerWith(() => loader());
      onDispose = container;
      container.listen(displayPreferencesProvider, (_, _) {});
      container.read(displayPreferencesProvider.notifier);
      await drain();
      expect(container.read(displayPreferencesProvider).failed, isFalse);

      // Close the first store before the swap, so any read of its retained
      // instance would fail loudly, and make the swap itself fail at the
      // record boundary. The failing rebuild emission still retains storeA
      // in value.
      await storeA.close();
      loader = () async {
        throw StateError('failed replacement loader');
      };
      container.invalidate(recordStoreProvider);
      await expectLater(
        container.read(recordStoreProvider.future),
        throwsA(isA<StateError>()),
      );
      await drain();
      await nothingSurfaces(
        () async => container.read(displayPreferencesProvider).failed,
        reason:
            'a failed rebuild still retains the retired store in the '
            'emitted value and the controller must not read it into the '
            'display failure state',
      );
      expect(container.read(displayPreferencesProvider).busy, isFalse);
    } finally {
      await disposeFixture(owned, root, onDispose);
    }
  });

  test(
    'a replacement dataset with no persisted setting loads its own default',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-time-swap-');
      final owned = <RecordStore>[];
      ProviderContainer? onDispose;
      try {
        final storeA = await openStore(root, owned, 'a');
        final storeB = await openStore(root, owned, 'b');
        RecordStore current = storeA;
        final container = containerWith(() async => current);
        onDispose = container;
        container.listen(displayPreferencesProvider, (_, _) {});
        final notifier = container.read(displayPreferencesProvider.notifier);
        await drain();
        await notifier.setTimeFormat(TimeFormat.h12);
        await waitFor(
          () async =>
              container.read(displayPreferencesProvider).timeFormat ==
              TimeFormat.h12,
          reason: 'the first edit must be applied to state',
        );

        // storeB carries no display setting, so it must supply the default
        // rather than keep the replaced dataset's value.
        current = storeB;
        container.invalidate(recordStoreProvider);
        await waitFor(
          () async =>
              container.read(displayPreferencesProvider).timeFormat ==
                  TimeFormat.system &&
              !container.read(displayPreferencesProvider).failed,
          reason:
              'a replacement without a persisted setting must retire any '
              'value from the replaced dataset',
        );
        expect(container.read(displayPreferencesProvider).busy, isFalse);
      } finally {
        await disposeFixture(owned, root, onDispose);
      }
    },
  );

  test(
    'unreadable persisted display data surfaces a truthful load failure',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-time-swap-');
      final owned = <RecordStore>[];
      ProviderContainer? onDispose;
      try {
        final storeA = await openStore(root, owned, 'a');
        final storeB = await openStore(root, owned, 'b');
        await storeB.writeSetting('display', 'not-json');
        RecordStore current = storeA;
        final container = containerWith(() async => current);
        onDispose = container;
        container.listen(displayPreferencesProvider, (_, _) {});
        container.read(displayPreferencesProvider.notifier);
        await drain();
        expect(container.read(displayPreferencesProvider).failed, isFalse);

        current = storeB;
        container.invalidate(recordStoreProvider);
        await waitFor(
          () async => container.read(displayPreferencesProvider).failed,
          reason:
              'the replacement dataset unreadable data must surface as a '
              'truthful current load failure',
        );
        expect(
          container.read(displayPreferencesProvider).timeFormat,
          TimeFormat.system,
          reason: 'unreadable data must not adopt a value',
        );
        expect(container.read(displayPreferencesProvider).busy, isFalse);
      } finally {
        await disposeFixture(owned, root, onDispose);
      }
    },
  );

  test('a locked app cannot publish a format change', () async {
    final root = await Directory.systemTemp.createTemp('vital-time-swap-');
    final owned = <RecordStore>[];
    ProviderContainer? onDispose;
    try {
      final store = await openStore(root, owned, 'a');
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(DisplayReloadLock.new),
        ],
      );
      onDispose = container;
      container.listen(displayPreferencesProvider, (_, _) {});
      final notifier = container.read(displayPreferencesProvider.notifier);
      await drain();
      await notifier.setTimeFormat(TimeFormat.h24);
      expect(
        await store.readSetting('display'),
        isNull,
        reason: 'a locked session must not write a format change',
      );
      expect(
        container.read(displayPreferencesProvider).timeFormat,
        TimeFormat.system,
      );
      expect(container.read(displayPreferencesProvider).busy, isFalse);
    } finally {
      await disposeFixture(owned, root, onDispose);
    }
  });
  test('a successful replacement loads its own time format and clears a prior failure', () async {
    final root = await Directory.systemTemp.createTemp('vital-time-swap-');
    final owned = <RecordStore>[];
    ProviderContainer? onDispose;
    try {
      final storeA = await openStore(root, owned, 'a');
      final storeB = await openStore(root, owned, 'b');
      await storeB.writeSetting('display', '{"timeFormat":"h24"}');
      RecordStore current = storeA;
      final writes = <Completer<void>>[];
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => current),
          appLockProvider.overrideWith(DisplayReloadUnlock.new),
          displayPreferenceWriterProvider.overrideWithValue((value) {
            final completer = Completer<void>();
            writes.add(completer);
            return completer.future;
          }),
        ],
      );
      onDispose = container;
      container.listen(displayPreferencesProvider, (_, _) {});
      final notifier = container.read(displayPreferencesProvider.notifier);
      await drain();

      // Fail a save while storeA is still the current dataset.
      final pending = notifier.setTimeFormat(TimeFormat.h24);
      await drain();
      expect(container.read(displayPreferencesProvider).busy, isTrue);
      writes.single.completeError(StateError('current dataset write failed'));
      await waitFor(
        () async => container.read(displayPreferencesProvider).failed,
        reason: 'the failed current save surfaces truthfully',
      );
      await pending;

      current = storeB;
      container.invalidate(recordStoreProvider);
      await waitFor(
        () async =>
            container.read(displayPreferencesProvider).timeFormat ==
            TimeFormat.h24,
        reason: 'the replacement dataset persisted format must load',
      );
      expect(container.read(displayPreferencesProvider).failed, isFalse);
      expect(container.read(displayPreferencesProvider).busy, isFalse);
    } finally {
      await disposeFixture(owned, root, onDispose);
    }
  });

  test(
    'a current write failure rolls back and clears busy before a retry',
    () async {
      var fail = true;
      final calls = <String>[];
      final container = ProviderContainer(
        overrides: [
          // Pin the store surface so no late record transition rebuilds the
          // shared notifier mid-test.
          storeLoaderProvider.overrideWithValue(
            () => Completer<RecordStore>().future,
          ),
          appLockProvider.overrideWith(DisplayReloadUnlock.new),
          displayPreferenceWriterProvider.overrideWithValue((value) async {
            calls.add(value);
            if (fail) throw StateError('injected display write failure');
          }),
        ],
      );
      try {
        final notifier = container.read(displayPreferencesProvider.notifier);
        await drain();

        final pending = notifier.setTimeFormat(TimeFormat.h24);
        await drain();
        expect(
          container.read(displayPreferencesProvider).timeFormat,
          TimeFormat.system,
          reason: 'the failed publication rolls back',
        );
        expect(container.read(displayPreferencesProvider).failed, isTrue);
        expect(container.read(displayPreferencesProvider).busy, isFalse);
        await pending;

        fail = false;
        await notifier.setTimeFormat(TimeFormat.h24);
        expect(
          container.read(displayPreferencesProvider).timeFormat,
          TimeFormat.h24,
        );
        expect(calls, hasLength(2));
        expect(container.read(displayPreferencesProvider).failed, isFalse);
        expect(container.read(displayPreferencesProvider).busy, isFalse);
      } finally {
        await disposeFixture(const [], null, container);
      }
    },
  );

  test(
    'a rebuild mid-write serialises instead of overlapping stores',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-time-swap-');
      final owned = <RecordStore>[];
      ProviderContainer? onDispose;
      try {
        final storeA = await openStore(root, owned, 'a');
        final storeB = await openStore(root, owned, 'b');
        RecordStore current = storeA;
        final writes = <Completer<void>>[];
        final written = <String>[];
        final container = ProviderContainer(
          overrides: [
            storeLoaderProvider.overrideWithValue(() async => current),
            appLockProvider.overrideWith(DisplayReloadUnlock.new),
            displayPreferenceWriterProvider.overrideWithValue((value) {
              written.add(value);
              final completer = Completer<void>();
              writes.add(completer);
              return completer.future;
            }),
          ],
        );
        onDispose = container;
        container.listen(displayPreferencesProvider, (_, _) {});
        final notifier = container.read(displayPreferencesProvider.notifier);
        await drain();
        final pending = notifier.setTimeFormat(TimeFormat.h12);
        await drain();
        expect(writes, hasLength(1));

        // A rebuild keeps controls busy while the previous write still owns
        // the publication slot, so the UI cannot offer a silently ignored edit.
        current = storeB;
        container.invalidate(recordStoreProvider);
        await container.read(recordStoreProvider.future);
        await drain();
        expect(container.read(displayPreferencesProvider).busy, isTrue);
        final overlap = notifier.setTimeFormat(TimeFormat.h24);
        expect(writes, hasLength(1));
        expect(overlap, completes);

        // The write outcome is fenced: the replaced generation's write cannot
        // move the newer generation's state away from its own default.
        writes.single.complete();
        await pending;
        await drain();
        expect(
          container.read(displayPreferencesProvider).timeFormat,
          TimeFormat.system,
          reason: 'an old-generation write can no longer set state',
        );
        expect(container.read(displayPreferencesProvider).busy, isFalse);

        // A newer decision publishes once the older write has settled.
        final retry = notifier.setTimeFormat(TimeFormat.h24);
        expect(writes, hasLength(2));
        writes.last.complete();
        await retry;
        expect(written.last, contains('"h24"'));
        expect(
          container.read(displayPreferencesProvider).timeFormat,
          TimeFormat.h24,
        );
      } finally {
        await disposeFixture(owned, root, onDispose);
      }
    },
  );
}

/// Lock stub mirrors the existing `AppLockController` driver overrides so
/// `setTimeFormat` sees an unlocked covered session.
class DisplayReloadUnlock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

class DisplayReloadLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: true);
}
