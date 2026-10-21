import 'package:true_grit_vital/ui/stitch_ui.dart';

import 'fixtures/single_user.dart';

import 'package:fl_chart/fl_chart.dart' as plot;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/charts/chart_plot.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart'
    show LabelledInput;
import 'package:true_grit_vital/features/history/history_pages.dart'
    show HistoryEntryCard;

import 'stock_ui_test.dart' show item;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

void main() {
  appTest(
    'charts keep selected ownership, exact units, gaps and source return context',
    (tester) async {
      final f = await launch(tester);
      final selected = await runIo(tester, () async {
        final adult = await f.store.configureOwnProfile(
          commandId: 'adult',
          name: 'Morgan',
          adultConfirmed: true,
        );
        final medicine = await item(
          f.store,
          personId: adult.id,
          name: 'Morgan medicine',
        );
        final liquid = await item(
          f.store,
          personId: adult.id,
          name: 'Morgan liquid',
          unit: 'ml',
        );
        final mine = await item(f.store, name: 'Private other medicine');
        for (final day in [1, 3]) {
          await f.store.record(
            commandId: 'm$day',
            personId: adult.id,
            expectedPersonRevision: adult.revision,
            itemId: medicine.id,
            amount: '$day',
            actualAt: DateTime.utc(2026, 10, day, 12),
          );
        }
        await f.store.record(
          commandId: 'liquid',
          personId: adult.id,
          expectedPersonRevision: adult.revision,
          itemId: liquid.id,
          amount: '2',
          actualAt: DateTime.utc(2026, 10, 2, 12),
        );
        await f.store.record(
          commandId: 'mine',
          expectedPersonRevision: adult.revision,
          itemId: mine.id,
          amount: '999',
          actualAt: DateTime.utc(2026, 10, 1, 12),
        );
        return (adult: adult, medicine: medicine);
      });
      final location = Uri(
        path: '/charts',
        queryParameters: {
          'scope': selected!.adult.id,
          'item': selected.medicine.id,
          'from': '2026-10-01T00:00:00Z',
          'before': '2026-10-05T00:00:00Z',
        },
      ).toString();
      f.container.read(routerProvider).go(location);
      await settle(tester);
      expect(find.text('Person: Morgan'), findsOneWidget);
      expect(find.text('4 mg'), findsOneWidget);
      expect(find.text('2 recorded doses'), findsOneWidget);
      expect(find.textContaining('Private other medicine'), findsNothing);
      expect(find.textContaining('999'), findsNothing);
      expect(find.byType(ChartPlot), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label?.contains('recorded amounts in mg') ==
                  true,
        ),
        findsOneWidget,
      );
      final summary = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((widget) => widget.properties.label)
          .whereType<String>()
          .singleWhere((label) => label.contains('recorded amounts in mg'));
      expect(summary, contains('Person: Morgan'));
      expect(summary, contains('4 mg'));
      expect(summary, contains('2 recorded doses'));
      expect(summary, contains('Oct'));
      await tap(tester, 'Morgan medicine · mg');
      await tap(tester, 'Morgan liquid · ml');
      expect(find.text('2 ml'), findsOneWidget);
      expect(find.text('4 mg'), findsNothing);
      await tap(tester, 'Morgan liquid · ml');
      await tap(tester, 'Morgan medicine · mg');
      final canvas = tester.widget<plot.LineChart>(find.byType(plot.LineChart));
      expect(canvas.data.lineBarsData.single.isCurved, isFalse);
      expect(
        canvas.data.lineBarsData.single.spots.any((spot) => spot.isNull()),
        isTrue,
      );
      await tap(tester, 'Table');
      expect(find.text('No recorded use'), findsWidgets);
      expect(find.text('1 mg'), findsWidgets);
      expect(find.text('3 mg'), findsWidgets);
      final view = find.text('View').first;
      await tester.ensureVisible(view);
      await tester.tap(view);
      await settle(tester);
      expect(find.textContaining('Morgan medicine'), findsWidgets);
      expect(find.textContaining('Morgan liquid'), findsNothing);
      final inspect = find.descendant(
        of: find.byType(HistoryEntryCard),
        matching: find.byType(StitchIcon),
      );
      await tester.ensureVisible(inspect.first);
      await tester.tap(inspect.first);
      await settle(tester);
      expect(find.text('Source'), findsWidgets);
      await tap(tester, 'Back');
      expect(find.text('Charts'), findsOneWidget);
      expect(find.text('4 mg'), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'unknown ingredient strength stays unknown and retains its ml source',
    (tester) async {
      final f = await launch(tester);
      final product = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: 'product',
          expectedPersonRevision: 2,
          name: 'Saved product',
          form: 'liquid',
          unit: 'ml',
          type: 'Medicine',
          productComponents: [
            ProductComponent(
              ingredientId: 'unknown-ingredient',
              name: 'Unknown strength ingredient',
            ),
            ProductComponent(
              ingredientId: 'known-ingredient',
              name: 'Known ingredient',
              concentrationText: '2',
            ),
          ],
        ),
      ))!;
      await runIo(tester, () async {
        final label = (await f.store.productLabel(
          personId: meId,
          itemId: product.id,
        ))!;
        await f.store.recordProduct(
          commandId: 'product-use',
          personId: meId,
          expectedPersonRevision: 2,
          itemId: product.id,
          actualAt: DateTime.utc(2026, 10, 2, 12),
          use: ProductUseInput(
            expectedGeneration: f.store.generation,
            label: label,
            enteredVolume: EnteredStockAmount('0.5', 'ml'),
          ),
        );
      });
      f.container
          .read(routerProvider)
          .go(
            '/charts?scope=me&from=2026-10-01T00:00:00Z&before=2026-10-05T00:00:00Z&kind=ingredient&subject=unknown-ingredient&unit=mg&mode=table&sources=true',
          );
      await settle(tester);
      expect(find.text('Unknown'), findsWidgets);
      expect(find.text('Known total'), findsNothing);
      expect(find.text('1 ingredient amount'), findsOneWidget);
      expect(find.text('0 mg'), findsNothing);
      expect(find.textContaining('0.5 ml'), findsWidgets);
      expect(find.text('Unknown strength ingredient · mg'), findsOneWidget);
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'source pages restore the chain after a time correction and focus stable paging targets',
    (tester) async {
      final f = await launch(tester);
      final medicine = (await runIo(
        tester,
        () => item(f.store, name: 'Paged medicine'),
      ))!;
      await runIo(tester, () async {
        for (var index = 0; index < 51; index++) {
          await f.store.record(
            commandId: 'paged-$index',
            expectedPersonRevision: 2,
            itemId: medicine.id,
            amount: '1',
            actualAt: DateTime.utc(2026, 10, 2, 12, 0, index),
          );
        }
      });
      f.container
          .read(routerProvider)
          .go(
            '/charts?scope=me&from=2026-10-01T00:00:00Z&before=2026-10-05T00:00:00Z&sources=true',
          );
      await settle(tester);
      expect(find.byType(HistoryEntryCard), findsNWidgets(25));
      await tap(tester, 'Next');
      expect(find.byType(HistoryEntryCard), findsNWidgets(25));
      final next = find.text('Next');
      await tester.ensureVisible(next);
      Focus.of(tester.element(next)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'chart source page',
      );
      var reachedSource = false;
      for (var step = 0; step < 100; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<HistoryEntryCard>() !=
            null) {
          reachedSource = true;
          break;
        }
      }
      expect(
        reachedSource,
        isTrue,
        reason: 'Every source inspection must be keyboard reachable',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('Source'), findsWidgets);
      await tap(tester, 'Correct');
      final date = find.descendant(
        of: find.widgetWithText(LabelledInput, 'Actual date'),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(date);
      await tester.enterText(date, '2026-10-03');
      await tap(tester, 'Save');
      expect(find.text('Charts'), findsOneWidget);
      expect(find.byType(HistoryEntryCard), findsNothing);
      // Moving the old last record ahead of the saved cursor must still leave
      // a route back to the earlier page, even after correction rebuilt Charts.
      await tap(tester, 'Previous');
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'chart source page',
      );
      expect(find.byType(HistoryEntryCard), findsNWidgets(25));
      await tap(tester, 'Previous');
      expect(find.byType(HistoryEntryCard), findsNWidgets(25));
      expect(find.text('Previous'), findsNothing);
      expect(find.text('51 mg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'chart table remains usable at large text with invalid range feedback',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      final medicine = (await runIo(
        tester,
        () => item(f.store, name: 'A full medicine name'),
      ))!;
      await runIo(
        tester,
        () => f.store.record(
          commandId: 'dose',
          expectedPersonRevision: 2,
          itemId: medicine.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 2),
        ),
      );
      f.container
          .read(routerProvider)
          .go('/charts?from=2026-10-01T00:00:00Z&before=2026-10-05T00:00:00Z');
      await settle(tester);
      expect(
        find.text('Use the table to inspect this range of quantities.'),
        findsOneWidget,
      );
      await tap(tester, 'Table');
      expect(find.text('1 mg'), findsWidgets);
      await tap(tester, 'Range');
      await tester.enterText(find.byType(TextField).first, '2026-10-06');
      await tap(tester, 'Apply');
      expect(
        find.text('Choose valid dates with the end after the start.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'voided-only use keeps its source without fabricating a numeric total',
    (tester) async {
      final f = await launch(tester);
      await runIo(tester, () async {
        final medicine = await item(f.store, name: 'Voided medicine');
        final record = await f.store.record(
          commandId: 'void-use',
          expectedPersonRevision: 2,
          itemId: medicine.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 2),
        );
        await f.store.voidRecord(
          commandId: 'void',
          recordId: record.id,
          expectedRevision: 1,
          expectedPersonRevision: 2,
        );
      });
      f.container
          .read(routerProvider)
          .go(
            '/charts?from=2026-10-01T00:00:00Z&before=2026-10-05T00:00:00Z&sources=true',
          );
      await settle(tester);
      expect(find.text('Total'), findsNothing);
      expect(find.text('0 mg'), findsNothing);
      expect(find.byType(HistoryEntryCard), findsNothing);
      expect(find.text('No recorded sources in this range.'), findsOneWidget);
      await tap(tester, 'Voided');
      expect(
        find.text(
          'Voided records are shown here but do not count towards totals.',
        ),
        findsOneWidget,
      );
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      expect(find.text('Total'), findsNothing);
      expect(find.text('0 mg'), findsNothing);
    },
  );

  appTest(
    'invalid local viewport offers range repair instead of an ineffective retry',
    (tester) async {
      final f = await launch(tester);
      f.container
          .read(routerProvider)
          .go('/charts?from=2020-01-01T00:00:00Z&before=2026-10-05T00:00:00Z');
      await settle(tester);
      expect(
        find.text('Choose a shorter range to show every record.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      await tester.ensureVisible(find.text('Range').last);
      await tester.tap(find.text('Range').last);
      await settle(tester);
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.enterText(find.byType(TextField).first, '2026-10-01');
      await tester.enterText(find.byType(TextField).last, '2026-10-05');
      await tap(tester, 'Apply');
      expect(
        find.text('Choose a shorter range to show every record.'),
        findsNothing,
      );
      expect(find.text('No recorded use in this range.'), findsOneWidget);
    },
  );
  appTest('malformed display zone offers an explicit UTC reset', (
    tester,
  ) async {
    final f = await launch(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: ProviderScope(
          overrides: [displayZoneProvider.overrideWithValue('')],
          child: const VitalApp(),
        ),
      ),
    );
    f.container
        .read(routerProvider)
        .go('/charts?from=2026-10-01T00:00:00Z&before=2026-10-05T00:00:00Z');
    await settle(tester);
    expect(
      find.text('The display time zone is unavailable. Reset to show UTC.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsNothing);
    await tap(tester, 'Reset');
    expect(
      find.text('The display time zone is unavailable. Reset to show UTC.'),
      findsNothing,
    );
    expect(find.text('Shown in UTC'), findsOneWidget);
  });
  appTest(
    'combined amounts count separately from their source card and table paging keeps focus',
    (tester) async {
      final f = await launch(tester);
      await runIo(tester, () async {
        final medicine = await item(f.store, name: 'Combined medicine');
        await f.store.recordCombined(
          CombinedUseCommand(
            commandId: 'combined',
            expectedGeneration: f.store.generation,
            personId: meId,
            expectedPersonRevision: 2,
            actualAt: DateTime.utc(2026, 10, 2),
            components: [
              for (var i = 0; i < 2; i++)
                CombinedUseComponent(
                  itemId: medicine.id,
                  expectedItemRevision: medicine.revision,
                  enteredAmount: '1',
                ),
            ],
          ),
        );
      });
      f.container
          .read(routerProvider)
          .go(
            '/charts?from=2026-10-01T00:00:00Z&before=2026-11-01T00:00:00Z&mode=table&sources=true',
          );
      await settle(tester);
      expect(find.text('2 recorded doses'), findsNWidgets(2));
      expect(
        find.text('A combined record can contain several amounts.'),
        findsNWidgets(2),
      );
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      await tap(tester, 'Next');
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'chart table page',
      );
      expect(find.text('Next'), findsNothing);
      await tap(tester, 'Previous');
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'chart table page',
      );
      expect(find.text('Previous'), findsNothing);
      expect(find.text('2 recorded doses'), findsNWidgets(2));
    },
  );
}
