import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/attachments.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import '../vital_app_test.dart' show runIo, settle, tap, waitForText;
import 'attachment_controller_test.dart' show InventoryGateway;

import 'package:true_grit_vital/data/record_store.dart';

class RuntimeLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

void main() {
  testWidgets(
    'unmounting the attachment runtime cancels periodic maintenance before container disposal',
    (tester) async {
      final store = Completer<RecordStore>();
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() => store.future),
          appLockProvider.overrideWith(RuntimeLock.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AttachmentRuntime(child: SizedBox.shrink()),
        ),
      );
      await tester.pump();
      expect(container.exists(attachmentsControllerProvider), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump();
      expect(container.read(attachmentsControllerProvider).busy, isFalse);
      // The widget harness also verifies that no periodic fake-clock timer leaks.
    },
  );
  testWidgets(
    'current file page imports a captured job and shuts its real store down through the IO bridge',
    (tester) async {
      final directory = (await runIo(
        tester,
        () => Directory.systemTemp.createTemp('vital-attachment-runtime-ui-'),
      ))!;
      final store = (await runIo(
        tester,
        () => RecordStore.open(
          path: '${directory.path}/files.db',
          key: List.generate(32, (i) => i + 1),
          isNew: true,
        ),
      ))!;
      final item = (await runIo(tester, () async {
        await store.editProfile(
          commandId: 'adult',
          personId: meId,
          expectedRevision: 1,
          name: 'Main adult',
          adultConfirmed: true,
        );
        return store.createItem(
          commandId: 'item',
          personId: meId,
          expectedPersonRevision: 2,
          name: 'Captured medicine',
          form: 'tablet',
          unit: 'mg',
          type: 'Medicine',
        );
      }))!;
      final files = InventoryGateway();
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(RuntimeLock.new),
          attachmentGatewayProvider.overrideWithValue(files),
          observedDeviceZoneProvider.overrideWith(
            (ref) =>
                Stream.value(DeviceZoneObservation.fromId('Europe/London')),
          ),
        ],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const VitalApp(),
          ),
        );
        await settle(tester);
        container.read(routerProvider).go('/files/$meId/item/${item.id}');
        await settle(tester);
        await tap(tester, 'Choose');
        await waitForText(tester, 'File added to this record.');
        final saved = (await runIo(
          tester,
          () => store.attachments(personId: meId),
        ))!.single;
        expect(saved.targetId, item.id);
        expect(files.finished, contains(files.picked.single));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        container.dispose();
        await runIo(tester, store.close);
        await runIo(tester, () => directory.delete(recursive: true));
      }
    },
  );
}
