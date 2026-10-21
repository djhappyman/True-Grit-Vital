import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import 'app_lock.dart';
import 'storage.dart';

export '../domain/history/history.dart';

typedef HistoryReader = Future<TimelinePage> Function(TimelineQuery);
typedef HistoryWatcher = Stream<TimelinePage> Function(TimelineQuery);
final historyReaderProvider = Provider<HistoryReader>(
  (ref) =>
      (query) async =>
          (await ref.read(recordStoreProvider.future)).timeline(query),
);
final historyWatcherProvider = Provider<HistoryWatcher>(
  (ref) => (query) async* {
    yield* (await ref.read(recordStoreProvider.future)).watchTimeline(query);
  },
);

/// A bounded browsing window. Only its first page is subscribed while visible.
class HistoryState {
  const HistoryState({
    this.query,
    this.entries = const [],
    this.next,
    this.loading = false,
    this.olderLoading = false,
    this.stale = false,
    this.refreshed = false,
    this.error,
    this.pages = 0,
    this.schemaVersion = 0,
    this.datasetGeneration = '',
    this.anchored = false,
  });
  final TimelineQuery? query;
  final List<TimelineEntry> entries;
  final TimelineCursor? next;
  final bool loading, olderLoading, stale, refreshed;
  final Object? error;
  final int pages;

  /// Cursor metadata from the latest page read, so a correction can mint an
  /// exact seek cursor without guessing the store identity.
  final int schemaVersion;
  final String datasetGeneration;

  /// True while the window starts at an explicitly sought entry rather than
  /// the top of the filtered list. Such a window holds its position and only
  /// re-reads on Refresh; the top subscription is not attached.
  final bool anchored;
}

final historyControllerProvider = NotifierProvider.autoDispose
    .family<HistoryController, HistoryState, String>(HistoryController.new);

class HistoryController extends Notifier<HistoryState> {
  HistoryController(this.routeIdentity);
  final String routeIdentity;
  StreamSubscription<TimelinePage>? _live;
  int _epoch = 0;
  bool _visible = true, atTop = true;
  static const maxWindowPages = 8;
  @override
  HistoryState build() {
    ref.watch(recordStoreProvider.select((s) => s.value?.generation));
    ref.onDispose(() {
      _epoch++;
      unawaited(_live?.cancel());
    });
    ref.listen(appLockProvider, (_, next) {
      if (next.locked) {
        _epoch++;
        unawaited(_live?.cancel());
        _live = null;
        state = HistoryState(
          query: state.query,
          refreshed: true,
          schemaVersion: state.schemaVersion,
          datasetGeneration: state.datasetGeneration,
        );
      } else if (next.ready && _visible && state.query != null) {
        configure(state.query!, force: true);
      }
    });
    return const HistoryState();
  }

  bool _current(int epoch) =>
      ref.mounted && _epoch == epoch && !ref.read(appLockProvider).locked;
  Future<void> configure(TimelineQuery query, {bool force = false}) async {
    if (!force && state.query?.identity == query.identity) return;
    final epoch = ++_epoch;
    await _live?.cancel();
    _live = null;
    if (!_current(epoch)) return;
    state = HistoryState(
      query: query.firstPage,
      loading: true,
      refreshed: force,
    );
    if (_visible) _subscribe(epoch);
  }

  void _subscribe(int epoch) {
    final query = state.query;
    // An anchored window is not the top of the filtered list; the top
    // subscription would compare a different page against it and mark the
    // window stale on every store change. Anchor windows re-read on Refresh.
    if (query == null ||
        !_current(epoch) ||
        !_visible ||
        state.anchored) {
      return;
    }
    _live = ref
        .read(historyWatcherProvider)(query.firstPage)
        .listen(
          (page) {
            if (!_visible ||
                !_current(epoch) ||
                page.queryIdentity != state.query?.identity) {
              return;
            }
            if (state.entries.isNotEmpty && (!atTop || state.pages > 1)) {
              if (_signature(page.entries) !=
                  _signature(state.entries.take(query.limit))) {
                state = HistoryState(
                  query: state.query,
                  entries: state.entries,
                  next: state.next,
                  stale: true,
                  pages: state.pages,
                  schemaVersion: page.schemaVersion,
                  datasetGeneration: page.datasetGeneration,
                );
              }
              return;
            }
            state = HistoryState(
              query: query,
              entries: page.entries,
              next: page.next,
              pages: 1,
              refreshed: state.refreshed,
              schemaVersion: page.schemaVersion,
              datasetGeneration: page.datasetGeneration,
            );
          },
          onError: (Object error) {
            if (!_current(epoch)) return;
            state = HistoryState(
              query: state.query,
              entries: state.entries,
              next: state.next,
              error: error,
              pages: state.pages,
              stale: state.entries.isNotEmpty,
              schemaVersion: state.schemaVersion,
              datasetGeneration: state.datasetGeneration,
            );
          },
        );
  }

  String _signature(Iterable<TimelineEntry> entries) => entries
      .map(
        (e) => switch (e) {
          RecordTimelineEntry() => '${e.id.sortKey}:${e.record.revision}',
          CombinedTimelineEntry() =>
            '${e.id.sortKey}:${e.components.map((c) => c.record.revision).join(',')}',
          SkippedTimelineEntry() => '${e.id.sortKey}:${e.action.revision}',
        },
      )
      .join('|');
  Future<void> visible(bool value) async {
    if (_visible == value) return;
    _visible = value;
    await _live?.cancel();
    _live = null;
    if (value) _subscribe(_epoch);
  }

  Future<void> refresh() async {
    final query = state.query;
    if (query == null) return;
    await configure(query.firstPage, force: true);
  }

