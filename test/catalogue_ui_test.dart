import 'fixtures/single_user.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/data/catalogue/catalogue_manager.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder input(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);
Future<void> enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(input(label));
  await tester.enterText(input(label), value);
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
  String strength,
) async {
  final notice = File('${root.path}/$version.notice');
  await notice.writeAsString(
    'Synthetic invented test source. Not real medicines.',
  );
  final projection = File('${root.path}/$version.jsonl');
  await projection.writeAsString(
    '${jsonEncode(CatalogueProduct(code: 'fiction-1', conceptClass: 'SYNTHETIC', name: 'Invented amber', form: 'tablet', strength: strength).toJson())}\n',
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

void main() {
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
      await enter(tester, 'Search medicines', 'Unmatched original name');
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
        tester.widget<TextField>(input('Search medicines')).controller!.text,
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
      await enter(tester, 'Search medicines', 'Absent fictional product');
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
      await enter(tester, 'Search medicines', 'Invented amber');
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
    await tester.enterText(input('Search medicines'), 'Invented amber');
    await tester.enterText(input('Search medicines'), 'Newest absent');
    pending.complete(source.reader);
    await settle(tester);
    await waitForText(
      tester,
      'No catalogue match for “Newest absent”. You can enter it as a custom substance.',
    );
    expect(find.text('Invented amber'), findsNothing);
    await tester.enterText(input('Search medicines'), 'Invented amber');
    await tester.enterText(input('Search medicines'), 'Still absent');
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
      await enter(tester, 'Search medicines', 'Invented amber');
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
    await enter(tester, 'Search medicines', 'Invented amber');
    expect(
      find.text('Unable to search. Try again or enter a custom substance.'),
      findsOneWidget,
    );
    await tap(tester, 'Retry');
    await waitForText(tester, 'Invented amber');
    expect(attempts, 2);
    expect(
      tester.widget<TextField>(input('Search medicines')).controller!.text,
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
      await enter(tester, 'Search medicines', 'My custom product');
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
}
