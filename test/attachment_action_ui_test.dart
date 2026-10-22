import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/attachments/attachment_pages.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'attachment_ui_test.dart'
    show attachmentAppTest, fixture, seedFile, FixtureFileGateway, field;
import 'daily_plan_ui_test.dart' show tap;
import 'vital_app_test.dart' show runIo, settle;
import 'visual_framework_test.dart' show saveCapture;

const captures = String.fromEnvironment('VITAL_UI_SNAPSHOTS');

void main() {
  if (captures.isNotEmpty) {
    setUpAll(() async {
      await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
            rootBundle.load(
              'packages/shadcn_flutter/lib/icons/LucideIcons.ttf',
            ),
          ))
          .load();
      await (FontLoader('StitchSans')
            ..addFont(
              rootBundle.load('assets/fonts/StitchNotoSans-Regular.ttf'),
            )
            ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Medium.ttf'))
            ..addFont(
              rootBundle.load('assets/fonts/StitchNotoSans-SemiBold.ttf'),
            )
            ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Bold.ttf')))
          .load();
      await (FontLoader('NotoSans')
            ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
          .load();
    });
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final width in [320.0, 390.0, 430.0]) {
        attachmentAppTest('T02 capture ${mode.name} $width at double text', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final gateway = FixtureFileGateway(
            Uint8List.fromList([1, 2, 3]),
            shareEnabled: true,
          );
          final f = await fixture(tester, gateway: gateway);
          final boundary = GlobalKey();
          final scope = tester.widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          );
          await tester.pumpWidget(RepaintBoundary(key: boundary, child: scope));
          f.container.read(appearanceProvider.notifier).setMode(mode);
          await settle(tester);
          f.container.read(appearanceProvider.notifier).setReduceMotion(true);
          await settle(tester);
          final file = (await runIo(
            tester,
            () => seedFile(
              f.store,
              f.item,
              gateway.source,
              name: 'Synthetic original file with a complete readable name.bin',
            ),
          ))!;
          f.container.read(routerProvider).go('/attachment/${file.id}');
          await settle(tester);
          expect(tester.takeException(), isNull);
          await saveCapture(
            tester,
            boundary,
            '${mode.name}-${width.toInt()}-viewer-2x',
          );
          await tap(tester, 'Share');
          expect(find.byType(VitalDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await saveCapture(
            tester,
            boundary,
            '${mode.name}-${width.toInt()}-confirmation-2x',
          );
          await tap(tester, 'Cancel');
          expect(f.handoff.shares, 0);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  for (final command in ['Delete', 'Save', 'Share']) {
    attachmentAppTest(
      '$command confirmation expires across a lock/unlock cycle',
      (tester) async {
        final gateway = FixtureFileGateway(
          Uint8List.fromList([1, 2, 3]),
          shareEnabled: true,
        );
        final f = await fixture(tester, gateway: gateway);
        final file = (await runIo(
          tester,
          () => seedFile(f.store, f.item, gateway.source),
        ))!;
        await runIo(
          tester,
          () => f.container.read(appLockProvider.notifier).setEnabled(true),
        );
        final router = f.container.read(routerProvider);
        router.go('/attachment/${file.id}');
        await settle(tester);
        await tap(tester, command);
        expect(find.byType(VitalDialog), findsOneWidget);
        final lock = f.container.read(appLockProvider.notifier);
        lock.lifecycle(AppLifecycleState.inactive);
        await settle(tester);
        lock.lifecycle(AppLifecycleState.resumed);
        await runIo(tester, lock.unlock);
        await settle(tester);
        await tap(tester, command);
        await settle(tester);
        expect(
          await runIo(tester, () => f.store.attachmentById(file.id)),
          isNotNull,
        );
        expect(gateway.saved, isNull);
        expect(f.handoff.shares, 0);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/attachment/${file.id}',
        );
      },
    );
  }

  attachmentAppTest('double activation opens one destructive confirmation', (
    tester,
  ) async {
    final f = await fixture(tester);
    final file = (await runIo(
      tester,
      () => seedFile(f.store, f.item, Uint8List.fromList([1, 2, 3])),
    ))!;
    f.container.read(routerProvider).go('/attachment/${file.id}');
    await settle(tester);
    final activate = tester
        .widget<VitalButton>(find.widgetWithText(VitalButton, 'Delete'))
        .onPressed!;
    activate();
    activate();
    await settle(tester);
    expect(find.byType(VitalDialog), findsOneWidget);
    await tap(tester, 'Cancel');
    expect(find.byType(VitalDialog), findsNothing);
    expect(
      await runIo(tester, () => f.store.attachmentById(file.id)),
      isNotNull,
    );
  });

  attachmentAppTest(
    'a delayed delete completion cannot redirect a departed route',
    (tester) async {
      final entered = Completer<void>(), finish = Completer<void>();
      final f = await fixture(
        tester,
        deleteOverride: (request) async {
          await request.store.deleteAttachment(
            commandId: request.commandId,
            attachment: request.attachment,
            expectedPersonRevision: request.expectedPersonRevision,
          );
          entered.complete();
          await finish.future;
        },
      );
      final file = (await runIo(
        tester,
        () => seedFile(f.store, f.item, Uint8List.fromList([1, 2, 3])),
      ))!;
      final router = f.container.read(routerProvider);
      router.go('/attachment/${file.id}');
      await settle(tester);
      await tap(tester, 'Delete');
      await tap(tester, 'Delete');
      await runIo(tester, () => entered.future);
      router.go('/substances');
      await settle(tester);
      finish.complete();
      await settle(tester);
      expect(router.routeInformationProvider.value.uri.path, '/substances');
      expect(
        await runIo(tester, () => f.store.attachmentById(file.id)),
        isNull,
      );
    },
  );

  attachmentAppTest('double Open returns to its original list with one Back', (
    tester,
  ) async {
    final f = await fixture(tester);
    final file = (await runIo(
      tester,
      () => seedFile(f.store, f.item, Uint8List.fromList([1, 2, 3])),
    ))!;
    final router = f.container.read(routerProvider);
    final source = attachmentRoute(file);
    router.go(source);
    await settle(tester);
    final activate = tester
        .widget<VitalButton>(find.widgetWithText(VitalButton, 'Open'))
        .onPressed!;
    activate();
    activate();
    await settle(tester);
    expect(find.text('Original file'), findsOneWidget);
    router.pop();
    await settle(tester);
    expect(find.text('Original file'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, source);
  });

  attachmentAppTest(
    'a historical file remains readable after its dose is voided',
    (tester) async {
      final f = await fixture(tester);
      final actual = (await runIo(
        tester,
        () => f.store.record(
          commandId: newCommandId(),
          itemId: f.item.id,
          personId: meId,
          expectedPersonRevision: 2,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 22, 12),
        ),
      ))!;
      final file = (await runIo(
        tester,
        () => seedFile(
          f.store,
          f.item,
          Uint8List.fromList([1, 2, 3]),
          kind: AttachmentTargetKind.record,
          target: actual.id,
          revision: actual.revision,
        ),
      ))!;
      await runIo(
        tester,
        () => f.store.voidRecord(
          commandId: newCommandId(),
          recordId: actual.id,
          expectedRevision: actual.revision,
          expectedPersonRevision: 2,
        ),
      );
      f.container.read(routerProvider).go(attachmentRoute(file));
      await settle(tester);
      await tap(tester, 'Open');
      expect(find.text('Original file'), findsOneWidget);
      expect(
        await runIo(tester, () => f.store.attachmentById(file.id)),
        isNotNull,
      );
    },
  );

  attachmentAppTest(
    'a retained rename draft cannot save through another file route',
    (tester) async {
      final f = await fixture(tester);
      final first = (await runIo(
        tester,
        () => seedFile(f.store, f.item, Uint8List.fromList([1, 2, 3])),
      ))!;
      final second = (await runIo(
        tester,
        () => seedFile(
          f.store,
          f.item,
          Uint8List.fromList([4, 5, 6]),
          name: 'Second.bin',
        ),
      ))!;
      final router = f.container.read(routerProvider);
      router.go('/attachment/${first.id}/rename');
      await settle(tester);
      await tester.enterText(field('File name'), 'Retain this first draft');
      final staleSave = tester
          .widget<VitalButton>(find.widgetWithText(VitalButton, 'Save'))
          .onPressed!;
      router.go('/attachment/${second.id}/rename');
      await settle(tester);
      staleSave();
      await settle(tester);
      expect(
        await runIo(
          tester,
          () async => (await f.store.attachmentById(first.id))!.name,
        ),
        first.name,
      );
      expect(
        await runIo(
          tester,
          () async => (await f.store.attachmentById(second.id))!.name,
        ),
        second.name,
      );
      router.go('/attachment/${first.id}/rename');
      await settle(tester);
      expect(
        tester.widget<TextField>(field('File name')).controller!.text,
        'Retain this first draft',
      );
    },
  );

  attachmentAppTest(
    'an uncertain delete cannot move to another viewer identity',
    (tester) async {
      final attempts = <AttachmentDeleteRequest>[];
      final f = await fixture(
        tester,
        deleteOverride: (request) async {
          attempts.add(request);
          if (attempts.length == 1) throw StateError('injected-lost-reply');
          await request.store.deleteAttachment(
            commandId: request.commandId,
            attachment: request.attachment,
            expectedPersonRevision: request.expectedPersonRevision,
          );
        },
      );
      final first = (await runIo(
        tester,
        () => seedFile(f.store, f.item, Uint8List.fromList([1, 2, 3])),
      ))!;
      final second = (await runIo(
        tester,
        () => seedFile(
          f.store,
          f.item,
          Uint8List.fromList([4, 5, 6]),
          name: 'Second.bin',
        ),
      ))!;
      final router = f.container.read(routerProvider);
      router.go('/attachment/${first.id}');
      await settle(tester);
      await tap(tester, 'Delete');
      await tap(tester, 'Delete');
      expect(attempts, hasLength(1));
      router.go('/attachment/${second.id}');
      await settle(tester);
      await tap(tester, 'Delete');
      await tap(tester, 'Delete');
      expect(
        await runIo(tester, () => f.store.attachmentById(first.id)),
        isNotNull,
      );
      expect(
        await runIo(tester, () => f.store.attachmentById(second.id)),
        isNull,
      );
      expect(attempts, hasLength(2));
      expect(attempts.last.commandId, isNot(attempts.first.commandId));
      expect(attempts.last.attachment.id, second.id);
    },
  );

  for (final interruption in ['lock cycle', 'route departure and return']) {
    attachmentAppTest(
      'delete rolls back after $interruption inside its transaction',
      (tester) async {
        final entered = Completer<void>(), finish = Completer<void>();
        final f = await fixture(
          tester,
          deleteOverride: (request) => request.store.deleteAttachment(
            commandId: request.commandId,
            attachment: request.attachment,
            expectedPersonRevision: request.expectedPersonRevision,
            beforeCommit: () async {
              entered.complete();
              await finish.future;
              if (!request.canCommit()) {
                throw const CommandConflict('app_locked');
              }
            },
          ),
        );
        final file = (await runIo(
          tester,
          () => seedFile(f.store, f.item, Uint8List.fromList([1, 2, 3])),
        ))!;
        await runIo(
          tester,
          () => f.container.read(appLockProvider.notifier).setEnabled(true),
        );
        final router = f.container.read(routerProvider);
        router.go('/attachment/${file.id}');
        await settle(tester);
        await tap(tester, 'Delete');
        await tap(tester, 'Delete');
        await runIo(tester, () => entered.future);
        if (interruption == 'lock cycle') {
          final lock = f.container.read(appLockProvider.notifier);
          lock.lifecycle(AppLifecycleState.inactive);
          lock.lifecycle(AppLifecycleState.resumed);
          await runIo(tester, lock.unlock);
        } else {
          unawaited(router.push('/settings'));
          await tester.pump();
          router.pop();
          await tester.pump();
        }
        finish.complete();
        await settle(tester);
        final unchanged = (await runIo(
          tester,
          () => f.store.attachmentById(file.id),
        ))!;
        expect(unchanged.revision, file.revision);
        expect(unchanged.name, file.name);
        expect(
          find.text('Unlock Vital to continue this file action.'),
          findsNothing,
        );
        expect(
          router.routeInformationProvider.value.uri.path,
          '/attachment/${file.id}',
        );
      },
    );
  }
}
