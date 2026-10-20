import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode;
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';

/// Regression coverage for AppearanceController across dataset replacement.
///
/// The controller keeps a shared notifier across record-store invalidations
/// (the restore path), so delayed loads and writes from the replaced dataset
/// must be fenced by an epoch instead of persistent instance flags. Pending
/// and failing rebuild emissions of the record surface still carry a value,
/// and that value is the store the previous generation already retired, so
/// the controller must only read a settled store.
///
/// Every fixture keeps ownership explicit: the container and every store the
/// test opened are closed before the fixture root is removed, on the success
/// and failure paths alike, because encrypted SQLite handles can still be
/// live during a plain directory removal.
void main() {
  final key = List.generate(32, (i) => i + 1);

  /// Opens a real encrypted store and hands ownership to [owned]; the test
  /// closes every opened store before deleting its fixture root.
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

  /// Closes the container and every owned store, then removes the fixture
  /// root last. A store close failure must still leave the root removed.
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

  /// Real SQLite work crosses an isolate, so a condition drawn from the store
  /// itself is re-read in real time until it holds or the bounded budget is
  /// spent. [polls] keeps the timeout meaningful without sleep inflation.
  Future<void> waitFor(
    Future<bool> Function() condition, {
    String? reason,
    int polls = 2000,
  }) async {
    for (var i = 0; i < polls; i++) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await pumpEventQueue();
    }
    fail(reason ?? 'appearance fixture condition never held');
  }

  /// Bounded negative probe. At the probed point nothing reputable is left
  /// scheduled (by design: the controller must schedule nothing), so expiry
  /// of this budget is itself the pass condition; the window is far wider
  /// than the cross-isolate latency every positive condition in this file
  /// resolves in within its first few polls.
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

  /// Drains chained microtasks and ready events without any real-time sleep.
  /// Conditions that depend on real SQLite work use [waitFor] instead.
  Future<void> drain() => pumpEventQueue();

  test(
    'a replacement dataset loads even after edits in the old dataset',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-appearance-');
      final owned = <RecordStore>[];
      ProviderContainer? onDispose;
      try {
        final storeA = await openStore(root, owned, 'a');
        final storeB = await openStore(root, owned, 'b');
        await storeB.writeSetting(
          'appearance',
          '{"mode":"system","opaque":false,"reduceMotion":true}',
        );
        RecordStore current = storeA;
        final container = ProviderContainer(
          overrides: [
            storeLoaderProvider.overrideWithValue(() async => current),
          ],
        );
        onDispose = container;
        // Keep every appearance surface active, mirroring app listeners.
        container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
        container.listen(appearanceErrorProvider, (_, _) {});
        container.listen(appearanceBusyProvider, (_, _) {});
        container.read(appearanceProvider.notifier);
        // storeA is empty, so preferences stay default until a first edit;
        // the empty read sets no state and raises no banner.
        await drain();
        expect(
          container.read(appearanceProvider),
          const AppearancePreferences(),
        );

        container.read(appearanceProvider.notifier).setMode(ThemeMode.dark);
        await waitFor(() async {
          final persisted = await storeA.readSetting('appearance');
          return persisted != null &&
              AppearancePreferences.decode(persisted).mode == ThemeMode.dark;
        }, reason: 'the first edit must reach the current dataset');
        expect(container.read(appearanceProvider).mode, ThemeMode.dark);

        // Mirror restore: retire the previous dataset, activate the new one.
        current = storeB;
        container.invalidate(recordStoreProvider);
        await waitFor(
          () async => container.read(appearanceProvider).reduceMotion,
          reason:
              'the replacement dataset persisted appearance must load even '
              'when the shared notifier saw an edit against the old dataset',
        );
        expect(container.read(appearanceProvider).opaque, false);
        expect(container.read(appearanceProvider).mode, ThemeMode.system);
        expect(container.read(appearanceErrorProvider), false);
        expect(container.read(appearanceBusyProvider), false);
      } finally {
        await disposeFixture(owned, root, onDispose);
      }
    },
  );

  test(
    'an old dataset write error cannot rewrite newer generation state',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-appearance-');
      final owned = <RecordStore>[];
      ProviderContainer? onDispose;
      try {
        final storeA = await openStore(root, owned, 'a');
        final storeB = await openStore(root, owned, 'b');
        RecordStore current = storeA;
        final writes = <Completer<void>>[];
        final container = ProviderContainer(
          overrides: [
            storeLoaderProvider.overrideWithValue(() async => current),
            appearanceWriterProvider.overrideWithValue((value) {
              final completer = Completer<void>();
              writes.add(completer);
              return completer.future;
            }),
          ],
        );
        onDispose = container;
        // Keep every appearance surface active, mirroring app listeners.
        container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
        container.listen(appearanceErrorProvider, (_, _) {});
        container.listen(appearanceBusyProvider, (_, _) {});
        container.read(appearanceProvider.notifier);
        await drain();

        container.read(appearanceProvider.notifier).setOpaque(true);
        expect(container.read(appearanceProvider).opaque, true);
        expect(container.read(appearanceBusyProvider), true);
        expect(writes, hasLength(1));
        // While the first write is in flight a second publication is serialised
        // away rather than interleave.
        container.read(appearanceProvider.notifier).setOpaque(false);
        expect(writes, hasLength(1));
        expect(container.read(appearanceBusyProvider), true);

        current = storeB;
        container.invalidate(recordStoreProvider);
        await drain();
        // storeB carries no appearance setting, so the new generation defaults.
        expect(
          container.read(appearanceProvider),
          const AppearancePreferences(),
        );

        writes.single.completeError(StateError('old dataset write failed'));
        await drain();
        expect(
          container.read(appearanceProvider),
          const AppearancePreferences(),
          reason:
              'a stale write failure must not roll the newer generation '
              'back to the old optimistic value',
        );
        expect(
          container.read(appearanceErrorProvider),
          false,
          reason:
              'a stale write failure must not surface its error in the '
              'newer generation',
        );
        expect(container.read(appearanceBusyProvider), false);

        // The genuine in-flight write still block until its completion, then
        // the new generation can retry its own publication.
        container.read(appearanceProvider.notifier).setOpaque(true);
        expect(writes, hasLength(2));
        expect(container.read(appearanceBusyProvider), true);
        writes.last.complete();
        await waitFor(
          () async => !container.read(appearanceBusyProvider),
          reason: 'the retired write finished, so the indicator must clear',
        );
        expect(container.read(appearanceProvider).opaque, true);
      } finally {
        await disposeFixture(owned, root, onDispose);
      }
    },
  );

  test(
    'a current write failure restores the committed value and retries',
    () async {
      var fail = true;
      final calls = <String>[];
      final container = ProviderContainer(
        overrides: [
          // Pin the store surface: without an override the default loader runs
          // a real bootstrap whose late AsyncValue transitions would rebuild
          // the shared notifier mid-test.
          storeLoaderProvider.overrideWithValue(
            () => Completer<RecordStore>().future,
          ),
          appearanceWriterProvider.overrideWithValue((value) async {
            calls.add(value);
            if (fail) throw StateError('injected appearance write failure');
          }),
        ],
      );
      try {
        container.read(appearanceProvider.notifier);
        await drain();

        container.read(appearanceProvider.notifier).setReduceMotion(true);
        await drain();
        expect(
          container.read(appearanceProvider),
          const AppearancePreferences(),
          reason: 'the failed publication rolls back to the committed value',
        );
        expect(container.read(appearanceErrorProvider), true);
        expect(container.read(appearanceBusyProvider), false);

        fail = false;
        container.read(appearanceProvider.notifier).setReduceMotion(true);
        await drain();
        expect(container.read(appearanceProvider).reduceMotion, true);
        expect(calls, hasLength(2));
        expect(container.read(appearanceErrorProvider), false);
        expect(container.read(appearanceBusyProvider), false);
      } finally {
        await disposeFixture(const [], null, container);
      }
    },
  );

  test('a pending initial load never clobbers a user edit', () async {
    final root = await Directory.systemTemp.createTemp('vital-appearance-');
    final owned = <RecordStore>[];
    ProviderContainer? onDispose;
    try {
      final store = await openStore(root, owned, 'a');
      await store.writeSetting(
        'appearance',
        '{"mode":"dark","opaque":false,"reduceMotion":false}',
      );
      final container = ProviderContainer(
        overrides: [storeLoaderProvider.overrideWithValue(() async => store)],
      );
      onDispose = container;
      // Keep every appearance surface active, mirroring app listeners.
      container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
      container.listen(appearanceErrorProvider, (_, _) {});
      container.listen(appearanceBusyProvider, (_, _) {});
      final notifier = container.read(appearanceProvider.notifier);
      notifier.setMode(ThemeMode.light);
      await waitFor(() async {
        final persisted = await store.readSetting('appearance');
        // Gate on the controller state as well: a read that raced the
        // publication applies its fresh result only after the write
        // settles, so the persisted value alone can arrive early.
        return persisted != null &&
            AppearancePreferences.decode(persisted).mode == ThemeMode.light &&
            container.read(appearanceProvider).mode == ThemeMode.light;
      }, reason: 'the user edit must reach the current dataset');
      expect(
        container.read(appearanceProvider).mode,
        ThemeMode.light,
        reason:
            'the persisted dark mode read must not clobber the user '
            'edit that landed while it was still in flight',
      );
    } finally {
      await disposeFixture(owned, root, onDispose);
    }
  });

  test(
    'a successful replacement load clears a prior dataset failure',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-appearance-');
      final owned = <RecordStore>[];
      ProviderContainer? onDispose;
      try {
        final storeA = await openStore(root, owned, 'a');
        final storeB = await openStore(root, owned, 'b');
        await storeB.writeSetting(
          'appearance',
          '{"mode":"system","opaque":false,"reduceMotion":true}',
        );
        RecordStore current = storeA;
        final writes = <Completer<void>>[];
        final container = ProviderContainer(
          overrides: [
            storeLoaderProvider.overrideWithValue(() async => current),
            appearanceWriterProvider.overrideWithValue((value) {
              final completer = Completer<void>();
              writes.add(completer);
              return completer.future;
            }),
          ],
        );
        onDispose = container;
        // Keep every appearance surface active, mirroring app listeners.
        container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
        container.listen(appearanceErrorProvider, (_, _) {});
        container.listen(appearanceBusyProvider, (_, _) {});
        container.read(appearanceProvider.notifier);
        await drain();

        // Fail a save while storeA is still the current dataset.
        container.read(appearanceProvider.notifier).setOpaque(true);
        expect(container.read(appearanceProvider).opaque, true);
        expect(container.read(appearanceBusyProvider), true);
        writes.single.completeError(StateError('current dataset write failed'));
        await waitFor(
          () async => container.read(appearanceErrorProvider),
          reason: 'the failed current save surfaces truthfully',
        );
        expect(container.read(appearanceBusyProvider), false);
        expect(
          container.read(appearanceProvider),
          const AppearancePreferences(),
          reason: 'the failure rolls back the optimistic value',
        );

        current = storeB;
        container.invalidate(recordStoreProvider);
        await waitFor(
          () async => container.read(appearanceProvider).reduceMotion,
          reason: 'the replacement dataset data must actually load',
        );
        expect(
          container.read(appearanceErrorProvider),
          false,
          reason:
              'the replacement dataset successful load must retire the '
              'failure banner its predecessor left, including after a '
              'non-empty read',
        );
        expect(container.read(appearanceBusyProvider), false);
      } finally {
        await disposeFixture(owned, root, onDispose);
      }
    },
  );

  test(
    'a replacement dataset with no setting clears a prior failure',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-appearance-');
      final owned = <RecordStore>[];
      ProviderContainer? onDispose;
      try {
        final storeA = await openStore(root, owned, 'a');
        final storeB = await openStore(root, owned, 'b');
        RecordStore current = storeA;
        final writes = <Completer<void>>[];
        final container = ProviderContainer(
          overrides: [
            storeLoaderProvider.overrideWithValue(() async => current),
            appearanceWriterProvider.overrideWithValue((value) {
              final completer = Completer<void>();
              writes.add(completer);
              return completer.future;
            }),
          ],
        );
        onDispose = container;
        // Keep every appearance surface active, mirroring app listeners.
        container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
        container.listen(appearanceErrorProvider, (_, _) {});
        container.listen(appearanceBusyProvider, (_, _) {});
        container.read(appearanceProvider.notifier);
        await drain();

        container.read(appearanceProvider.notifier).setOpaque(true);
        writes.single.completeError(StateError('current dataset write failed'));
        await waitFor(
          () async => container.read(appearanceErrorProvider),
          reason: 'the failed current save surfaces truthfully',
        );

        current = storeB;
        container.invalidate(recordStoreProvider);
        await waitFor(
          () async => !container.read(appearanceErrorProvider),
          reason:
              'a successful default load (no persisted setting) must also '
              'retire the prior dataset failure banner',
        );
        expect(
          container.read(appearanceProvider),
          const AppearancePreferences(),
        );
        expect(container.read(appearanceBusyProvider), false);
      } finally {
        await disposeFixture(owned, root, onDispose);
      }
    },
  );

  test('a replacement dataset with unreadable setting data surfaces its load failure', () async {
    final root = await Directory.systemTemp.createTemp('vital-appearance-');
    final owned = <RecordStore>[];
    ProviderContainer? onDispose;
    try {
      final storeA = await openStore(root, owned, 'a');
      final storeB = await openStore(root, owned, 'b');
      await storeB.writeSetting('appearance', 'not-json');
      RecordStore current = storeA;
      final container = ProviderContainer(
        overrides: [storeLoaderProvider.overrideWithValue(() async => current)],
      );
      onDispose = container;
      // Keep every appearance surface active, mirroring app listeners.
      container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
      container.listen(appearanceErrorProvider, (_, _) {});
      container.listen(appearanceBusyProvider, (_, _) {});
      container.read(appearanceProvider.notifier);
      await drain();
      expect(container.read(appearanceErrorProvider), false);

      current = storeB;
      container.invalidate(recordStoreProvider);
      await waitFor(
        () async => container.read(appearanceErrorProvider),
        reason:
            'the replacement dataset unreadable data must surface as a '
            'truthful current load failure',
      );
      expect(
        container.read(appearanceProvider),
        const AppearancePreferences(),
        reason: 'unreadable persisted data must not adopt any raw value',
      );
      expect(container.read(appearanceBusyProvider), false);
    } finally {
      await disposeFixture(owned, root, onDispose);
    }
  });

  test(
    'a replacement store that can no longer read surfaces its load failure',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-appearance-');
      final owned = <RecordStore>[];
      ProviderContainer? onDispose;
      try {
        final storeA = await openStore(root, owned, 'a');
        final storeB = await openStore(root, owned, 'b');
        RecordStore current = storeA;
        final container = ProviderContainer(
          overrides: [
            storeLoaderProvider.overrideWithValue(() async => current),
          ],
        );
        onDispose = container;
        // Keep every appearance surface active, mirroring app listeners.
        container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
        container.listen(appearanceErrorProvider, (_, _) {});
        container.listen(appearanceBusyProvider, (_, _) {});
        container.read(appearanceProvider.notifier);
        await drain();
        expect(container.read(appearanceErrorProvider), false);

        // Make the replacement read deterministically fail before the swap.
        await storeB.close();
        current = storeB;
        container.invalidate(recordStoreProvider);
        await waitFor(
          () async => container.read(appearanceErrorProvider),
          reason:
              'a current-epoch load whose read fails at the store boundary '
              'must surface truthfully',
        );
        expect(
          container.read(appearanceProvider),
          const AppearancePreferences(),
        );
        expect(container.read(appearanceBusyProvider), false);
      } finally {
        await disposeFixture(owned, root, onDispose);
      }
    },
  );

  test('a pending record reload never reads the retired store into preference state', () async {
    final root = await Directory.systemTemp.createTemp('vital-appearance-');
    final owned = <RecordStore>[];
    ProviderContainer? onDispose;
    try {
      final storeA = await openStore(root, owned, 'a');
      await storeA.writeSetting(
        'appearance',
        '{"mode":"system","opaque":true,"reduceMotion":false}',
      );
      Future<RecordStore> Function() loader = () async => storeA;
      final container = ProviderContainer(
        overrides: [storeLoaderProvider.overrideWithValue(() => loader())],
      );
      onDispose = container;
      // Keep every appearance surface active, mirroring app listeners.
      container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
      container.listen(appearanceErrorProvider, (_, _) {});
      container.listen(appearanceBusyProvider, (_, _) {});
      container.read(appearanceProvider.notifier);
      await waitFor(
        () async => container.read(appearanceProvider).opaque,
        reason: 'the first dataset data must settle first',
      );
      await drain();

      // A manual invalidate is the dataset-swap path: while the pending
      // emission resolves, the record surface retains the retired storeA
      // in its value. The controller must not read it into state.
      loader = () => Completer<RecordStore>().future;
      container.invalidate(recordStoreProvider);
      await drain();
      await nothingSurfaces(
        () async =>
            container.read(appearanceProvider) != const AppearancePreferences(),
        reason:
            'a manual invalidate keeps the retired store in the pending '
            'value and the controller must not read it as settled state',
      );
      expect(container.read(appearanceErrorProvider), false);
      expect(container.read(appearanceBusyProvider), false);
    } finally {
      await disposeFixture(owned, root, onDispose);
    }
  });

  test(
    'a failed record swap never reads the retired store into the error banner',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-appearance-');
      final owned = <RecordStore>[];
      ProviderContainer? onDispose;
      try {
        final storeA = await openStore(root, owned, 'a');
        Future<RecordStore> Function() loader = () async => storeA;
        final container = ProviderContainer(
          overrides: [storeLoaderProvider.overrideWithValue(() => loader())],
        );
        onDispose = container;
        // Keep every appearance surface active, mirroring app listeners.
        container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
        container.listen(appearanceErrorProvider, (_, _) {});
        container.listen(appearanceBusyProvider, (_, _) {});
        container.read(appearanceProvider.notifier);
        await drain();
        expect(container.read(appearanceErrorProvider), false);

        // Close the first store before the swap, so its read fails without
        // timing ambiguity, and make the swap itself fail at the record
        // boundary. The failing rebuild emission still retains storeA in
        // value.
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
        // The record failure belongs to the record surface; it must not be
        // attributed to the appearance loader either.
        await nothingSurfaces(
          () async => container.read(appearanceErrorProvider),
          reason:
              'a manual invalidate whose build fails still retains the '
              'retired store in the emitted value and the controller must '
              'not read it into the appearance banner',
        );
        expect(
          container.read(appearanceProvider),
          const AppearancePreferences(),
        );
        expect(container.read(appearanceBusyProvider), false);
      } finally {
        await disposeFixture(owned, root, onDispose);
      }
    },
  );
}
