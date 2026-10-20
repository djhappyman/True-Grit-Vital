import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';

/// Regression coverage for AppearanceController across dataset replacement.
/// The controller keeps a shared notifier across record-store invalidations
/// (the restore path), so delayed loads and writes from the replaced dataset
/// must be fenced by an epoch instead of persistent instance flags.
void main() {
  final key = List.generate(32, (i) => i + 1);

  Future<RecordStore> openStore(Directory root, String name) async {
    final directory = Directory('${root.path}/$name')..createSync();
    return RecordStore.open(
      path: '${directory.path}/db',
      key: key,
      isNew: true,
    );
  }

  AppearancePreferences parse(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return AppearancePreferences(
      mode: ThemeMode.values.firstWhere(
        (m) => m.name == data['mode'],
        orElse: () => ThemeMode.system,
      ),
      opaque: data['opaque'] == true,
      reduceMotion: data['reduceMotion'] == true,
    );
  }

  /// Real SQLite writes cross isolates; poll real time until the condition
  /// holds or the bounded budget is spent.
  Future<void> waitFor(Future<bool> Function() condition) async {
    for (var i = 0; i < 2000; i++) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await pumpEventQueue();
    }
    fail('appearance fixture condition never held');
  }

  Future<void> flush() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await pumpEventQueue();
    }
  }

  test('a replacement dataset loads even after edits in the old dataset', () async {
    final root = await Directory.systemTemp.createTemp('vital-appearance-');
    try {
      final storeA = await openStore(root, 'a');
      final storeB = await openStore(root, 'b');
      await storeB.writeSetting(
        'appearance',
        jsonEncode({'mode': 'system', 'opaque': false, 'reduceMotion': true}),
      );
      RecordStore current = storeA;
      addTearDown(() => storeB.close());
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue((() async => current)),
        ],
      );
      // Keep every appearance surface active, mirroring app listeners.
      container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
      container.listen(appearanceErrorProvider, (_, _) {});
      container.listen(appearanceBusyProvider, (_, _) {});
      addTearDown(container.dispose);
      // Keep every appearance surface active, mirroring app listeners.
      container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
      container.listen(appearanceErrorProvider, (_, _) {});
      container.listen(appearanceBusyProvider, (_, _) {});

      container.read(appearanceProvider.notifier);
      // storeA is empty, so preferences stay default until a first edit.
      await flush();
      expect(container.read(appearanceProvider), const AppearancePreferences());

      container.read(appearanceProvider.notifier).setMode(ThemeMode.dark);
      await waitFor(() async {
        final persisted = await storeA.readSetting('appearance');
        return parse(persisted ?? '{}').mode == ThemeMode.dark;
      });
      expect(container.read(appearanceProvider).mode, ThemeMode.dark);

      // Mirror restore: retire the previous dataset, activate the new one.
      current = storeB;
      container.invalidate(recordStoreProvider);
      await flush();

      expect(
        container.read(appearanceProvider).reduceMotion,
        true,
        reason:
            'the replacement dataset persisted appearance must load even when '
            'the shared notifier saw an edit against the old dataset',
      );
      expect(container.read(appearanceProvider).opaque, false);
      expect(container.read(appearanceProvider).mode, ThemeMode.system);
      expect(container.read(appearanceErrorProvider), false);
      expect(container.read(appearanceBusyProvider), false);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'an old dataset write error cannot rewrite newer generation state',
    () async {
      final root = await Directory.systemTemp.createTemp('vital-appearance-');
      try {
        final storeA = await openStore(root, 'a');
        final storeB = await openStore(root, 'b');
        RecordStore current = storeA;
        addTearDown(() => storeB.close());
        final writes = <Completer<void>>[];
        final container = ProviderContainer(
          overrides: [
            storeLoaderProvider.overrideWithValue((() async => current)),
            appearanceWriterProvider.overrideWithValue((value) {
              final completer = Completer<void>();
              writes.add(completer);
              return completer.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        // Keep every appearance surface active, mirroring app listeners.
        container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
        container.listen(appearanceErrorProvider, (_, _) {});
        container.listen(appearanceBusyProvider, (_, _) {});
        container.read(appearanceProvider.notifier);
        await flush();

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
        await flush();
        // storeB carries no appearance setting, so the new generation defaults.
        expect(
          container.read(appearanceProvider),
          const AppearancePreferences(),
        );

        writes.single.completeError(StateError('old dataset write failed'));
        await flush();
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
        await flush();
        expect(container.read(appearanceProvider).opaque, true);
        expect(container.read(appearanceBusyProvider), false);
      } finally {
        await root.delete(recursive: true);
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
      addTearDown(container.dispose);
      container.read(appearanceProvider.notifier);
      await flush();

      container.read(appearanceProvider.notifier).setReduceMotion(true);
      await flush();
      expect(
        container.read(appearanceProvider),
        const AppearancePreferences(),
        reason: 'the failed publication rolls back to the committed value',
      );
      expect(container.read(appearanceErrorProvider), true);
      expect(container.read(appearanceBusyProvider), false);

      fail = false;
      container.read(appearanceProvider.notifier).setReduceMotion(true);
      await flush();
      expect(container.read(appearanceProvider).reduceMotion, true);
      expect(calls, hasLength(2));
      expect(container.read(appearanceErrorProvider), false);
      expect(container.read(appearanceBusyProvider), false);
    },
  );

  test('a pending initial load never clobbers a user edit', () async {
    final root = await Directory.systemTemp.createTemp('vital-appearance-');
    try {
      final store = await openStore(root, 'a');
      addTearDown(store.close);
      await store.writeSetting(
        'appearance',
        jsonEncode({'mode': 'dark', 'opaque': false, 'reduceMotion': false}),
      );
      final container = ProviderContainer(
        overrides: [storeLoaderProvider.overrideWithValue((() async => store))],
      );
      addTearDown(container.dispose);
      // Keep every appearance surface active, mirroring app listeners.
      container.listen(appearanceProvider, (_, _) {}, fireImmediately: true);
      container.listen(appearanceErrorProvider, (_, _) {});
      container.listen(appearanceBusyProvider, (_, _) {});
      final notifier = container.read(appearanceProvider.notifier);
      notifier.setMode(ThemeMode.light);
      await flush();
      await waitFor(() async {
        final persisted = await store.readSetting('appearance');
        return parse(persisted ?? '{}').mode == ThemeMode.light;
      });
      expect(
        container.read(appearanceProvider).mode,
        ThemeMode.light,
        reason:
            'the persisted dark mode read must not clobber the user '
            'edit that landed while it was still in flight',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
