import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

import '../vital_app_test.dart' show appTest, launch, settle, tap, waitForText;

void main() {
  appTest('keyring failure retries without showing an empty dataset', (
    tester,
  ) async {
    final pending = Completer<RecordStore>();
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
        storeLoaderProvider.overrideWithValue(() {
          attempts++;
          if (attempts == 1) return pending.future;
          throw const StorageBootstrapException('storage_recovery_required');
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    await tester.pump();
    // The privacy gate covers startup before the encrypted preference is read.
    expect(find.text('Opening protected records.'), findsOneWidget);
    expect(find.text('Nothing recorded'), findsNothing);
    pending.completeError(
      const StorageBootstrapException('linux_keyring_unavailable'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keyring unavailable'), findsOneWidget);
    expect(find.textContaining('Unlock the desktop keyring'), findsOneWidget);
    expect(find.text('Nothing recorded'), findsNothing);
    await tap(tester, 'Retry');
    expect(attempts, 2);
    expect(find.text('Keyring unavailable'), findsNothing);
    expect(find.text('Nothing recorded'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('desktop resize preserves draft and keyboard field traversal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await launch(tester);
    tester.view.physicalSize = const Size(1000, 360);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 800);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpAndSettle();
    await tap(tester, 'Substances');
    await tap(tester, 'Create');
    final name = find.descendant(
      of: find.widgetWithText(LabelledInput, 'Full name'),
      matching: find.byType(TextField),
    );
    await tester.enterText(name, 'Synthetic desktop full substance name');
    final initialFocus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(same(initialFocus)));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(initialFocus));
    for (final width in [640.0, 1000.0, 480.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(name).controller!.text,
        'Synthetic desktop full substance name',
      );
      expect(tester.takeException(), isNull);
    }
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(LabelledInput, 'Type'),
        matching: find.byType(TextField),
      ),
      'Supplement',
    );
    await tap(tester, 'Oral');
    await tap(tester, 'Tablet');
    await tap(tester, 'Create');
    await waitForText(tester, 'Setup');
    await waitForText(tester, 'Synthetic desktop full substance name');
    expect(tester.takeException(), isNull);
    await settle(tester);
  });
}
