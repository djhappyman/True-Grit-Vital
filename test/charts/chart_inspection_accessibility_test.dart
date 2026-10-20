import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Focus;
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/vital_app.dart' show routerProvider;
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_pages.dart'
    show HistoryEntryCard;
import 'package:true_grit_vital/ui/vital_ui.dart';

import '../stock_ui_test.dart' show item;
import '../vital_app_test.dart' show appTest, launch, runIo, settle, tap;

void main() {
  appTest(
    'chart bucket commands name the exact series, period and zone for keyboard inspection',
    (tester) async {
      final f = await launch(tester);
      final medicine = (await runIo(
        tester,
        () => item(f.store, name: 'Equal medicine'),
      ))!;
      await runIo(tester, () async {
        for (final day in [1, 3]) {
          await f.store.record(
            commandId: 'equal-$day',
            personId: meId,
            expectedPersonRevision: (await f.store.profileById(meId))!.revision,
            itemId: medicine.id,
            amount: '2',
            actualAt: DateTime.utc(2026, 10, day, 12),
          );
        }
      });
      f.container
          .read(routerProvider)
          .go(
            '/charts?scope=me&item=${medicine.id}'
            '&from=2026-10-01T00:00:00Z&before=2026-10-05T00:00:00Z'
            '&mode=table',
          );
      await settle(tester);
      final semantics = tester.ensureSemantics();

      expect(find.text('Equal medicine · mg'), findsOneWidget);
      final bucketCommands = find.bySemanticsLabel(
        RegExp(r'^View sources for Equal medicine in mg for '),
      );
      expect(
        bucketCommands,
        findsNWidgets(5),
        reason: 'Every table bucket needs its own contextual View command',
      );
      final firstDay = find.bySemanticsLabel(
        RegExp(
          r'^View sources for Equal medicine in mg for '
          r'Thursday, 1 October 2026\. Europe/London\.$',
        ),
      );
      final thirdDay = find.bySemanticsLabel(
        RegExp(
          r'^View sources for Equal medicine in mg for '
          r'Saturday, 3 October 2026\. Europe/London\.$',
        ),
      );
      expect(firstDay, findsOneWidget);
      expect(thirdDay, findsOneWidget);
      expect(
        tester
            .getSemantics(firstDay)
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
        reason: 'The contextual command keeps its button role',
      );
      final rangeCommand = find.bySemanticsLabel(
        RegExp(r'^View sources for Equal medicine in mg: '),
      );
      expect(
        rangeCommand,
        findsOneWidget,
        reason: 'The whole-range source command also needs its exact context',
      );
      final rangeLabel = tester
          .getSemantics(rangeCommand)
          .getSemanticsData()
          .label;
      expect(rangeLabel, contains('Thursday, 1 October 2026'));
      expect(rangeLabel, contains('Europe/London'));

      // Two rows show the same 2 mg value. The accessible command must still
      // distinguish their different civil days.
      final labels = [
        for (var index = 0; index < 5; index++)
          tester
              .getSemantics(bucketCommands.at(index))
              .getSemanticsData()
              .label,
      ];
      expect(labels.toSet(), hasLength(5));
      expect(
        labels.where((label) => label.contains('Saturday, 3 October 2026')),
        hasLength(1),
      );

      final keyboardTarget = find.descendant(
        of: firstDay,
        matching: find.text('View'),
      );
      Focus.of(tester.element(keyboardTarget)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);

      expect(find.byType(HistoryEntryCard), findsOneWidget);
      expect(find.textContaining('Thursday, 1 October 2026'), findsWidgets);
      expect(
        find.textContaining('Saturday, 3 October 2026'),
        findsNothing,
        reason: 'Activating one bucket must open only that bucket sources',
      );
      expect(find.text('Equal medicine · mg'), findsOneWidget);

      final inspect = find.descendant(
        of: find.byType(HistoryEntryCard),
        matching: find.text('View'),
      );
      await tester.ensureVisible(inspect);
      await tester.tap(inspect);
      await settle(tester);
      expect(find.text('Source'), findsWidgets);
      await tap(tester, 'Back');
      expect(find.text('Charts'), findsOneWidget);
      expect(find.text('Equal medicine · mg'), findsOneWidget);
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  appTest(
    'boundary zoom disables instead of clearing the chosen bucket and series',
    (tester) async {
      final f = await launch(tester);
      final medicine = (await runIo(
        tester,
        () => item(f.store, name: 'Zoom medicine'),
      ))!;
      await runIo(
        tester,
        () async => f.store.record(
          commandId: 'zoom-dose',
          personId: meId,
          expectedPersonRevision: (await f.store.profileById(meId))!.revision,
          itemId: medicine.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 1, 12),
        ),
      );
      f.container
          .read(routerProvider)
          .go(
            '/charts?scope=me&item=${medicine.id}'
            '&from=2026-10-01T00:00:00Z&before=2026-10-02T00:00:00Z'
            '&mode=table',
          );
      await settle(tester);

      VitalButton zoomButton(String label) =>
          tester.widget<VitalButton>(find.widgetWithText(VitalButton, label));
      expect(zoomButton('Narrow').onPressed, isNull);
      expect(zoomButton('Widen').onPressed, isNotNull);

      final rowView = find.text('View').first;
      await tester.ensureVisible(rowView);
      await tester.tap(rowView);
      await settle(tester);
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      final selectedSources = find.textContaining('Thursday, 1 October 2026');
      expect(selectedSources, findsWidgets);

      await tester.ensureVisible(find.text('Narrow'));
      await tester.tap(find.text('Narrow'));
      await settle(tester);
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      expect(selectedSources, findsWidgets);
      expect(find.text('Zoom medicine · mg'), findsOneWidget);

      await tap(tester, 'Widen');
      expect(find.byType(HistoryEntryCard), findsNothing);
      expect(find.text('Zoom medicine · mg'), findsOneWidget);
      expect(zoomButton('Narrow').onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('a sub-day range cannot widen through Narrow', (tester) async {
    final f = await launch(tester);
    f.container
        .read(routerProvider)
        .go(
          '/charts?scope=me&from=2026-10-01T12:00:00Z'
          '&before=2026-10-01T13:00:00Z&mode=table',
        );
    await settle(tester);
    final narrow = tester.widget<VitalButton>(
      find.widgetWithText(VitalButton, 'Narrow'),
    );
    expect(narrow.onPressed, isNull);
    expect(
      tester
          .widget<VitalButton>(find.widgetWithText(VitalButton, 'Widen'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('widest bounded zoom disables instead of doing nothing silently', (
    tester,
  ) async {
    final f = await launch(tester);
    final from = DateTime.utc(2016, 10, 25);
    final before = from.add(const Duration(days: 3650));
    f.container
        .read(routerProvider)
        .go(
          '/charts?scope=me&from=${from.toIso8601String()}'
          '&before=${before.toIso8601String()}&bucket=month',
        );
    await settle(tester);

    VitalButton zoomButton(String label) =>
        tester.widget<VitalButton>(find.widgetWithText(VitalButton, label));
    expect(zoomButton('Widen').onPressed, isNull);
    expect(zoomButton('Narrow').onPressed, isNotNull);
    expect(find.text('Widen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
