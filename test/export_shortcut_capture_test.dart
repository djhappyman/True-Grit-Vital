import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/exports/export_pages.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'vital_app_test.dart' show appTest, runIo, settle, waitForText;

const _captureDirectory = String.fromEnvironment('VITAL_EXPORT_CAPTURE');

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  if (_captureDirectory.isEmpty) return;
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

DateTime _fixedNow() => DateTime.utc(2026, 10, 22, 12);

Future<ProviderContainer> _launch(WidgetTester tester) async {
  final directory = await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-export-capture-'),
  );
  final key = List.generate(32, (i) => i + 1);
  final store = (await runIo(
    tester,
    () => RecordStore.open(
      path: '${directory!.path}/test.db',
      key: key,
      isNew: true,
    ),
  ))!;
  await runIo(tester, () async {
    await store.editProfile(
      commandId: 'fixture-adult',
      personId: meId,
      expectedRevision: 1,
      name: 'Alex',
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
      exportNowProvider.overrideWithValue(_fixedNow),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
    await directory!.delete(recursive: true);
  });
  return container;
}

void main() {
  setUpAll(() async {
    await (FontLoader('StitchSans')
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Bold.ttf')))
        .load();
    await (FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
        .load();
    await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
          rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
        ))
        .load();
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('Export shortcut selection renders in ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final container = await _launch(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const VitalApp(),
        ),
      );
      await settle(tester);
      container.read(appearanceProvider.notifier).setMode(theme);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      container.read(routerProvider).push('/exports');
      await settle(tester);
      await waitForText(tester, 'Export');
      await waitForText(tester, 'Date shortcuts');
      expect(tester.takeException(), isNull);
      await _capture(tester, boundaryKey, '${theme.name}-export');

      if (_captureDirectory.isNotEmpty) {
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find
                    .byWidgetPredicate(
                      (w) =>
                          w is SingleChildScrollView &&
                          w.scrollDirection == Axis.vertical,
                    )
                    .first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final viewport = scrollable.position.viewportDimension;
        final content = viewport + scrollable.position.maxScrollExtent;
        tester.view.physicalSize = Size(
          390,
          (844 + math.max(0, content - viewport)).ceilToDouble(),
        );
        await settle(tester);
        await _capture(tester, boundaryKey, '${theme.name}-export-full');
      }

      if (theme == ThemeMode.dark) {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.view.physicalSize = const Size(320, 740);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await settle(tester);
        await tester.ensureVisible(find.text('Date shortcuts'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await _capture(tester, boundaryKey, 'dark-export-narrow-double-text');
      }
    });
  }
}
