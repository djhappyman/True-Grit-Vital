import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_source_link.dart';
import 'package:true_grit_vital/features/supporting/supporting_trends.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

/// Captures are opt-in so the default regression run stays fast.
const captures = String.fromEnvironment('VITAL_TREND_SOURCE_CAPTURES');

LabPanelSnapshot panel(
  String id, {
  required String title,
  required String labId,
  required String labName,
  required String unit,
  required String value,
  required SupportingDate collection,
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: title,
  collectionDate: collection,
  reportDate: collection.isPositionable
      ? collection
      : SupportingDate.day(CivilDate(2026, 10, 20)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryId: labId,
    laboratoryName: labName,
    methodId: 'method-a',
    methodText: 'Method A',
    specimenId: 'specimen-a',
    specimenText: 'Serum',
  ),
  results: [
    LabResultSnapshot(
      id: 'result-$id',
      metricId: 'metric',
      markerName: 'Marker',
      originalMarkerText: 'Marker',
      value: SupportingValue.numeric(value),
      unit: unit,
      referenceRange: SourceReferenceRange(originalText: '3 to 7'),
    ),
  ],
);

Future<SupportingRevision> savePanel(
  WidgetTester tester,
  RecordStore store,
  LabPanelSnapshot snapshot, {
  required String command,
}) async {
  final person = (await runIo(tester, () => store.profileById(meId)))!;
  return (await runIo(
    tester,
    () => store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: command,
        generation: store.generation,
        expectedPersonRevision: person.revision,
        expectedRevision: null,
        panel: snapshot,
      ),
    ),
  ))!;
}

String identityOf(SupportingRevision revision) =>
    SupportingComparisonKey.forResult(
      revision,
      revision.snapshot.results.single,
    ).identity;

SupportingTrendGroup selectedGroup(WidgetTester tester) =>
    tester.widget<SupportingPlot>(find.byType(SupportingPlot)).group;

