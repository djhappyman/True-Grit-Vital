import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/today_hero.dart'
    show todayNowProvider;
import 'package:true_grit_vital/features/reports/report_item_seed.dart';
import 'package:true_grit_vital/platform/device_zone.dart'
    show DeviceZoneObservation;
import 'package:true_grit_vital/platform/artifact_transfer.dart'
    show UnsupportedArtifactTransfer;
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captureDirectory = String.fromEnvironment('VITAL_REPORT_ITEM_CAPTURE');
const _fixtureRevision = 2;

DateTime _now() => DateTime.utc(2026, 10, 20, 12);

SubstanceItem _item({
  String id = 'synthetic-item',
  String name = 'Synthetic long substance name',
  String personId = meId,
}) => SubstanceItem(
  id: id,
  personId: personId,
  name: name,
  form: 'Capsule',
  unit: 'mg',
  type: 'Medicine',
);

Future<SubstanceItem> _createItem(
  WidgetTester tester,
  RecordStore store, {
  required String commandId,
  required String name,
}) async => (await runIo(
  tester,
  () => store.createItem(
    expectedPersonRevision: _fixtureRevision,
    commandId: commandId,
    name: name,
    form: 'Capsule',
    unit: 'mg',
    type: 'Medicine',
  ),
))!;

Future<void> _openOverview(
  WidgetTester tester,
  ProviderContainer container,
  SubstanceItem item,
) async {
  container.read(routerProvider).push('/substance/${item.id}');
  await settle(tester);
  await waitForText(tester, item.name);
  await waitForText(tester, 'Record');
}

