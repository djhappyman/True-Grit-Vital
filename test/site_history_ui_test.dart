import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show MaterialLocalizations;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/combined_pages.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captures = String.fromEnvironment('VITAL_SITE_HISTORY_CAPTURES');

final _at = DateTime.utc(2026, 10, 20, 9, 30);

Future<void> loadFonts() async {
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
}

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);

Finder _openFor(String recordId) =>
    find.byKey(ValueKey('site-history-open-$recordId'));

Finder _openText(Finder open) =>
    find.descendant(of: open, matching: find.text('Open'));

Finder get _openButtons => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('site-history-open-'),
);

Future<SubstanceItem> _item(RecordStore store, String name) async =>
    store.createItem(
      commandId: newCommandId(),
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      name: name,
      form: 'liquid',
      unit: 'ml',
      type: 'Medicine',
    );

Future<UseRecord> _record(
  RecordStore store,
  SubstanceItem item,
  DateTime at, {
  String? site,
}) async => store.record(
  commandId: newCommandId(),
  itemId: item.id,
  amount: '1',
  actualAt: at,
  siteLabel: site,
  expectedPersonRevision: (await store.profileById(meId))!.revision,
);

Future<void> _openSite(
  WidgetTester tester,
  ProviderContainer container,
  String recordId,
) async {
  container.read(routerProvider).go('/site/$meId/$recordId');
  await settle(tester);
  await waitForText(tester, 'Site history');
}

