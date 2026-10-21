import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import 'app_lock.dart';
import 'storage.dart';

export '../domain/history/history.dart';

typedef HistoryReader = Future<TimelinePage> Function(TimelineQuery);
typedef HistoryWatcher = Stream<TimelinePage> Function(TimelineQuery);
typedef HistoryAnchorReader = Future<TimelineAnchoredPage> Function(
  TimelineQuery,
  TimelineEntryId,
);
typedef HistoryAnchorWatcher = Stream<TimelineAnchoredPage> Function(
  TimelineQuery,
  TimelineEntryId,
);

/// Inspection-splice seam. Resolves an entry's CURRENT query-matching
/// version in one bounded transaction, so a correction between the caller's
/// fetch and this read cannot splice a stale revision back into the window.
typedef HistoryEntrySnapshotReader = Future<ResolvedHistoryEntry?> Function(
  TimelineQuery,
  TimelineEntryId,
);

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
final historyAnchorReaderProvider = Provider<HistoryAnchorReader>(
  (ref) =>
      (query, anchor) async =>
          (await ref.read(recordStoreProvider.future))
              .timelineAnchor(query, anchor: anchor),
);
final historyAnchorWatcherProvider = Provider<HistoryAnchorWatcher>(
  (ref) => (query, anchor) async* {
    yield* (await ref.read(recordStoreProvider.future))
        .watchTimelineAnchor(query, anchor);
  },
);
final historyEntrySnapshotProvider = Provider<HistoryEntrySnapshotReader>(
  (ref) =>
      (query, id) async =>
          (await ref.read(recordStoreProvider.future))
              .historyEntrySnapshot(query, id),
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
    this.anchorUnavailable = false,
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
  /// the top of the filtered list. Such a window keeps its position and is
  /// observed through the bounded anchored window of its first row, so a
  /// later correction or deletion updates it or marks it stale.
  final bool anchored;

  /// True when the sought anchor no longer resolves inside the current
  /// filtered snapshot. Such a window keeps its position and shows the stale
  /// refresh path instead of widening filters with an out-of-filter row.
  final bool anchorUnavailable;
}

final historyControllerProvider = NotifierProvider.autoDispose
    .family<HistoryController, HistoryState, String>(HistoryController.new);

