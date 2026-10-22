import 'package:true_grit_vital/features/settings/settings_pages.dart';
import 'package:true_grit_vital/features/settings/settings_widgets.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';

import 'dart:async';

import 'package:true_grit_vital/features/recording/combined_pages.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';
import 'package:true_grit_vital/features/history/history_source.dart';

import 'package:true_grit_vital/features/catalogue/catalogue_picker.dart';
import 'package:true_grit_vital/data/catalogue/catalogue_manager.dart';

import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/privacy.dart';
import 'package:true_grit_vital/domain/privacy/settings_capabilities.dart';
import 'package:true_grit_vital/platform/app_auth.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/features/plans/today_hero.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

/// Keep the widget fake clock moving while real SQLite transactions complete.
/// A repository watcher may hold a snapshot transaction started in the fake
/// zone; awaiting its competing write inside one runAsync would deadlock.
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
      throw TimeoutException('Widget fixture IO did not complete');
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
  // Drift isolate replies cross real IO and the widget fake clock. Bounded
  // Everyone reads need several alternating turns before their stream settles.
  for (var i = 0; i < 36; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

Future<
  ({RecordStore store, ProviderContainer container, String path, List<int> key})
>
launch(
  WidgetTester tester, {
  Future<void> Function(String)? appearanceWriter,
  List<DateTime> Function(DateTime)? timeResolver,
  Future<UseRecord> Function(RecordStore, RecordInput)? recordWriter,
  Future<UseRecord> Function(RecordStore, VoidInput)? voidWriter,
  Future<CombinedUseResult> Function(RecordStore, CombinedUseCommand)?
  combinedWriter,
  bool completeSetup = true,
  Future<CatalogueReader?> Function()? catalogueLoader,
  AppAuthGateway? auth,
  SettingsCapabilities? settingsCapabilities,
  ProfilePrivacyActions? privacyActions,
  Future<String> Function(String asset)? licenceLoader,
  DateTime Function()? todayClock,
  DeviceZoneObservation? zoneObservation,
}) async {
  final directory = await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-widget-'),
  );
  final key = List.generate(32, (i) => i + 1);
  final path = '${directory!.path}/test.db';
  final store = (await runIo(
    tester,
    () => RecordStore.open(path: path, key: key, isNew: true),
  ))!;
  if (completeSetup) {
    await runIo(tester, () async {
      final me = (await store.profileById(meId))!;
      await store.editProfile(
        commandId: 'fixture-adult',
        personId: meId,
        expectedRevision: me.revision,
        name: 'Me',
        adultConfirmed: true,
      );
      await store.saveBrowsingScope(const FeedScope.me());
    });
  }
  final container = ProviderContainer(
    overrides: [
      if (todayClock != null) todayNowProvider.overrideWithValue(todayClock),
      if (combinedWriter != null)
        combinedWriterProvider.overrideWithValue(
          (command) => combinedWriter(store, command),
        ),
      if (auth != null) appAuthGatewayProvider.overrideWithValue(auth),
      if (settingsCapabilities != null)
        settingsCapabilitiesProvider.overrideWithValue(settingsCapabilities),
      if (privacyActions != null)
        profilePrivacyActionsProvider.overrideWithValue(privacyActions),
      if (licenceLoader != null)
        licenceTextLoaderProvider.overrideWithValue(licenceLoader),
      if (catalogueLoader != null)
        catalogueLoaderProvider.overrideWithValue(catalogueLoader),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(
          zoneObservation ?? DeviceZoneObservation.fromId('Europe/London'),
        ),
      ),
      storeLoaderProvider.overrideWithValue(() => Future.value(store)),
      artifactTransferGatewayProvider.overrideWithValue(
        const UnsupportedArtifactTransfer(),
      ),
      if (appearanceWriter != null)
        appearanceWriterProvider.overrideWithValue(appearanceWriter),
      if (timeResolver != null)
        actualTimeResolverProvider.overrideWithValue(timeResolver),
      if (voidWriter != null)
        voidWriterProvider.overrideWithValue(
          (input) => voidWriter(store, input),
        ),
      if (recordWriter != null)
        recordWriterProvider.overrideWithValue(
          (input) => recordWriter(store, input),
        ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    // Closing watched reads also needs the widget clock to keep moving.
    await runIo(tester, store.close);
    await directory.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  return (store: store, container: container, path: path, key: key);
}

/// Wait for a rendered result rather than assuming a fixed number of IO turns.
Future<void> waitForText(WidgetTester tester, String text) async {
  final elapsed = Stopwatch()..start();
  while (find.text(text).evaluate().isEmpty) {
    if (elapsed.elapsed > const Duration(seconds: 30)) {
      throw TestFailure('Expected rendered text did not appear: $text');
    }
    await runIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester tester, String text) async {
  if (find.byType(SettingsPage).evaluate().isNotEmpty &&
      find.widgetWithText(SettingsNavigationRow, text).evaluate().isEmpty) {
    final group = switch (text) {
      'Privacy' || 'Diagnostics' => 'Privacy',
      'Reports' || 'Exports' || 'Backup' || 'Restore' => 'Data',
      _ => null,
    };
    if (group != null) {
      await tester.tap(
        find
            .descendant(
              of: find.byType(SettingsPage),
              matching: find.text(group),
            )
            .first,
      );
      await settle(tester);
    }
  }

  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  final iconLabel = find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == text,
  );
  if (find.text(text).evaluate().isEmpty && iconLabel.evaluate().isEmpty) {
    await waitForText(tester, text);
  }
  final target = find.text(text).evaluate().isNotEmpty
      ? find.text(text).last
      : iconLabel.last;
  // Provider replies and keyboard dismissal can change the form's height.
  // Reveal only after those layouts settle, then verify the actual hit target.
  for (var attempt = 0; attempt < 3; attempt++) {
    await tester.ensureVisible(target);
    await settle(tester);
    if (target.hitTestable().evaluate().isNotEmpty) break;
  }
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await settle(tester);
}

void appTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    }
  });
}

