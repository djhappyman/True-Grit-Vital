import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/substances/substance_collection.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart'
    show appTest, runIo, settle, tap, waitForText;

const statusCaptureDirectory = String.fromEnvironment('VITAL_STATUS_CAPTURES');
const statusZone = 'Europe/London';

enum SeedPlan { none, active, paused, asNeeded, future, ended }

typedef SeedSpec = (String name, String type, SeedPlan plan);

Future<({RecordStore store, ProviderContainer container})> launchStatusCollection(
  WidgetTester tester,
  List<SeedSpec> specs, {
  Stream<List<SubstanceItem>> Function(
    RecordStore store,
    SubstancesPageQuery query,
  )?
  overridePages,
  Stream<SubstanceStatusSnapshot> Function(
    RecordStore store,
    SubstanceStatusQuery query,
  )?
  overrideStatus,
}) async {
  final dir = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-substance-status-ui-'),
  ))!;
  final store = (await runIo(tester, () async {
    final opened = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    await opened.editProfile(
      commandId: 'setup',
      personId: meId,
      expectedRevision: 1,
      name: 'Main Adult',
      adultConfirmed: true,
    );
    await opened.saveBrowsingScope(const FeedScope.me());
    return opened;
  }))!;
  final now = DateTime.now().toUtc();
  final today = DailyResolver().clock.dateAt(now, statusZone);
  for (final spec in specs) {
    await runIo(tester, () async {
      final owner = (await store.profileById(meId))!;
      final item = await store.createItem(
        commandId: newCommandId(),
        personId: owner.id,
        expectedPersonRevision: owner.revision,
        name: spec.$1,
        form: 'Tablet',
        unit: 'mg',
        type: spec.$2,
      );
      final timing = switch (spec.$3) {
        SeedPlan.none => null,
        SeedPlan.asNeeded => const AsNeeded(),
        _ => DailyCount(
          1,
          PlannedAmount(
            quantity: ExactQuantity.parse('1'),
            enteredText: '1',
            unit: 'mg',
          ),
        ),
      };
      if (timing == null) return;
      final ownerAfterItem = (await store.profileById(meId))!;
      await store.saveDailyPlan(
        commandId: newCommandId(),
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'plan-${item.id}',
          itemId: item.id,
          versionId: 'version-${item.id}',
          start: spec.$3 == SeedPlan.future
              ? today.addDays(1)
              : today.addDays(-7),
          endExclusive: spec.$3 == SeedPlan.ended
              ? today.addDays(-5)
              : null,
          timing: timing,
          zoneBasis: FixedHome(statusZone),
          pauses: spec.$3 == SeedPlan.paused
              ? [
                  PlanPause(
                    start: now.subtract(const Duration(hours: 1)),
                    resume: now.add(const Duration(hours: 1)),
                  ),
                ]
              : const [],
        ),
        expectedPersonRevision: ownerAfterItem.revision,
        expectedGeneration: store.generation,
      );
    });
  }
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() async => store),
      appAuthGatewayProvider.overrideWithValue(FakeAuth()),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId(statusZone)),
      ),
      if (overridePages != null)
        substancesPageProvider.overrideWith((ref, query) async* {
          final store = await ref.watch(recordStoreProvider.future);
          yield* overridePages(store, query);
        }),
      if (overrideStatus != null)
        substanceStatusSnapshotProvider.overrideWith((ref, query) async* {
          final store = await ref.watch(recordStoreProvider.future);
          yield* overrideStatus(store, query);
        }),
    ],
  );
  addTearDown(() async {
    container.dispose();
    // Closing watched reads also needs the widget clock to keep moving.
    await runIo(tester, store.close);
    await dir.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  container.read(routerProvider).go('/substances');
  await settle(tester);
  return (store: store, container: container);
}

int cards(WidgetTester tester) => find.byType(SubstanceIdentityCard).evaluate().length;

void main() {
  appTest('status counts and filters compose as one whole collection', (
    tester,
  ) async {
    await launchStatusCollection(tester, [
      ('Alpha', 'Medicine', SeedPlan.active),
      ('Beta', 'Medicine', SeedPlan.active),
      ('Gamma', 'Medicine', SeedPlan.paused),
      ('Delta', 'Supplement', SeedPlan.active),
      ('Epsilon', 'Supplement', SeedPlan.asNeeded),
      ('Zeta', 'Supplement', SeedPlan.none),
    ]);
    await waitForText(tester, 'All statuses (6)');
    expect(find.text('Active (3)'), findsOneWidget);
    expect(find.text('Paused (1)'), findsOneWidget);
    expect(find.text('As needed (1)'), findsOneWidget);
    expect(find.text('Unscheduled (1)'), findsOneWidget);
    expect(
      find.text(
        'An item with more than one plan can appear under each matching status. '
        'Future and ended plans count as unscheduled.',
      ),
      findsOneWidget,
    );
    await waitForText(tester, 'Alpha');
    expect(cards(tester), 6);

    await tap(tester, 'Active (3)');
    expect(cards(tester), 3);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Delta'), findsOneWidget);
    expect(find.text('Gamma'), findsNothing);
    expect(find.text('Epsilon'), findsNothing);

    await tap(tester, 'Paused (1)');
    expect(cards(tester), 1);
    expect(find.text('Gamma'), findsOneWidget);
    await tap(tester, 'As needed (1)');
    expect(cards(tester), 1);
    expect(find.text('Epsilon'), findsOneWidget);
    await tap(tester, 'Unscheduled (1)');
    expect(cards(tester), 1);
    expect(find.text('Zeta'), findsOneWidget);
    await tap(tester, 'All statuses (6)');
    expect(cards(tester), 6);
  });

  appTest('status filters combine with type and name search', (tester) async {
    await launchStatusCollection(tester, [
      ('Alpha', 'Medicine', SeedPlan.active),
      ('Beta', 'Medicine', SeedPlan.active),
      ('Gamma', 'Medicine', SeedPlan.paused),
      ('Delta', 'Supplement', SeedPlan.active),
      ('Epsilon', 'Supplement', SeedPlan.asNeeded),
      ('Zeta', 'Supplement', SeedPlan.none),
    ]);
    await waitForText(tester, 'Supplement (3)');
    await tap(tester, 'Supplement (3)');
    await waitForText(tester, 'All statuses (3)');
    await waitForText(tester, 'Delta');
    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Paused (0)'), findsOneWidget);
    expect(find.text('As needed (1)'), findsOneWidget);
    expect(find.text('Unscheduled (1)'), findsOneWidget);
    expect(cards(tester), 3);

    await tap(tester, 'Active (1)');
    expect(cards(tester), 1);
    expect(find.text('Delta'), findsOneWidget);
    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Epsilon');
    await settle(tester);
    await waitForText(tester, 'No matches');
    await waitForText(tester, 'All statuses (1)');
    expect(find.text('Active (0)'), findsOneWidget);
    expect(find.text('As needed (1)'), findsOneWidget);
    expect(cards(tester), 0);

    await tap(tester, 'Clear');
    expect(cards(tester), 6);
    expect(
      (tester.widget<TextField>(find.byType(TextField).first)).controller!.text,
      isEmpty,
    );
    expect(find.text('All statuses (6)'), findsOneWidget);
  });

  appTest('a status change resets paging before a page can go stale', (
    tester,
  ) async {
    await launchStatusCollection(tester, [
      for (var i = 1; i <= 55; i++)
        ('Range ${i.toString().padLeft(2, '0')}', 'Medicine', SeedPlan.active),
    ]);
    await waitForText(tester, 'Active (55)');
    await waitForText(tester, 'Range 01');
    expect(cards(tester), 50);
    expect(find.text('More'), findsOneWidget);
    await tap(tester, 'More');
    await waitForText(tester, 'Range 51');
    expect(cards(tester), 55);
    expect(find.text('More'), findsNothing);

    await tap(tester, 'Paused (0)');
    expect(cards(tester), 0);
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('More'), findsNothing);

    await tap(tester, 'All statuses (55)');
    expect(cards(tester), 50);
    expect(find.text('More'), findsOneWidget);
    await tap(tester, 'More');
    await waitForText(tester, 'Range 51');
    expect(cards(tester), 55);

    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Range 55');
    await settle(tester);
    expect(cards(tester), 1);
    expect(find.text('More'), findsNothing);
  });

  appTest('a status query failure keeps controls and recovers on retry', (
    tester,
  ) async {
    var loads = 0;
    await launchStatusCollection(
      tester,
      [
        ('Alpha', 'Medicine', SeedPlan.active),
        ('Gamma', 'Medicine', SeedPlan.paused),
      ],
      overrideStatus: (store, query) async* {
        loads++;
        if (loads == 1) throw StateError('injected status failure');
        yield* store.watchSubstanceStatusSnapshot(
          scope: query.scope,
          search: query.search,
          typeId: query.typeId.isEmpty ? null : query.typeId,
          now: query.asOf,
          observedZone: query.zone,
        );
      },
    );
    expect(
      find.text('The substance list is unavailable right now.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tap(tester, 'Retry');
    await waitForText(tester, 'Active (1)');
    await waitForText(tester, 'Alpha');
    expect(find.text('Paused (1)'), findsOneWidget);
    expect(cards(tester), 2);
  });

  appTest('status pills stay usable with full names at narrow double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launchStatusCollection(tester, [
      (
        'A very long synthetic substance name for scaling',
        'Supplement',
        SeedPlan.active,
      ),
      ('Gamma', 'Medicine', SeedPlan.paused),
    ]);
    await waitForText(tester, 'All statuses (2)');
    await waitForText(tester, 'A very long synthetic substance name for scaling');
    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Paused (1)'), findsOneWidget);
    await tap(tester, 'Active (1)');
    expect(find.byType(SubstanceIdentityCard), findsOneWidget);
    expect(
      find.text('A very long synthetic substance name for scaling'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.text('Active (1)'));
    expect(node.getSemanticsData().flagsCollection.isSelected, ui.Tristate.isTrue);
    handle.dispose();
  });

  appTest('status filters render in light and dark reference captures', (
    tester,
  ) async {
    final fixture = await launchStatusCollection(tester, [
      ('Alpha', 'Medicine', SeedPlan.active),
      ('Beta', 'Medicine', SeedPlan.active),
      ('Gamma', 'Medicine', SeedPlan.paused),
      ('Delta', 'Supplement', SeedPlan.active),
      ('Epsilon', 'Supplement', SeedPlan.asNeeded),
      ('Zeta', 'Supplement', SeedPlan.none),
    ]);
    await waitForText(tester, 'All statuses (6)');
    await waitForText(tester, 'Alpha');
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
      ),
    );
    await settle(tester);
    fixture.container.read(routerProvider).go('/substances');
    await settle(tester);
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      fixture.container.read(appearanceProvider.notifier).setMode(theme);
      await settle(tester);
      if (statusCaptureDirectory.isEmpty) continue;
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$statusCaptureDirectory/${theme.name}-substances-status.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
    expect(tester.takeException(), isNull);
  });
}
