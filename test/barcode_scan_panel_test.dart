import 'dart:io';

import 'package:flutter/widgets.dart'
    show AppLifecycleState, SizedBox, ValueKey, Navigator, PageRouteBuilder;
import 'package:shadcn_flutter/shadcn_flutter.dart' show TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/data/barcode/barcode_links.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/barcode/gtin.dart';
import 'package:true_grit_vital/platform/barcode_camera.dart';

import 'barcode_scan_fixture.dart';

final class _StoreSwitch extends Notifier<RecordStore> {
  _StoreSwitch(this.initial);
  final RecordStore initial;
  @override
  RecordStore build() => initial;
  void set(RecordStore value) => state = value;
}

String gtin13(int serial) {
  final base = '40000000${serial.toString().padLeft(4, '0')}';
  var sum = 0;
  var weight = 3;
  for (var i = base.length - 1; i >= 0; i--) {
    sum += (base.codeUnitAt(i) - 0x30) * weight;
    weight = 4 - weight;
  }
  return '$base${(10 - sum % 10) % 10}';
}

CatalogueSnapshot snapshot(String name, String strength) => CatalogueSnapshot(
  product: CatalogueProduct(
    code: 'synthetic',
    conceptClass: 'SYNTHETIC',
    name: name,
    form: 'tablet',
    strength: strength,
  ),
  manifest: CatalogueManifest(
    version: 'test',
    sourceId: 'synthetic',
    releaseDate: '2026-10-23',
    sourceUrl: 'https://example.invalid',
    sourceSha256: '0' * 64,
    projectionSha256: '0' * 64,
    licence: 'Synthetic',
    attribution: 'Synthetic',
    licenceSha256: '0' * 64,
    recordCount: 1,
    admissionReference: 'test-only',
    synthetic: true,
  ),
);

