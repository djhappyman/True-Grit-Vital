import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/history.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';

import 'stock_ui_test.dart' show enter;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

/// Daily offsets keep timestamps distinct so the anchor position is exact.
Future<List<UseRecord>> seededHistory(RecordStore store, {int count = 30}) async {
  final item = await store.createItem(
    commandId: newCommandId(),
    expectedPersonRevision: 2,
    name: 'Anchored original medicine name',
    form: 'Tablet',
    unit: 'mg',
    type: 'Medicine',
  );
  final records = <UseRecord>[];
  for (var i = 0; i < count; i++) {
    records.add(
      await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        personId: item.personId,
        expectedPersonRevision: 2,
        amount: '${i + 1}',
        actualAt: DateTime.utc(2026, 10, 19, 10).add(Duration(days: i)),
      ),
    );
  }
  return records;
}

HistoryState stateFor(ProviderContainer container, Uri uri) =>
    container.read(historyControllerProvider(uri.toString()));

Uri currentLocation(ProviderContainer container) => container
    .read(routerProvider)
    .routeInformationProvider
    .value
    .uri;

Finder entryCard(UseRecord record) => find.byWidgetPredicate(
  (widget) => widget is HistoryEntryCard && widget.entry.id.value == record.id,
);

Future<void> inspectCard(WidgetTester tester, UseRecord record) async {
  final view = find.descendant(
    of: entryCard(record),
    matching: find.text('View'),
  );
  await tester.ensureVisible(view);
  await settle(tester);
  await tester.tap(view);
  await settle(tester);
}

/// Runs bounded real-IO turns until the history window satisfies [ready].
/// The landing after a correction is a fresh window whose reads finish
/// across several store turns, so a single settle is not enough.
Future<HistoryState> settledWindow(
  WidgetTester tester,
  ({RecordStore store, ProviderContainer container, String path, List<int> key})
  f,
  bool Function(HistoryState state) ready,
) async {
  return (await runIo<HistoryState>(tester, () async {
    for (var attempt = 0; attempt < 80; attempt++) {
      final uri = currentLocation(f.container);
      if (uri.path != '/history') {
        throw StateError('navigation left /history: $uri');
      }
      final state = stateFor(f.container, uri);
      if (ready(state)) return state;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw StateError('the history window never reached the expected state');
  }))!;
}

void main() {
  appTest(
    'a moved correction offers View that reloads the window at its position',
    (tester) async {
      final f = await launch(tester);
      final record = (await runIo(tester, () async {
        final records = await seededHistory(f.store);
        return records[6];
      }))!;
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      await inspectCard(tester, record);
      await tap(tester, 'Correct');
      await enter(tester, 'Actual date', '2026-09-01');
      await tap(tester, 'Save');
      await settledWindow(tester, f, (state) => state.query != null && !state.loading && state.entries.isNotEmpty);
      final uri = currentLocation(f.container);
      expect(uri.path, '/history');
      expect(uri.queryParameters['anchor'], 'r:${record.id}');
      final identity = stateFor(f.container, uri).query!.identity;
      final state = stateFor(f.container, uri);
      expect(state.pages, 1);
      expect(
        state.entries.any((entry) => entry.id.value == record.id),
        isFalse,
        reason: 'the entry moved below the loaded window',
      );
      expect(find.textContaining('This entry moved to'), findsOneWidget);
      // The banner's jump button is the page's first 'View' (entry cards add
      // their own inspect 'View' buttons further down the list).
      final jump = find.text('View').first;
      await tester.ensureVisible(jump);
      await settle(tester);
      await tester.tap(jump);
      final moved = await settledWindow(
        tester,
        f,
        (state) => state.anchored && state.entries.isNotEmpty,
      );
      expect(moved.query!.identity, identity);
      expect(moved.pages, 1);
      expect(moved.entries.first.id.sortKey, 'r:${record.id}');
      expect(
        moved.entries.map((entry) => entry.id.sortKey).toSet().length,
        moved.entries.length,
        reason: 'no duplicate or missing rows around the moved anchor',
      );
      final subject = moved.entries.first as RecordTimelineEntry;
      expect(subject.record.revision, greaterThan(record.revision));
      final card = entryCard(record);
      expect(card, findsOneWidget);
      final position = tester.getRect(card);
      expect(position.top, greaterThanOrEqualTo(0));
      expect(
        position.bottom,
        lessThanOrEqualTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'an unmoved correction re-lands on its row without a moved banner',
    (tester) async {
      final f = await launch(tester);
      final record = (await runIo(tester, () async {
        // records[24] sits inside the first page of the newest-first window,
        // so the correction stays in the re-landed window.
        final records = await seededHistory(f.store);
        return records[24];
      }))!;
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      await inspectCard(tester, record);
      await tap(tester, 'Correct');
      await enter(tester, 'Amount', '9');
      await tap(tester, 'Save');
      await settledWindow(
        tester,
        f,
        (state) =>
            state.query != null &&
            !state.loading &&
            state.entries.any((entry) => entry.id.value == record.id),
      );
      final uri = currentLocation(f.container);
      expect(uri.path, '/history');
      expect(uri.queryParameters['anchor'], 'r:${record.id}');
      final state = stateFor(f.container, uri);
      final updated = state.entries
          .whereType<RecordTimelineEntry>()
          .firstWhere((entry) => entry.id.value == record.id);
      expect(updated.record.enteredAmount, '9');
      expect(updated.record.revision, greaterThan(record.revision));
      expect(updated.record.actualAt.toUtc(), record.actualAt.toUtc());
      expect(
        find.textContaining('This entry moved to'),
        findsNothing,
        reason: 'the date did not change so nothing moved',
      );
      expect(
        find.textContaining('History refreshed'),
        findsOneWidget,
        reason: 'the saved state is announced on the anchored landing',
      );
      final card = entryCard(record);
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
