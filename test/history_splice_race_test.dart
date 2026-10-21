import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/history.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/app_auth.dart';

/// Deterministic fake lock so controller tests can gate on the lock
/// lifecycle without the platform auth bootstrap.
final class _TestingLockController extends AppLockController {
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
Future<HistoryState> _awaitState(
  HistoryState Function() read,
  bool Function(HistoryState state) ready,
) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    final state = read();
    if (ready(state)) return state;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('the history window never reached the expected state');
}

void main() {
  group('the history splice race repairs', () {
    late Directory dir;
    late RecordStore store;
    late SubstanceItem item;
    final key = List.generate(32, (i) => i + 1);
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vital-splice-races-');
      final path = '${dir.path}/db';
      store = await RecordStore.open(path: path, key: key, isNew: true);
      item = await store.createItem(
        commandId: newCommandId(),
        name: 'Splice race medicine',
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
      Completer<ResolvedHistoryEntry?>? entryGate,
      StreamController<TimelineAnchoredPage>? anchorStream,
      StreamController<TimelinePage>? pages,
    }) => ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() => Future.value(store)),
        appLockProvider.overrideWith(() => _TestingLockController()),
        if (entryGate != null)
          historyEntrySnapshotProvider.overrideWithValue(
            (query, id) => entryGate.future,
          ),
        if (anchorStream != null)
          historyAnchorWatcherProvider.overrideWithValue(
            (query, anchor) => anchorStream.stream,
          ),
        if (pages != null)
          historyWatcherProvider.overrideWithValue((query) => pages.stream),
      ],
    );

    test(
      'lead: repeated unavailable anchor emissions preserve other rows',
      () async {
        final records = [
          for (var i = 0; i < 3; i++)
            await store.record(
              commandId: newCommandId(),
              itemId: item.id,
              amount: '1',
              actualAt: DateTime.utc(2026, 10, 17 + i, 10),
            ),
        ];
        final stream = StreamController<TimelineAnchoredPage>.broadcast(
          sync: true,
        );
        addTearDown(stream.close);
        final container = spliceContainer(anchorStream: stream);
        addTearDown(container.dispose);
        await container.read(recordStoreProvider.future);
        final provider = historyControllerProvider('repeat-missing');
        addTearDown(container.listen(provider, (_, _) {}).close);
        final controller = container.read(provider.notifier);
        final query = TimelineQuery(
          filter: TimelineFilter(),
          displayZone: 'UTC',
          limit: 3,
        );
        await controller.configure(query);
        final loaded = await _awaitState(
          () => container.read(provider),
          (state) => state.entries.length == records.length,
        );
        await controller.seek(loaded.entries.first);
        await _awaitState(
          () => container.read(provider),
          (state) => state.anchored && state.entries.length == 3,
        );
        final missing = TimelineAnchoredPage(
          queryIdentity: query.identity,
          schemaVersion: loaded.schemaVersion,
          datasetGeneration: store.generation,
          entries: const [],
          anchorAvailable: false,
          hasMore: false,
        );
        stream.add(missing);
        expect(container.read(provider).entries.length, 2);
        stream.add(missing);
        expect(
          container.read(provider).entries.length,
          2,
          reason:
              'the second unavailable emission must not retire an unrelated '
              'new first row; only the watched anchor is withdrawn once',
        );
        expect(
          container
              .read(provider)
              .entries
              .map((entry) => entry.id.value)
              .contains(records[2].id),
          isFalse,
          reason: 'the watched anchor row stays withdrawn',
        );
        expect(
          container
              .read(provider)
              .entries
              .map((entry) => entry.id.value)
              .toSet(),
          {records[0].id, records[1].id},
          reason: 'the two unrelated in-filter rows keep their position',
        );
      },
    );

    test('a combined splice preserves every component revision', () async {
      final at = DateTime.utc(2026, 10, 19, 10);
      var first = await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        amount: '1',
        actualAt: at,
      );
      for (var i = 0; i < 2; i++) {
        first = await store.correct(
          commandId: newCommandId(),
          recordId: first.id,
          expectedRevision: first.revision,
          amount: '${i + 2}',
          actualAt: at,
        );
      }
      final second = await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        amount: '1',
        actualAt: at,
      );
      CombinedTimelineEntry entry(UseRecord last) => CombinedTimelineEntry(
        actionId: 'combined-splice',
        components: [
          CombinedTimelineComponent(position: 0, record: first, matched: true),
          CombinedTimelineComponent(position: 1, record: last, matched: true),
        ],
      );
      final old = entry(second);
      final corrected = await store.correct(
        commandId: newCommandId(),
        recordId: second.id,
        expectedRevision: second.revision,
        amount: '7',
        actualAt: at,
      );
      final fresh = entry(corrected);
      final gate = Completer<ResolvedHistoryEntry?>();
      final pages = StreamController<TimelinePage>.broadcast(sync: true);
      addTearDown(pages.close);
      final container = spliceContainer(entryGate: gate, pages: pages);
      addTearDown(container.dispose);
      await container.read(recordStoreProvider.future);
      final provider = historyControllerProvider('combined-revisions');
      addTearDown(container.listen(provider, (_, _) {}).close);
      final controller = container.read(provider.notifier);
      final query = TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC');
      final metadata = await store.timeline(query);
      TimelinePage page(CombinedTimelineEntry row) => TimelinePage(
        query: query,
        schemaVersion: metadata.schemaVersion,
        datasetGeneration: store.generation,
        entries: [row],
      );
      await controller.configure(query);
      pages.add(page(old));
      final splice = controller.spliceEntry(old);
      pages.add(page(fresh));
      gate.complete(
        ResolvedHistoryEntry(
          entry: old,
          queryIdentity: query.identity,
          schemaVersion: metadata.schemaVersion,
          datasetGeneration: store.generation,
        ),
      );
      await splice;
      final result =
          container.read(provider).entries.single as CombinedTimelineEntry;
      expect(result.components[1].record.enteredAmount, '7');
      expect(result.components[1].record.revision, corrected.revision);
    });

    test(
      'a settled same-generation reload reattaches the visible query',
      () async {
        final record = await store.record(
          commandId: newCommandId(),
          itemId: item.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 19, 10),
        );
        Completer<RecordStore>? reload;
        var subscriptions = 0;
        final container = ProviderContainer(
          overrides: [
            recordStoreProvider.overrideWith(
              (ref) => reload?.future ?? Future.value(store),
            ),
            appLockProvider.overrideWith(_TestingLockController.new),
            historyWatcherProvider.overrideWithValue((query) {
              subscriptions++;
              return store.watchTimeline(query);
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(recordStoreProvider.future);
        final provider = historyControllerProvider('reload-visible');
        addTearDown(container.listen(provider, (_, _) {}).close);
        final controller = container.read(provider.notifier);
        await controller.configure(
          TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
        );
        await _awaitState(
          () => container.read(provider),
          (state) => state.entries.isNotEmpty,
        );
        expect(subscriptions, 1);
        reload = Completer<RecordStore>();
        container.invalidate(recordStoreProvider);
        expect(container.read(recordStoreProvider).isLoading, isTrue);
        reload.complete(store);
        await container.read(recordStoreProvider.future);
        await _awaitState(
          () => container.read(provider),
          (state) => !state.loading && subscriptions == 2,
        );
        await store.correct(
          commandId: newCommandId(),
          recordId: record.id,
          expectedRevision: record.revision,
          amount: '7',
          actualAt: record.actualAt,
        );
        await _awaitState(
          () => container.read(provider),
          (state) => state.entries.whereType<RecordTimelineEntry>().any(
            (entry) => entry.record.enteredAmount == '7',
          ),
        );
      },
    );

    test('lead: a completed splice is safe after disposal', () async {
      await store.record(
        commandId: newCommandId(),
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 19, 10),
      );
      final gate = Completer<ResolvedHistoryEntry?>();
      final container = spliceContainer(entryGate: gate);
      await container.read(recordStoreProvider.future);
      final provider = historyControllerProvider('disposed-splice');
      container.listen(provider, (_, _) {});
      final controller = container.read(provider.notifier);
      final query = TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC');
      await controller.configure(query);
      final loaded = await _awaitState(
        () => container.read(provider),
        (state) => state.entries.isNotEmpty,
      );
      final pending = controller.spliceEntry(loaded.entries.first);
      container.dispose();
      gate.complete(
        ResolvedHistoryEntry(
          entry: loaded.entries.first,
          queryIdentity: query.identity,
          schemaVersion: loaded.schemaVersion,
          datasetGeneration: store.generation,
        ),
      );
      await pending;
    });

    test(
      'lead: a same-generation splice cannot regress a live corrected row',
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
        final container = spliceContainer(entryGate: gate);
        addTearDown(container.dispose);
        final provider = historyControllerProvider('same-generation');
        await container.read(recordStoreProvider.future);
        addTearDown(container.listen(provider, (_, _) {}).close);
        final controller = container.read(provider.notifier);
        final query = TimelineQuery(
          filter: TimelineFilter(),
          displayZone: 'UTC',
        );
        await controller.configure(query);
        final seeded = await _awaitState(() => container.read(provider), (
          state,
        ) {
          final row = state.entries
              .whereType<RecordTimelineEntry>()
              .where((entry) => entry.id.value == records[0].id)
              .firstOrNull;
          return !state.loading &&
              row != null &&
              row.record.revision == records[0].revision;
        });
        final cached = seeded.entries
            .whereType<RecordTimelineEntry>()
            .firstWhere((entry) => entry.id.value == records[0].id);
        expect(cached.record.enteredAmount, '1');
        // An ordinary correction lands through the live watch first; the
        // dataset generation does not change, so only revision coherence
        // can reject the stale splice result.
        await store.correct(
          commandId: newCommandId(),
          recordId: records[0].id,
          expectedRevision: records[0].revision,
          amount: '7',
          actualAt: records[0].actualAt,
        );
        final corrected = await _awaitState(() => container.read(provider), (
          state,
        ) {
          final row = state.entries
              .whereType<RecordTimelineEntry>()
              .where((entry) => entry.id.value == records[0].id)
              .firstOrNull;
          return !state.loading &&
              row != null &&
              row.record.enteredAmount == '7';
        });
        final splice = controller.spliceEntry(cached);
        gate.complete(
          ResolvedHistoryEntry(
            entry: cached,
            queryIdentity: corrected.query!.identity,
            schemaVersion: corrected.schemaVersion,
            datasetGeneration: store.generation,
          ),
        );
        await splice;
        final after = container.read(provider);
        expect(after.error, isNull);
        final row = after.entries.whereType<RecordTimelineEntry>().firstWhere(
          (entry) => entry.id.value == records[0].id,
        );
        expect(
          row.record.enteredAmount,
          '7',
          reason: 'the same-generation stale splice never regresses the row',
        );
        expect(row.record.revision, greaterThan(cached.record.revision));
      },
    );

    test(
      'lead: a current row that moved during a splice is never forced in place',
      () async {
        final records = [
          for (var i = 0; i < 3; i++)
            await store.record(
              commandId: newCommandId(),
              itemId: item.id,
              amount: '${i + 1}',
              actualAt: DateTime.utc(2026, 10, 17 + i, 10),
            ),
        ];
        final gate = Completer<ResolvedHistoryEntry?>();
        final container = spliceContainer(entryGate: gate);
        addTearDown(container.dispose);
        final provider = historyControllerProvider('moved-during-read');
        await container.read(recordStoreProvider.future);
        addTearDown(container.listen(provider, (_, _) {}).close);
        final controller = container.read(provider.notifier);
        await controller.configure(
          TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
        );
        final seeded = await _awaitState(() => container.read(provider), (
          state,
        ) {
          final row = state.entries
              .whereType<RecordTimelineEntry>()
              .where((entry) => entry.id.value == records[1].id)
              .firstOrNull;
          return !state.loading && row != null;
        });
        final cached = seeded.entries
            .whereType<RecordTimelineEntry>()
            .firstWhere((entry) => entry.id.value == records[1].id);
        final splice = controller.spliceEntry(cached);
        // The row moves to a later day while the resolution waits on the
        // injected seam; the live window reorders around it at the same
        // generation.
        await store.correct(
          commandId: newCommandId(),
          recordId: records[1].id,
          expectedRevision: records[1].revision,
          amount: '9',
          actualAt: DateTime.utc(2026, 10, 25, 10),
        );
        await _awaitState(() => container.read(provider), (state) {
          final row = state.entries
              .whereType<RecordTimelineEntry>()
              .where((entry) => entry.id.value == records[1].id)
              .firstOrNull;
          return !state.loading &&
              row != null &&
              row.record.actualAt == DateTime.utc(2026, 10, 25, 10);
        });
        gate.complete(
          ResolvedHistoryEntry(
            entry: cached,
            queryIdentity: seeded.query!.identity,
            schemaVersion: seeded.schemaVersion,
            datasetGeneration: store.generation,
          ),
        );
        await splice;
        final after = container.read(provider);
        expect(after.error, isNull);
        expect(
          after.stale,
          isTrue,
          reason: 'a moved current row keeps the refresh path, never forced',
        );
        expect(
          after.entries.any((entry) => entry.id.value == records[1].id),
          isFalse,
          reason:
              'neither the stale version nor the moved one stays in an '
              'out-of-order place; refresh re-reads the bounded window',
        );
        final remaining = [
          for (final entry in after.entries)
            if (entry is RecordTimelineEntry) entry.record.actualAt,
        ];
        final ordered = [...remaining]..sort((a, b) => b.compareTo(a));
        expect(remaining, ordered, reason: 'the window order stays intact');
      },
    );

    test('lead: a null resolution after a fresher window update cannot withdraw the row', () async {
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
      final container = spliceContainer(entryGate: gate);
      addTearDown(container.dispose);
      final provider = historyControllerProvider('stale-null');
      await container.read(recordStoreProvider.future);
      addTearDown(container.listen(provider, (_, _) {}).close);
      final controller = container.read(provider.notifier);
      await controller.configure(
        TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
      );
      final seeded = await _awaitState(() => container.read(provider), (state) {
        final row = state.entries
            .whereType<RecordTimelineEntry>()
            .where((entry) => entry.id.value == records[0].id)
            .firstOrNull;
        return !state.loading && row != null;
      });
      final cached = seeded.entries.whereType<RecordTimelineEntry>().firstWhere(
        (entry) => entry.id.value == records[0].id,
      );
      final splice = controller.spliceEntry(cached);
      await store.correct(
        commandId: newCommandId(),
        recordId: records[0].id,
        expectedRevision: records[0].revision,
        amount: '7',
        actualAt: records[0].actualAt,
      );
      final corrected = await _awaitState(() => container.read(provider), (
        state,
      ) {
        final row = state.entries
            .whereType<RecordTimelineEntry>()
            .where((entry) => entry.id.value == records[0].id)
            .firstOrNull;
        return !state.loading && row != null && row.record.enteredAmount == '7';
      });
      expect(corrected.stale, isFalse);
      // The resolution arrived before the window update but completes
      // after it: the stale null job must not withdraw the fresher row.
      gate.complete(null);
      await splice;
      final after = container.read(provider);
      expect(after.error, isNull);
      expect(after.stale, isFalse);
      final row = after.entries.whereType<RecordTimelineEntry>().firstWhere(
        (entry) => entry.id.value == records[0].id,
      );
      expect(row.record.enteredAmount, '7');
      expect(after.entries.length, records.length);
    });
  });
}