Future<void> _expand(WidgetTester tester) async {
  if (find.text('Recent sites').evaluate().isEmpty) return;
  await tap(tester, 'Recent sites');
  await settle(tester);
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final elapsed = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (elapsed.elapsed > const Duration(seconds: 30)) {
      throw TestFailure('Expected widget did not appear: $finder');
    }
    await runIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _tapOpen(WidgetTester tester, Finder open) async {
  final text = _openText(open);
  await tester.ensureVisible(text);
  await settle(tester);
  await tester.tap(text);
  await settle(tester);
}

String _location(ProviderContainer container) {
  final configuration = container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration;
  final last = configuration.matches.lastOrNull;
  return last is ImperativeRouteMatch
      ? last.matches.uri.toString()
      : configuration.uri.toString();
}

void main() {
  setUpAll(loadFonts);

  appTest('saved site history opens the source without touching the draft', (
    tester,
  ) async {
    final f = await launch(
      tester,
      zoneObservation: DeviceZoneObservation.fromId('UTC'),
    );
    final item = (await runIo(tester, () => _item(f.store, 'Site dose')))!;
    final record = (await runIo(
      tester,
      () => _record(f.store, item, _at, site: 'Left arm'),
    ))!;
    await _openSite(tester, f.container, record.id);

    expect(find.text('Recent sites'), findsOneWidget);
    expect(_openFor(record.id), findsNothing, reason: 'collapsed by default');
    expect(await runIo(tester, f.store.drafts), isEmpty);

    await _expand(tester);
    await _waitFor(tester, _openFor(record.id));
    expect(find.text('Left arm'), findsWidgets);
    expect(find.text('Site dose'), findsWidgets);
    expect(find.text('Recorded'), findsOneWidget);
    final localizations = MaterialLocalizations.of(
      tester.element(find.byType(SiteForm)),
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('site-history-row-${record.id}')),
        matching: find.textContaining(
          'Actual: ${localizations.formatFullDate(_at)}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      await runIo(tester, f.store.drafts),
      isEmpty,
      reason: 'expanding read-only history is not an edit',
    );

    await _tapOpen(tester, _openFor(record.id));
    await waitForText(tester, 'Source');
    final location = Uri.parse(_location(f.container));
    expect(location.pathSegments, ['history-source', 'record', record.id]);
    expect(location.queryParameters['person'], meId);
    expect(location.queryParameters['return'], '/site/$meId/${record.id}');
    expect(find.text('Left arm'), findsWidgets);

    await tap(tester, 'Back');
    await settle(tester);
    expect(find.text('Site history'), findsOneWidget);
    expect(
      find.widgetWithText(LabelledInput, 'Site (optional)'),
      findsOneWidget,
    );
    expect(await runIo(tester, f.store.drafts), isEmpty);
    expect(
      (await runIo(
        tester,
        () => f.store.recordById(record.id, personId: meId),
      ))!.revision,
      record.revision,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('site history keeps an unfinished site and exact draft on return', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => _item(f.store, 'Draft dose')))!;
    final record = (await runIo(
      tester,
      () => _record(f.store, item, _at, site: 'Left arm'),
    ))!;
    await _openSite(tester, f.container, record.id);
    await _expand(tester);
    await _waitFor(tester, _openFor(record.id));

    await tester.ensureVisible(_field('Site (optional)'));
    await tester.enterText(_field('Site (optional)'), 'Unfinished site');
    await settle(tester);
    final draft = (await runIo(tester, f.store.drafts))!.single;
    expect(draft.kind, DraftKind.siteEdit);
    expect(draft.fields['site'], 'Unfinished site');

    await _tapOpen(tester, _openFor(record.id));
    await waitForText(tester, 'Source');
    await tap(tester, 'Back');
    await settle(tester);
    expect(find.text('Unfinished site'), findsOneWidget);
    expect(
      (await runIo(tester, f.store.drafts))!.single.fields['site'],
      'Unfinished site',
    );
    expect(
      (await runIo(
        tester,
        () => f.store.recordById(record.id, personId: meId),
      ))!.siteLabel,
      'Left arm',
      reason: 'inspection never saves the draft',
    );

    // The site form is a task popover, so platform Back is its dismissal path.
    await tester.binding.handlePopRoute();
    await settle(tester);
    await waitForText(tester, 'Unsaved changes');
    await tap(tester, 'Keep');
    await settle(tester);
    expect(find.text('Unfinished site'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('voided and corrected site entries keep their current state', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => _item(f.store, 'Changed dose')))!;
    final corrected = (await runIo(
      tester,
      () => _record(f.store, item, _at, site: 'Left arm'),
    ))!;
    final voided = (await runIo(
      tester,
      () => _record(
        f.store,
        item,
        _at.add(const Duration(hours: 1)),
        site: 'Right thigh',
      ),
    ))!;
    await runIo(tester, () async {
      final profile = (await f.store.profileById(meId))!;
      await f.store.correct(
        commandId: newCommandId(),
        recordId: corrected.id,
        expectedRevision: corrected.revision,
        amount: '2',
        actualAt: _at,
        expectedPersonRevision: profile.revision,
      );
    });
    await runIo(tester, () async {
      final profile = (await f.store.profileById(meId))!;
      await f.store.voidRecord(
        commandId: newCommandId(),
        recordId: voided.id,
        expectedRevision: voided.revision,
        expectedPersonRevision: profile.revision,
      );
    });

    await _openSite(tester, f.container, corrected.id);
    await _expand(tester);
    await _waitFor(tester, _openFor(voided.id));
    expect(find.text('Corrected dose, revision 2'), findsOneWidget);
    expect(find.text('Voided'), findsOneWidget);
    expect(find.text('Right thigh'), findsOneWidget);
    expect(_openFor(corrected.id), findsOneWidget);
    expect(_openFor(voided.id), findsOneWidget);

    await _tapOpen(tester, _openFor(voided.id));
    await waitForText(tester, 'Source');
    expect(find.text('Voided'), findsWidgets);
    await tap(tester, 'Back');
    await settle(tester);
    expect(find.text('Right thigh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('site history pages by dose time and hides while locked', (
    tester,
  ) async {
    final f = await launch(tester, auth: FakeAuth());
    final item = (await runIo(tester, () => _item(f.store, 'Paged dose')))!;
    final records = <UseRecord>[];
    await runIo(tester, () async {
      for (var index = 0; index < 25; index++) {
        records.add(
          await _record(
            f.store,
            item,
            _at.add(Duration(hours: index)),
            site: 'Site ${(index + 1).toString().padLeft(2, '0')}',
          ),
        );
      }
      final profile = (await f.store.profileById(meId))!;
      await f.store.editProfile(
        commandId: newCommandId(),
        personId: meId,
        expectedRevision: profile.revision,
        name: 'Me',
        adultConfirmed: true,
      );
      await f.container.read(appLockProvider.notifier).setEnabled(true);
    });
    await _openSite(tester, f.container, records.last.id);
    await _expand(tester);
    await waitForText(tester, 'Site 25');
    expect(_openButtons, findsNWidgets(20));
    expect(_openFor(records.first.id), findsNothing);
    expect(find.text('Previous'), findsNothing);

    await tap(tester, 'Next');
    await waitForText(tester, 'Site 01');
    expect(_openFor(records.first.id), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);
    expect(_openButtons, findsNWidgets(5));

    await tap(tester, 'Previous');
    await waitForText(tester, 'Site 25');
    expect(_openFor(records.last.id), findsOneWidget);
    expect(find.text('Previous'), findsNothing);

    await tester.ensureVisible(_field('Site (optional)'));
    await tester.enterText(_field('Site (optional)'), 'Locked draft site');
    await settle(tester);
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Site 25'), findsNothing);
    expect(find.text('Site history'), findsNothing);

    await tap(tester, 'Unlock');
    await settle(tester);
    await waitForText(tester, 'Site history');
    expect(find.text('Locked draft site'), findsOneWidget);
    expect(find.text('Site 25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('site history refreshes saved changes without replacing the draft', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => _item(f.store, 'Live site dose')))!;
    final editing = (await runIo(
      tester,
      () => _record(f.store, item, _at, site: 'Left arm'),
    ))!;
    final other = (await runIo(
      tester,
      () => _record(
        f.store,
        item,
        _at.add(const Duration(hours: 1)),
        site: 'Right thigh',
      ),
    ))!;
    await _openSite(tester, f.container, editing.id);
    await _expand(tester);
    await waitForText(tester, 'Right thigh');
    await tester.ensureVisible(_field('Site (optional)'));
    await tester.enterText(_field('Site (optional)'), 'Unfinished site');
    await settle(tester);
    Future<void> changeSite(String? label) => runIo(tester, () async {
      await f.store.updateSite(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: (await f.store.profileById(meId))!.revision,
        expectedGeneration: f.store.generation,
        recordId: other.id,
        expectedRevision: other.revision,
        siteLabel: label,
      );
    });
    await changeSite('Updated saved site');
    await waitForText(tester, 'Updated saved site');
    await changeSite(null);
    await settle(tester);
    expect(find.text('Updated saved site'), findsNothing);
    expect(find.text('Unfinished site'), findsOneWidget);
    expect(
      (await runIo(tester, f.store.drafts))!.single.fields['site'],
      'Unfinished site',
    );
    expect(tester.takeException(), isNull);
  });

  appTest('site history returns from a page emptied by a live site clear', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => _item(f.store, 'Paged live dose'),
    ))!;
    final records = <UseRecord>[];
    await runIo(tester, () async {
      for (var index = 0; index < 21; index++) {
        records.add(
          await _record(
            f.store,
            item,
            _at.add(Duration(hours: index)),
            site: 'Saved site $index',
          ),
        );
      }
    });
    await _openSite(tester, f.container, records.last.id);
    await _expand(tester);
    await _waitFor(tester, _openFor(records.last.id));
    await tap(tester, 'Next');
    await _waitFor(tester, _openFor(records.first.id));
    await runIo(tester, () async {
      await f.store.updateSite(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: (await f.store.profileById(meId))!.revision,
        expectedGeneration: f.store.generation,
        recordId: records.first.id,
        expectedRevision: records.first.revision,
        siteLabel: null,
      );
    });
    await _waitFor(tester, _openFor(records.last.id));
    expect(find.text('Previous'), findsNothing);
    expect(_openButtons, findsNWidgets(20));
    expect(tester.takeException(), isNull);
  });

  appTest('site history is explicit when no saved site exists', (tester) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => _item(f.store, 'No site dose')))!;
    final record = (await runIo(tester, () => _record(f.store, item, _at)))!;
    await _openSite(tester, f.container, record.id);
    await _expand(tester);
    await waitForText(tester, 'No saved sites.');
    expect(_openButtons, findsNothing);
    expect(find.text('Recent sites'), findsOneWidget);
    expect(await runIo(tester, f.store.drafts), isEmpty);
    expect(tester.takeException(), isNull);
  });

  appTest('site history layouts at narrow widths in both themes', (
    tester,
  ) async {
    const output = String.fromEnvironment('VITAL_SITE_HISTORY_CAPTURES');
    if (output.isEmpty) return;
    final f = await launch(tester);
    final item = (await runIo(tester, () => _item(f.store, 'Site dose')))!;
    final first = (await runIo(
      tester,
      () => _record(f.store, item, _at, site: 'Left arm'),
    ))!;
    await runIo(
      tester,
      () => _record(
        f.store,
        item,
        _at.add(const Duration(hours: 1)),
        site: 'Right thigh',
      ),
    );
    await runIo(tester, () async {
      await f.store.updateSite(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: (await f.store.profileById(meId))!.revision,
        expectedGeneration: f.store.generation,
        recordId: first.id,
        expectedRevision: first.revision,
        siteLabel: 'Left thigh',
      );
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: RepaintBoundary(key: boundary, child: const VitalApp()),
      ),
    );
    await settle(tester);
    await _openSite(tester, f.container, first.id);
    await _expand(tester);
    await waitForText(tester, 'Left thigh');

    for (final (width, scale) in [(390.0, 1.0), (430.0, 1.0), (320.0, 2.0)]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await settle(tester);
      await tester.ensureVisible(_openFor(first.id));
      await settle(tester);
      expect(tester.takeException(), isNull);
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        f.container.read(appearanceProvider.notifier).setMode(mode);
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$output/${width.toInt()}x${scale.toInt()}x-${mode.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