  Future<void> older() async {
    final next = state.next, query = state.query;
    if (next == null || query == null || state.olderLoading || state.loading) {
      return;
    }
    final epoch = _epoch, previous = state;
    state = HistoryState(
      query: query,
      entries: previous.entries,
      next: next,
      olderLoading: true,
      stale: previous.stale,
      pages: previous.pages,
      schemaVersion: previous.schemaVersion,
      datasetGeneration: previous.datasetGeneration,
      anchored: previous.anchored,
    );
    try {
      final page = await ref.read(historyReaderProvider)(
        query.withCursor(next),
      );
      if (!_current(epoch) || page.queryIdentity != query.identity) return;
      final replacing = previous.pages >= maxWindowPages;
      final seen = <String>{};
      final merged = [
        for (final entry in [
          ...(replacing ? <TimelineEntry>[] : previous.entries),
          ...page.entries,
        ])
          if (seen.add(entry.id.sortKey)) entry,
      ];
      state = HistoryState(
        query: query,
        entries: List.unmodifiable(merged),
        next: page.next,
        pages: replacing ? 1 : previous.pages + 1,
        stale: previous.stale,
        refreshed: replacing,
        schemaVersion: page.schemaVersion,
        datasetGeneration: page.datasetGeneration,
        anchored: previous.anchored,
      );
    } catch (error) {
      if (!_current(epoch)) return;
      if (error is TimelineCursorException && error.code == 'cursor_expired') {
        await configure(query.firstPage, force: true);
        return;
      }
      state = HistoryState(
        query: query,
        entries: previous.entries,
        next: next,
        error: error,
        pages: previous.pages,
        stale: previous.stale,
        schemaVersion: previous.schemaVersion,
        datasetGeneration: previous.datasetGeneration,
        anchored: previous.anchored,
      );
    }
  }

  /// Restarts the window at an exact entry position, keeping filters and
  /// query identity. Used to follow a corrected or backfilled entry that
  /// moved outside the loaded range.
  Future<void> seek(TimelineEntry anchor) async {
    final query = state.query;
    if (query == null || state.loading || state.olderLoading) return;
    final TimelineCursor position;
    try {
      position = TimelineCursor.at(
        occurredAt: anchor.occurredAt,
        sortKey: anchor.id.sortKey,
        query: query,
        schemaVersion: state.schemaVersion,
        datasetGeneration: state.datasetGeneration,
      );
    } on TimelineCursorException {
      // Cursor metadata was not carried by a page read yet; do not invent it.
      return;
    }
    final epoch = ++_epoch;
    await _live?.cancel();
    _live = null;
    if (!_current(epoch)) return;
    state = HistoryState(
      query: query,
      loading: true,
      refreshed: true,
      schemaVersion: state.schemaVersion,
      datasetGeneration: state.datasetGeneration,
      anchored: true,
    );
    try {
      final page = await ref.read(historyReaderProvider)(
        query.withCursor(position),
      );
      if (!_current(epoch) || page.queryIdentity != query.identity) return;
      state = HistoryState(
        query: query,
        entries: [anchor, ...page.entries],
        next: page.next,
        pages: 1,
        refreshed: true,
        schemaVersion: page.schemaVersion,
        datasetGeneration: page.datasetGeneration,
        anchored: true,
      );
    } catch (error) {
      if (!_current(epoch)) return;
      state = HistoryState(
        query: query,
        error: error,
        schemaVersion: state.schemaVersion,
        datasetGeneration: state.datasetGeneration,
        anchored: true,
      );
    }
  }

  /// Replaces one visible row in place with its current version and keeps
  /// the window, position and cursor intact. Used when a correction changed
  /// the entry without moving it in the get order.
  void spliceEntry(TimelineEntry updated) {
    final query = state.query;
    if (query == null) return;
    final index = state.entries.indexWhere(
      (entry) => entry.id.sortKey == updated.id.sortKey,
    );
    if (index < 0) return;
    state = HistoryState(
      query: query,
      entries: List.unmodifiable([
        for (final (position, entry) in state.entries.indexed)
          if (position == index) updated else entry,
      ]),
      next: state.next,
      pages: state.pages,
      refreshed: true,
      stale: state.stale,
      schemaVersion: state.schemaVersion,
      datasetGeneration: state.datasetGeneration,
      anchored: state.anchored,
    );
  }

  /// Removes one visible row whose source no longer resolves, keeping the
  /// window position. Used when a correction removed the browsed entry.
  void withdrawEntry(TimelineEntryId id) {
    final query = state.query;
    if (query == null) return;
    final remaining = state.entries
        .where((entry) => entry.id.sortKey != id.sortKey)
        .toList();
    if (remaining.length == state.entries.length) return;
    state = HistoryState(
      query: query,
      entries: List.unmodifiable(remaining),
      next: state.next,
      pages: state.pages,
      stale: state.stale,
      schemaVersion: state.schemaVersion,
      datasetGeneration: state.datasetGeneration,
      anchored: state.anchored,
    );
  }
}

String historyLocation({
  FeedScope? scope,
  String? itemId,
  String? actualUnit,
  DateTime? fromInstant,
  DateTime? beforeInstant,
  Iterable<String> typeIds = const [],
  Iterable<String> eventIds = const [],
  String? anchor,
}) => Uri(
  path: '/history',
  queryParameters: {
    if (scope != null) 'scope': scope.isEveryone ? 'everyone' : scope.personId!,
    'item': ?itemId,
    'unit': ?actualUnit,
    if (fromInstant != null) 'from': fromInstant.toUtc().toIso8601String(),
    if (beforeInstant != null)
      'before': beforeInstant.toUtc().toIso8601String(),
    if (typeIds.isNotEmpty) 'type': typeIds.join(','),
    if (eventIds.isNotEmpty) 'event': eventIds.join(','),
    'anchor': ?anchor,
  },
).toString();