class HistoryController extends Notifier<HistoryState> {
  HistoryController(this.routeIdentity);
  final String routeIdentity;
  StreamSubscription<Object>? _live;
  int _epoch = 0;
  bool _visible = true, atTop = true;
  static const maxWindowPages = 8;
  @override
  HistoryState build() {
    ref.watch(recordStoreProvider.select((s) => s.value?.generation));
    ref.listen(recordStoreProvider, (previous, next) {
      // While the store is loading, errored or replaced no pending private
      // work may finish on a retired snapshot; the settled store and the
      // UI's reconfigured query own the next window state instead.
      if (next.isLoading || next.hasError) {
        _epoch++;
        unawaited(_live?.cancel());
        _live = null;
      } else if ((previous?.isLoading == true || previous?.hasError == true) &&
          next.hasValue &&
          _visible &&
          state.query != null) {
        unawaited(configure(state.query!, force: true));
      }
    });
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

  /// The settled store's dataset identity, or null while the store is
  /// loading, errored or replaced. A retained loading AsyncValue must never
  /// be read as the current store, so a retired generation never passes or
  /// fences any window work.
  String? get _storeGeneration {
    final snapshot = ref.read(recordStoreProvider);
    if (!snapshot.hasValue || snapshot.isLoading || snapshot.hasError) {
      return null;
    }
    return snapshot.requireValue.generation;
  }

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
    final anchored = state.anchored && state.entries.isNotEmpty;
    // The anchored watcher resolves [watched] once at subscribe time: the
    // actually observed anchor identity, not whatever row happens to come
    // first later. Withdrawals and staleness must never retire a row behind
    // the observed identity. A window with no rows has no watched anchor.
    final watched = state.entries.isNotEmpty ? state.entries.first.id : null;
    void onError(Object error, StackTrace stackTrace) {
      if (!_current(epoch)) return;
      state = HistoryState(
        query: state.query,
        entries: state.entries,
        next: state.next,
        error: error,
        pages: state.pages,
        stale: state.entries.isNotEmpty || state.anchored,
        anchored: state.anchored,
        anchorUnavailable: state.anchorUnavailable,
        schemaVersion: state.schemaVersion,
        datasetGeneration: state.datasetGeneration,
      );
    }

    if (anchored) {
      // The anchored window keeps its position and updates in place when the
      // emission still aligns with the loaded rows.
      _live = ref
          .read(historyAnchorWatcherProvider)(query, state.entries.first.id)
          .listen((page) {
            if (!_visible ||
                !_current(epoch) ||
                page.queryIdentity != state.query?.identity ||
                page.datasetGeneration != _storeGeneration) {
              return;
            }
            _applyAnchorPage(page, watched!);
          }, onError: onError);
      return;
    }
    _live = ref.read(historyWatcherProvider)(query.firstPage).listen((page) {
      if (!_visible ||
          !_current(epoch) ||
          page.queryIdentity != state.query?.identity ||
          page.datasetGeneration != _storeGeneration) {
        return;
      }
      if (state.entries.isNotEmpty && (!atTop || state.pages > 1)) {
        if (_signature(page.entries) !=
            _signature(state.entries.take(query.limit))) {
          state = HistoryState(
            query: query,
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
    }, onError: onError);
  }

  /// Applies one bounded anchored window emission.
  ///
  /// Parent order that still aligns and shows only newer versions of the
  /// same rows is spliced in place, so an edit after seeking updates the
  /// window visibly. Rows that moved out of the snapshot, dropped or
  /// reordered parents leave the position intact and mark the window stale,
  /// and an anchor that no longer resolves keeps the position with the
  /// refresh path visible instead of silently widening filters.
  void _applyAnchorPage(TimelineAnchoredPage page, TimelineEntryId watched) {
    final previous = state, query = previous.query;
    if (query == null) return;
    if (!page.anchorAvailable) {
      _markAnchorStale(page, previous, watched);
      return;
    }
    // When the watched anchor was withdrawn earlier, the window's first row
    // no longer stands for the observed anchor: a fresh emission anchored at
    // the watched row re-lands the window instead of comparing unrelated
    // rows, so availability recovers coherently behind the same identity.
    final recovered =
        previous.entries.isEmpty ||
        previous.entries.first.id.sortKey != watched.sortKey;
    if (recovered) {
      if (page.entries.isEmpty ||
          page.entries.first.id.sortKey != watched.sortKey) {
        // The emission does not stand for a window anchored at the watched
        // row: keep the withdrawn posture and the refresh path.
        _markAnchorStale(page, previous, watched);
        return;
      }
      state = HistoryState(
        query: query,
        entries: page.entries,
        next: _cursorFrom(page, query),
        pages: previous.pages,
        stale: false,
        refreshed: previous.refreshed,
        schemaVersion: page.schemaVersion,
        datasetGeneration: page.datasetGeneration,
        anchored: true,
        anchorUnavailable: false,
      );
      return;
    }
    final window = previous.entries.take(page.entries.length).toList();
    final aligned =
        page.entries.length <= previous.entries.length &&
        window.indexed.every(
          (pair) => pair.$2.id.sortKey == page.entries[pair.$1].id.sortKey,
        );
    if (!aligned) {
      _markAnchorStale(page, previous, watched);
      return;
    }
    if (page.entries.length < previous.entries.length) {
      // A shorter emission covers the first page of a wider window: keep the
      // position untouched unless the observed page itself changed. The tail
      // pages are not revalidated by this emission, so an earlier stale
      // claim stays readable.
      if (_signature(window) == _signature(page.entries)) return;
      _markAnchorStale(page, previous, watched);
      return;
    }
    // The visible window is fully covered by the aligned emission, so the
    // continuation is re-minted from the CURRENT page metadata instead of
    // being retained: a moved single-row anchor keeps Next at its new
    // position, and a page whose hasMore changed exposes the continuation
    // immediately instead of leaving Next null forever.
    final next = _cursorFrom(page, query);
    final unchanged =
        _signature(previous.entries) == _signature(page.entries) &&
        ((next == null) == (previous.next == null)) &&
        (next == null || next.encode() == previous.next!.encode());
    if (unchanged) {
      // The window already mirrors the current emission, so any earlier
      // stale claim about it is out of date.
      if (previous.stale) {
        state = HistoryState(
          query: query,
          entries: previous.entries,
          next: previous.next,
          pages: previous.pages,
          refreshed: previous.refreshed,
          schemaVersion: previous.schemaVersion,
          datasetGeneration: previous.datasetGeneration,
          anchored: true,
          anchorUnavailable: false,
        );
      }
      return;
    }
    state = HistoryState(
      query: query,
      entries: page.entries,
      next: next,
      pages: previous.pages,
      stale: false,
      refreshed: previous.refreshed,
      schemaVersion: page.schemaVersion,
      datasetGeneration: page.datasetGeneration,
      anchored: true,
      anchorUnavailable: false,
    );
  }

  TimelineCursor? _cursorFrom(TimelineAnchoredPage page, TimelineQuery query) =>
      !page.hasMore || page.entries.isEmpty
      ? null
      : TimelineCursor.at(
          occurredAt: page.entries.last.occurredAt,
          sortKey: page.entries.last.id.sortKey,
          query: query,
          schemaVersion: page.schemaVersion,
          datasetGeneration: page.datasetGeneration,
        );

  void _markAnchorStale(
    TimelineAnchoredPage page,
    HistoryState previous,
    TimelineEntryId watched,
  ) {
    final query = previous.query;
    if (query == null) return;
    // The observed anchor row itself no longer resolves inside the filtered
    // snapshot, so only an unavailable emission may retire it: withdraw
    // exactly the watched identity from the anchored window while the
    // in-filter rows behind it keep their position and the refresh path is
    // offered. A repeated unavailable emission about the same identity must
    // never retire an unrelated new first row. An available emission that
    // misaligned only keeps the position claim, never a row.
    final entries = !page.anchorAvailable
        ? List<TimelineEntry>.unmodifiable(
            previous.entries.where(
              (entry) => entry.id.sortKey != watched.sortKey,
            ),
          )
        : previous.entries;
    state = HistoryState(
      query: query,
      entries: entries,
      next: previous.next,
      pages: previous.pages,
      stale: true,
      schemaVersion: page.schemaVersion,
      datasetGeneration: page.datasetGeneration,
      anchored: true,
      // An emission that says the anchor no longer resolves has the last
      // word, so an unavailable anchor never keeps advertising the moved
      // View offer built on its stored row. A later emission anchored at
      // the watched row again re-lands the window and clears it.
      anchorUnavailable: previous.anchorUnavailable || !page.anchorAvailable,
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
    if (!ref.mounted) return;
    if (_visible == value) return;
    _visible = value;
    final epoch = ++_epoch;
    final live = _live;
    _live = null;
    await live?.cancel();
    if (!_current(epoch)) return;
    if (!value) {
      // A hidden window owns no more pending private work: a seek or splice
      // captured before the page lost visibility never applies unseen. Lock,
      // dispose, replacement reload and reconfigure fence the same way.
      return;
    }
    final query = state.query;
    if (query == null) return;
    if (state.loading || state.olderLoading) {
      // An interrupted page or seek read never parks a stuck load: restart
      // the same filters and offer any position path again.
      await configure(query.firstPage, force: true);
      return;
    }
    _subscribe(_epoch);
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
      anchorUnavailable: previous.anchorUnavailable,
    );
    try {
      final page = await ref.read(historyReaderProvider)(
        query.withCursor(next),
      );
      if (!ref.mounted || !_current(epoch)) return;
      final storeGeneration = _storeGeneration;
      if (storeGeneration == null ||
          page.datasetGeneration != storeGeneration ||
          page.queryIdentity != query.identity) {
        return;
      }
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
        anchorUnavailable: previous.anchorUnavailable,
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
        anchorUnavailable: previous.anchorUnavailable,
      );
    }
  }

  /// Restarts the window at an exact entry position, keeping filters and
  /// query identity. Used to follow a corrected or backfilled entry that
  /// moved outside the loaded range.
  ///
  /// One bounded store read validates the anchor against the current
  /// filtered snapshot: a deleted, re-voided or moved-out-of-filter anchor
  /// keeps the position and shows the stale refresh path instead of forcing
  /// a stale row into the window or widening filters.
  Future<void> seek(TimelineEntry anchor) async {
    final query = state.query;
    if (query == null || state.loading || state.olderLoading) return;
    final epoch = ++_epoch;
    await _live?.cancel();
    _live = null;
    if (!_current(epoch)) return;
    final previous = state;
    state = HistoryState(
      query: query,
      loading: true,
      refreshed: true,
      schemaVersion: previous.schemaVersion,
      datasetGeneration: previous.datasetGeneration,
      anchored: true,
    );
    try {
      final page = await ref.read(historyAnchorReaderProvider)(
        query,
        anchor.id,
      );
      if (!ref.mounted || !_current(epoch)) return;
      final storeGeneration = _storeGeneration;
      if (storeGeneration == null ||
          page.datasetGeneration != storeGeneration) {
        // The anchored page resolved on a loading, retired or replaced
        // store: a later settled re-read owns the window state.
        return;
      }
      if (page.queryIdentity != query.identity) return;
      if (!page.anchorAvailable) {
        state = HistoryState(
          query: query,
          entries: previous.entries,
          next: previous.next,
          pages: previous.pages,
          refreshed: false,
          stale: true,
          schemaVersion: page.schemaVersion,
          datasetGeneration: page.datasetGeneration,
          anchored: true,
          anchorUnavailable: true,
        );
        if (_visible) _subscribe(epoch);
        return;
      }
      state = HistoryState(
        query: query,
        entries: page.entries,
        next: !page.hasMore || page.entries.isEmpty
            ? null
            : TimelineCursor.at(
                occurredAt: page.entries.last.occurredAt,
                sortKey: page.entries.last.id.sortKey,
                query: query,
                schemaVersion: page.schemaVersion,
                datasetGeneration: page.datasetGeneration,
              ),
        pages: 1,
        refreshed: true,
        schemaVersion: page.schemaVersion,
        datasetGeneration: page.datasetGeneration,
        anchored: true,
      );
      if (_visible) _subscribe(epoch);
    } catch (error) {
      if (!_current(epoch)) return;
      state = HistoryState(
        query: query,
        error: error,
        refreshed: true,
        pages: previous.pages,
        schemaVersion: previous.schemaVersion,
        datasetGeneration: previous.datasetGeneration,
        anchored: true,
      );
    }
  }

  /// Replaces one visible row in place with its current version and keeps
  /// the window, position and cursor intact. Used when a correction changed
  /// the entry without moving it in the get order.
  ///
  /// The bounded snapshot seam resolves the entry's CURRENT stored version
  /// through the same branch SQL and combined parent match as `timeline`,
  /// so the caller's possibly stale cached revision is never spliced back:
  /// the row arrives validated with the resolution's schema and generation.
  /// An entry that left the filters, resolved at a superseded generation, or
  /// landed after a reconfigure or lock restarts the window, is withdrawn
  /// and the window marked stale; a moved parent identity never forces the
  /// cached row.
  Future<void> spliceEntry(TimelineEntry updated) async {
    final query = state.query;
    if (query == null) return;
    final epoch = _epoch, sortKey = updated.id.sortKey;
    if (!ref.mounted || !_current(epoch)) return;
    if (!state.entries.any((entry) => entry.id.sortKey == sortKey)) return;
    ResolvedHistoryEntry? resolved;
    try {
      resolved = await ref.read(historyEntrySnapshotProvider)(
        query,
        updated.id,
      );
    } on TimelineQueryException {
      // The bounded seam reports too-broad event filters as typed failures;
      // treat them as outside the snapshot so no unvalidated row stays, and
      // Refresh re-reads through the normal bounded path.
      resolved = null;
    } on CommandConflict {
      // The store refuses reads while locked or closing: a later settled
      // window wins and nothing is spliced here.
      resolved = null;
    }
    // After the await and before ANY ref or state access again: a disposed,
    // locked, hidden-facing replacement epoch or superseded controller never
    // touches the window.
    if (!ref.mounted || !_current(epoch)) return;
    final storeState = ref.read(recordStoreProvider);
    if (!storeState.hasValue || storeState.isLoading || storeState.hasError) {
      // The store that is loading, replaced or errored owns the next window
      // state: a splice started on the retained previous store is retired.
      return;
    }
    if (resolved != null &&
        storeState.requireValue.generation != resolved.datasetGeneration) {
      // The dataset moved on after the resolution on a replaced store: the
      // originating job is superseded and a later emission owns the
      // window state.
      return;
    }
    if (state.query?.identity != query.identity) return;
    final index = state.entries.indexWhere(
      (entry) => entry.id.sortKey == sortKey,
    );
    if (index < 0) return;
    final visible = state.entries[index];
    if (resolved == null ||
        resolved.queryIdentity != query.identity ||
        resolved.entry.id.sortKey != sortKey) {
      // A null or mismatched resolution means the entry's row at that
      // position no longer stands in the current filtered snapshot. A job
      // that a fresher window emission already superseded with a newer
      // visible version must never withdraw it.
      if (_hasNewerRevision(updated, visible)) return;
      state = HistoryState(
        query: query,
        entries: List.unmodifiable([
          for (final (position, entry) in state.entries.indexed)
            if (position != index) entry,
        ]),
        next: state.next,
        pages: state.pages,
        stale: true,
        schemaVersion: state.schemaVersion,
        datasetGeneration: state.datasetGeneration,
        anchored: state.anchored,
        anchorUnavailable: state.anchorUnavailable,
      );
      return;
    }
    if (resolved.entry.occurredAt != visible.occurredAt) {
      // The row changed position while the snapshot read ran: applying it
      // in place would force an out-of-order row and no repaired cursor, so
      // the current row is withdrawn and the refresh path is offered for a
      // bounded re-read instead of a forced reorder.
      state = HistoryState(
        query: query,
        entries: List.unmodifiable([
          for (final (position, entry) in state.entries.indexed)
            if (position != index) entry,
        ]),
        next: state.next,
        pages: state.pages,
        stale: true,
        schemaVersion: state.schemaVersion,
        datasetGeneration: state.datasetGeneration,
        anchored: state.anchored,
        anchorUnavailable: state.anchorUnavailable,
      );
      return;
    }
    if (_hasNewerRevision(resolved.entry, visible)) {
      // Same-generation superseded content: the live window already reaches
      // a newer version of the row, so the stale job is rejected without a
      // regression to the older revision.
      return;
    }
    if (_signature([resolved.entry]) == _signature([visible])) return;
    state = HistoryState(
      query: query,
      entries: List.unmodifiable([
        for (final (position, entry) in state.entries.indexed)
          if (position == index) resolved.entry else entry,
      ]),
      next: state.next,
      pages: state.pages,
      refreshed: true,
      stale: state.stale,
      schemaVersion: resolved.schemaVersion,
      datasetGeneration: resolved.datasetGeneration,
      anchored: state.anchored,
      anchorUnavailable: state.anchorUnavailable,
    );
  }

  bool _hasNewerRevision(TimelineEntry before, TimelineEntry after) =>
      switch ((before, after)) {
        (RecordTimelineEntry old, RecordTimelineEntry current) =>
          current.record.revision > old.record.revision,
        (SkippedTimelineEntry old, SkippedTimelineEntry current) =>
          current.action.revision > old.action.revision,
        (CombinedTimelineEntry old, CombinedTimelineEntry current) =>
          current.components.any(
            (current) => old.components.every(
              (old) =>
                  old.record.id != current.record.id ||
                  old.record.revision < current.record.revision,
            ),
          ),
        _ => true,
      };

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
      anchorUnavailable: state.anchorUnavailable,
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
