import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show GlobalKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode;
import 'package:true_grit_vital/data/barcode/barcode_links.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/barcode/gtin.dart';
import 'package:true_grit_vital/platform/barcode_camera.dart';

import 'barcode_scan_fixture.dart';
import 'barcode_scan_panel_test.dart' show gtin13, snapshot;

void main() {
  setUpAll(loadBarcodeFonts);

  testWidgets('barcode scanner states are readable in both themes', (
    tester,
  ) async {
    const output = String.fromEnvironment('VITAL_R04_CAPTURES');
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('vital-barcode-capture-'),
    ))!;
    addTearDown(() => directory.delete(recursive: true));
    final store = (await tester.runAsync(
      () => RecordStore.open(
        path: '${directory.path}/records.db',
        key: List.generate(32, (i) => i + 19),
        isNew: true,
      ),
    ))!;
    addTearDown(store.close);
    final linked = Gtin.tryParse(gtin13(21))!;
    final unlinked = Gtin.tryParse(gtin13(22))!;
    await tester.runAsync(() async {
      await store.createItem(
        commandId: 'capture-item',
        name: 'Synthetic heart medicine',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
        catalogueSnapshot: snapshot('Synthetic heart medicine', '12.5 mg'),
      );
      await store.createItem(
        commandId: 'capture-second',
        name: 'Synthetic evening capsule',
        form: 'capsule',
        unit: 'count',
        type: 'medicine',
      );
      final first = (await store.items()).firstWhere(
        (item) => item.name == 'Synthetic heart medicine',
      );
      await BarcodeLinkRepository(store).link(
        code: linked,
        itemId: first.id,
        expectedItemRevision: first.revision,
        expectedDetailRevision: 0,
        replace: false,
        canCommit: () => true,
      );
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final narrow in [false, true]) {
        final key = GlobalKey();
        final probe = BarcodeCameraProbe();
        await pumpBarcodePanel(
          tester,
          store: store,
          probe: probe,
          captureKey: key,
          brightness: mode == ThemeMode.dark
              ? ui.Brightness.dark
              : ui.Brightness.light,
          size: Size(narrow ? 320 : 390, narrow ? 1100 : 844),
          textScale: narrow ? 2 : 1,
        );
        await _capture(tester, key, output, mode, narrow, 'camera');
        probe.detected!([linked.printed]);
        await settleBarcode(tester);
        await _capture(tester, key, output, mode, narrow, 'review');
        await tester.tap(find.text('Rescan'));
        await settleBarcode(tester);
        probe.detected!([unlinked.printed]);
        await settleBarcode(tester);
        await _capture(tester, key, output, mode, narrow, 'not-linked');
      }
    }

    final probe = BarcodeCameraProbe();
    final key = GlobalKey();
    await pumpBarcodePanel(tester, store: store, probe: probe, captureKey: key);
    probe.failure!(BarcodeCameraFailure.permissionDenied);
    await settleBarcode(tester);
    await _capture(tester, key, output, ThemeMode.light, false, 'permission');
  });
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String output,
  ThemeMode mode,
  bool narrow,
  String state,
) async {
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '$output/${mode.name}-${narrow ? '320-2x' : '390'}-$state.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
