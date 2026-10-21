import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/substances/substance_collection.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart' show appTest, runIo, settle;

Future<void> tap(WidgetTester tester, String text) async {
  tester.testTextInput.hide();
  await settle(tester);
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
  await settle(tester);
}

Future<({RecordStore store, ProviderContainer container})> launchCollection(
  WidgetTester tester,
  List<(String, String)> seeds, {
  // Regression hook: when given, page reads go through this injectable
  // delegate on the existing substancesPageProvider instead of straight to
  // the store, so tests can reproduce real data failures.
  Stream<List<SubstanceItem>> Function(
    RecordStore store,
    SubstancesPageQuery query,
  )?
  overridePages,
  Stream<List<SubstanceTypeSummary>> Function(
    RecordStore store,
    SubstancesTypeQuery query,
  )?
  overrideTypes,
}) async {
  final dir = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-substance-collection-'),
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
  var owner = (await runIo(tester, () => store.profileById(meId)))!;
  for (final (name, type) in seeds) {
    await runIo(tester, () async {
      await store.createItem(
        commandId: newCommandId(),
        personId: owner.id,
        expectedPersonRevision: owner.revision,
        name: name,
        form: 'Tablet',
        unit: 'mg',
        type: type,
      );
      owner = (await store.profileById(meId))!;
    });
  }
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() async => store),
      appAuthGatewayProvider.overrideWithValue(FakeAuth()),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      if (overrideTypes != null)
        substanceTypesProvider.overrideWith((ref, query) async* {
          final store = await ref.watch(recordStoreProvider.future);
          yield* overrideTypes(store, query);
        }),
      if (overridePages != null)
        substancesPageProvider.overrideWith((ref, query) async* {
          final store = await ref.watch(recordStoreProvider.future);
          yield* overridePages(store, query);
        }),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
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

Future<void> searchFor(WidgetTester tester, String value) async {
  final field = find.byType(TextField).first;
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await settle(tester);
}

int visibleFocusRings(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(SubstanceIdentityCard),
        matching: find.byType(DecoratedBox),
      ),
    )
    .where((box) {
      final decoration = box.decoration;
      // The shared focus ring is the only outlined border drawn in a card.
      return switch (decoration) {
        ShapeDecoration(shape: OutlinedBorder(side: final side)) =>
          side.width > 0,
        _ => false,
      };
    })
    .length;

