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
  });
  final TimelineQuery? query;
  final List<TimelineEntry> entries;
  final TimelineCursor? next;
  final bool loading, olderLoading, stale, refreshed;
  final Object? error;
  final int pages;
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
        state = HistoryState(query: state.query, refreshed: true);
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
    if (query == null || !_current(epoch) || !_visible) return;
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
      );
    }
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
