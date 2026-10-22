import 'fixtures/single_user.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_theme.dart';
import 'package:true_grit_vital/data/catalogue/catalogue_manager.dart';
import 'package:true_grit_vital/features/catalogue/catalogue_picker.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder input(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);
Finder catalogueInput() => input('Search medicines');
Finder catalogueClear() => find.byKey(const ValueKey('catalogue-query-clear'));
Future<void> enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(input(label));
  await tester.enterText(input(label), value);
  await settle(tester);
}

Future<void> enterSearch(WidgetTester tester, String value) async {
  await tester.ensureVisible(catalogueInput());
  await tester.enterText(catalogueInput(), value);
  await settle(tester);
}

Future<({CatalogueManager manager, CatalogueReader reader, Directory root})>
corpus() async {
  final root = await Directory.systemTemp.createTemp('vital-catalogue-ui-');
  final manager = CatalogueManager(
    Directory('${root.path}/installed'),
    allowSynthetic: true,
  );
  final reader = await install(manager, root, 'first', '7 mg');
  return (manager: manager, reader: reader, root: root);
}

Future<CatalogueReader> install(
  CatalogueManager manager,
  Directory root,
  String version,
  String strength, {
  String name = 'Invented amber',
  String form = 'tablet',
}) async {
  final notice = File('${root.path}/$version.notice');
  await notice.writeAsString(
    'Synthetic invented test source. Not real medicines.',
  );
  final projection = File('${root.path}/$version.jsonl');
  await projection.writeAsString(
    '${jsonEncode(CatalogueProduct(code: 'fiction-1', conceptClass: 'SYNTHETIC', name: name, form: form, strength: strength).toJson())}\n',
  );
  final m = CatalogueManifest(
    version: version,
    sourceId: 'synthetic-fixture',
    releaseDate: '2026-10-19',
    sourceUrl: 'https://example.invalid/test',
    sourceSha256: '0' * 64,
    projectionSha256: await catalogueFileSha256(projection),
    licence: 'Synthetic test fixture',
    attribution: 'Invented UI test data',
    licenceSha256: await catalogueFileSha256(notice),
    recordCount: 1,
    admissionReference: 'explicit-test-only',
    synthetic: true,
  );
  await manager.stage(
    projection: projection,
    licenceNotice: notice,
    manifest: m,
  );
  await manager.activate(version);
  return (await manager.openActive())!;
}

final class FakeCatalogueSearch implements CatalogueSearchHandle {
  final calls = <String>[];
  final pending = <String, Completer<CatalogueSearchPage?>>{};
  bool closed = false;

  @override
  Future<CatalogueSearchPage?> search(String query) {
    calls.add(query);
    final reply = Completer<CatalogueSearchPage?>();
    pending[query] = reply;
    return reply.future;
  }

  void reply(String query, CatalogueSearchPage page) =>
      pending.remove(query)!.complete(page);

  void fail(String query, Object error) =>
      pending.remove(query)!.completeError(error);

  @override
  void close() {
    closed = true;
    for (final reply in pending.values) {
      if (!reply.isCompleted) reply.complete(null);
    }
    pending.clear();
  }
}

CatalogueSearchPage cataloguePage(
  CatalogueReader reader,
  String query, {
  String name = 'Invented amber',
  String form = 'tablet',
  String strength = '7 mg',
}) => CatalogueSearchPage(
  query: query,
  products: [
    CatalogueProduct(
      code: 'fiction-1',
      conceptClass: 'SYNTHETIC',
      name: name,
      form: form,
      strength: strength,
    ),
  ],
  manifest: reader.manifest,
  needsRefinement: false,
);