void main() {
  appTest('create, record, correct and Undo retain durable history', (
    tester,
  ) async {
    final fixture = await launch(tester);
    await tap(tester, 'Substances');
    await tap(tester, 'Create');
    await tester.enterText(
      find.byType(TextField).at(0),
      'Synthetic full substance name',
    );
    await tester.enterText(find.byType(TextField).at(1), 'Supplement');
    await tap(tester, 'Oral');
    await tap(tester, 'Tablet');
    await tap(tester, 'Create');
    await waitForText(tester, 'Setup');
    final item = (await runIo(tester, () => fixture.store.items()))!.single;
    fixture.container.read(routerProvider).go('/substance/${item.id}');
    await waitForText(tester, 'Synthetic full substance name');
    await tap(tester, 'Record');
    await tester.enterText(find.byType(TextField).at(0), '0.125000');
    await tap(tester, 'Save');
    expect(find.text('Me: 0.125000 count'), findsOneWidget);
    await tap(tester, 'Correct');
    await tester.enterText(find.byType(TextField).at(0), '0.5');
    await tap(tester, 'Save');
    expect(find.text('Me: 0.5 count'), findsOneWidget);
    await tap(tester, 'Undo');
    expect(find.text('Voided'), findsOneWidget);
    final rows = await runIo(tester, fixture.store.records);
    expect(rows!.single.personId, meId);
    expect(rows.single.revision, 3);
    expect(rows.single.isVoided, true);
    final history = await runIo(
      tester,
      () => fixture.store.history(rows.single.id),
    );
    expect(history!.map((r) => r.enteredAmount), ['0.125000', '0.5', '0.5']);
    expect(tester.takeException(), isNull);
  });
  appTest('invalid amount stays in form and stale correction is explicit', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'item',
        name: 'Synthetic item',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    await settle(tester);
    final record = (await runIo(
      tester,
      () => f.store.record(
        expectedPersonRevision: 2,
        commandId: 'record',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.now(),
      ),
    ))!;
    f.container.read(routerProvider).push('/correct/${record.id}');
    await settle(tester);
    for (final invalid in ['0', '1,000', '0,125000']) {
      await tester.enterText(find.byType(TextField).first, invalid);
      await tap(tester, 'Save');
      expect(find.textContaining('Use a decimal point'), findsOneWidget);
    }
    await tester.enterText(find.byType(TextField).first, '2');
    await settle(tester);
    await runIo(
      tester,
      () => f.store.correct(
        expectedPersonRevision: 2,
        commandId: 'competing',
        recordId: record.id,
        expectedRevision: 1,
        amount: '3',
        actualAt: record.actualAt,
      ),
    );
    await settle(tester);
    await tap(tester, 'Save');
    expect(find.textContaining('This record has changed.'), findsOneWidget);
    final rows = await runIo(tester, f.store.records);
    expect(rows!.single.enteredAmount, '3');
  });
  appTest('ambiguous clock requires an explicit instant before commit', (
    tester,
  ) async {
    final earlier = DateTime.utc(2026, 10, 25, 0, 30),
        later = DateTime.utc(2026, 10, 25, 1, 30);
    final f = await launch(tester, timeResolver: (_) => [earlier, later]);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'fold-item',
        name: 'Synthetic fold fixture',
        form: 'Tablet',
        unit: 'count',
        type: 'Medicine',
      ),
    ))!;
    f.container.read(routerProvider).push('/record/${item.id}');
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '1');
    await tap(tester, 'Save');
    expect(
      find.text(
        'This clock time occurs twice. Choose the earlier or later time.',
      ),
      findsOneWidget,
    );
    expect(await runIo(tester, f.store.records), isEmpty);
    await tap(tester, 'Later');
    await tap(tester, 'Save');
    final rows = await runIo(tester, f.store.records);
    expect(rows!.single.actualAt, later);
  });

  appTest(
    'history pages explicitly and corrections load beyond the first page',
    (tester) async {
      final f = await launch(tester);
      late UseRecord oldest;
      await runIo(tester, () async {
        final item = await f.store.createItem(
          expectedPersonRevision: 2,
          commandId: 'pages-item',
          name: 'Synthetic paging fixture',
          form: 'Tablet',
          unit: 'count',
          type: 'Medicine',
        );
        for (var i = 1; i <= 51; i++) {
          oldest = await f.store.record(
            expectedPersonRevision: 2,
            commandId: 'page-$i',
            itemId: item.id,
            amount: '$i',
            actualAt: DateTime(2026, 10, 19, 12).subtract(Duration(minutes: i)),
          );
        }
      });
      f.container.read(routerProvider).go('/history?view=list');
      await settle(tester);
      expect(find.byType(HistoryEntryCard), findsNWidgets(25));
      expect(find.text('More'), findsOneWidget);
      await tap(tester, 'More');
      expect(find.byType(HistoryEntryCard), findsNWidgets(50));
      await tap(tester, 'More');
      expect(find.byType(HistoryEntryCard), findsNWidgets(51));
      final oldestView = find.descendant(
        of: find.byKey(ValueKey('r:${oldest.id}')),
        matching: find.byType(StitchIcon),
      );
      await tester.ensureVisible(oldestView);
      await settle(tester);
      await tester.tap(oldestView);
      await settle(tester);
      expect(find.byType(HistorySourcePage), findsOneWidget);
      expect(
        tester
            .widget<HistorySourcePage>(find.byType(HistorySourcePage))
            .personId,
        meId,
      );
      await tap(tester, 'Correct');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '51',
      );
      await tap(tester, 'Cancel');
      expect(find.byType(HistorySourcePage), findsOneWidget);
      await tap(tester, 'Back');
      expect(find.byType(HistoryEntryCard), findsNWidgets(51));
      expect(find.text('More'), findsNothing);
    },
  );

  appTest('failed save retains details and retries one durable command', (
    tester,
  ) async {
    final ids = <String>[];
    final f = await launch(
      tester,
      recordWriter: (store, input) {
        ids.add(input.commandId);
        return store.record(
          expectedPersonRevision: 2,
          commandId: input.commandId,
          itemId: input.itemId,
          amount: input.amount,
          actualAt: input.actualAt,
          personId: input.personId,
          failBeforeCommit: ids.length == 1,
        );
      },
    );
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: 2,
        commandId: 'retry-item',
        name: 'Synthetic retry fixture',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    ))!;
    f.container.read(routerProvider).push('/record/${item.id}');
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '0.25');
    await tap(tester, 'Save');
    expect(
      find.text(
        'The save could not be confirmed. Retry with the same details.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '0.25',
    );
    expect(await runIo(tester, f.store.records), isEmpty);
    expect(find.textContaining('Saved for Me'), findsNothing);
    await tap(tester, 'Retry');
    expect(ids.length, 2);
    expect(ids.first, ids.last);
    final rows = await runIo(tester, f.store.records);
    expect(rows!.length, 1);
    expect(rows.single.enteredAmount, '0.25');
    expect(
      find.text('Saved for Me: Synthetic retry fixture, 0.25 mg.'),
      findsOneWidget,
    );
  });

  appTest('unfinished entry has one clear discard decision', (tester) async {
    await launch(tester);
    await tap(tester, 'Substances');
    await tap(tester, 'Create');
    await tester.enterText(
      find.byType(TextField).first,
      'Unsaved synthetic item',
    );
    await tap(tester, 'Back');
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tap(tester, 'Keep');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Unsaved synthetic item',
    );
    await tap(tester, 'Back');
    await tap(tester, 'Discard');
    // Only the new persistent Substances search field remains, empty.
    final remaining = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(remaining.length, 1);
    expect(remaining.single.controller!.text, isEmpty);
    expect(find.text('Unsaved synthetic item'), findsNothing);
    expect(find.text('Create'), findsWidgets);
  });

  appTest('appearance persists and mounted draft survives colour change', (
    tester,
  ) async {
    final f = await launch(tester);
    await tap(tester, 'Substances');
    await tap(tester, 'Create');
    await tester.enterText(
      find.byType(TextField).first,
      'Unfinished full name',
    );
    final editing = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller;
    final focus = FocusManager.instance.primaryFocus;
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final offset = scroll.pixels;
    f.container.read(appearanceProvider.notifier).setOpaque(true);
    await settle(tester);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(scroll.pixels, offset);

    await tap(tester, 'Appearance');
    await tap(tester, 'Dark');
    expect(f.container.read(appearanceProvider).mode, ThemeMode.dark);
    final saved = await runIo(tester, () => f.store.readSetting('appearance'));
    expect(saved, contains('dark'));
    await tap(tester, 'Back');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller,
      same(editing),
    );
    expect(editing!.text, 'Unfinished full name');
  });
  appTest('appearance reopens saved choice and failed write rolls back', (
    tester,
  ) async {
    final f = await launch(
      tester,
      appearanceWriter: (_) async {
        throw StateError('synthetic_write_failure');
      },
    );
    await tap(tester, 'Settings');
    await tap(tester, 'Appearance');
    await tap(tester, 'Dark');
    expect(f.container.read(appearanceProvider).mode, ThemeMode.system);
    expect(
      find.text('Appearance was not saved. Try the choice again.'),
      findsOneWidget,
    );
    expect(
      await runIo(tester, () => f.store.readSetting('appearance')),
      isNull,
    );
    await runIo(
      tester,
      () => f.store.writeSetting(
        'appearance',
        '{"mode":"dark","opaque":true,"reduceMotion":true}',
      ),
    );
    final reopened = ProviderContainer(
      overrides: [
        recordStoreProvider.overrideWithValue(AsyncData(f.store)),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
      ],
    );
    addTearDown(reopened.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: reopened, child: const VitalApp()),
    );
    await settle(tester);
    expect(reopened.read(appearanceProvider).mode, ThemeMode.dark);
    expect(reopened.read(appearanceProvider).opaque, true);
    expect(reopened.read(appearanceProvider).reduceMotion, true);
  });

  appTest('narrow large text allows form and settings without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester);
    await tap(tester, 'Substances');
    await tap(tester, 'Create');
    await tester.enterText(
      find.byType(TextField).first,
      'Long synthetic substance name with all details',
    );
    await tap(tester, 'Appearance');
    await tap(tester, 'Reduce motion');
    expect(tester.takeException(), isNull);
  });
  appTest('loading and unsupported storage never imply empty success', (
    tester,
  ) async {
    final completer = Completer<RecordStore>();
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() => completer.future),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const VitalApp()),
    );
    await tester.pump();
    expect(find.text('Opening protected records.'), findsOneWidget);
    expect(find.text('Nothing recorded'), findsNothing);
    completer.completeError(
      const StorageBootstrapException('unsupported_host'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Recording is available in the Android and Linux apps. This platform cannot open personal records.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
