import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/supporting/screen_panel_widgets.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/features/supporting/supporting_source_link.dart';

import 'app_lock_controller_test.dart' show ControlledAuth;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const _marker = 'Earlier comparison marker';
const _value = '1.25';
const _origin =
    '/supporting?person=me&kind=labPanel&basis=collection'
    '&unknown=false&voided=false&from=2026-01-01&before=2026-12-31';

String _sourceKey(String record, String result) =>
    'screen-panel-source-$record-$result';

SupportingRevision _panel(
  String id,
  int day, {
  required String title,
  String value = _value,
  String? unit = 'mg/L',
  bool withRange = true,
  String metric = 'prior-marker',
}) => SupportingRevision(
  snapshot: LabPanelSnapshot(
    id: SupportingRecordId(id: id, personId: meId),
    title: title,
    collectionDate: SupportingDate.day(CivilDate(2026, 10, day)),
    reportDate: SupportingDate.unknown(),
    provenance: SupportingProvenance(
      mode: SupportingProvenanceMode.manualTranscription,
      laboratoryId: 'lab',
      methodId: 'method',
      specimenId: 'serum',
    ),
    results: [
      LabResultSnapshot(
        id: 'result-$id',
        metricId: metric,
        markerName: _marker,
        value: SupportingValue.numeric(value),
        unit: unit,
        referenceRange: withRange
            ? SourceReferenceRange(originalText: '1.0 - 2.0')
            : null,
      ),
    ],
  ),
  revision: 1,
  operationId: '$id-1',
  enteredAt: DateTime.utc(2026),
  revisionEnteredAt: DateTime.utc(2026),
);

Future<void> _save(
  WidgetTester tester,
  RecordStore store,
  List<SupportingRevision> records,
) async {
  final owner = (await runIo(tester, () => store.profileById(meId)))!;
  for (final record in records) {
    await runIo(
      tester,
      () => store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'save-${record.id.id}',
          generation: store.generation,
          expectedPersonRevision: owner.revision,
          panel: record.snapshot as LabPanelSnapshot,
        ),
      ),
    );
  }
}

Future<void> _openViewed(
  WidgetTester tester,
  ({RecordStore store, ProviderContainer container, String path, List<int> key})
  f,
) async {
  f.container
      .read(routerProvider)
      .go(
        Uri(
          path: '/supporting/me/viewed',
          queryParameters: {'return': _origin},
        ).toString(),
      );
  await waitForText(tester, 'Current saved panel');
}