void main() {
  appTest('search reaches every stored substance beyond the first page', (
    tester,
  ) async {
    await launchCollection(tester, [
      for (var i = 1; i <= 55; i++)
        ('Range ${i.toString().padLeft(2, '0')}', 'Medicine'),
    ]);
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(50));
    expect(find.text('More'), findsOneWidget);
    await tap(tester, 'More');
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(55));
    // Search for an item that exists only past the first 50 loaded cards.
    await searchFor(tester, 'Range 55');
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(1));
    // find.text also matches the search field, so match the card title only.
    expect(
      find.descendant(
        of: find.byType(SubstanceIdentityCard),
        matching: find.text('Range 55'),
      ),
      findsOneWidget,
    );
    expect(find.text('More'), findsNothing);
    // A lone wildcard stays literal; no stored name contains a percent sign.
    await searchFor(tester, '%');
    expect(find.byType(SubstanceIdentityCard), findsNothing);
    expect(find.text('No matches'), findsOneWidget);
  });
  appTest('search treats wildcard, backslash and apostrophe input literally', (
    tester,
  ) async {
    await launchCollection(tester, [
      ('100% pure', 'Medicine'),
      ('A_B test', 'Medicine'),
      ('AxB test', 'Medicine'),
      ('O\'Brien dose', 'Medicine'),
      ('Half\\done', 'Medicine'),
    ]);
    await searchFor(tester, '100%');
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(1));
    expect(find.text('100% pure'), findsOneWidget);
    await searchFor(tester, '%pure');
    expect(find.byType(SubstanceIdentityCard), findsNothing);
    await searchFor(tester, 'A_B');
    expect(find.text('A_B test'), findsOneWidget);
    expect(find.text('AxB test'), findsNothing);
    await searchFor(tester, 'O\'Brien');
    expect(find.text('O\'Brien dose'), findsOneWidget);
    await searchFor(tester, 'Half\\');
    expect(find.text('Half\\done'), findsOneWidget);
    // Clearing returns to the whole collection in its stored order.
    await searchFor(tester, '');
    final labels = [
      '100% pure',
      'A_B test',
      'AxB test',
      'Half\\done',
      "O'Brien dose",
    ];
    var previous = -1.0;
    for (final label in labels) {
      final top = tester.getTopLeft(find.text(label).first).dy;
      expect(top, greaterThanOrEqualTo(previous));
      previous = top;
    }
  });
  appTest('type filters combine with search and clear in one action', (
    tester,
  ) async {
    await launchCollection(tester, [
      ('Ibuprofen', 'Medicine'),
      ('Paracetamol', 'Medicine'),
      ('Loperamide', 'Medicine'),
      ('Vitamin C', 'Supplement'),
      ('Vitamin D', 'Supplement'),
    ]);
    expect(find.textContaining('All (5)'), findsOneWidget);
    expect(find.textContaining('Medicine (3)'), findsOneWidget);
    expect(find.textContaining('Supplement (2)'), findsOneWidget);
    await tap(tester, 'Supplement (2)');
    expect(find.text('Ibuprofen'), findsNothing);
    expect(find.text('Vitamin C'), findsOneWidget);
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(2));
    // Filter and search apply together over the whole collection.
    await searchFor(tester, 'C');
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(1));
    expect(find.text('Vitamin C'), findsOneWidget);
    // A filtered combination with no results keeps its recovery action.
    await searchFor(tester, 'Dose none');
    expect(find.text('No matches'), findsOneWidget);
    await tap(tester, 'Clear');
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(5));
    expect(find.textContaining('All (5)'), findsOneWidget);
    // A second clear stays offered while results remain filtered.
    await tap(tester, 'Medicine (3)');
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(3));
    expect(find.text('Clear'), findsWidgets);
  });
  appTest('creating a substance lives through an active filter', (
    tester,
  ) async {
    final fixture = await launchCollection(tester, [
      ('Vitamin C', 'Supplement'),
      ('Ibuprofen', 'Medicine'),
    ]);
    await searchFor(tester, 'Live');
    expect(find.byType(SubstanceIdentityCard), findsNothing);
    final owner = (await runIo(tester, () => fixture.store.profileById(meId)))!;
    await runIo(
      tester,
      () => fixture.store.createItem(
        commandId: newCommandId(),
        personId: owner.id,
        expectedPersonRevision: owner.revision,
        name: 'Live vitamin K',
        form: 'Tablet',
        unit: 'mg',
        type: 'Supplement',
      ),
    );
    await settle(tester);
    expect(find.text('Live vitamin K'), findsOneWidget);
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(1));
  });
  appTest('query, filter and list survive a detail visit and back', (
    tester,
  ) async {
    await launchCollection(tester, [
      ('Vitamin C', 'Supplement'),
      ('Vitamin D', 'Supplement'),
      ('Ibuprofen', 'Medicine'),
    ]);
    await searchFor(tester, 'Vit');
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(2));
    await tap(tester, 'Vitamin C');
    // The existing detail/history route keeps its content and actions.
    expect(find.text('History'), findsWidgets);
    expect(find.text('Vitamin C'), findsWidgets);
    await tap(tester, 'Back');
    await settle(tester);
    expect(
      (tester.widget<TextField>(find.byType(TextField).first)).controller!.text,
      'Vit',
    );
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(2));
    expect(find.text('Ibuprofen'), findsNothing);
  });
  appTest('empty collection keeps the create offer and no filter pills', (
    tester,
  ) async {
    await launchCollection(tester, const []);
    expect(find.textContaining('Create a substance'), findsOneWidget);
    expect(find.textContaining('All ('), findsNothing);
    expect(find.byType(SubstanceIdentityCard), findsNothing);
  });
  appTest('selected type stays visible when search matches another type', (
    tester,
  ) async {
    await launchCollection(tester, [
      ('Ibuprofen', 'Medicine'),
      ('Vitamin C', 'Supplement'),
    ]);
    await tap(tester, 'Supplement (1)');
    await searchFor(tester, 'Ibuprofen');
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Supplement (0)'), findsOneWidget);
    await tap(tester, 'All (1)');
    expect(find.text('Ibuprofen'), findsWidgets);
    expect(find.byType(SubstanceIdentityCard), findsOneWidget);
  });
  appTest('search and filters keep full text usable at narrow double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await launchCollection(tester, [
      ('Ibuprofen', 'Medicine'),
      ('A very long synthetic substance name for scaling', 'Supplement'),
    ]);
    await searchFor(tester, 'Ibuprofen');
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(1));
    // The search field keeps its accessible label and the Clear control
    // remains reachable without shrinking accessible text.
    await tap(tester, 'Clear');
    expect(find.text('All (2)'), findsOneWidget);
    expect(
      find.text('A very long synthetic substance name for scaling'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  appTest('selected type keeps counts across edits, detail visits and back', (
    tester,
  ) async {
    await launchCollection(tester, [
      ('Ibuprofen', 'Medicine'),
      ('Vitamin C', 'Supplement'),
      ('Vitamin D', 'Supplement'),
    ]);
    await tap(tester, 'Supplement (2)');
    await searchFor(tester, 'Vit');
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(2));
    expect(find.textContaining('Supplement (2)'), findsOneWidget);
    await tap(tester, 'Vitamin C');
    expect(find.text('History'), findsWidgets);
    await tap(tester, 'Back');
    await settle(tester);
    // The selection, its live count and the guarded search all come back.
    expect(
      (tester.widget<TextField>(find.byType(TextField).first)).controller!.text,
      'Vit',
    );
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(2));
    expect(find.textContaining('Supplement (2)'), findsOneWidget);
    // Editing the search keeps the selection visible even at a zero count.
    await searchFor(tester, 'ZZZ none');
    expect(find.text('No matches'), findsOneWidget);
    expect(find.textContaining('Supplement (0)'), findsOneWidget);
  });
  appTest('data failures keep search and filters with a retry in reach', (
    tester,
  ) async {
    var pageLoads = 0;
    await launchCollection(
      tester,
      [('Ibuprofen', 'Medicine')],
      overridePages: (store, query) async* {
        pageLoads++;
        if (pageLoads == 1) throw StateError('injected store failure');
        yield* store.watchItems(
          scope: query.scope,
          search: query.search,
          typeId: query.typeId.isEmpty ? null : query.typeId,
          limit: 51,
          offset: query.offset,
        );
      },
    );
    // The failure report shares the screen with the mounted search tools and
    // the real filter pills instead of replacing them.
    expect(find.textContaining('All (1)'), findsOneWidget);
    expect(find.textContaining('Medicine (1)'), findsOneWidget);
    expect(
      find.text('The substance list is unavailable right now.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tap(tester, 'Retry');
    // Retrying reloads from the injected store and the list recovers.
    expect(find.byType(SubstanceIdentityCard), findsNWidgets(1));
    expect(find.text('Ibuprofen'), findsOneWidget);
  });
  appTest('zero-match selected type follows a stored rename', (tester) async {
    final fixture = await launchCollection(tester, [
      ('Ibuprofen', 'Medicine'),
      ('Vitamin C', 'Supplement'),
    ]);
    await tap(tester, 'Supplement (1)');
    await searchFor(tester, 'Ibuprofen');
    await runIo(tester, () async {
      final item = (await fixture.store.items(search: 'Vitamin C')).single;
      final type = (await fixture.store.itemTypeById(
        item.typeId!,
        personId: meId,
      ))!;
      await fixture.store.renameItemType(
        commandId: newCommandId(),
        typeId: type.id,
        expectedRevision: type.revision,
        expectedPersonRevision: 2,
        name: 'Vitamins',
      );
    });
    await settle(tester);
    expect(find.text('Vitamins (0)'), findsOneWidget);
    expect(find.text('Supplement (0)'), findsNothing);
  });
  appTest('loading type counts stay unknown until the query completes', (
    tester,
  ) async {
    final gate = Completer<void>();
    await launchCollection(
      tester,
      [('Ibuprofen', 'Medicine'), ('Vitamin C', 'Supplement')],
      overrideTypes: (store, query) async* {
        if (query.search == 'Ibuprofen') await gate.future;
        yield* store.watchItemTypeCounts(
          scope: query.scope,
          search: query.search,
        );
      },
    );
    await tap(tester, 'Supplement (1)');
    await searchFor(tester, 'Ibuprofen');
    try {
      expect(find.text('Supplement'), findsOneWidget);
      expect(find.text('Supplement (0)'), findsNothing);
    } finally {
      gate.complete();
    }
    await settle(tester);
    expect(find.text('Supplement (0)'), findsOneWidget);
  });
  appTest('keyboard focus marks the identity row and Enter opens it', (
    tester,
  ) async {
    await launchCollection(tester, [('Ibuprofen', 'Medicine')]);
    expect(visibleFocusRings(tester), isZero);
    // shadcn follows the platform highlight mode: keyboard traversal enables
    // the focus ring, while a touch or programmatic focus need not show one.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);
    final node = Focus.maybeOf(tester.element(find.text('Ibuprofen').first));
    expect(node, isNotNull);
    node!.requestFocus();
    await settle(tester);
    expect(node.hasFocus, isTrue);
    // One visible ring marks the focused row; none appeared before focus.
    expect(visibleFocusRings(tester), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(find.text('History'), findsWidgets);
    await tap(tester, 'Back');
    await settle(tester);
    // The ring leaves with the focus; the row stays tappable.
    expect(find.byType(SubstanceIdentityCard), findsOneWidget);
  });
}