/// Launcher for the busy state. The shared launcher cannot inject a pending
/// capture, and Riverpod cannot add an override after the container is built.
Future<({RecordStore store, ProviderContainer container})> _launchWithCapture(
  WidgetTester tester,
  Future<ReportCapture> Function() capture,
) async {
  final directory = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-report-item-'),
  ))!;
  final store = (await runIo(
    tester,
    () => RecordStore.open(
      path: '${directory.path}/test.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    ),
  ))!;
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
  final container = ProviderContainer(
    overrides: [
      todayNowProvider.overrideWithValue(_now),
      appAuthGatewayProvider.overrideWithValue(FakeAuth()),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      storeLoaderProvider.overrideWithValue(() => Future.value(store)),
      artifactTransferGatewayProvider.overrideWithValue(
        const UnsupportedArtifactTransfer(),
      ),
      reportCaptureProvider.overrideWithValue((request) => capture()),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await runIo(tester, store.close);
    await directory.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  return (store: store, container: container);
}

Future<void> _openReport(WidgetTester tester, SubstanceItem item) async {
  await tap(tester, 'More');
  await settle(tester);
  await tap(tester, 'Report');
  await settle(tester);
}

Future<void> _selectSection(WidgetTester tester, String label) async {
  final target = find.descendant(
    of: find.byType(VitalSegments<int>),
    matching: find.text(label),
  );
  await tester.tap(target.first);
  await settle(tester);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (captureDirectory.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    if (captureDirectory.isEmpty) return;
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
    await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
          rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
        ))
        .load();
  });

  group('single-item report seed', () {
    test('uses the existing default range, display zone and exact item', () {
      final plan = itemReportPlan(
        item: _item(id: 'exact-item'),
        displayZone: 'Europe/London',
        now: DateTime.utc(2026, 10, 20, 23, 30),
      ) as ItemReportReady;
      expect(plan.selection.template, ReportTemplateId.r01SubstanceSummary);
      expect(plan.selection.personId, meId);
      // The display projection is the next London civil day, not the UTC day.
      expect(plan.selection.fromDate, CivilDate(2026, 1, 1));
      expect(plan.selection.beforeDate, CivilDate(2026, 10, 22));
      expect(plan.selection.displayZone, 'Europe/London');
      expect(plan.selection.itemIds, {'exact-item'});
      expect(plan.selection.includeNotes, isFalse);
      expect(plan.selection.includeAttachments, isFalse);
      expect(plan.selection.includeSupporting, isFalse);
      expect(plan.selection.includeStock, isFalse);
    });

    test('an unavailable zone is reported instead of guessing a date', () {
      final plan = itemReportPlan(
        item: _item(),
        displayZone: 'Nowhere/Synthetic',
        now: _now(),
      );
      expect(plan, isA<ItemReportBlocked>());
      expect(
        (plan as ItemReportBlocked).reason,
        ItemReportBlock.zoneUnavailable,
      );
    });

    test('an unrepresentable range edge fails truthfully', () {
      final plan = itemReportPlan(
        item: _item(),
        displayZone: 'UTC',
        now: DateTime.utc(9999, 12, 31, 12),
      );
      expect(plan, isA<ItemReportBlocked>());
      expect(
        (plan as ItemReportBlocked).reason,
        ItemReportBlock.rangeUnavailable,
      );
    });

    test('the report location round-trips the exact item and return path', () {
      final plan = itemReportPlan(
        item: _item(id: 'item_01-A'),
        displayZone: 'Europe/London',
        now: _now(),
      ) as ItemReportReady;
      final location = itemReportLocation(
        plan: plan,
        returnLocation: '/substance/item_01-A?section=2&name=a b',
      );
      final uri = Uri.parse(location);
      expect(uri.path, '/reports');
      expect(uri.queryParameters['item'], 'item_01-A');
      expect(uri.queryParameters['template'], 'summary');
      expect(uri.queryParameters['from'], '2026-01-01');
      expect(uri.queryParameters['before'], '2026-10-21');
      expect(
        uri.queryParameters['return'],
        '/substance/item_01-A?section=2&name=a b',
      );
      expect(reportItemId('bad/id'), isNull);
      expect(reportItemId(''), isNull);
      expect(reportItemId(null), isNull);
    });

    test('a foreign item is not treated as the owner item', () {
      expect(reportItemOwnedBy(_item(personId: 'other'), meId), isFalse);
      expect(reportItemOwnedBy(_item(), meId), isTrue);
      expect(reportItemOwnedBy(null, meId), isFalse);
    });
  });

  appTest('overview Report seeds only this item and never generates', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final item = await _createItem(
      tester,
      f.store,
      commandId: 'report-item',
      name: 'Synthetic long substance name',
    );
    await _openOverview(tester, f.container, item);
    await _openReport(tester, item);

    final uri = f.container.read(routerProvider).routerDelegate.state.uri;
    expect(uri.path, '/reports');
    expect(uri.queryParameters['item'], item.id);
    expect(uri.queryParameters['from'], '2026-01-01');
    expect(uri.queryParameters['before'], '2026-10-21');
    expect(uri.queryParameters['return'], '/substance/${item.id}');

    final selection = f.container.read(reportControllerProvider).selection!;
    expect(selection.template, ReportTemplateId.r01SubstanceSummary);
    expect(selection.fromDate, CivilDate(2026, 1, 1));
    expect(selection.beforeDate, CivilDate(2026, 10, 21));
    expect(selection.displayZone, 'Europe/London');
    expect(selection.itemIds, {item.id});
    expect(selection.includeNotes, isFalse);
    expect(selection.includeAttachments, isFalse);
    expect(selection.includeSupporting, isFalse);
    expect(selection.includeStock, isFalse);
    final state = f.container.read(reportControllerProvider);
    expect(state.phase, ReportPhase.idle);
    expect(state.artifact, isNull);
    expect(find.text('Report item'), findsOneWidget);
    expect(find.text(item.name), findsWidgets);
    expect(find.text('Only this item is included.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('missing and malformed item links never select all items', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final router = f.container.read(routerProvider);
    router.push(
      '/reports?item=missing-target&return=/substance/missing-target',
    );
    await settle(tester);
    await waitForText(
      tester,
      'This item is unavailable. It may have been deleted. '
      'Go back and choose another report.',
    );
    expect(f.container.read(reportControllerProvider).selection, isNull);
    expect(find.text('All items'), findsNothing);
    expect(find.text('Preview'), findsNothing);

    router.go('/reports?item=bad%2Ftarget');
    await settle(tester);
    await waitForText(
      tester,
      'This item link is not valid. Go back and choose another report.',
    );
    expect(f.container.read(reportControllerProvider).selection, isNull);
    expect(find.text('All items'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('a different report draft needs explicit Replace', (tester) async {
    final f = await launch(tester, todayClock: _now);
    final item = await _createItem(
      tester,
      f.store,
      commandId: 'replace-item',
      name: 'Replacement report item',
    );
    final router = f.container.read(routerProvider);
    router.push('/reports?from=2025-01-01&before=2025-02-01');
    await settle(tester);
    final existing = f.container.read(reportControllerProvider).selection!;
    expect(existing.fromDate, CivilDate(2025, 1, 1));

    await _openOverview(tester, f.container, item);
    await _openReport(tester, item);
    expect(find.text('Replace report?'), findsOneWidget);
    expect(
      find.text(
        'The report editor has a different selection. '
        'Replace it with this item report?',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Cancel');
    await settle(tester);
    expect(router.routerDelegate.state.uri.path, '/substance/${item.id}');
    expect(
      f.container.read(reportControllerProvider).selection!.identity,
      existing.identity,
    );

    await _openReport(tester, item);
    await tap(tester, 'Replace');
    await settle(tester);
    expect(router.routerDelegate.state.uri.path, '/reports');
    final replaced = f.container.read(reportControllerProvider);
    expect(replaced.selection!.itemIds, {item.id});
    expect(replaced.phase, ReportPhase.idle);
    expect(replaced.artifact, isNull);
    expect(tester.takeException(), isNull);
  });

  appTest('a direct item link keeps an active draft until Replace', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final item = await _createItem(
      tester,
      f.store,
      commandId: 'direct-item',
      name: 'Direct item report',
    );
    final router = f.container.read(routerProvider);
    router.push('/reports?from=2025-01-01&before=2025-02-01');
    await settle(tester);
    final existing = f.container.read(reportControllerProvider).selection!;
    router.push(
      '/reports?item=${item.id}&template=event&from=2026-01-01&before=2026-10-21',
    );
    await settle(tester);
    expect(find.text('Report selected'), findsOneWidget);
    expect(find.text('Requested item: ${item.name}'), findsOneWidget);
    expect(
      f.container.read(reportControllerProvider).selection!.identity,
      existing.identity,
    );
    await tap(tester, 'Replace');
    await settle(tester);
    expect(f.container.read(reportControllerProvider).selection!.itemIds, {
      item.id,
    });
    expect(
      f.container.read(reportControllerProvider).selection!.template,
      ReportTemplateId.r01SubstanceSummary,
    );
    expect(find.text('Only this item is included.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('an impossible item range fails truthfully without throwing', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final item = await _createItem(
      tester,
      f.store,
      commandId: 'edge-item',
      name: 'Edge range item',
    );
    f.container
        .read(routerProvider)
        .push('/reports?item=${item.id}&from=9999-12-31&before=9999-12-31');
    await settle(tester);
    await waitForText(
      tester,
      'The report dates are unavailable. Check the link, then try again.',
    );
    expect(f.container.read(reportControllerProvider).selection, isNull);
    expect(find.text('All items'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('a busy report blocks the item shortcut without replacing it', (
    tester,
  ) async {
    final capture = Completer<ReportCapture>();
    final f = await _launchWithCapture(tester, () => capture.future);
    final item = await _createItem(
      tester,
      f.store,
      commandId: 'busy-item',
      name: 'Busy report item',
    );
    final router = f.container.read(routerProvider);
    router.push('/reports?from=2025-01-01&before=2025-02-01');
    await settle(tester);
    f.container
        .read(reportControllerProvider.notifier)
        .generate(use24Hour: true);
    await settle(tester);
    expect(f.container.read(reportControllerProvider).busy, isTrue);

    await _openOverview(tester, f.container, item);
    await _openReport(tester, item);
    expect(find.text('Report in progress'), findsOneWidget);
    expect(find.text('Replace report?'), findsNothing);
    expect(
      f.container.read(reportControllerProvider).selection!.fromDate,
      CivilDate(2025, 1, 1),
    );
    await tap(tester, 'Done');
    await settle(tester);
    expect(router.routerDelegate.state.uri.path, '/substance/${item.id}');

    f.container.read(reportControllerProvider.notifier).cancel();
    capture.completeError(const ReportCancelled());
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  appTest('locking during replacement cancels the item seed', (tester) async {
    final f = await launch(tester, auth: FakeAuth(), todayClock: _now);
    final item = await _createItem(
      tester,
      f.store,
      commandId: 'locked-item',
      name: 'Locked report item',
    );
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    final router = f.container.read(routerProvider);
    router.push('/reports?from=2025-01-01&before=2025-02-01');
    await settle(tester);
    await _openOverview(tester, f.container, item);
    await _openReport(tester, item);
    expect(find.text('Replace report?'), findsOneWidget);
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Replace report?'), findsNothing);
    expect(find.text('Unlock').hitTestable(), findsWidgets);
    expect(f.container.read(reportControllerProvider).selection, isNull);
    expect(tester.takeException(), isNull);
  });

  appTest('the same selection opens without a replacement question', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final item = await _createItem(
      tester,
      f.store,
      commandId: 'same-item',
      name: 'Same report item',
    );
    final router = f.container.read(routerProvider);
    await _openOverview(tester, f.container, item);
    await _openReport(tester, item);
    final seeded = f.container.read(reportControllerProvider).selection!;

    router.push('/substance/${item.id}');
    await settle(tester);
    await waitForText(tester, item.name);
    await _openReport(tester, item);
    expect(find.text('Replace report?'), findsNothing);
    expect(find.text('Report item'), findsOneWidget);
    expect(
      f.container.read(reportControllerProvider).selection!.identity,
      seeded.identity,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('Back keeps the overview section that opened the report', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final item = await _createItem(
      tester,
      f.store,
      commandId: 'section-item',
      name: 'Section report item',
    );
    await _openOverview(tester, f.container, item);
    await _selectSection(tester, 'Stock');
    expect(
      tester
          .widget<VitalSegments<int>>(find.byType(VitalSegments<int>))
          .selected,
      2,
    );
    await _openReport(tester, item);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/reports',
    );
    await tap(tester, 'Back');
    await settle(tester);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/substance/${item.id}',
    );
    expect(
      tester
          .widget<VitalSegments<int>>(find.byType(VitalSegments<int>))
          .selected,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'the item report keeps its full name at 320, 390 and 430 in ${mode.name}',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final f = await launch(tester, todayClock: _now);
        final item = await _createItem(
          tester,
          f.store,
          commandId: 'narrow-${mode.name}',
          name: 'Long synthetic substance name kept in full',
        );
        f.container.read(appearanceProvider.notifier).setMode(mode);
        await _openOverview(tester, f.container, item);
        await _openReport(tester, item);
        for (final width in [320.0, 390.0, 430.0]) {
          tester.view.physicalSize = Size(width, 740);
          await settle(tester);
          expect(find.text(item.name), findsWidgets);
          expect(find.text('Report item'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('item report captures use synthetic records in ${mode.name}', (
      tester,
    ) async {
      if (captureDirectory.isEmpty) return;
      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester, todayClock: _now);
      final item = await _createItem(
        tester,
        f.store,
        commandId: 'capture-${mode.name}',
        name: 'Synthetic long substance name',
      );
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      await _openOverview(tester, f.container, item);
      await _capture(tester, boundaryKey, '${mode.name}-item-report-action');
      await _openReport(tester, item);
      await waitForText(tester, 'Report item');
      await _capture(tester, boundaryKey, '${mode.name}-item-report');
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settle(tester);
      expect(tester.takeException(), isNull);
      await _capture(tester, boundaryKey, '${mode.name}-item-report-narrow');
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(390, 844);
      await settle(tester);
      f.container
          .read(routerProvider)
          .go('/reports?item=missing-target&return=/substance/${item.id}');
      await settle(tester);
      await waitForText(
        tester,
        'This item is unavailable. It may have been deleted. '
        'Go back and choose another report.',
      );
      await _capture(
        tester,
        boundaryKey,
        '${mode.name}-item-report-unavailable',
      );
    });
  }
}
