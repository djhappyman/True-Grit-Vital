import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'screen_record_dose_test.dart' show createItem, enterAmount;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

void main() {
  appTest('root pages retain search and synchronise dock routes', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(tester, () => createItem(f.store));
    final router = f.container.read(routerProvider);
    router.go('/substances');
    await settle(tester);
    final search = find.byType(TextField).hitTestable().first;
    await tester.enterText(search, 'needle');
    await settle(tester);
    final navigation = find.byType(ShellNavigation);
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Today')),
    );
    await settle(tester);
    expect(router.routeInformationProvider.value.uri.path, '/today');
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Substances')),
    );
    await settle(tester);
    expect(
      tester
          .widget<TextField>(find.byType(TextField).hitTestable().first)
          .controller!
          .text,
      'needle',
    );
    expect(find.byType(PageView), findsWidgets);
  });

  appTest('rapid dock changes finish at the last requested destination', (
    tester,
  ) async {
    final f = await launch(tester);
    final router = f.container.read(routerProvider);
    final navigation = find.byType(ShellNavigation);
    for (final destination in ['History', 'Substances', 'Events', 'Today']) {
      await tester.tap(
        find.descendant(of: navigation, matching: find.text(destination)),
      );
      await tester.pump(const Duration(milliseconds: 45));
    }
    await settle(tester);
    expect(router.routeInformationProvider.value.uri.path, '/today');
    final root = find.byType(PageView).first;
    expect(tester.widget<PageView>(root).controller!.page, 0);
    expect(tester.takeException(), isNull);
  });

  appTest(
    'calendar swipe changes month without changing the root destination',
    (tester) async {
      final f = await launch(tester);
      final router = f.container.read(routerProvider);
      router.go('/history');
      await settle(tester);
      final pager = find.descendant(
        of: find.byType(HistoryCalendarSection),
        matching: find.byType(PageView),
      );
      final page = tester.widget<PageView>(pager);
      final before = page.controller!.page!;
      await tester.drag(pager, const Offset(-700, 0));
      await settle(tester);
      expect(page.controller!.page, before + 1);
      expect(router.routeInformationProvider.value.uri.path, '/history');
      final options = find.byType(VitalLocalOptions);
      await tester.ensureVisible(options);
      await tester.tap(options);
      await settle(tester);
      final done = find.widgetWithText(Button, 'Done');
      await tester.ensureVisible(done);
      await settle(tester);
      expect(tester.getSize(done).height, greaterThanOrEqualTo(48));
      await tester.tap(done.hitTestable());
      await settle(tester);
    },
  );

  appTest('modal dose retains dirty work on scrim and Escape cancellation', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => createItem(f.store)))!;
    final router = f.container.read(routerProvider);
    router.push('/record/${item.id}');
    await settle(tester);
    expect(find.byType(VitalTaskFrame), findsOneWidget);
    await enterAmount(tester, '0.25');
    expect(find.text('Save').hitTestable(), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await tap(tester, 'Keep');
    expect(find.byType(DoseForm), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    await tap(tester, 'Keep');
    final handle = find
        .descendant(
          of: find.byType(VitalTaskFrame),
          matching: find.byType(GestureDetector),
        )
        .first;
    await tester.drag(handle, const Offset(0, 110));
    await settle(tester);
    await tap(tester, 'Keep');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await tap(tester, 'Discard');
    await settle(tester);
    expect(find.byType(DoseForm), findsNothing);
    expect((await runIo(tester, f.store.records))!, isEmpty);
  });

  appTest('pending save blocks sheet dismissal and dispatches only once', (
    tester,
  ) async {
    final gate = Completer<void>();
    var calls = 0;
    final f = await launch(
      tester,
      recordWriter: (store, input) async {
        calls++;
        await gate.future;
        return store.record(
          commandId: input.commandId,
          itemId: input.itemId,
          amount: input.amount,
          actualAt: input.actualAt,
          personId: input.personId,
          expectedPersonRevision: input.expectedPersonRevision,
        );
      },
    );
    final item = (await runIo(tester, () => createItem(f.store)))!;
    f.container.read(routerProvider).push('/record/${item.id}');
    await settle(tester);
    await enterAmount(tester, '0.25');
    await tap(tester, 'Save');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.byType(DoseForm), findsOneWidget);
    expect(calls, 1);
    gate.complete();
    await waitForText(tester, 'Saved for Me: Synthetic dose, 0.25 ml.');
    expect((await runIo(tester, f.store.records))!.length, 1);
  });

  appTest('reduced motion changes pages directly and keeps fixed hit targets', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(appearanceProvider.notifier).setReduceMotion(true);
    await settle(tester);
    f.container.read(routerProvider).go('/substances');
    await settle(tester);
    final target = find.widgetWithText(Button, 'Create').hitTestable();
    expect(target, findsWidgets);
    final button = target.first;
    final rect = tester.getRect(button);
    final gesture = await tester.startGesture(rect.center);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getRect(button), rect);
    await gesture.cancel();
    await tester.pumpAndSettle();
  });
  appTest('dose action remains above the keyboard at narrow double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester);
    final item = (await runIo(tester, () => createItem(f.store)))!;
    f.container.read(routerProvider).push('/record/${item.id}');
    await settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await settle(tester);
    final save = find.text('Save').hitTestable();
    expect(save, findsOneWidget);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(440));
    expect(tester.takeException(), isNull);
  });
}