Future<void> pumpCataloguePicker(
  WidgetTester tester, {
  required CatalogueReader reader,
  required TextEditingController query,
  required CatalogueSearchHandle handle,
  required ValueNotifier<bool> enabled,
  required ValueChanged<CatalogueSnapshot> onSelect,
  Brightness brightness = Brightness.light,
  GlobalKey? captureKey,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogueLoaderProvider.overrideWithValue(() async => reader),
      ],
      child: RepaintBoundary(
        key: captureKey,
        child: ShadcnApp(
          debugShowCheckedModeBanner: false,
          theme: vitalTheme(brightness),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'GB')],
          home: Scaffold(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder<bool>(
                  valueListenable: enabled,
                  builder: (context, value, _) => CataloguePicker(
                    query: query,
                    enabled: value,
                    createSearch: (_) => handle,
                    onSelect: onSelect,
                    onCustom: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const captures = String.fromEnvironment('VITAL_T04_CAPTURES');
  setUpAll(() async {
    if (captures.isEmpty) return;
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
  });
  appTest(
    'unavailable catalogue retains query in custom entry and encrypted draft',
    (tester) async {
      final f = await launch(tester);
      f.container.read(routerProvider).go('/create?person=$meId');
      await settle(tester);
      await tap(tester, 'Search');
      expect(
        find.text(
          'The medicine catalogue is unavailable. Enter a custom substance to continue.',
        ),
        findsOneWidget,
      );
      await enterSearch(tester, 'Unmatched original name');
      await tap(tester, 'Enter');
      expect(
        tester.widget<TextField>(input('Full name')).controller!.text,
        'Unmatched original name',
      );
      await runIo(tester, () async {
        final drafts = await f.store.drafts();
        expect(drafts.single.fields['query'], 'Unmatched original name');
        expect(drafts.single.fields['catalogue'], '');
      });
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      f.container.read(routerProvider).go('/create?person=$meId');
      await settle(tester);
      expect(
        tester.widget<TextField>(input('Full name')).controller!.text,
        'Unmatched original name',
      );
      await tap(tester, 'Search');
      expect(
        tester.widget<TextField>(catalogueInput()).controller!.text,
        'Unmatched original name',
      );
    },
  );

  appTest(
    'offline no-match differs from unavailable and custom name remains exact',
    (tester) async {
      final source = (await runIo(tester, corpus))!;
      addTearDown(() => source.root.delete(recursive: true));
      final f = await launch(
        tester,
        catalogueLoader: () async => source.reader,
      );
      f.container.read(routerProvider).go('/create?person=$meId');
      await settle(tester);
      await tap(tester, 'Search');
      await enterSearch(tester, 'Absent fictional product');
      await waitForText(
        tester,
        'No catalogue match for “Absent fictional product”. You can enter it as a custom substance.',
      );
      expect(
        find.textContaining('Source: synthetic-fixture. Version: first.'),
        findsOneWidget,
      );
      expect(find.text('Attribution: Invented UI test data'), findsOneWidget);
      await tap(tester, 'Enter');
      await enter(tester, 'Form', 'capsule');
      await tap(tester, 'mg');
      await enter(tester, 'Type', 'Personal');
      await tap(tester, 'Create');
      final items = (await runIo(tester, () => f.store.items()))!;
      expect(items.single.name, 'Absent fictional product');
      expect(items.single.catalogueSnapshot, isNull);
    },
  );

  appTest(
    'explicit catalogue selection pins source across update, dose and type rename',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final source = (await runIo(tester, corpus))!;
      addTearDown(() => source.root.delete(recursive: true));
      final f = await launch(
        tester,
        catalogueLoader: () async => source.reader,
      );
      final person = (await runIo(tester, () => f.store.profileById(meId)))!;
      final type = (await runIo(
        tester,
        () => f.store.createItemType(
          commandId: 'make-type',
          personId: meId,
          expectedPersonRevision: person.revision,
          name: 'Evening',
        ),
      ))!;
      f.container.read(routerProvider).go('/create?person=$meId');
      await settle(tester);
      await tap(tester, 'Search');
      await enterSearch(tester, 'Invented amber');
      await waitForText(tester, 'Invented amber');
      expect(
        find.text('Invented amber. Form: tablet. Strength: 7 mg.'),
        findsOneWidget,
      );
      await tap(tester, 'Select');
      await runIo(
        tester,
        () => install(source.manager, source.root, 'second', '11 mg'),
      );
      expect(
        find.textContaining('Source: synthetic-fixture. Version: first.'),
        findsOneWidget,
      );
      await tap(tester, 'mg');
      await tap(tester, 'Evening');
      await tap(tester, 'Create');
      final item = (await runIo(tester, () => f.store.items()))!.single;
      expect(item.catalogueSnapshot!.manifest.version, 'first');
      expect(item.catalogueSnapshot!.product.strength, '7 mg');
      expect(item.typeId, type.id);
      final record = (await runIo(
        tester,
        () => f.store.record(
          commandId: 'dose-before-rename',
          itemId: item.id,
          personId: meId,
          expectedPersonRevision: person.revision,
          amount: '2',
          actualAt: DateTime.utc(2026, 10, 19, 10),
        ),
      ))!;
      f.container.read(routerProvider).go('/types/$meId/edit?type=${type.id}');
      await settle(tester);
      expect(
        find.text(
          'Existing substances use the new name. Earlier dose records keep their saved type.',
        ),
        findsOneWidget,
      );
      await enter(tester, 'Type name', 'Night');
      await tap(tester, 'Save');
      await waitForText(tester, 'Night');
      final current = (await runIo(tester, () => f.store.itemById(item.id)))!;
      final old = (await runIo(
        tester,
        () => f.store.recordById(record.id, personId: meId),
      ))!;
      expect(current.type, 'Night');
      expect(old.type, 'Evening');
      expect(old.catalogueSnapshot!.manifest.version, 'first');
      f.container.read(routerProvider).go('/item/${item.id}');
      await settle(tester);
      expect(find.text('Attribution: Invented UI test data'), findsWidgets);
      expect(find.textContaining('Version: second'), findsNothing);
    },
  );

  appTest('late reader and search replies cannot replace newest query', (
    tester,
  ) async {
    final source = (await runIo(tester, corpus))!;
    addTearDown(() => source.root.delete(recursive: true));
    final pending = Completer<CatalogueReader?>();
    final f = await launch(tester, catalogueLoader: () => pending.future);
    f.container.read(routerProvider).go('/create?person=$meId');
    await settle(tester);
    await tap(tester, 'Search');
    await tester.enterText(catalogueInput(), 'Invented amber');
    await tester.enterText(catalogueInput(), 'Newest absent');
    pending.complete(source.reader);
    await settle(tester);
    await waitForText(
      tester,
      'No catalogue match for “Newest absent”. You can enter it as a custom substance.',
    );
    expect(find.text('Invented amber'), findsNothing);
    await tester.enterText(catalogueInput(), 'Invented amber');
    await tester.enterText(catalogueInput(), 'Still absent');
    await settle(tester);
    await waitForText(
      tester,
      'No catalogue match for “Still absent”. You can enter it as a custom substance.',
    );
    expect(find.text('Invented amber'), findsNothing);
  });
  appTest(
    'selected source draft survives lock and route reopening without changing adult',
    (tester) async {
      final source = (await runIo(tester, corpus))!;
      addTearDown(() => source.root.delete(recursive: true));
      final f = await launch(
        tester,
        catalogueLoader: () async => source.reader,
        auth: FakeAuth(),
      );
      final other = (await runIo(
        tester,
        () => f.store.configureOwnProfile(
          commandId: 'other-adult',
          name: 'Other adult',
          adultConfirmed: true,
        ),
      ))!;
      await settle(tester);
      f.container.read(routerProvider).go('/create?person=${other.id}');
      await settle(tester);
      await tap(tester, 'Search');
      await enterSearch(tester, 'Invented amber');
      await waitForText(tester, 'Invented amber');
      await tap(tester, 'Select');
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.inactive);
      await settle(tester);
      expect(find.text('Invented amber'), findsNothing);
      f.container
          .read(appLockProvider.notifier)
          .lifecycle(AppLifecycleState.resumed);
      await tap(tester, 'Unlock');
      expect(find.textContaining('Version: first'), findsOneWidget);
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      await settle(tester);
      f.container.read(routerProvider).go('/create?person=${other.id}');
      await settle(tester);
      expect(find.textContaining('Version: first'), findsOneWidget);
      expect(
        tester.widget<TextField>(input('Full name')).controller!.text,
        'Invented amber',
      );
      await tap(tester, 'mg');
      await enter(tester, 'Type', 'Personal');
      await tap(tester, 'Create');
      final items = (await runIo(
        tester,
        () => f.store.items(scope: FeedScope.person(other.id)),
      ))!;
      expect(items.single.personId, other.id);
      expect(items.single.catalogueSnapshot!.manifest.version, 'first');
      expect(
        (await runIo(
          tester,
          () => f.store.items(scope: const FeedScope.me()),
        ))!,
        hasLength(1),
      );
      expect((await runIo(tester, () => f.store.drafts()))!, isEmpty);
    },
  );

  appTest(
    'personal type create and duplicate recovery work at narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      f.container.read(routerProvider).go('/types/$meId/edit');
      await settle(tester);
      await enter(tester, 'Type name', 'Supplements');
      await tap(tester, 'Save');
      await waitForText(tester, 'Supplements');
      expect(tester.takeException(), isNull);
      f.container.read(routerProvider).go('/types/$meId/edit');
      await settle(tester);
      await enter(tester, 'Type name', 'Supplements');
      await tap(tester, 'Save');
      expect(
        find.text(
          'This person already has that type. Choose a different name.',
        ),
        findsOneWidget,
      );
      await enter(tester, 'Type name', 'Evening');
      await tap(tester, 'Save');
      await waitForText(tester, 'Evening');
      expect(tester.takeException(), isNull);
      final types = (await runIo(tester, () => f.store.itemTypes()))!;
      expect(types.map((t) => t.name).toSet(), {'Supplements', 'Evening'});
      f.container.read(routerProvider).go('/create?person=$meId');
      await settle(tester);
      await tap(tester, 'Search');
      expect(find.textContaining('catalogue is unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  appTest('loader failure retries a fresh source load and retains query', (
    tester,
  ) async {
    final source = (await runIo(tester, corpus))!;
    addTearDown(() => source.root.delete(recursive: true));
    var attempts = 0;
    final f = await launch(
      tester,
      catalogueLoader: () async {
        attempts++;
        if (attempts == 1) throw StateError('synthetic-open-failure');
        return source.reader;
      },
    );
    f.container.read(routerProvider).go('/create?person=$meId');
    await settle(tester);
    await tap(tester, 'Search');
    await enterSearch(tester, 'Invented amber');
    expect(
      find.text('Unable to search. Try again or enter a custom substance.'),
      findsOneWidget,
    );
    await tap(tester, 'Retry');
    await waitForText(tester, 'Invented amber');
    expect(attempts, 2);
    expect(
      tester.widget<TextField>(catalogueInput()).controller!.text,
      'Invented amber',
    );
    await tap(tester, 'Select');
    expect(find.textContaining('Version: first'), findsOneWidget);
  });

  appTest(
    'disposing picker invalidates late source completion and preserves custom entry',
    (tester) async {
      final source = (await runIo(tester, corpus))!;
      addTearDown(() => source.root.delete(recursive: true));
      final pending = Completer<CatalogueReader?>();
      final f = await launch(tester, catalogueLoader: () => pending.future);
      f.container.read(routerProvider).go('/create?person=$meId');
      await settle(tester);
      await tap(tester, 'Search');
      await enterSearch(tester, 'My custom product');
      await tap(tester, 'Enter');
      pending.complete(source.reader);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Version: first'), findsNothing);
      expect(
        tester.widget<TextField>(input('Full name')).controller!.text,
        'My custom product',
      );
      expect(find.text('Select'), findsNothing);
    },
  );

  testWidgets('typing waits for the bounded debounce and Enter flushes once', (
    tester,
  ) async {
    final source = (await runIo(tester, corpus))!;
    addTearDown(() => source.root.delete(recursive: true));
    final query = TextEditingController();
    final enabled = ValueNotifier(true);
    final handle = FakeCatalogueSearch();
    addTearDown(query.dispose);
    addTearDown(enabled.dispose);
    await pumpCataloguePicker(
      tester,
      reader: source.reader,
      query: query,
      handle: handle,
      enabled: enabled,
      onSelect: (_) {},
    );
    await tester.enterText(catalogueInput(), 'Inv');
    await tester.pump(const Duration(milliseconds: 299));
    expect(handle.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(handle.calls, ['Inv']);
    await tester.enterText(catalogueInput(), 'Invented');
    await tester.pump(const Duration(milliseconds: 299));
    expect(handle.calls, ['Inv']);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(handle.calls, ['Inv', 'Invented']);
    await tester.pump(const Duration(milliseconds: 600));
    expect(handle.calls, ['Inv', 'Invented']);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(handle.calls, ['Inv', 'Invented']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late and out-of-order replies cannot replace the newest query', (
    tester,
  ) async {
    final source = (await runIo(tester, corpus))!;
    addTearDown(() => source.root.delete(recursive: true));
    final query = TextEditingController();
    final enabled = ValueNotifier(true);
    final handle = FakeCatalogueSearch();
    CatalogueSnapshot? selected;
    addTearDown(query.dispose);
    addTearDown(enabled.dispose);
    await pumpCataloguePicker(
      tester,
      reader: source.reader,
      query: query,
      handle: handle,
      enabled: enabled,
      onSelect: (value) => selected = value,
    );
    await tester.enterText(catalogueInput(), 'First');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(catalogueInput(), 'Second');
    await tester.pump(const Duration(milliseconds: 300));
    expect(handle.calls, ['First', 'Second']);
    handle.reply(
      'Second',
      cataloguePage(source.reader, 'Second', name: 'Second product'),
    );
    await tester.pump();
    expect(find.text('Second product'), findsOneWidget);
    handle.fail('First', StateError('stale read'));
    await tester.pump();
    expect(find.text('Second product'), findsOneWidget);
    expect(
      find.text('Unable to search. Try again or enter a custom substance.'),
      findsNothing,
    );
    expect(find.text('Searching the offline catalogue…'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Select'));
    await tester.pump();
    expect(selected!.product.name, 'Second product');
    expect(query.text, 'Second');
    await tester.enterText(catalogueInput(), 'Third');
    await tester.pump(const Duration(milliseconds: 300));
    expect(handle.calls, ['First', 'Second', 'Third']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(handle.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear resets query and results immediately without a read', (
    tester,
  ) async {
    final source = (await runIo(tester, corpus))!;
    addTearDown(() => source.root.delete(recursive: true));
    final query = TextEditingController();
    final enabled = ValueNotifier(true);
    final handle = FakeCatalogueSearch();
    addTearDown(query.dispose);
    addTearDown(enabled.dispose);
    await pumpCataloguePicker(
      tester,
      reader: source.reader,
      query: query,
      handle: handle,
      enabled: enabled,
      onSelect: (_) {},
    );
    await tester.enterText(catalogueInput(), 'Invented amber');
    await tester.pump(const Duration(milliseconds: 300));
    handle.reply(
      'Invented amber',
      cataloguePage(source.reader, 'Invented amber'),
    );
    await tester.pump();
    expect(find.text('Invented amber'), findsWidgets);
    expect(catalogueClear(), findsOneWidget);
    await tester.tap(catalogueClear());
    await tester.pump();
    expect(query.text, isEmpty);
    expect(find.text('Invented amber'), findsNothing);
    expect(
      find.text('Enter a name, form or strength to search offline.'),
      findsOneWidget,
    );
    expect(catalogueClear(), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(handle.calls, ['Invented amber']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disabling cancels a pending debounce and re-enabling searches', (
    tester,
  ) async {
    final source = (await runIo(tester, corpus))!;
    addTearDown(() => source.root.delete(recursive: true));
    final query = TextEditingController();
    final enabled = ValueNotifier(true);
    final handle = FakeCatalogueSearch();
    addTearDown(query.dispose);
    addTearDown(enabled.dispose);
    await pumpCataloguePicker(
      tester,
      reader: source.reader,
      query: query,
      handle: handle,
      enabled: enabled,
      onSelect: (_) {},
    );
    await tester.enterText(catalogueInput(), 'Inv');
    await tester.pump(const Duration(milliseconds: 100));
    enabled.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(handle.calls, isEmpty);
    enabled.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(handle.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(handle.calls, ['Inv']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    're-enable retires an in-flight reply and permits a fresh search',
    (tester) async {
      final source = (await runIo(tester, corpus))!;
      addTearDown(() => source.root.delete(recursive: true));
      final query = TextEditingController();
      final enabled = ValueNotifier(true);
      final handle = FakeCatalogueSearch();
      addTearDown(query.dispose);
      addTearDown(enabled.dispose);
      await pumpCataloguePicker(
        tester,
        reader: source.reader,
        query: query,
        handle: handle,
        enabled: enabled,
        onSelect: (_) {},
      );
      await tester.enterText(catalogueInput(), 'Inv');
      await tester.pump(catalogueSearchDebounce);
      final oldReply = handle.pending['Inv']!;
      enabled.value = false;
      await tester.pump();
      enabled.value = true;
      await tester.pump();
      await tester.pump(catalogueSearchDebounce);
      expect(handle.calls, ['Inv', 'Inv']);
      oldReply.complete(
        cataloguePage(source.reader, 'Inv', name: 'Retired result'),
      );
      await tester.pump();
      expect(find.text('Retired result'), findsNothing);
      handle.reply(
        'Inv',
        cataloguePage(source.reader, 'Inv', name: 'Current result'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current result'), findsOneWidget);
      expect(find.text('Searching the offline catalogue…'), findsNothing);
      query.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(handle.calls, [
        'Inv',
        'Inv',
      ], reason: 'Caret movement is not typing.');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a retained result action cannot select after the query changes',
    (tester) async {
      final source = (await runIo(tester, corpus))!;
      addTearDown(() => source.root.delete(recursive: true));
      final query = TextEditingController();
      final enabled = ValueNotifier(true);
      final handle = FakeCatalogueSearch();
      CatalogueSnapshot? selected;
      addTearDown(query.dispose);
      addTearDown(enabled.dispose);
      await pumpCataloguePicker(
        tester,
        reader: source.reader,
        query: query,
        handle: handle,
        enabled: enabled,
        onSelect: (value) => selected = value,
      );
      await tester.enterText(catalogueInput(), 'Inv');
      await tester.pump(catalogueSearchDebounce);
      handle.reply('Inv', cataloguePage(source.reader, 'Inv'));
      await tester.pump();
      final choose = tester
          .widget<VitalButton>(find.widgetWithText(VitalButton, 'Select'))
          .onPressed!;
      query.text = 'Different';
      choose();
      expect(selected, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('320 wide at 2x shows complete product and source copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final source = (await runIo(tester, corpus))!;
    addTearDown(() => source.root.delete(recursive: true));
    final query = TextEditingController();
    final enabled = ValueNotifier(true);
    final handle = FakeCatalogueSearch();
    addTearDown(query.dispose);
    addTearDown(enabled.dispose);
    await pumpCataloguePicker(
      tester,
      reader: source.reader,
      query: query,
      handle: handle,
      enabled: enabled,
      onSelect: (_) {},
    );
    const name = 'Invented amber extract with a complete descriptive name';
    const form = 'prolonged-release film-coated tablet';
    const strength = '7.5 mg per 5 ml';
    await tester.enterText(catalogueInput(), 'Invented');
    await tester.pump(const Duration(milliseconds: 300));
    handle.reply(
      'Invented',
      cataloguePage(
        source.reader,
        'Invented',
        name: name,
        form: form,
        strength: strength,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('$name. Form: $form. Strength: $strength.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Source: synthetic-fixture. Version: first. Released: 2026-10-19.',
      ),
      findsOneWidget,
    );
    expect(find.text('Attribution: Invented UI test data'), findsOneWidget);
    expect(find.text('Licence: Synthetic test fixture'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (captures.isNotEmpty) {
      final boundary = GlobalKey();
      for (final brightness in Brightness.values) {
        // Remount a real picker for each theme with a fresh synthetic reply.
        final themedHandle = FakeCatalogueSearch();
        final themedQuery = TextEditingController(text: 'Invented');
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpCataloguePicker(
          tester,
          reader: source.reader,
          query: themedQuery,
          handle: themedHandle,
          enabled: enabled,
          onSelect: (_) {},
          brightness: brightness,
          captureKey: boundary,
        );
        themedHandle.reply(
          'Invented',
          cataloguePage(
            source.reader,
            'Invented',
            name: name,
            form: form,
            strength: strength,
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '$captures/${brightness.name}-catalogue-320x2.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        themedQuery.dispose();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
