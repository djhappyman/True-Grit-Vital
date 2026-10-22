import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';

import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart' show appTest, launch, settle;

void main() {
  setUpAll(loadFonts);
  appTest('delete decision remains safe and readable in both themes', (
    tester,
  ) async {
    const output = String.fromEnvironment('VITAL_T13_CAPTURES');
    final f = await launch(tester);
    final key = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: RepaintBoundary(key: key, child: const VitalApp()),
      ),
    );
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    f.container.read(routerProvider).go('/settings/privacy');
    await settle(tester);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      f.container.read(appearanceProvider.notifier).setMode(mode);
      for (final narrow in [false, true]) {
        tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = narrow ? 2 : 1;
        await settle(tester);
        final target = find.byKey(const ValueKey('privacy-delete-me'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await settle(tester);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'privacy-delete-cancel',
        );
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        expect(find.text('Delete').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$output/${mode.name}-${narrow ? '320-2x' : '390'}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(
          find.text('Records deleted. Your profile is still available.'),
          findsNothing,
        );
      }
    }
  });
}
