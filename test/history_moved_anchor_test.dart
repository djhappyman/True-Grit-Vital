import 'package:true_grit_vital/ui/stitch_ui.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/history.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';
import 'package:true_grit_vital/platform/app_auth.dart';

import 'stock_ui_test.dart' show enter;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

/// Deterministic fake lock so controller tests can gate on the lock
/// lifecycle without the platform auth bootstrap.
final class TestingLockController extends AppLockController {
  @override
  AppLockState build() => AppLockState(
    ready: true,
    locked: false,
    enabled: false,
    availability: AppAuthAvailability.unsupported,
  );
}

/// Bounded wait on a live copy of the state so controller tests do not
/// depend on the number of store turns a re-read needs.
Future<HistoryState> awaitState(
  HistoryState Function() read,
  bool Function(HistoryState state) ready,
) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    final state = read();
    if (ready(state)) return state;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('the splice window never reached the expected state');
}

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
    matching: find.byType(StitchIcon),
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
        await store.historyEntrySnapshot(
          query(),
          TimelineEntryId.record('no-such-record'),
        ),
        isNull,
      );
      final matched = await store.historyEntrySnapshot(
        query(),
        TimelineEntryId.record(last.id),
      );
      expect(matched, isNotNull);
      expect(matched!.entry.id.value, last.id);
      expect(matched.queryIdentity, query().identity);
      expect(matched.datasetGeneration, store.generation);
      expect(
        await store.historyEntrySnapshot(
          query(filter: TimelineFilter(fromInstant: DateTime.utc(2026, 11, 1))),
          TimelineEntryId.record(last.id),
        ),
        isNull,
      );
    });

    test(
      'a splice snapshot returns the current revision, never a cached one',
      () async {
        final records = [
          for (var i = 0; i < 2; i++)
            await store.record(
              commandId: newCommandId(),
              itemId: item.id,
              amount: '${i + 1}',
              actualAt: DateTime.utc(2026, 10, 19, 10).add(Duration(days: i)),
            ),
        ];
        final page = await store.timeline(query());
        final old = page.entries.whereType<RecordTimelineEntry>().firstWhere(
          (entry) => entry.id.value == records[0].id,
        );
        expect(old.record.enteredAmount, '1');
        await store.correct(
          commandId: newCommandId(),
          recordId: records[0].id,
          expectedRevision: records[0].revision,
          amount: '7',
          actualAt: records[0].actualAt,
        );
        final resolved = await store.historyEntrySnapshot(
          query(),
          TimelineEntryId.record(records[0].id),
        );
        expect(resolved, isNotNull);
        expect(resolved!.entry.id.sortKey, old.id.sortKey);
        expect(resolved.schemaVersion, greaterThanOrEqualTo(1));
        expect(resolved.datasetGeneration, store.generation);
        final entry = resolved.entry as RecordTimelineEntry;
        expect(
          entry.record.enteredAmount,
          '7',
          reason: 'the CURRENT row is returned, not the version at fetch time',
        );
        expect(entry.record.revision, greaterThan(old.record.revision));
      },
    );

    test(
      'a splice snapshot withdraws a row voided between fetch and splice',
      () async {
        final records = [
          for (var i = 0; i < 2; i++)
            await store.record(
              commandId: newCommandId(),
              itemId: item.id,
              amount: '${i + 1}',
              actualAt: DateTime.utc(2026, 10, 19, 10).add(Duration(days: i)),
            ),
        ];
        await store.voidRecord(
          commandId: newCommandId(),
          recordId: records[0].id,
          expectedRevision: records[0].revision,
        );
        expect(
          await store.historyEntrySnapshot(
            query(filter: TimelineFilter(status: TimelineStatus.recorded)),
            TimelineEntryId.record(records[0].id),
          ),
          isNull,
          reason: 'a voided row never stays in a Recorded-only view',
        );
        final all = await store.historyEntrySnapshot(
          query(filter: TimelineFilter(status: TimelineStatus.all)),
          TimelineEntryId.record(records[0].id),
        );
        expect(all, isNotNull);
        expect((all!.entry as RecordTimelineEntry).record.isVoided, isTrue);
      },
    );
  });

  group('the splice lifecycle gating', () {
    late Directory dir;
    late RecordStore store;
    late SubstanceItem item;
    final key = List.generate(32, (i) => i + 1);
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vital-splice-gate-');
      final path = '${dir.path}/db';
      store = await RecordStore.open(path: path, key: key, isNew: true);
      item = await store.createItem(
        commandId: newCommandId(),
        name: 'Splice gating medicine',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );
    });
    tearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });

    ProviderContainer spliceContainer({
      Completer<ResolvedHistoryEntry?>? gate,
    }) => ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() => Future.value(store)),
        appLockProvider.overrideWith(() => TestingLockController()),
        if (gate != null)
          historyEntrySnapshotProvider.overrideWithValue(
            (query, id) => gate.future,
          ),
      ],
    );

    test(
      'a late splice across a reconfigure and a lock does not win',
      () async {
        final records = [
          for (var i = 0; i < 3; i++)
            await store.record(
              commandId: newCommandId(),
              itemId: item.id,
              amount: '${i + 1}',
              actualAt: DateTime.utc(
                2026,
                10,
                19,
                10,
              ).subtract(Duration(days: i)),
            ),
        ];
        final gate = Completer<ResolvedHistoryEntry?>();
        final container = spliceContainer(gate: gate);
        addTearDown(container.dispose);
        final provider = historyControllerProvider('late-splice');
        await container.read(recordStoreProvider.future);
        addTearDown(container.listen(provider, (_, _) {}).close);
        final controller = container.read(provider.notifier);
        await controller.configure(
          TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
        );
        final state = await awaitState(() => container.read(provider), (state) {
          final row = state.entries
              .whereType<RecordTimelineEntry>()
              .where((entry) => entry.id.value == records[1].id)
              .firstOrNull;
          return !state.loading && row != null;
        });
        final old = state.entries.whereType<RecordTimelineEntry>().firstWhere(
          (entry) => entry.id.value == records[1].id,
        );
        // The live record is corrected again while the splice resolution
        // waits on the injected seam.
        await store.correct(
          commandId: newCommandId(),
          recordId: records[1].id,
          expectedRevision: records[1].revision,
          amount: '7',
          actualAt: records[1].actualAt,
        );
        final splice = controller.spliceEntry(old);
        final moved = TimelineQuery(
          displayZone: 'UTC',
          filter: TimelineFilter(status: TimelineStatus.skipped),
        );
        await controller.configure(moved);
        await awaitState(() => container.read(provider), (state) {
          return state.query?.identity == moved.identity && !state.loading;
        });
        container.read(appLockProvider.notifier).lock();
        gate.complete(
          ResolvedHistoryEntry(
            entry: old,
            queryIdentity: state.query!.identity,
            schemaVersion: state.schemaVersion,
            datasetGeneration: store.generation,
          ),
        );
        await splice;
        final finalState = container.read(provider);
        expect(
          finalState.error,
          isNull,
          reason: 'the superseded splice must not park a stale row or error',
        );
        expect(finalState.query?.identity, moved.identity);
        expect(
          finalState.entries.every((entry) => entry.id.value != records[1].id),
          isTrue,
          reason:
              'the locked window stays empty; the stale splice never applies',
        );
      },
    );

    test(
      'a splice resolved at a superseded generation cannot regress a row',
      () async {
        final records = [
          for (var i = 0; i < 2; i++)
            await store.record(
              commandId: newCommandId(),
              itemId: item.id,
              amount: '${i + 1}',
              actualAt: DateTime.utc(2026, 10, 19, 10).add(Duration(days: i)),
            ),
        ];
        final gate = Completer<ResolvedHistoryEntry?>();
        final container = spliceContainer(gate: gate);
        addTearDown(container.dispose);
        final provider = historyControllerProvider('gate-generation');
        await container.read(recordStoreProvider.future);
        addTearDown(container.listen(provider, (_, _) {}).close);
        await container
            .read(provider.notifier)
            .configure(
              TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
            );
        final seeded = await awaitState(() => container.read(provider), (
          state,
        ) {
          final row = state.entries
              .whereType<RecordTimelineEntry>()
              .where((entry) => entry.id.value == records[0].id)
              .firstOrNull;
          return !state.loading && row != null;
        });
        final cached = seeded.entries
            .whereType<RecordTimelineEntry>()
            .firstWhere((entry) => entry.id.value == records[0].id);
        expect(cached.record.enteredAmount, '1');
        // The record is corrected while the splice resolution waits on the
        // injected seam; the resolution then arrives holding the stale cached
        // row under a generation the store no longer reports.
        await store.correct(
          commandId: newCommandId(),
          recordId: records[0].id,
          expectedRevision: records[0].revision,
          amount: '7',
          actualAt: records[0].actualAt,
        );
        // The live window first reflects the correction through the bounded
        // watch; the splice candidate stays on the superseded row.
        final corrected = await awaitState(() => container.read(provider), (
          state,
        ) {
          final current = state.entries
              .whereType<RecordTimelineEntry>()
              .where((entry) => entry.id.value == records[0].id)
              .firstOrNull;
          return !state.loading &&
              current != null &&
              current.record.enteredAmount == '7';
        });
        final splice = container.read(provider.notifier).spliceEntry(cached);
        gate.complete(
          ResolvedHistoryEntry(
            entry: cached,
            queryIdentity: corrected.query!.identity,
            schemaVersion: corrected.schemaVersion,
            datasetGeneration: 'superseded-generation',
          ),
        );
        await splice;
        final after = container.read(provider);
        expect(after.query?.identity, seeded.query?.identity);
        final row = after.entries.whereType<RecordTimelineEntry>().firstWhere(
          (entry) => entry.id.value == records[0].id,
        );
        expect(
          row.record.enteredAmount,
          '7',
          reason: 'a superseded splice never regresses the corrected row',
        );
        expect(row.record.revision, greaterThan(cached.record.revision));
      },
    );

    test('a limit-one anchored window re-mints its continuation when rows appear below', () async {
      final windowed = TimelineQuery(
        filter: TimelineFilter(),
        displayZone: 'UTC',
        limit: 1,
      );
      final newer = await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 19, 10),
      );
      final older = await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        amount: '2',
        actualAt: DateTime.utc(2026, 10, 18, 10),
      );
      final container = spliceContainer();
      addTearDown(container.dispose);
      final provider = historyControllerProvider('limit-one');
      await container.read(recordStoreProvider.future);
      addTearDown(container.listen(provider, (_, _) {}).close);
      final controller = container.read(provider.notifier);
      await controller.configure(windowed);
      await awaitState(() => container.read(provider), (state) {
        return !state.loading && state.entries.isNotEmpty;
      });
      final olderEntry =
          (await store.timeline(
                TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
              )).entries
              .whereType<RecordTimelineEntry>()
              .firstWhere((entry) => entry.id.value == older.id);
      await controller.seek(olderEntry);
      await awaitState(() => container.read(provider), (state) {
        return state.anchored && state.entries.single.id.value == older.id;
      });
      expect(container.read(provider).next, isNull);
      // A further matching row is recorded below the anchored window: the
      // aligned limit-one emission cannot carry it, so the window must
      // expose the continuation instead of leaving Next null forever.
      final added = await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        amount: '3',
        actualAt: DateTime.utc(2026, 10, 17, 10),
      );
      await awaitState(
        () => container.read(provider),
        (state) => state.next != null,
      );
      expect(container.read(provider).next, isNotNull);
      expect(newer.revision, greaterThan(0), reason: 'fixture sanity');
      await controller.older();
      final merged = await awaitState(() => container.read(provider), (state) {
        return state.entries.length == 2 && !state.olderLoading;
      });
      expect(merged.entries.map((entry) => entry.id.value), [
        older.id,
        added.id,
      ]);
      expect(
        merged.entries.map((entry) => entry.id.value).toSet().length,
        2,
        reason: 'no duplicate or lost matching rows at the limit-one anchor',
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
      f.container.read(routerProvider).go('/history?view=list');
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
    f.container.read(routerProvider).go('/history?view=list');
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
      f.container.read(routerProvider).go('/history?view=list');
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
      f.container.read(routerProvider).go('/history?view=list');
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
      f.container.read(routerProvider).go('/history?view=list');
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

  appTest('a stale splice cannot regress a record corrected again after it', (
    tester,
  ) async {
    final f = await launch(tester);
    final record = (await runIo(tester, () async {
      final records = await seededHistory(f.store);
      return records[20];
    }))!;
    // The row version captured before the inspections: the candidate a
    // delayed or stale splice could splice back.
    final stale = (await runIo(tester, () async {
      final initial = await f.store.timeline(
        TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
      );
      return initial.entries.whereType<RecordTimelineEntry>().firstWhere(
        (entry) => entry.id.value == record.id,
      );
    }))!;
    f.container.read(routerProvider).go('/history?view=list');
    await settle(tester);
    await settledWindow(
      tester,
      f,
      (state) =>
          state.query != null &&
          !state.loading &&
          state.entries.any((entry) => entry.id.value == record.id),
    );
    await inspectCard(tester, record);
    await tap(tester, 'Correct');
    await enter(tester, 'Amount', '7');
    await tap(tester, 'Save');
    await settledWindow(tester, f, (state) {
      final row = state.entries
          .whereType<RecordTimelineEntry>()
          .where((entry) => entry.id.value == record.id)
          .firstOrNull;
      return row != null && row.record.enteredAmount == '7';
    });
    // A second correction lands while the stale candidate stays cached:
    // a stale splice at this point must not regress revision, amount or date.
    final current = (await runIo(tester, () async {
      final now = (await f.store.recordById(record.id))!;
      await f.store.correct(
        commandId: newCommandId(),
        recordId: record.id,
        expectedRevision: now.revision,
        amount: '9',
        actualAt: now.actualAt,
        expectedPersonRevision: 2,
      );
      return now;
    }))!;
    await runIo(
      tester,
      () => f.container
          .read(
            historyControllerProvider(currentLocation(f.container).toString())
                .notifier,
          )
          .spliceEntry(stale),
    );
    final finalState = await settledWindow(tester, f, (state) {
      final row = state.entries
          .whereType<RecordTimelineEntry>()
          .where((entry) => entry.id.value == record.id)
          .firstOrNull;
      return row != null && row.record.enteredAmount == '9';
    });
    expect(finalState.stale, isFalse);
    final subject = finalState.entries
        .whereType<RecordTimelineEntry>()
        .firstWhere((entry) => entry.id.value == record.id);
    expect(subject.record.enteredAmount, '9');
    expect(subject.record.revision, greaterThan(stale.record.revision));
    expect(subject.record.actualAt.toUtc(), current.actualAt.toUtc());
    expect(
      find.textContaining('This entry moved to'),
      findsNothing,
      reason: 'the date never moved',
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  appTest(
    'an anchor leaving the snapshot while anchored drops the moved View and shows refresh',
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
            state.entries.any((entry) => entry.id.value == record.id),
      );
      // Move the entry to another day INSIDE the window: View reloads the
      // anchored window at its new position.
      await inspectCard(tester, record);
      await tap(tester, 'Correct');
      await enter(tester, 'Actual date', '2026-10-02');
      await tap(tester, 'Save');
      await settledWindow(
        tester,
        f,
        (state) =>
            state.query != null &&
            !state.loading &&
            state.entries.isNotEmpty &&
            // The corrected position stays in-filter, so the visible top
            // window may either keep the moved row withdrawn or re-land
            // it at its corrected timestamp. Either way the window must
            // not keep standing for the superseded October 4 row.
            state.entries.every(
              (entry) =>
                  entry.id.value != record.id ||
                  entry.occurredAt.toUtc() == DateTime.utc(2026, 10, 2, 10),
            ),
      );
      expect(find.textContaining('This entry moved to'), findsOneWidget);
      final jump = find.text('View').first;
      await tester.ensureVisible(jump);
      await settle(tester);
      await tester.tap(jump);
      final anchored = await settledWindow(
        tester,
        f,
        (state) =>
            state.anchored &&
            !state.loading &&
            state.entries.isNotEmpty &&
            !state.anchorUnavailable,
      );
      expect(anchored.entries.first.id.sortKey, 'r:${record.id}');
      // The anchor is corrected again to a day OUTSIDE the applied window
      // while the anchored window is visible: the bounded anchored watch
      // re-resolves the anchor, finds it out of the snapshot, and the
      // window must show refresh instead of an out-of-filter row or a
      // moved View built on its stored row.
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
          amount: current.enteredAmount,
          actualAt: DateTime.utc(2026, 9, 1, 10),
          expectedPersonRevision: 2,
        ),
      );
      final after = await settledWindow(
        tester,
        f,
        (state) => state.anchored && state.stale && state.anchorUnavailable,
      );
      await settle(tester);
      expect(
        after.entries.any((entry) => entry.id.value == record.id),
        isFalse,
        reason: 'the out-of-filter row is never kept visible',
      );
      expect(
        find.textContaining('This entry moved to'),
        findsNothing,
        reason: 'the unavailable anchor stops advertising View',
      );
      expect(
        find.textContaining('History changed'),
        findsOneWidget,
        reason: 'the refresh path stays offered without widening filters',
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
