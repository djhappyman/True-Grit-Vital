import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/history.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';

import 'stock_ui_test.dart' show enter;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

/// Daily offsets keep timestamps distinct so the anchor position is exact.
Future<List<UseRecord>> seededHistory(
  RecordStore store, {
  int count = 30,
}) async {
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

/// A dense window inside one narrow date range for filter-boundary tests.
Future<List<UseRecord>> seededWindow(RecordStore store, {int count = 4}) async {
  final item = await store.createItem(
    commandId: newCommandId(),
    expectedPersonRevision: 2,
    name: 'Windowed medicine',
    form: 'Tablet',
    unit: 'mg',
    type: 'Medicine',
  );
  return [
    for (var i = 0; i < count; i++)
      await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        personId: item.personId,
        expectedPersonRevision: 2,
        amount: '${i + 1}',
        actualAt: DateTime.utc(2026, 10, 2, 10).add(Duration(days: i)),
      ),
  ];
}

HistoryState stateFor(ProviderContainer container, Uri uri) =>
    container.read(historyControllerProvider(uri.toString()));

Uri currentLocation(ProviderContainer container) =>
    container.read(routerProvider).routeInformationProvider.value.uri;

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
  group('the anchored window seam', () {
    late Directory dir;
    late RecordStore store;
    late SubstanceItem item;
    final key = List.generate(32, (i) => i + 1);
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vital-anchor-seam-');
      final path = '${dir.path}/db';
      store = await RecordStore.open(path: path, key: key, isNew: true);
      item = await store.createItem(
        commandId: newCommandId(),
        name: 'Seam medicine',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
    });
    tearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    TimelineQuery query({TimelineFilter? filter, int limit = 25}) =>
        TimelineQuery(
          filter: filter ?? TimelineFilter(),
          displayZone: 'UTC',
          limit: limit,
        );
    Future<List<UseRecord>> tiedRecords(int count) async {
      final records = <UseRecord>[];
      for (var i = 0; i < count; i++) {
        records.add(
          await store.record(
            commandId: newCommandId(),
            itemId: item.id,
            amount: '${i + 1}',
            actualAt: DateTime.utc(2026, 10, 19, 10),
          ),
        );
      }
      return records;
    }

    test('bounds the window at the query limit over tied positions', () async {
      final records = await tiedRecords(6);
      final all = await store.timeline(query(limit: 6));
      final keys = all.entries.map((entry) => entry.id.sortKey).toList();
      expect(keys.toSet().length, records.length);
      // Shared instant: sort-key ascending inside the tie.
      expect(keys, keys.toList()..sort());
      // The second tie member probes the full-page boundary: the window is
      // exactly the query limit, no duplicates, and the last parent stays
      // behind the reported boundary instead of being pulled forward.
      final anchored = await store.timelineAnchor(
        query(limit: 4),
        anchor: all.entries[1].id,
      );
      expect(anchored.anchorAvailable, isTrue);
      expect(anchored.hasMore, isTrue);
      expect(
        anchored.entries.map((entry) => entry.id.sortKey),
        keys.sublist(1, 5),
      );
      // A one-slot window returns only the anchor, still reporting more.
      final first = await store.timelineAnchor(
        query(limit: 1),
        anchor: all.entries[0].id,
      );
      expect(first.entries.map((entry) => entry.id.sortKey), [keys.first]);
      expect(first.hasMore, isTrue);
    });

    test('reports an anchor that left the date filter unavailable', () async {
      final records = [
        for (var i = 0; i < 2; i++)
          await store.record(
            commandId: newCommandId(),
            itemId: item.id,
            amount: '${i + 1}',
            actualAt: DateTime.utc(2026, 10, 19, 10).add(Duration(days: i)),
          ),
      ];
      final outside = await store.timelineAnchor(
        query(
          filter: TimelineFilter(
            fromInstant: DateTime.utc(2026, 11, 1),
            beforeInstant: DateTime.utc(2026, 11, 30),
          ),
        ),
        anchor: TimelineEntryId.record(records[0].id),
      );
      expect(outside.anchorAvailable, isFalse);
      expect(outside.entries, isEmpty);
      final inside = await store.timelineAnchor(
        query(
          filter: TimelineFilter(
            fromInstant: DateTime.utc(2026, 10, 1),
            beforeInstant: DateTime.utc(2026, 10, 30),
          ),
        ),
        anchor: TimelineEntryId.record(records[0].id),
      );
      expect(inside.anchorAvailable, isTrue);
      expect(inside.entries.first.id.value, records[0].id);
    });

    test('follows the status filter for voided anchors', () async {
      final records = [
        for (var i = 0; i < 2; i++)
          await store.record(
            commandId: newCommandId(),
            itemId: item.id,
            amount: '${i + 1}',
            actualAt: DateTime.utc(2026, 10, 19, 10).add(Duration(days: i)),
          ),
      ];
      final voided = await store.voidRecord(
        commandId: newCommandId(),
        recordId: records[0].id,
        expectedRevision: records[0].revision,
      );
      final anchor = TimelineEntryId.record(voided.id);
      final recordedOnly = await store.timelineAnchor(
        query(filter: TimelineFilter(status: TimelineStatus.recorded)),
        anchor: anchor,
      );
      expect(recordedOnly.anchorAvailable, isFalse);
      expect(recordedOnly.entries, isEmpty);
      final allView = await store.timelineAnchor(
        query(filter: TimelineFilter(status: TimelineStatus.all)),
        anchor: anchor,
      );
      expect(allView.anchorAvailable, isTrue);
      expect(allView.entries.first.id.value, voided.id);
      final voidedView = await store.timelineAnchor(
        query(filter: TimelineFilter(status: TimelineStatus.voided)),
        anchor: anchor,
      );
      expect(voidedView.anchorAvailable, isTrue);
    });

    test('reports an absent anchor and unmatched row unavailable', () async {
      final absent = await store.timelineAnchor(
        query(),
        anchor: TimelineEntryId.record('no-such-record'),
      );
      expect(absent.anchorAvailable, isFalse);
      expect(absent.entries, isEmpty);
      final last = await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 19, 10),
      );
      expect(
        await store.historyEntryInQuery(
          query(),
          TimelineEntryId.record('no-such-record'),
        ),
        isFalse,
      );
      expect(
        await store.historyEntryInQuery(
          query(),
          TimelineEntryId.record(last.id),
        ),
        isTrue,
      );
      expect(
        await store.historyEntryInQuery(
          query(filter: TimelineFilter(fromInstant: DateTime.utc(2026, 11, 1))),
          TimelineEntryId.record(last.id),
        ),
        isFalse,
      );
    });
  });

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
      await settledWindow(
        tester,
        f,
        (state) =>
            state.query != null && !state.loading && state.entries.isNotEmpty,
      );
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

  appTest('an unmoved correction re-lands on its row without a moved banner', (
    tester,
  ) async {
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
    final updated = state.entries.whereType<RecordTimelineEntry>().firstWhere(
      (entry) => entry.id.value == record.id,
    );
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
  });

  appTest(
    'a record voided while inspecting leaves the recorded view with the refresh path',
    (tester) async {
      final f = await launch(tester);
      final record = (await runIo(tester, () async {
        final records = await seededHistory(f.store);
        return records[6];
      }))!;
      f.container.read(routerProvider).go('/history?status=recorded');
      await settle(tester);
      final initial = await settledWindow(
        tester,
        f,
        (state) =>
            state.query != null &&
            !state.loading &&
            state.entries.any((entry) => entry.id.value == record.id),
      );
      expect(initial.stale, isFalse, reason: 'sanity: the seeded view is calm');
      await inspectCard(tester, record);
      await runIo(
        tester,
        () => f.store.voidRecord(
          commandId: newCommandId(),
          recordId: record.id,
          expectedRevision: record.revision,
          personId: meId,
          expectedPersonRevision: 2,
        ),
      );
      await tap(tester, 'Back');
      final after = await settledWindow(
        tester,
        f,
        (state) =>
            state.stale &&
            state.entries.every((entry) => entry.id.value != record.id),
      );
      expect(after.anchorUnavailable, isFalse);
      expect(
        find.textContaining('This entry moved to'),
        findsNothing,
        reason: 'nothing moved; the row left the recorded filter',
      );
      expect(
        find.textContaining('History changed'),
        findsOneWidget,
        reason: 'the withdrawn row offers the refresh path',
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'a correction that moves outside a narrow date window shows the refresh path without widening it',
    (tester) async {
      final f = await launch(tester);
      final records = (await runIo(tester, () => seededWindow(f.store)))!;
      final record = records[2];
      f.container
          .read(routerProvider)
          .go(
            '/history?from=2026-10-02T00:00:00.000Z&before=2026-10-06T00:00:00.000Z',
          );
      await settle(tester);
      await settledWindow(
        tester,
        f,
        (state) =>
            state.query != null &&
            !state.loading &&
            state.entries.length == records.length,
      );
      await inspectCard(tester, record);
      await tap(tester, 'Correct');
      await enter(tester, 'Actual date', '2026-09-01');
      await tap(tester, 'Save');
      await settledWindow(
        tester,
        f,
        (state) =>
            state.query != null &&
            !state.loading &&
            state.entries.isNotEmpty &&
            state.entries.every((entry) => entry.id.value != record.id),
      );
      // The old row left the filtered window but the corrected one stays
      // outside it too, so View keeps the position and offers refresh
      // instead of widening the filter with an out-of-filter row.
      final jump = find.text('View').first;
      await tester.ensureVisible(jump);
      await settle(tester);
      await tester.tap(jump);
      final landed = await settledWindow(
        tester,
        f,
        (state) => state.anchorUnavailable && state.stale,
      );
      expect(landed.anchored, isTrue);
      expect(
        landed.entries.every(
          (entry) => records.any(
            (seeded) => entry.id.value == seeded.id && seeded != record,
          ),
        ),
        isTrue,
        reason: 'only in-filter rows are kept; the moved row is never inserted',
      );
      expect(
        find.textContaining('This entry moved to'),
        findsNothing,
        reason: 'the stored view row no longer stands for the entry',
      );
      expect(
        find.textContaining('History changed'),
        findsOneWidget,
        reason: 'the unavailable anchor shows the refresh path',
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'an anchor that changes again before View lands on its current content',
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
      await settledWindow(
        tester,
        f,
        (state) =>
            state.query != null &&
            !state.loading &&
            state.entries.isNotEmpty &&
            state.entries.every((entry) => entry.id.value != record.id),
      );
      expect(find.textContaining('This entry moved to'), findsOneWidget);
      // The anchor changes again before the offer is accepted: a stale row
      // minted from the first correction must never enter the window.
      final current = (await runIo(
        tester,
        () => f.store.recordById(record.id),
      ))!;
      expect(current.revision, greaterThan(record.revision));
      await runIo(
        tester,
        () => f.store.correct(
          commandId: newCommandId(),
          recordId: record.id,
          expectedRevision: current.revision,
          amount: '5',
          actualAt: current.actualAt,
          expectedPersonRevision: 2,
        ),
      );
      final jump = find.text('View').first;
      await tester.ensureVisible(jump);
      await settle(tester);
      await tester.tap(jump);
      final moved = await settledWindow(
        tester,
        f,
        (state) => state.anchored && state.entries.isNotEmpty,
      );
      expect(moved.anchorUnavailable, isFalse);
      expect(moved.stale, isFalse);
      expect(moved.entries.first.id.sortKey, 'r:${record.id}');
      final subject = moved.entries.first as RecordTimelineEntry;
      expect(
        subject.record.revision,
        greaterThan(current.revision),
        reason: 'the window shows the current version, not the stale one',
      );
      expect(subject.record.enteredAmount, '5');
      expect(
        moved.entries.map((entry) => entry.id.sortKey).toSet().length,
        moved.entries.length,
        reason: 'no duplicate or missing rows around the anchor',
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'an edit after seeking updates its row in place with the refresh path quiet',
    (tester) async {
      final f = await launch(tester);
      final record = (await runIo(tester, () async {
        // records[8] holds amount '9' so the later edit moves off it.
        final records = await seededHistory(f.store);
        return records[8];
      }))!;
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      await inspectCard(tester, record);
      await tap(tester, 'Correct');
      await enter(tester, 'Actual date', '2026-09-01');
      await tap(tester, 'Save');
      final before = await settledWindow(
        tester,
        f,
        (state) =>
            state.query != null &&
            !state.loading &&
            state.entries.isNotEmpty &&
            state.entries.every((entry) => entry.id.value != record.id),
      );
      expect(before.anchorUnavailable, isFalse);
      expect(find.textContaining('This entry moved to'), findsOneWidget);
      final jump = find.text('View').first;
      await tester.ensureVisible(jump);
      await settle(tester);
      await tester.tap(jump);
      // The seek lands the controller-anchored window at the row's current
      // position; its bounded anchored watch stays attached.
      final anchored = await settledWindow(
        tester,
        f,
        (state) => state.anchored && !state.loading && state.entries.isNotEmpty,
      );
      expect(anchored.anchorUnavailable, isFalse);
      expect(anchored.entries.first.id.sortKey, 'r:${record.id}');
      final current = (await runIo(
        tester,
        () => f.store.recordById(record.id),
      ))!;
      await runIo(
        tester,
        () => f.store.correct(
          commandId: newCommandId(),
          recordId: record.id,
          expectedRevision: current.revision,
          amount: '11',
          actualAt: current.actualAt,
          expectedPersonRevision: 2,
        ),
      );
      final updated = await settledWindow(tester, f, (state) {
        final row = state.entries
            .whereType<RecordTimelineEntry>()
            .where((entry) => entry.id.value == record.id)
            .firstOrNull;
        return row != null && row.record.enteredAmount == '11';
      });
      expect(updated.anchored, isTrue);
      expect(updated.anchorUnavailable, isFalse);
      expect(
        updated.stale,
        isFalse,
        reason: 'an aligned same-length emission updates in place',
      );
      expect(updated.entries.first.id.sortKey, 'r:${record.id}');
      final row = updated.entries.whereType<RecordTimelineEntry>().firstWhere(
        (entry) => entry.id.value == record.id,
      );
      expect(row.record.revision, greaterThan(current.revision));
      expect(
        find.textContaining('History changed'),
        findsNothing,
        reason: 'no refresh path is needed while rows update in place',
      );
      // The URL anchor offer from the date correction stays visible on the
      // seek-landed window; nothing here widens or resets it.
      expect(find.textContaining('This entry moved to'), findsOneWidget);
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'a void after seeking updates its row in place and keeps the anchored position',
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
      await settledWindow(
        tester,
        f,
        (state) =>
            state.query != null &&
            state.loading == false &&
            state.entries.isNotEmpty &&
            state.entries.every((entry) => entry.id.value != record.id),
      );
      expect(find.textContaining('This entry moved to'), findsOneWidget);
      final jump = find.text('View').first;
      await tester.ensureVisible(jump);
      await settle(tester);
      await tester.tap(jump);
      final anchored = await settledWindow(
        tester,
        f,
        (state) => state.anchored && !state.loading && state.entries.isNotEmpty,
      );
      expect(anchored.anchorUnavailable, isFalse);
      expect(anchored.stale, isFalse);
      // The record is voided again while the anchored window is visible: the
      // bounded anchored watch re-reads the same position-first window, so
      // the row shows its current voided version instead of going stale.
      final current = (await runIo(
        tester,
        () => f.store.recordById(record.id),
      ))!;
      await runIo(
        tester,
        () => f.store.voidRecord(
          commandId: newCommandId(),
          recordId: record.id,
          expectedRevision: current.revision,
          personId: meId,
          expectedPersonRevision: 2,
        ),
      );
      final voidedUpdate = await settledWindow(tester, f, (state) {
        final row = state.entries
            .whereType<RecordTimelineEntry>()
            .where((entry) => entry.id.value == record.id)
            .firstOrNull;
        return row != null && row.record.isVoided;
      });
      expect(voidedUpdate.anchored, isTrue);
      expect(voidedUpdate.anchorUnavailable, isFalse);
      expect(
        voidedUpdate.stale,
        isFalse,
        reason: 'an aligned same-length emission updates in place',
      );
      expect(voidedUpdate.entries.first.id.sortKey, 'r:${record.id}');
      final row = voidedUpdate.entries
          .whereType<RecordTimelineEntry>()
          .firstWhere((entry) => entry.id.value == record.id);
      expect(row.record.revision, greaterThan(current.revision));
      expect(
        find.textContaining('History changed'),
        findsNothing,
        reason: 'the in-place voided update needs no refresh path',
      );
      expect(find.textContaining('This entry moved to'), findsOneWidget);
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