void main() {
  setUpAll(loadBarcodeFonts);

  late Directory directory;
  late RecordStore store;
  late SubstanceItem first;
  late SubstanceItem second;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-barcode-panel-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (i) => i + 13),
      isNew: true,
    );
    first = await store.createItem(
      commandId: 'first',
      name: 'Synthetic pack one',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
      catalogueSnapshot: snapshot('Synthetic pack one', '25 mg'),
    );
    second = await store.createItem(
      commandId: 'second',
      name: 'Synthetic pack two',
      form: 'capsule',
      unit: 'count',
      type: 'medicine',
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<void> link(Gtin code, SubstanceItem item) =>
      BarcodeLinkRepository(store).link(
        code: code,
        itemId: item.id,
        expectedItemRevision: item.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      );

  testWidgets('a confirmed link shows full identity and requires Use', (
    tester,
  ) async {
    final code = Gtin.tryParse(gtin13(1))!;
    await tester.runAsync(() => link(code, first));
    final probe = BarcodeCameraProbe();
    SubstanceItem? used;
    await pumpBarcodePanel(
      tester,
      store: store,
      probe: probe,
      onUse: (item) {
        used = item;
        return true;
      },
    );
    expect(find.text('Scan pack'), findsOneWidget);
    expect(find.byKey(const ValueKey('barcode-fake-camera')), findsOneWidget);
    probe.detected!([code.printed]);
    await settleBarcode(tester);
    expect(find.text('Review pack'), findsOneWidget);
    expect(find.textContaining('Synthetic pack one'), findsWidgets);
    expect(find.textContaining('25 mg'), findsWidgets);
    expect(used, isNull, reason: 'camera output must not select on its own');
    await tester.tap(find.text('Use'));
    await settleBarcode(tester);
    expect(used?.id, first.id);
  });

  testWidgets('the quick chooser opens Scan and Cancel restores manual entry', (
    tester,
  ) async {
    final probe = BarcodeCameraProbe();
    await pumpQuickChoice(tester, store: store, probe: probe);
    expect(find.textContaining('Synthetic pack one'), findsWidgets);
    await tester.tap(find.text('Scan'));
    await settleBarcode(tester);
    expect(find.text('Scan pack'), findsOneWidget);
    expect(find.byKey(const ValueKey('barcode-fake-camera')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settleBarcode(tester);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.textContaining('Synthetic pack one'), findsWidgets);
    expect(find.text('Create'), findsOneWidget);
    expect(probe.disposed, 1);
  });

  testWidgets('a new link is explicit, durable and then reusable', (
    tester,
  ) async {
    final probe = BarcodeCameraProbe();
    SubstanceItem? used;
    await pumpBarcodePanel(
      tester,
      store: store,
      probe: probe,
      onUse: (item) {
        used = item;
        return true;
      },
    );
    probe.detected!([gtin13(2)]);
    await settleBarcode(tester);
    expect(find.text('Not linked'), findsOneWidget);
    await tester.tap(find.textContaining('Synthetic pack two'));
    await settleBarcode(tester);
    expect(find.text('Review pack'), findsOneWidget);
    expect(find.textContaining('Synthetic pack two'), findsWidgets);
    await tester.tap(find.text('Link'));
    await settleBarcode(tester);
    expect(find.text('Pack linked'), findsOneWidget);
    final links = (await tester.runAsync(
      () => BarcodeLinkRepository(store).load(),
    ))!;
    expect(links.forGtin(Gtin.tryParse(gtin13(2))!), hasLength(1));
    expect(links.forGtin(Gtin.tryParse(gtin13(2))!).single.itemId, second.id);
    await tester.tap(find.text('Use'));
    await settleBarcode(tester);
    expect(used?.id, second.id);
  });

  testWidgets(
    'duplicate detections collapse but distinct codes need a choice',
    (tester) async {
      final firstCode = Gtin.tryParse(gtin13(3))!;
      await tester.runAsync(() => link(firstCode, first));
      final probe = BarcodeCameraProbe();
      await pumpBarcodePanel(tester, store: store, probe: probe);
      probe.detected!([firstCode.printed, firstCode.printed]);
      await settleBarcode(tester);
      expect(find.text('Review pack'), findsOneWidget);
    },
  );

  testWidgets('multiple distinct codes are listed for an explicit choice', (
    tester,
  ) async {
    final firstCode = Gtin.tryParse(gtin13(5))!;
    final secondCode = Gtin.tryParse(gtin13(6))!;
    await tester.runAsync(() => link(secondCode, second));
    final probe = BarcodeCameraProbe();
    await pumpBarcodePanel(tester, store: store, probe: probe);
    probe.detected!([firstCode.printed, secondCode.printed]);
    await settleBarcode(tester);
    expect(find.text('Choose a code'), findsOneWidget);
    await tester.tap(find.textContaining(secondCode.printed));
    await settleBarcode(tester);
    expect(find.text('Review pack'), findsOneWidget);
    expect(find.textContaining('Synthetic pack two'), findsWidgets);
  });

  testWidgets('manual entry validates and follows the same review', (
    tester,
  ) async {
    final code = Gtin.tryParse(gtin13(7))!;
    await tester.runAsync(() => link(code, first));
    final probe = BarcodeCameraProbe();
    await pumpBarcodePanel(tester, store: store, probe: probe);
    await tester.tap(find.text('Enter'));
    await settleBarcode(tester);
    await tester.enterText(find.byType(TextField), '4006381333932');
    await tester.tap(find.text('Check'));
    await settleBarcode(tester);
    expect(find.text('Code not valid'), findsOneWidget);
    await tester.enterText(find.byType(TextField), code.printed);
    await tester.tap(find.text('Check'));
    await settleBarcode(tester);
    expect(find.text('Review pack'), findsOneWidget);
    expect(find.textContaining('Synthetic pack one'), findsWidgets);
  });

  testWidgets('permission denial hides the camera and keeps manual entry', (
    tester,
  ) async {
    final probe = BarcodeCameraProbe();
    await pumpBarcodePanel(tester, store: store, probe: probe);
    probe.failure!(BarcodeCameraFailure.permissionDenied);
    await settleBarcode(tester);
    expect(find.text('Camera blocked'), findsOneWidget);
    expect(find.byKey(const ValueKey('barcode-fake-camera')), findsNothing);
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets(
    'leaving the foreground removes the camera and ignores late results',
    (tester) async {
      final code = Gtin.tryParse(gtin13(12))!;
      await tester.runAsync(() => link(code, first));
      final probe = BarcodeCameraProbe();
      await pumpBarcodePanel(tester, store: store, probe: probe);
      expect(probe.disposed, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleBarcode(tester);
      expect(find.text('Scan paused'), findsOneWidget);
      expect(find.byKey(const ValueKey('barcode-fake-camera')), findsNothing);
      expect(probe.disposed, 1);
      probe.failure!(BarcodeCameraFailure.permissionDenied);
      probe.detected!([code.printed]);
      await settleBarcode(tester);
      expect(find.text('Scan paused'), findsOneWidget);
      expect(find.text('Review pack'), findsNothing);
    },
  );

  testWidgets('an old camera cannot deliver into a restarted scan', (
    tester,
  ) async {
    final code = Gtin.tryParse(gtin13(15))!;
    await tester.runAsync(() => link(code, first));
    final probe = BarcodeCameraProbe();
    await pumpBarcodePanel(tester, store: store, probe: probe);
    final oldDetected = probe.detected!;
    final oldFailure = probe.failure!;
    await tester.tap(find.text('Enter'));
    await settleBarcode(tester);
    await tester.tap(find.text('Camera'));
    await settleBarcode(tester);
    oldDetected([code.printed]);
    oldFailure(BarcodeCameraFailure.permissionDenied);
    await settleBarcode(tester);
    expect(find.text('Scan pack'), findsOneWidget);
    expect(find.byKey(const ValueKey('barcode-fake-camera')), findsOneWidget);
    expect(find.text('Review pack'), findsNothing);
    probe.detected!([code.printed]);
    await settleBarcode(tester);
    expect(find.text('Review pack'), findsOneWidget);
  });

  testWidgets('route disposal tears the camera down', (tester) async {
    final probe = BarcodeCameraProbe();
    await pumpBarcodePanel(tester, store: store, probe: probe);
    expect(probe.mounts, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(probe.disposed, 1);
  });

  testWidgets('a replaced dataset removes the camera and requires a rescan', (
    tester,
  ) async {
    final probe = BarcodeCameraProbe();
    final switchStore = NotifierProvider<_StoreSwitch, RecordStore>(
      () => _StoreSwitch(store),
    );
    final directory2 = await tester.runAsync(
      () => Directory.systemTemp.createTemp('vital-barcode-panel-two-'),
    );
    final secondStore = (await tester.runAsync(
      () => RecordStore.open(
        path: '${directory2!.path}/records.db',
        key: List.generate(32, (i) => i + 17),
        isNew: true,
      ),
    ))!;
    addTearDown(() async {
      await secondStore.close();
      await directory2!.delete(recursive: true);
    });
    final container = await pumpBarcodePanel(
      tester,
      store: store,
      probe: probe,
      storeSource: switchStore,
    );
    expect(find.byKey(const ValueKey('barcode-fake-camera')), findsOneWidget);
    container.read(switchStore.notifier).set(secondStore);
    await settleBarcode(tester);
    expect(find.byKey(const ValueKey('barcode-fake-camera')), findsNothing);
    expect(probe.disposed, 1);
    expect(find.text('Review pack'), findsNothing);
  });

  testWidgets('a lock removes the camera and refuses a late result', (
    tester,
  ) async {
    final code = Gtin.tryParse(gtin13(8))!;
    await tester.runAsync(() => link(code, first));
    final probe = BarcodeCameraProbe();
    final lock = TestAppLock();
    final container = await pumpBarcodePanel(
      tester,
      store: store,
      probe: probe,
      lockFactory: () => lock,
    );
    expect(container.read(appLockProvider).locked, isFalse);
    container.read(appLockProvider.notifier).lock();
    await settleBarcode(tester);
    expect(find.text('App locked'), findsOneWidget);
    expect(find.byKey(const ValueKey('barcode-fake-camera')), findsNothing);
    probe.detected!([code.printed]);
    await settleBarcode(tester);
    expect(find.text('Review pack'), findsNothing);
  });

  testWidgets('a changed substance is reviewed again before Use', (
    tester,
  ) async {
    final code = Gtin.tryParse(gtin13(9))!;
    await tester.runAsync(() => link(code, first));
    final probe = BarcodeCameraProbe();
    SubstanceItem? used;
    await pumpBarcodePanel(
      tester,
      store: store,
      probe: probe,
      onUse: (item) {
        used = item;
        return true;
      },
    );
    probe.detected!([code.printed]);
    await settleBarcode(tester);
    final detail = await tester.runAsync(() => store.itemDetail(first.id));
    await tester.runAsync(
      () => store.saveItemDetail(
        commandId: 'rename',
        itemId: first.id,
        instructions: '',
        notes: '',
        expectedRevision: detail?.revision,
        name: 'Renamed synthetic pack',
        expectedItemRevision: first.revision,
      ),
    );
    await tester.tap(find.text('Use'));
    await settleBarcode(tester);
    expect(used, isNull);
    expect(find.text('The substance changed. Check it again.'), findsOneWidget);
    expect(find.textContaining('Renamed synthetic pack'), findsWidgets);
    await tester.tap(find.text('Use'));
    await settleBarcode(tester);
    expect(used?.name, 'Renamed synthetic pack');
  });

  testWidgets('a wrong link can be changed only through an explicit replace', (
    tester,
  ) async {
    final code = Gtin.tryParse(gtin13(10))!;
    await tester.runAsync(() => link(code, first));
    final probe = BarcodeCameraProbe();
    await pumpBarcodePanel(tester, store: store, probe: probe);
    probe.detected!([code.printed]);
    await settleBarcode(tester);
    await tester.tap(find.text('Change'));
    await settleBarcode(tester);
    await tester.tap(find.textContaining('Synthetic pack two'));
    await settleBarcode(tester);
    await tester.tap(find.text('Link'));
    await settleBarcode(tester);
    expect(find.text('Already linked'), findsOneWidget);
    expect(find.textContaining('Synthetic pack one'), findsWidgets);
    expect(
      (await tester.runAsync(() => BarcodeLinkRepository(store).load()))!
          .forGtin(code)
          .single
          .itemId,
      first.id,
    );
    await tester.tap(find.text('Replace'));
    await settleBarcode(tester);
    expect(find.text('Pack linked'), findsOneWidget);
    expect(
      (await tester.runAsync(() => BarcodeLinkRepository(store).load()))!
          .forGtin(code)
          .single
          .itemId,
      second.id,
    );
  });

  testWidgets('a missing linked substance offers a fresh explicit link', (
    tester,
  ) async {
    final code = Gtin.tryParse(gtin13(11))!;
    await tester.runAsync(
      () => store.writeSetting(
        barcodeLinksSettingKey,
        BarcodeLinkIndex([
          BarcodeLink(
            gtin: code,
            itemId: 'missing-item',
            reviewedName: 'Missing synthetic pack',
            reviewedForm: 'tablet',
            reviewedStrength: '',
            linkedAt: DateTime.utc(2026, 10, 23),
          ),
        ]).encode(),
      ),
    );
    final probe = BarcodeCameraProbe();
    await pumpBarcodePanel(tester, store: store, probe: probe);
    probe.detected!([code.printed]);
    await settleBarcode(tester);
    expect(find.text('Link missing'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
  });
  testWidgets('lock and unlock never revive an old scan review', (
    tester,
  ) async {
    final code = Gtin.tryParse(gtin13(85))!;
    await tester.runAsync(() => link(code, first));
    final probe = BarcodeCameraProbe();
    final lock = TestAppLock();
    final container = await pumpBarcodePanel(
      tester,
      store: store,
      probe: probe,
      lockFactory: () => lock,
    );
    probe.detected!([code.printed]);
    await settleBarcode(tester);
    expect(find.text('Review pack'), findsOneWidget);
    container.read(appLockProvider.notifier).lock();
    lock.reopenForTest();
    await settleBarcode(tester);
    expect(find.text('Review pack'), findsNothing);
    expect(find.text('Scan paused'), findsOneWidget);
    expect(probe.disposed, greaterThan(0));
  });
  testWidgets(
    'covering the route disposes the camera and return requires Rescan',
    (tester) async {
      final probe = BarcodeCameraProbe();
      await pumpBarcodePanel(tester, store: store, probe: probe);
      final navigator = Navigator.of(tester.element(find.text('Scan pack')));
      navigator.push(
        PageRouteBuilder<void>(pageBuilder: (_, _, _) => const SizedBox()),
      );
      await settleBarcode(tester);
      expect(probe.disposed, greaterThan(0));
      navigator.pop();
      await settleBarcode(tester);
      expect(find.text('Scan paused'), findsOneWidget);
      expect(find.byKey(const ValueKey('barcode-fake-camera')), findsNothing);
    },
  );
}
