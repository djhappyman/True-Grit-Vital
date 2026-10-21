import 'package:true_grit_vital/ui/stitch_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Size, ValueKey;
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/charts/charts.dart';
import 'package:true_grit_vital/features/history/history_pages.dart'
    show HistoryEntryCard;

import 'stock_ui_test.dart' show item;
import 'vital_app_test.dart' show appTest, launch, runIo, settle;

/// Selects the source status through the local segment, never through a card
/// badge that happens to share the same word.
Future<void> selectSources(
  WidgetTester tester,
  String label, {
  required String expected,
}) async {
  final target = find.descendant(
    of: find.byKey(const ValueKey('chart-source-status')),
    matching: find.text(label),
  );
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
  expect(find.text(expected), findsWidgets);
}

void main() {
  appTest(
    'chart source counts name doses, explain combined cards and keep voided history explicit',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      await runIo(tester, () async {
        final medicine = await item(f.store, name: 'Scoped medicine');
        await f.store.recordCombined(
          CombinedUseCommand(
            commandId: 'combined',
            expectedGeneration: f.store.generation,
            personId: meId,
            expectedPersonRevision: 2,
            actualAt: DateTime.utc(2026, 10, 2, 12),
            components: [
              for (var index = 0; index < 2; index++)
                CombinedUseComponent(
                  itemId: medicine.id,
                  expectedItemRevision: medicine.revision,
                  enteredAmount: '1',
                ),
            ],
          ),
        );
        await f.store.record(
          commandId: 'ordinary',
          expectedPersonRevision: 2,
          itemId: medicine.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 3, 12),
        );
        final voided = await f.store.record(
          commandId: 'voided',
          expectedPersonRevision: 2,
          itemId: medicine.id,
          amount: '5',
          actualAt: DateTime.utc(2026, 10, 4, 12),
        );
        await f.store.voidRecord(
          commandId: 'void',
          recordId: voided.id,
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
      // Two doses inside one combined record plus one ordinary dose. The
      // voided dose is absent from both the total and the default sources.
      expect(find.text('3 mg'), findsWidgets);
      expect(find.text('3 recorded doses'), findsOneWidget);
      expect(
        find.text('A combined record can contain several amounts.'),
        findsOneWidget,
      );
      expect(find.textContaining('administrations'), findsNothing);
      expect(find.byType(HistoryEntryCard), findsNWidgets(2));
      expect(find.text('5 mg · liquid'), findsNothing);
      expect(
        find.text(
          'Voided records are shown here but do not count towards totals.',
        ),
        findsNothing,
      );

      await selectSources(
        tester,
        'Voided',
        expected:
            'Voided records are shown here but do not count towards totals.',
      );
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      expect(find.text('5 mg · liquid'), findsOneWidget);
      expect(find.text('3 mg'), findsWidgets);

      await selectSources(tester, 'Recorded', expected: '3 recorded doses');
      expect(find.byType(HistoryEntryCard), findsNWidgets(2));
      expect(find.text('5 mg · liquid'), findsNothing);
      expect(
        find.text(
          'Voided records are shown here but do not count towards totals.',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'changing source status resets paging and the return route keeps its exact scope',
    (tester) async {
      final f = await launch(tester);
      await runIo(tester, () async {
        final medicine = await item(f.store, name: 'Paged scope medicine');
        for (var index = 0; index < 26; index++) {
          await f.store.record(
            commandId: 'recorded-$index',
            expectedPersonRevision: 2,
            itemId: medicine.id,
            amount: '1',
            actualAt: DateTime.utc(2026, 10, 2, 12, 0, index),
          );
        }
        for (var index = 0; index < 27; index++) {
          final record = await f.store.record(
            commandId: 'voided-$index',
            expectedPersonRevision: 2,
            itemId: medicine.id,
            amount: '9',
            actualAt: DateTime.utc(2026, 10, 3, 12, 0, index),
          );
          await f.store.voidRecord(
            commandId: 'void-$index',
            recordId: record.id,
            expectedRevision: 1,
            expectedPersonRevision: 2,
          );
        }
      });
      f.container
          .read(routerProvider)
          .go(
            '/charts?from=2026-10-01T00:00:00Z&before=2026-10-05T00:00:00Z&sources=true',
          );
      await settle(tester);
      expect(find.text('26 recorded doses'), findsOneWidget);
      expect(find.byType(HistoryEntryCard), findsNWidgets(25));
      final firstNext = find.text('Next').last;
      await tester.ensureVisible(firstNext);
      await settle(tester);
      await tester.tap(firstNext);
      await settle(tester);
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      expect(find.text('Previous'), findsOneWidget);

      // A different status is a different source query. It starts at the first
      // page instead of reusing a cursor from the recorded list.
      await selectSources(
        tester,
        'Voided',
        expected:
            'Voided records are shown here but do not count towards totals.',
      );
      expect(find.byType(HistoryEntryCard), findsNWidgets(25));
      expect(find.text('Previous'), findsNothing);
      expect(find.text('9 mg · liquid'), findsWidgets);
      final secondNext = find.text('Next').last;
      await tester.ensureVisible(secondNext);
      await settle(tester);
      await tester.tap(secondNext);
      await settle(tester);
      expect(find.byType(HistoryEntryCard), findsNWidgets(2));
      expect(find.text('Previous'), findsOneWidget);

      // The detail return route must restore the voided scope and the second
      // page cursor chain, not fall back to recorded sources.
      final inspect = find.descendant(
        of: find.byType(HistoryEntryCard),
        matching: find.byType(StitchIcon),
      );
      await tester.ensureVisible(inspect.first);
      await tester.tap(inspect.first);
      await settle(tester);
      await tester.tap(find.text('Back').first);
      await settle(tester);
      expect(find.byType(HistoryEntryCard), findsNWidgets(2));
      expect(find.text('Previous'), findsOneWidget);
      expect(
        find.text(
          'Voided records are shown here but do not count towards totals.',
        ),
        findsOneWidget,
      );

      // Returning to recorded sources starts from its first page again.
      await selectSources(tester, 'Recorded', expected: '26 recorded doses');
      expect(find.byType(HistoryEntryCard), findsNWidgets(25));
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('9 mg · liquid'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('an incompatible restored source cursor resets to the chosen scope', (
    tester,
  ) async {
    final f = await launch(tester);
    late String recordedCursor;
    await runIo(tester, () async {
      final medicine = await item(f.store, name: 'Cursor scope medicine');
      for (var index = 0; index < 26; index++) {
        await f.store.record(
          commandId: 'recorded-$index',
          expectedPersonRevision: 2,
          itemId: medicine.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 2, 12, 0, index),
        );
      }
      for (var index = 0; index < 2; index++) {
        final record = await f.store.record(
          commandId: 'voided-$index',
          expectedPersonRevision: 2,
          itemId: medicine.id,
          amount: '9',
          actualAt: DateTime.utc(2026, 10, 3, 12, 0, index),
        );
        await f.store.voidRecord(
          commandId: 'void-$index',
          recordId: record.id,
          expectedRevision: 1,
          expectedPersonRevision: 2,
        );
      }
      final request = ChartDrilldownRequest(
        series: ChartSeriesKey(
          personId: meId,
          subject: ChartSubject.item(medicine.id),
          unit: 'mg',
        ),
        fromInstant: DateTime.utc(2026, 10, 1),
        beforeInstant: DateTime.utc(2026, 10, 5),
        displayZone: f.container.read(displayZoneProvider),
        status: TimelineStatus.recorded,
      );
      recordedCursor = (await f.store.chartDrilldown(request)).next!.encode();
    });
    f.container
        .read(routerProvider)
        .go(
          Uri(
            path: '/charts',
            queryParameters: {
              'from': '2026-10-01T00:00:00Z',
              'before': '2026-10-05T00:00:00Z',
              'sources': 'true',
              'sourcesStatus': 'voided',
              'cursor': recordedCursor,
            },
          ).toString(),
        );
    await settle(tester);
    expect(find.text('Unable to load history. Try again.'), findsNothing);
    expect(find.byType(HistoryEntryCard), findsNWidgets(2));
    expect(find.text('9 mg · liquid'), findsWidgets);
    expect(find.text('1 mg · liquid'), findsNothing);
    expect(
      find.text(
        'Voided records are shown here but do not count towards totals.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
