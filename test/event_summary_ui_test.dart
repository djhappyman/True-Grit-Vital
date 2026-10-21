import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'event_ui_test.dart' show enter;
import 'screen_events_support.dart';
import 'screen_settings_hub_test.dart' show loadFonts;
import 'settings_vault_ui_test.dart' show capture;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Future<EventRecord> seed(WidgetTester tester, RecordStore store) async {
  final item = await screenEventItem(tester, store, 'Original substance name');
  final saved = await screenEvent(
    tester,
    store,
    id: 'notes-event',
    name: 'Autumn recorded course',
    type: 'prescription',
    start: EventDate.day(CivilDate(2026, 10, 1)),
    end: EventDate.day(CivilDate(2026, 10, 30)),
    items: [item],
  );
  await runIo(
    tester,
    () => store.record(
      commandId: 'event-record',
      itemId: item.id,
      amount: '0.125',
      actualAt: DateTime.utc(2026, 10, 24, 8),
      expectedPersonRevision: 2,
    ),
  );
  return saved;
}

void main() {
  setUpAll(loadFonts);
  appTest('event notes save in the canonical editor and recover as a draft', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    final event = await seed(tester, f.store);
    final router = f.container.read(routerProvider);
    router.go('/event/${event.id}/edit?notes=true');
    await waitForText(tester, 'Notes');
    const note =
        'Private original wording: 0.125 mg.\nSecond line stays separate.';
    await enter(tester, 'Notes', note);
    router.go('/event/${event.id}');
    await settle(tester);
    expect((await runIo(tester, () => f.store.drafts()))!, hasLength(1));
    router.go('/event/${event.id}/edit?notes=true');
    await waitForText(tester, 'Notes');
    await settle(tester);
    final input = find.descendant(
      of: find.widgetWithText(LabelledInput, 'Notes'),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(input).controller!.text, note);
    await tap(tester, 'Review');
    await tap(tester, 'Save');
    await waitForText(tester, 'Event totals');
    expect(router.routerDelegate.state.uri.path, '/event/${event.id}');
    expect(
      (await runIo(tester, () => f.store.eventById(event.id)))!.notes,
      note,
    );
    expect(
      (await runIo(
        tester,
        () => f.store.eventHistory(event.id),
      ))!.map((e) => e.notes),
      ['', note],
    );
    expect(
      find.text(note),
      findsNothing,
      reason: 'private text stays hidden until disclosed',
    );
    await tap(tester, 'Notes');
    expect(find.text(note), findsOneWidget);
    expect(
      tester
          .widget<VitalMetric>(
            find.widgetWithText(VitalMetric, 'Recorded doses'),
          )
          .value,
      '1',
    );
    await runIo(tester, () async {
      final item = (await f.store.items()).single;
      await f.store.record(
        commandId: newCommandId(),
        expectedPersonRevision: 2,
        itemId: item.id,
        amount: '0.25',
        actualAt: DateTime.utc(2026, 10, 24, 9),
      );
    });
    await settle(tester);
    expect(
      tester
          .widget<VitalMetric>(
            find.widgetWithText(VitalMetric, 'Recorded doses'),
          )
          .value,
      '2',
    );
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'event summaries and notes fit safe areas and reduced motion in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.reset);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final f = await launch(tester, todayClock: screenEventsNow);
        final event = await seed(tester, f.store);
        final command = SaveEventCommand(
          commandId: 'event-note',
          generation: f.store.generation,
          expectedRevision: event.revision,
          expectedPersonRevision: 2,
          event: event.copyWith(
            revision: event.revision + 1,
            notes: 'Original event context, entered by hand.',
          ),
        );
        await runIo(
          tester,
          () async => f.store.saveEvent(
            command,
            membershipReview: await f.store.previewEventMembership(command),
          ),
        );
        f.container.read(appearanceProvider.notifier).setMode(mode);
        final key = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: RepaintBoundary(key: key, child: const VitalApp()),
          ),
        );
        f.container.read(routerProvider).go('/event/${event.id}');
        await waitForText(tester, 'Event totals');
        await tester.ensureVisible(find.text('Event totals'));
        await settle(tester);
        await tap(tester, 'Notes');
        await tester.ensureVisible(find.text('Event totals'));
        await settle(tester);
        await capture(tester, key, '${mode.name}-event-totals');
        tester.view.physicalSize = const Size(320, 740);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await settle(tester);
        await tester.ensureVisible(find.text('Event totals'));
        await settle(tester);
        await capture(tester, key, '${mode.name}-event-totals-narrow');
        expect(
          find.text('Original event context, entered by hand.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