void main() {
  test('source URI keeps the earlier identity and the nested return URL', () {
    final source = SupportingRecordId(personId: meId, id: 'prior-b');
    final current = Uri(
      path: '/supporting/me/viewed',
      queryParameters: {'return': _origin},
    ).toString();
    final uri = Uri.parse(
      supportingSourceLocation(source, returnLocation: current),
    );
    expect(uri.pathSegments, ['supporting', meId, 'prior-b']);
    expect(uri.queryParameters['return'], current);
    expect(
      Uri.parse(uri.queryParameters['return']!).queryParameters['return'],
      _origin,
    );
  });

  setUpAll(loadFonts);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'panel comparison opens the newest duplicate value and returns through '
      'the filtered detail in ${mode.name}',
      (tester) async {
        final handle = tester.ensureSemantics();
        final f = await launch(tester);
        await _save(tester, f.store, [
          _panel('prior-a', 10, title: 'Oldest saved panel'),
          _panel('prior-b', 12, title: 'Earlier saved panel'),
          _panel('viewed', 15, title: 'Current saved panel'),
        ]);
        f.container.read(appearanceProvider.notifier).setMode(mode);
        await _openViewed(tester, f);
        await waitForText(tester, 'Change: 0.');
        await tap(tester, 'With range (1)');
        expect(
          tester
              .widget<ScreenPanelFilters>(find.byType(ScreenPanelFilters))
              .selected,
          ScreenPanelResultFilter.withRange,
        );

        final source = find.byKey(
          ValueKey(_sourceKey('prior-b', 'result-prior-b')),
        );
        expect(source, findsOneWidget);
        expect(
          find.byKey(ValueKey(_sourceKey('prior-a', 'result-prior-a'))),
          findsNothing,
        );
        expect(tester.getSize(source).height, greaterThanOrEqualTo(48));
        final data = tester.getSemantics(source).getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.label, contains('Earlier saved panel'));
        expect(data.label, contains('$_value mg/L'));

        final focusNode = Focus.of(
          tester.element(
            find.descendant(of: source, matching: find.text('Open')),
          ),
        );
        focusNode.requestFocus();
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);

        final prior = tester.widget<SupportingDetailPage>(
          find.byType(SupportingDetailPage),
        );
        expect(prior.id, 'prior-b');
        expect(prior.personId, meId);
        final returned = Uri.parse(prior.returnLocation!);
        expect(returned.path, '/supporting/me/viewed');
        expect(returned.queryParameters['return'], _origin);
        expect(find.text('Earlier saved panel'), findsOneWidget);
        expect(find.text('$_value mg/L'), findsOneWidget);

        await tap(tester, 'Back');
        await settle(tester);
        final viewed = tester.widget<SupportingDetailPage>(
          find.byType(SupportingDetailPage),
        );
        expect(viewed.id, 'viewed');
        expect(
          tester
              .widget<ScreenPanelFilters>(find.byType(ScreenPanelFilters))
              .selected,
          ScreenPanelResultFilter.withRange,
        );

        await tap(tester, 'Back');
        await settle(tester);
        expect(
          tester
              .widget<SupportingRecordsPage>(find.byType(SupportingRecordsPage))
              .location,
          _origin,
        );

        expect(
          (await runIo(
            tester,
            () => f.store.supportingRecord(meId, 'prior-b'),
          ))!.revision,
          1,
        );
        expect(
          (await runIo(
            tester,
            () => f.store.supportingRecord(meId, 'viewed'),
          ))!.revision,
          1,
        );
        expect((await runIo(tester, f.store.drafts))!, isEmpty);
        handle.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  appTest('no earlier result offers no source action', (tester) async {
    final f = await launch(tester);
    await _save(tester, f.store, [
      _panel('viewed', 15, title: 'Current saved panel'),
    ]);
    await _openViewed(tester, f);
    await waitForText(tester, 'No comparable earlier result.');
    expect(find.text('Open'), findsNothing);
    expect(
      find.byKey(ValueKey(_sourceKey('prior-a', 'result-prior-a'))),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('incompatible comparison offers no invented source', (tester) async {
    final f = await launch(tester);
    await _save(tester, f.store, [
      _panel('prior-a', 10, title: 'Earlier saved panel'),
      _panel('viewed', 15, title: 'Current saved panel', unit: null),
    ]);
    await _openViewed(tester, f);
    await waitForText(
      tester,
      'Comparison needs an exact or qualitative value and matching units, '
      'laboratory, method and specimen.',
    );
    expect(find.text('Open'), findsNothing);
    expect(
      find.byKey(ValueKey(_sourceKey('prior-a', 'result-prior-a'))),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('ambiguous same-day earlier values offer no source', (tester) async {
    final f = await launch(tester);
    await _save(tester, f.store, [
      _panel('prior-a', 12, title: 'Earlier saved panel'),
      _panel('prior-b', 12, title: 'Other earlier saved panel'),
      _panel('viewed', 15, title: 'Current saved panel'),
    ]);
    await _openViewed(tester, f);
    await waitForText(
      tester,
      'Collection dates do not establish an unambiguous previous result.',
    );
    expect(find.text('Open'), findsNothing);
    expect(
      find.byKey(ValueKey(_sourceKey('prior-a', 'result-prior-a'))),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey(_sourceKey('prior-b', 'result-prior-b'))),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('a missing earlier source keeps the unavailable state', (
    tester,
  ) async {
    final f = await launch(tester);
    final location = supportingSourceLocation(
      SupportingRecordId(personId: meId, id: 'gone'),
      returnLocation: '/supporting/me/viewed',
    );
    f.container.read(routerProvider).go(location);
    await waitForText(
      tester,
      'This supporting record is unavailable for this person.',
    );
    expect(find.text('Open'), findsNothing);
    expect((await runIo(tester, f.store.drafts))!, isEmpty);
    expect(tester.takeException(), isNull);
  });

  appTest('lock hides the comparison and its source action', (tester) async {
    final f = await launch(tester, auth: ControlledAuth());
    await _save(tester, f.store, [
      _panel('prior-a', 10, title: 'Earlier saved panel'),
      _panel('viewed', 15, title: 'Current saved panel'),
    ]);
    await _openViewed(tester, f);
    await waitForText(tester, 'Change: 0.');
    final source = find.byKey(
      ValueKey(_sourceKey('prior-a', 'result-prior-a')),
    );
    expect(source, findsOneWidget);

    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Unlock'), findsWidgets);
    expect(find.text('Earlier saved panel'), findsNothing);
    expect(source, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('prior source action fits 320px double text in ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final f = await launch(tester);
      await _save(tester, f.store, [
        _panel(
          'prior-a',
          10,
          title: 'An earlier saved panel with a complete readable title',
        ),
        _panel('viewed', 15, title: 'Current saved panel'),
      ]);
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await _openViewed(tester, f);
      await waitForText(tester, 'Change: 0.');
      final source = find.byKey(
        ValueKey(_sourceKey('prior-a', 'result-prior-a')),
      );
      await tester.scrollUntilVisible(
        source,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      expect(source, findsOneWidget);
      expect(tester.getSize(source).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);

      await tester.tap(source);
      await settle(tester);
      expect(
        tester
            .widget<SupportingDetailPage>(find.byType(SupportingDetailPage))
            .id,
        'prior-a',
      );
      expect(
        find.text('An earlier saved panel with a complete readable title'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  appTest('capture prior source actions in both themes', (tester) async {
    const output = String.fromEnvironment('VITAL_PANEL_SOURCE_CAPTURES');
    if (output.isEmpty) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await launch(tester);
    await _save(tester, f.store, [
      _panel('prior-a', 10, title: 'Earlier saved panel'),
      _panel('viewed', 15, title: 'Current saved panel'),
    ]);
    final key = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: RepaintBoundary(key: key, child: const VitalApp()),
      ),
    );
    await _openViewed(tester, f);
    await waitForText(tester, 'Change: 0.');
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await settle(tester);
      final source = find.byKey(
        ValueKey(_sourceKey('prior-a', 'result-prior-a')),
      );
      await tester.scrollUntilVisible(
        source,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$output/${mode.name}-panel-source.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
