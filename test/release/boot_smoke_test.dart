import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

/// Release-readiness boot fixture.
///
/// Boots the real application shell against an isolated synthetic SQLite
/// dataset. It deliberately uses no real keyring, no real dataset and no
/// device, so it is safe to run on any Flutter host. Passing this fixture
/// proves host shell boot only; it does not prove native launch, physical
/// Android behaviour, accessibility or performance.
Future<T?> runIo<T>(WidgetTester tester, Future<T> Function() action) async {
  T? result;
  Object? failure;
  StackTrace? stack;
  var complete = false;
  await tester.runAsync(() async {
    unawaited(
      Future<T>.sync(action).then(
        (value) {
          result = value;
          complete = true;
        },
        onError: (Object error, StackTrace trace) {
          failure = error;
          stack = trace;
          complete = true;
        },
      ),
    );
  });
  final elapsed = Stopwatch()..start();
  while (!complete) {
    if (elapsed.elapsed > const Duration(seconds: 60)) {
      throw TimeoutException('Boot fixture IO did not complete');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
  return result;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 36; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('boots the real shell on isolated synthetic storage', (
    tester,
  ) async {
    final directory = (await runIo(
      tester,
      () => Directory.systemTemp.createTemp('vital-boot-'),
    ))!;
    final key = List<int>.generate(32, (index) => index + 1);
    final store = (await runIo(
      tester,
      () => RecordStore.open(
        path: '${directory.path}/boot.db',
        key: key,
        isNew: true,
      ),
    ))!;
    await runIo(tester, () async {
      final me = (await store.profileById(meId))!;
      await store.editProfile(
        commandId: 'boot-adult',
        personId: meId,
        expectedRevision: me.revision,
        name: 'Me',
        adultConfirmed: true,
      );
      await store.saveBrowsingScope(const FeedScope.me());
    });

    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() => Future.value(store)),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await store.close();
      await directory.delete(recursive: true);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    await settle(tester);

    expect(find.text('TRUE GRIT: VITAL'), findsOneWidget);
    expect(find.text('Empty'), findsNWidgets(3));
    expect(find.text('Today'), findsWidgets);

    await tester.tap(find.text('Substances').last);
    await settle(tester);
    expect(find.text('Substances'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