Future<void> selectGroup(WidgetTester tester, String unit) async {
  final target = find.textContaining('Unit: $unit').first;
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

/// Live refresh crosses the store generation and provider rebuild, so wait for
/// a positive on-screen signal instead of asserting against a previous read.
Future<void> waitForWidget(WidgetTester tester, Finder finder) async {
  final elapsed = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw TestFailure('Expected widget did not appear: $finder');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> waitForCondition(
  WidgetTester tester,
  bool Function() condition,
  String reason,
) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw TestFailure('Timed out waiting for $reason');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

Finder tableOpens() => find.descendant(
  of: find
      .ancestor(of: find.text('Table'), matching: find.byType(VitalSection))
      .first,
  matching: find.text('Open'),
);

Finder undatedOpens() => find.descendant(
  of: find
      .ancestor(
        of: find.text('Undated results'),
        matching: find.byType(VitalSection),
      )
      .first,
  matching: find.text('Open'),
);

SupportingDetailPage detail(WidgetTester tester) =>
    tester.widget<SupportingDetailPage>(find.byType(SupportingDetailPage));

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String path,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
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
    await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
          rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
        ))
        .load();
  });
  group('canonical source locations', () {
    test(
      'pin the exact record revision and keep the return context intact',
      () {
        final id = SupportingRecordId(id: 'record-2_A', personId: meId);
        final trends = supportingTrendsLocation(
          personId: meId,
          metricId: 'Marker & unit?/é',
          from: CivilDate(2026, 1, 2),
          before: CivilDate(2026, 12, 31),
          basis: SupportingDateBasis.report,
          group: 'group/id?&é',
          groupPage: 2,
          tablePage: 1,
          undatedPage: 2,
        );
        // The metric, group and nested return all carry reserved characters.
        expect(trends, contains('%26'));
        final parsedTrends = Uri.parse(trends);
        expect(parsedTrends.path, '/supporting/$meId/trends');
        expect(parsedTrends.pathSegments, ['supporting', meId, 'trends']);
        expect(parsedTrends.queryParameters, {
          'metric': 'Marker & unit?/é',
          'from': '2026-01-02',
          'before': '2026-12-31',
          'basis': 'report',
          'group': 'group/id?&é',
          'groupPage': '2',
          'table': '1',
          'undated': '2',
        });

        final source = supportingSourceLocation(
          id,
          revision: 4,
          returnLocation: trends,
        );
        final parsed = Uri.parse(source);
        expect(parsed.path, '/supporting/$meId/record-2_A');
        expect(parsed.pathSegments, ['supporting', meId, 'record-2_A']);
        expect(parsed.queryParameters['revision'], '4');
        // The nested query is one encoded value, not a second unescaped query.
        expect(parsed.queryParameters['return'], trends);
        expect(source.indexOf('?'), source.lastIndexOf('?'));
      },
    );

    test('omit absent revision and default browsing positions', () {
      final id = SupportingRecordId(id: 'record', personId: meId);
      expect(Uri.parse(supportingSourceLocation(id)).queryParameters, isEmpty);
      // Record and owner identifiers are path segments, not concatenated text.
      // The domain admits only [A-Za-z0-9_-], so a valid identity stays intact.
      final reserved = SupportingRecordId(
        id: 'record-2_A',
        personId: 'person-2_A',
      );
      final encoded = Uri.parse(supportingSourceLocation(reserved));
      expect(encoded.pathSegments, [
        'supporting',
        reserved.personId,
        reserved.id,
      ]);
      expect(encoded.queryParameters, isEmpty);
      expect(
        Uri.parse(
          supportingSourceLocation(
            id,
            returnLocation: supportingTrendsLocation(
              personId: meId,
              metricId: 'metric',
              from: CivilDate(2026, 1, 1),
              before: CivilDate(2026, 2, 1),
            ),
          ),
        ).queryParameters.keys,
        ['return'],
      );
      expect(
        Uri.parse(
          supportingTrendsLocation(
            personId: meId,
            metricId: 'metric',
            from: CivilDate(2026, 1, 1),
            before: CivilDate(2026, 2, 1),
          ),
        ).queryParameters,
        {'metric': 'metric', 'from': '2026-01-01', 'before': '2026-02-01'},
      );
      expect(
        () => supportingTrendsLocation(
          personId: meId,
          metricId: 'metric',
          from: CivilDate(2026, 1, 1),
          before: CivilDate(2026, 2, 1),
          basis: SupportingDateBasis.entry,
        ),
        throwsArgumentError,
      );
    });
  });

  appTest(
    'table Open pins the viewed revision and returns to the same basis, group and page',
    (tester) async {
      final f = await launch(tester);
      final today = CivilDate.fromDateTime(DateTime.now());
      SupportingRevision? other;
      for (var index = 0; index < 27; index++) {
        await savePanel(
          tester,
          f.store,
          panel(
            'a${index.toString().padLeft(2, '0')}',
            title: 'Lab ${(index + 1).toString().padLeft(2, '0')}',
            labId: 'lab-a',
            labName: 'Lab One',
            unit: 'mg/L',
            value: '${index + 1}',
            collection: SupportingDate.day(today.addDays(-30 + index)),
          ),
          command: 'save-a-$index',
        );
      }
      other = await savePanel(
        tester,
        f.store,
        panel(
          'other',
          title: 'Lab other',
          labId: 'lab-b',
          labName: 'Lab Two',
          unit: 'g/L',
          value: '2',
          collection: SupportingDate.day(today),
        ),
        command: 'save-other',
      );

      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await waitForWidget(tester, find.text('Lab 01'));
      await settle(tester);

      // Report basis is part of the returned query, not a fresh default.
      await tap(tester, 'Report');
      await settle(tester);
      expect(
        tester
            .widget<VitalSegments<SupportingDateBasis>>(
              find.byType(VitalSegments<SupportingDateBasis>),
            )
            .selected,
        SupportingDateBasis.report,
      );

      await tap(tester, 'Next');
      await settle(tester);
      expect(find.text('Lab other'), findsOneWidget);
      expect(find.text('Lab 01'), findsNothing);

      await selectGroup(tester, 'g/L');
      expect(selectedGroup(tester).key.identity, identityOf(other));

      await tester.ensureVisible(tableOpens().last);
      await settle(tester);
      await tester.tap(tableOpens().last);
      await waitForWidget(tester, find.byType(SupportingDetailPage));
      await settle(tester);

      final opened = detail(tester);
      expect(opened.personId, meId);
      expect(opened.id, 'other');
      expect(opened.revision, other.revision);
      final back = Uri.parse(opened.returnLocation!);
      expect(back.pathSegments, ['supporting', meId, 'trends']);
      // The stored return is the applied report-basis view. Its own From field
      // stays mounted behind the pushed detail instead of being reset.
      expect(back.queryParameters['from'], today.addDays(-365).toString());
      expect(back.queryParameters['metric'], 'metric');
      expect(back.queryParameters['basis'], 'report');
      expect(back.queryParameters['group'], identityOf(other));
      expect(back.queryParameters['table'], '1');

      await tap(tester, 'Back');
      await settle(tester);
      expect(find.byType(SupportingTrendsPage), findsOneWidget);
      expect(find.text('Lab 27'), findsOneWidget);
      expect(find.text('Lab 01'), findsNothing);
      expect(selectedGroup(tester).key.identity, identityOf(other));

      // The same control is keyboard reachable and keeps the page on return.
      final open = tableOpens().last;
      await tester.ensureVisible(open);
      await settle(tester);
      Focus.of(tester.element(open)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.byType(SupportingDetailPage), findsOneWidget);
      await tap(tester, 'Back');
      await settle(tester);
      expect(find.text('Lab other'), findsOneWidget);
      expect(find.text('Lab 01'), findsNothing);
    },
  );

  appTest('malformed return dates require repair before applying a range', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container
        .read(routerProvider)
        .go(
          '/supporting/$meId/trends?metric=metric&from=2026-02-30&before=2026-03-02',
        );
    await settle(tester);
    expect(
      find.text('Enter valid dates. The end date must be after the start.'),
      findsOneWidget,
    );
    final field = find.descendant(
      of: find.widgetWithText(LabelledInput, 'From date'),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller!.text, '2026-02-30');
    expect(find.byType(SupportingPlot), findsNothing);
    await tester.ensureVisible(field);
    await tester.enterText(field, '2026-02-01');
    await tap(tester, 'Apply');
    await settle(tester);
    expect(
      find.text('Enter valid dates. The end date must be after the start.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('out-of-range returned pages clamp after the current rows arrive', (
    tester,
  ) async {
    final f = await launch(tester);
    await savePanel(
      tester,
      f.store,
      panel(
        'clamp-source',
        title: 'Clamped source',
        labId: 'lab',
        labName: 'Synthetic lab',
        unit: 'mg/L',
        value: '3',
        collection: SupportingDate.day(CivilDate(2026, 10, 20)),
      ),
      command: 'clamp-save',
    );
    f.container
        .read(routerProvider)
        .go(
          '/supporting/$meId/trends?metric=metric&from=2026-01-01&before=2027-01-01&table=9999&groupPage=9999&undated=9999',
        );
    await waitForWidget(tester, find.text('Clamped source'));
    expect(tableOpens(), findsOneWidget);
    await tester.ensureVisible(tableOpens());
    await tester.tap(tableOpens());
    await settle(tester);
    final location = f.container.read(routerProvider).routerDelegate.state.uri;
    final back = Uri.parse(location.queryParameters['return']!);
    expect(back.queryParameters.containsKey('table'), isFalse);
    expect(back.queryParameters.containsKey('groupPage'), isFalse);
    expect(back.queryParameters.containsKey('undated'), isFalse);
    expect(tester.takeException(), isNull);
  });

  appTest('duplicate values keep distinct source identities', (tester) async {
    final f = await launch(tester);
    final today = CivilDate.fromDateTime(DateTime.now());
    final first = await savePanel(
      tester,
      f.store,
      panel(
        'first',
        title: 'Same panel',
        labId: 'lab-a',
        labName: 'Lab One',
        unit: 'mg/L',
        value: '2',
        collection: SupportingDate.day(today.addDays(-2)),
      ),
      command: 'save-first',
    );
    final second = await savePanel(
      tester,
      f.store,
      panel(
        'second',
        title: 'Same panel',
        labId: 'lab-a',
        labName: 'Lab One',
        unit: 'mg/L',
        value: '2',
        collection: SupportingDate.day(today.addDays(-2)),
      ),
      command: 'save-second',
    );
    expect(identityOf(first), identityOf(second));

    f.container
        .read(routerProvider)
        .go('/supporting/$meId/trends?metric=metric');
    await waitForWidget(tester, find.text('Table'));
    await waitForWidget(tester, tableOpens());
    await settle(tester);
    expect(tableOpens(), findsNWidgets(2));

    final opened = <String>{};
    for (var index = 0; index < 2; index++) {
      await tester.ensureVisible(tableOpens().at(index));
      await settle(tester);
      await tester.tap(tableOpens().at(index));
      await waitForWidget(tester, find.byType(SupportingDetailPage));
      await settle(tester);
      final page = detail(tester);
      opened.add('${page.id}@${page.revision}');
      expect(page.personId, first.id.personId);
      expect(page.returnLocation, contains('metric=metric'));
      await tap(tester, 'Back');
      await settle(tester);
    }
    expect(opened, {
      '${first.id.id}@${first.revision}',
      '${second.id.id}@${second.revision}',
    });
  });

  appTest('an undated source opens its own record', (tester) async {
    final f = await launch(tester);
    final undated = await savePanel(
      tester,
      f.store,
      panel(
        'undated',
        title: 'Undated panel',
        labId: 'lab-a',
        labName: 'Lab One',
        unit: 'mg/L',
        value: '2',
        collection: SupportingDate.unknown(originalText: 'No date given'),
      ),
      command: 'save-undated',
    );
    f.container
        .read(routerProvider)
        .go('/supporting/$meId/trends?metric=metric');
    await waitForWidget(tester, find.text('Undated results'));
    await waitForWidget(tester, undatedOpens());
    await settle(tester);
    expect(find.text('Undated panel'), findsOneWidget);
    await tester.ensureVisible(undatedOpens().first);
    await settle(tester);
    await tester.tap(undatedOpens().first);
    await waitForWidget(tester, find.byType(SupportingDetailPage));
    await settle(tester);
    expect(detail(tester).id, undated.id.id);
    expect(detail(tester).revision, undated.revision);
    await tap(tester, 'Back');
    await settle(tester);
    expect(find.text('Undated panel'), findsOneWidget);
  });

  appTest('a direct source link returns to the exact trend view', (
    tester,
  ) async {
    final f = await launch(tester);
    final today = CivilDate.fromDateTime(DateTime.now());
    SupportingRevision? chosen;
    for (var index = 0; index < 27; index++) {
      final saved = await savePanel(
        tester,
        f.store,
        panel(
          'b${index.toString().padLeft(2, '0')}',
          title: 'Lab ${(index + 1).toString().padLeft(2, '0')}',
          labId: 'lab-a',
          labName: 'Lab One',
          unit: 'mg/L',
          value: '${index + 1}',
          collection: SupportingDate.day(today.addDays(-30 + index)),
        ),
        command: 'save-b-$index',
      );
      chosen = saved;
    }
    final returnLocation = supportingTrendsLocation(
      personId: meId,
      metricId: 'metric',
      from: today.addDays(-31),
      before: today.addDays(3),
      basis: SupportingDateBasis.report,
      group: identityOf(chosen!),
      tablePage: 1,
    );
    f.container
        .read(routerProvider)
        .go(
          supportingSourceLocation(
            chosen.id,
            revision: chosen.revision,
            returnLocation: returnLocation,
          ),
        );
    await waitForWidget(tester, find.byType(SupportingDetailPage));
    await settle(tester);
    expect(detail(tester).returnLocation, returnLocation);

    await tap(tester, 'Back');
    await waitForWidget(tester, find.byType(SupportingTrendsPage));
    await settle(tester);
    expect(
      tester
          .widget<VitalSegments<SupportingDateBasis>>(
            find.byType(VitalSegments<SupportingDateBasis>),
          )
          .selected,
      SupportingDateBasis.report,
    );
    expect(selectedGroup(tester).key.identity, identityOf(chosen));
    expect(find.text('Lab 27'), findsOneWidget);
    expect(find.text('Lab 01'), findsNothing);
    final fromField = find.descendant(
      of: find.widgetWithText(LabelledInput, 'From date'),
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(fromField).controller!.text,
      today.addDays(-31).toString(),
    );
    expect(tester.takeException(), isNull);
  });

  appTest('a locked trend does not open a stale source', (tester) async {
    final f = await launch(tester, auth: FakeAuth());
    final today = CivilDate.fromDateTime(DateTime.now());
    final saved = await savePanel(
      tester,
      f.store,
      panel(
        'locked',
        title: 'Locked panel',
        labId: 'lab-a',
        labName: 'Lab One',
        unit: 'mg/L',
        value: '2',
        collection: SupportingDate.day(today.addDays(-2)),
      ),
      command: 'save-locked',
    );
    await runIo(tester, () => f.store.writeSetting('app_lock', 'true'));
    f.container.invalidate(appLockProvider);
    await waitForCondition(
      tester,
      () => f.container.read(appLockProvider).ready,
      'the lock preference',
    );
    expect(f.container.read(appLockProvider).locked, isTrue);
    await f.container.read(appLockProvider.notifier).unlock();
    await waitForCondition(
      tester,
      () => !f.container.read(appLockProvider).locked,
      'the unlocked session',
    );

    f.container
        .read(routerProvider)
        .go('/supporting/$meId/trends?metric=metric');
    await waitForWidget(tester, find.text('Table'));
    await waitForWidget(tester, tableOpens());
    await settle(tester);
    expect(find.text(saved.snapshot.title), findsOneWidget);

    // The lifecycle lock lands after the frame that showed Open. The mounted
    // control must not navigate from that now-private frame, even if a stale
    // callback is invoked directly.
    final openButton = tester.widget<VitalButton>(
      find
          .ancestor(of: tableOpens().first, matching: find.byType(VitalButton))
          .first,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(f.container.read(appLockProvider).locked, isTrue);
    openButton.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(SupportingDetailPage), findsNothing);
    expect(find.widgetWithText(VitalButton, 'Unlock'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.byType(SupportingDetailPage), findsNothing);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('source return fits ${theme.name} at 320 px and double text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final f = await launch(tester);
      final boundaryKey = GlobalKey();
      if (captures.isNotEmpty) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
          ),
        );
      }
      final today = CivilDate.fromDateTime(DateTime.now());
      await savePanel(
        tester,
        f.store,
        panel(
          'narrow-a',
          title: 'Long original laboratory panel name',
          labId: 'lab-a',
          labName: 'Long laboratory source name',
          unit: 'umol/L',
          value: '12.5',
          collection: SupportingDate.day(today.addDays(-3)),
        ),
        command: 'save-narrow-a',
      );
      await savePanel(
        tester,
        f.store,
        panel(
          'narrow-b',
          title: 'Long original laboratory panel name',
          labId: 'lab-a',
          labName: 'Long laboratory source name',
          unit: 'umol/L',
          value: '14.5',
          collection: SupportingDate.day(today.addDays(-1)),
        ),
        command: 'save-narrow-b',
      );
      f.container.read(appearanceProvider.notifier).setMode(theme);
      f.container.read(appearanceProvider.notifier).setReduceMotion(true);
      f.container
          .read(routerProvider)
          .go('/supporting/$meId/trends?metric=metric');
      await waitForWidget(tester, find.text('Table'));
      await waitForWidget(tester, tableOpens());
      await settle(tester);
      expect(find.text('Open'), findsWidgets);
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-trends-320x2.png',
        );
      }
      await tester.ensureVisible(tableOpens().first);
      await settle(tester);
      await tester.tap(tableOpens().first);
      await waitForWidget(tester, find.byType(SupportingDetailPage));
      await settle(tester);
      expect(find.text('Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-source-320x2.png',
        );
      }
      await tap(tester, 'Back');
      await settle(tester);
      expect(find.textContaining('Unit: umol/L'), findsWidgets);
      expect(tester.takeException(), isNull);

      // A wider phone keeps the same controls at double text.
      tester.view.physicalSize = const Size(430, 900);
      await settle(tester);
      await tester.ensureVisible(tableOpens().first);
      await settle(tester);
      await tester.tap(tableOpens().first);
      await waitForWidget(tester, find.byType(SupportingDetailPage));
      await settle(tester);
      expect(find.text('Back'), findsOneWidget);
      await tap(tester, 'Back');
      await settle(tester);
      expect(find.text('Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
