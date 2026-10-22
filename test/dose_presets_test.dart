import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/dose_presets.dart';

class PresetTestLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void setLocked(bool value) =>
      state = AppLockState(ready: true, locked: value);
}

PlannedAmount planned(String amount, [String unit = 'mg']) => PlannedAmount(
  quantity: ExactQuantity.parse(amount),
  unit: unit,
  enteredText: amount,
);

Future<void> until(bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      fail('Preset state did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test(
    'presets retain exact quantities and deduplicate all schedule modes',
    () {
      final a = planned('0.100000'), b = planned('0.2');
      final slot = DailySlot(
        id: 's',
        time: WallTime(8, 0),
        amount: a,
        reminderEnabled: false,
      );
      expect(DosePreset('000.100000', 'mg').text, '0.1');
      expect(DosePreset('0,000001', 'ml').text, '0.000001');
      expect(() => DosePreset('0', 'mg'), throwsRangeError);
      expect(() => DosePreset('0.0000001', 'mg'), throwsFormatException);
      expect(scheduleDosePresets(const AsNeeded()), isEmpty);
      expect(scheduleDosePresets(DailyCount(2, a)).single.text, '0.1');
      expect(scheduleDosePresets(DailySlots([slot])).single.text, '0.1');
      expect(
        scheduleDosePresets(
          MixedDailyCount(count: 2, amount: a, slots: [slot]),
        ),
        hasLength(1),
      );
      final windows = scheduleDosePresets(
        DailyWindows(
          windows: [
            DailyWindow(
              id: 'a',
              start: WallTime(8, 0),
              end: WallTime(9, 0),
              amount: a,
            ),
            DailyWindow(
              id: 'b',
              start: WallTime(10, 0),
              end: WallTime(11, 0),
              amount: b,
            ),
          ],
        ),
      );
      expect(windows.map((p) => p.text), ['0.1', '0.2']);
      expect(
        scheduleDosePresets(
          ElapsedInterval(
            segmentId: 'i',
            duration: ExactElapsed.parseHours('24'),
            mode: IntervalMode.fixedPlanned,
            amount: a,
            plannedAnchor: DateTime.utc(2026, 10, 19),
          ),
        ).single.text,
        '0.1',
      );
    },
  );

  group('encrypted preset preferences', () {
    late Directory directory;
    late RecordStore store;
    late ProviderContainer container;
    late ProviderSubscription<DosePresetState> subscription;
    final owner = (personId: meId, itemId: 'item');
    final key = List.generate(32, (i) => i + 1);
    Future<void> Function(DosePresetWrite)? writer;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('vital-presets-');
      store = await RecordStore.open(
        path: '${directory.path}/db',
        key: key,
        isNew: true,
      );
      writer = null;
      container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(PresetTestLock.new),
          dosePresetWriterProvider.overrideWithValue(
            (write) =>
                writer?.call(write) ??
                write.store.writeSetting(
                  write.key,
                  write.value,
                  canCommit: write.canCommit,
                ),
          ),
        ],
      );
      subscription = container.listen(dosePresetsProvider(owner), (_, _) {});
      await until(() => !container.read(dosePresetsProvider(owner)).loading);
    });
    tearDown(() async {
      subscription.close();
      container.dispose();
      await store.close();
      await directory.delete(recursive: true);
    });
    test(
      'save, deduplication, reload and removal preserve exact input',
      () async {
        final controller = container.read(dosePresetsProvider(owner).notifier);
        await controller.add(DosePreset('0.125000', 'mg'));
        await controller.add(DosePreset('0.125', 'mg'));
        expect(container.read(dosePresetsProvider(owner)).values, hasLength(1));
        container.invalidate(dosePresetsProvider(owner));
        await until(() => !container.read(dosePresetsProvider(owner)).loading);
        final value = container.read(dosePresetsProvider(owner)).values.single;
        expect((value.text, value.unit), ('0.125', 'mg'));
        await container.read(dosePresetsProvider(owner).notifier).remove(value);
        expect(await store.readSetting(controller.storageKey), '[]');
        expect(await store.records(), isEmpty);
      },
    );
    test('encrypted backup snapshots retain user-saved amounts', () async {
      final controller = container.read(dosePresetsProvider(owner).notifier);
      await controller.add(DosePreset('0.000001', 'ml'));
      final snapshot = await store.createBackupSnapshot(
        directory: directory,
        sessionId: 'presets',
      );
      await store.releaseBackupPins('presets');
      final restored = await RecordStore.open(
        path: snapshot.path,
        key: key,
        isNew: false,
      );
      try {
        expect(
          await restored.readSetting(controller.storageKey),
          await store.readSetting(controller.storageKey),
        );
      } finally {
        await restored.close();
      }
    });
    test(
      'a failed write retains previous values without claiming success',
      () async {
        final controller = container.read(dosePresetsProvider(owner).notifier);
        await controller.add(DosePreset('1', 'ml'));
        writer = (_) => Future.error(StateError('test failure'));
        await controller.add(DosePreset('2', 'ml'));
        final state = container.read(dosePresetsProvider(owner));
        expect(state.failed, isTrue);
        expect(state.values.single.text, '1');
        expect(await store.readSetting(controller.storageKey), contains('"1"'));
      },
    );
    test(
      'locking during a pending write prevents publication even after unlock',
      () async {
        final gate = Completer<void>(), started = Completer<void>();
        writer = (write) async {
          started.complete();
          await gate.future;
          await write.store.writeSetting(
            write.key,
            write.value,
            canCommit: write.canCommit,
          );
        };
        final controller = container.read(dosePresetsProvider(owner).notifier);
        final save = controller.add(DosePreset('2', 'mg'));
        await started.future;
        final lock = container.read(appLockProvider.notifier) as PresetTestLock;
        lock.setLocked(true);
        await pumpEventQueue();
        lock.setLocked(false);
        await pumpEventQueue();
        gate.complete();
        await save;
        await until(() => !container.read(dosePresetsProvider(owner)).loading);
        expect(await store.readSetting(controller.storageKey), isNull);
        expect(container.read(dosePresetsProvider(owner)).values, isEmpty);
      },
    );
    test(
      'a dataset reload retires an in-flight write and loads fresh settings',
      () async {
        final gate = Completer<void>(), started = Completer<void>();
        writer = (write) async {
          started.complete();
          await gate.future;
          await write.store.writeSetting(
            write.key,
            write.value,
            canCommit: write.canCommit,
          );
        };
        final controller = container.read(dosePresetsProvider(owner).notifier);
        final save = controller.add(DosePreset('3', 'mg'));
        await started.future;
        store = await RecordStore.open(
          path: '${directory.path}/replacement',
          key: key,
          isNew: true,
        );
        await store.writeSetting(
          controller.storageKey,
          '[{"amount":"4","unit":"mg"}]',
        );
        container.invalidate(recordStoreProvider);
        await pumpEventQueue();
        gate.complete();
        await save;
        await until(() => !container.read(dosePresetsProvider(owner)).loading);
        expect(
          container.read(dosePresetsProvider(owner)).values.single.text,
          '4',
        );
        expect(await store.readSetting(controller.storageKey), contains('"4"'));
      },
    );
    test('the preset bound and corrupt stored data fail truthfully', () async {
      final controller = container.read(dosePresetsProvider(owner).notifier);
      for (var i = 1; i <= 9; i++) {
        await controller.add(DosePreset('$i', 'mg'));
      }
      expect(container.read(dosePresetsProvider(owner)).values, hasLength(8));
      await store.writeSetting(
        controller.storageKey,
        '[{"amount":"0","unit":"mg"}]',
      );
      container.invalidate(dosePresetsProvider(owner));
      await until(() => !container.read(dosePresetsProvider(owner)).loading);
      final state = container.read(dosePresetsProvider(owner));
      expect(state.failed && state.readFailed, isTrue);
      expect(state.values, isEmpty);
    });
    test(
      'replacement keeps order, exact values and survives restart',
      () async {
        final controller = container.read(dosePresetsProvider(owner).notifier);
        await controller.add(DosePreset('1', 'mg'));
        await controller.add(DosePreset('2', 'ml'));
        await controller.add(DosePreset('3', 'count'));
        final saved = await controller.replace(
          DosePreset('2', 'ml'),
          DosePreset('0,000001', 'ml'),
          allowedUnits: {'mg', 'ml', 'count'},
        );
        expect(saved, isTrue);
        String values() => container
            .read(dosePresetsProvider(owner))
            .values
            .map((value) => '${value.text} ${value.unit}')
            .join(',');
        expect(values(), '1 mg,0.000001 ml,3 count');
        container.invalidate(dosePresetsProvider(owner));
        await until(() => !container.read(dosePresetsProvider(owner)).loading);
        expect(values(), '1 mg,0.000001 ml,3 count');
        expect(await store.records(), isEmpty);
      },
    );
    test(
      'replacement rejects duplicate identity and unsupported units',
      () async {
        final controller = container.read(dosePresetsProvider(owner).notifier);
        await controller.add(DosePreset('1', 'mg'));
        final before = await store.readSetting(controller.storageKey);
        expect(
          await controller.replace(
            DosePreset('1', 'mg'),
            DosePreset('2', 'ml'),
            allowedUnits: {'mg'},
          ),
          isFalse,
        );
        expect(
          await controller.replace(
            DosePreset('1', 'mg'),
            DosePreset('1', 'oz'),
            allowedUnits: {'mg', 'ml'},
          ),
          isFalse,
        );
        expect(
          container.read(dosePresetsProvider(owner)).values.single.identity,
          DosePreset('1', 'mg').identity,
        );
        expect(await store.readSetting(controller.storageKey), before);
      },
    );
    test('a failed replacement keeps the old preset and retries', () async {
      final controller = container.read(dosePresetsProvider(owner).notifier);
      await controller.add(DosePreset('1', 'mg'));
      writer = (_) => Future.error(StateError('test failure'));
      expect(
        await controller.replace(
          DosePreset('1', 'mg'),
          DosePreset('2', 'mg'),
          allowedUnits: {'mg'},
        ),
        isFalse,
      );
      var state = container.read(dosePresetsProvider(owner));
      expect(state.failed, isTrue);
      expect(state.values.single.text, '1');
      expect(await store.readSetting(controller.storageKey), contains('"1"'));
      writer = null;
      expect(
        await controller.replace(
          DosePreset('1', 'mg'),
          DosePreset('2', 'mg'),
          allowedUnits: {'mg'},
        ),
        isTrue,
      );
      state = container.read(dosePresetsProvider(owner));
      expect(state.failed, isFalse);
      expect(state.values.single.text, '2');
      expect(await store.readSetting(controller.storageKey), contains('"2"'));
    });
    test('locking during a pending replacement publishes nothing', () async {
      final controller = container.read(dosePresetsProvider(owner).notifier);
      await controller.add(DosePreset('1', 'mg'));
      final gate = Completer<void>(), started = Completer<void>();
      writer = (write) async {
        started.complete();
        await gate.future;
        await write.store.writeSetting(
          write.key,
          write.value,
          canCommit: write.canCommit,
        );
      };
      final save = controller.replace(
        DosePreset('1', 'mg'),
        DosePreset('2', 'mg'),
        allowedUnits: {'mg'},
      );
      await started.future;
      final lock = container.read(appLockProvider.notifier) as PresetTestLock;
      lock.setLocked(true);
      await pumpEventQueue();
      lock.setLocked(false);
      await pumpEventQueue();
      gate.complete();
      expect(await save, isFalse);
      await until(() => !container.read(dosePresetsProvider(owner)).loading);
      expect(await store.readSetting(controller.storageKey), contains('"1"'));
      expect(
        container.read(dosePresetsProvider(owner)).values.single.text,
        '1',
      );
    });
    test('an expired edit context rejects a queued replacement', () async {
      final controller = container.read(dosePresetsProvider(owner).notifier);
      await controller.add(DosePreset('1', 'mg'));
      var current = true;
      final gate = Completer<void>(), started = Completer<void>();
      writer = (write) async {
        started.complete();
        await gate.future;
        await write.store.writeSetting(
          write.key,
          write.value,
          canCommit: write.canCommit,
        );
      };
      final save = controller.replace(
        DosePreset('1', 'mg'),
        DosePreset('2', 'mg'),
        allowedUnits: {'mg'},
        canCommit: () => current,
      );
      await started.future;
      current = false;
      gate.complete();
      expect(await save, isFalse);
      expect(await store.readSetting(controller.storageKey), contains('"1"'));
      expect(
        container.read(dosePresetsProvider(owner)).values.single.text,
        '1',
      );
    });

    test('a dataset change retires a pending replacement', () async {
      final controller = container.read(dosePresetsProvider(owner).notifier);
      await controller.add(DosePreset('1', 'mg'));
      final gate = Completer<void>(), started = Completer<void>();
      writer = (write) async {
        started.complete();
        await gate.future;
        await write.store.writeSetting(
          write.key,
          write.value,
          canCommit: write.canCommit,
        );
      };
      final save = controller.replace(
        DosePreset('1', 'mg'),
        DosePreset('2', 'mg'),
        allowedUnits: {'mg'},
      );
      await started.future;
      final old = store;
      store = await RecordStore.open(
        path: '${directory.path}/replacement-edit',
        key: key,
        isNew: true,
      );
      container.invalidate(recordStoreProvider);
      await pumpEventQueue();
      gate.complete();
      expect(await save, isFalse);
      await until(() => !container.read(dosePresetsProvider(owner)).loading);
      await old.close();
      final preserved = await RecordStore.open(
        path: old.databasePath,
        key: key,
        isNew: false,
      );
      try {
        expect(
          await preserved.readSetting(controller.storageKey),
          contains('"1"'),
        );
      } finally {
        await preserved.close();
      }
      expect(
        container.read(dosePresetsProvider(owner)).values,
        isEmpty,
        reason: 'The replacement dataset has no saved preset yet',
      );
    });
  });
}
