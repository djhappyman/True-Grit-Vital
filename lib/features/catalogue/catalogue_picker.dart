import '../../ui/vital_ui.dart';

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/catalogue/catalogue_manager.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart' show Heading, LabelledInput;

/// Bounded typing pause. Explicit keyboard Search/Enter bypasses it.
const catalogueSearchDebounce = Duration(milliseconds: 300);

/// Production remains unavailable until G05 admits an exact source release.
/// Tests inject a reader built by the real manager with explicit synthetic admission.
/// Readers are resource-free immutable path/manifest values. Each bounded search
/// owns its worker and closes its SQLite handle in finally. A late provider load
/// therefore has no persistent handle to release. The mounted picker owns and
/// closes its coalescing session, invalidating queued and late search replies.
final catalogueLoaderProvider = Provider<Future<CatalogueReader?> Function()>(
  (ref) =>
      () async => null,
);
final catalogueReaderProvider = FutureProvider.autoDispose<CatalogueReader?>(
  retry: (_, _) => null,
  (ref) => ref.watch(catalogueLoaderProvider)(),
);

/// The picker's coalescing query surface. The shipped implementation wraps the
/// installed-reader session. Tests can supply delayed or conflicting replies
/// without changing catalogue admission or search semantics.
abstract interface class CatalogueSearchHandle {
  Future<CatalogueSearchPage?> search(String query);
  void close();
}

final class _SessionSearchHandle implements CatalogueSearchHandle {
  _SessionSearchHandle(CatalogueReader reader)
    : _session = CatalogueSearchSession(reader);
  final CatalogueSearchSession _session;

  @override
  Future<CatalogueSearchPage?> search(String query) => _session.search(query);

  @override
  void close() => _session.close();
}

CatalogueSearchHandle _openSession(CatalogueReader reader) =>
    _SessionSearchHandle(reader);

class CatalogueSource extends StatelessWidget {
  const CatalogueSource({super.key, required this.snapshot});
  final CatalogueSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = snapshot.product, m = snapshot.manifest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(p.name),
        Text(
          t.catalogueProduct(
            p.name,
            p.form.isEmpty ? t.catalogueMissing : p.form,
            p.strength.isEmpty ? t.catalogueMissing : p.strength,
          ),
        ),
        Text(t.catalogueRelease(m.sourceId, m.version, m.releaseDate)),
        Text(t.catalogueAttribution(m.attribution)),
        Text(t.catalogueLicence(m.licence)),
      ],
    );
  }
}

/// A route-local session pins one verified source release throughout selection.
/// Latest-input generations also cover asynchronous reader loading and errors.
/// Typing waits for [catalogueSearchDebounce]; Enter/Search flushes once. Results
/// for a superseded query are neither rendered nor selectable.
class CataloguePicker extends ConsumerStatefulWidget {
  const CataloguePicker({
    super.key,
    required this.query,
    required this.onSelect,
    required this.onCustom,
    required this.enabled,
    this.createSearch = _openSession,
  });
  final TextEditingController query;
  final ValueChanged<CatalogueSnapshot> onSelect;
  final ValueChanged<String> onCustom;
  final bool enabled;

  /// Creates the coalescing search surface once the verified reader is pinned.
  final CatalogueSearchHandle Function(CatalogueReader reader) createSearch;

  @override
  ConsumerState<CataloguePicker> createState() => _CataloguePickerState();
}

class _CataloguePickerState extends ConsumerState<CataloguePicker> {
  CatalogueReader? reader;
  CatalogueSearchHandle? search;
  CatalogueSearchPage? page;
  bool loading = true, unavailable = false, failed = false, invalid = false;
  bool hasQuery = false;
  int generation = 0;
  Timer? debounce;
  String? inFlightQuery;
  late String lastQuery;
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    lastQuery = widget.query.text;
    hasQuery = widget.query.text.trim().isNotEmpty;
    widget.query.addListener(queryChanged);
    unawaited(runSearch());
  }

  @override
  void didUpdateWidget(covariant CataloguePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.query != widget.query;
    if (controllerChanged) {
      oldWidget.query.removeListener(queryChanged);
      widget.query.addListener(queryChanged);
      lastQuery = widget.query.text;
      hasQuery = widget.query.text.trim().isNotEmpty;
    }
    if (controllerChanged || oldWidget.enabled != widget.enabled) {
      if (!widget.enabled) {
        debounce?.cancel();
        generation++;
        inFlightQuery = null;
        page = null;
        loading = false;
      } else {
        restart();
      }
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    generation++;
    widget.query.removeListener(queryChanged);
    search?.close();
    focus.dispose();
    super.dispose();
  }

  /// A newer input always invalidates the previous generation before its reply
  /// can change loading, error or result state. Empty input resets immediately.
  void queryChanged() {
    final query = widget.query.text;
    if (query == lastQuery) return;
    lastQuery = query;
    final nextHasQuery = query.trim().isNotEmpty;
    debounce?.cancel();
    inFlightQuery = null;
    generation++;
    if (nextHasQuery) {
      if (!widget.enabled) {
        setState(() {
          hasQuery = true;
          loading = false;
          failed = false;
          invalid = false;
        });
        return;
      }
      setState(() {
        hasQuery = true;
        loading = true;
        failed = false;
        invalid = false;
      });
      debounce = Timer(catalogueSearchDebounce, () => unawaited(runSearch()));
      return;
    }
    setState(() {
      hasQuery = false;
      loading = false;
      page = null;
      failed = false;
      invalid = false;
      if (reader != null) unavailable = false;
    });
    if (widget.enabled) unawaited(runSearch(force: true));
  }

  /// Cancel any pending typing pause and search the current query immediately.
  /// A repeated flush for the query already in flight stays a single read.
  Future<void> runSearch({bool force = false}) async {
    debounce?.cancel();
    final current = generation;
    if (!mounted) return;
    if (!widget.enabled) {
      if (loading) setState(() => loading = false);
      return;
    }
    final query = widget.query.text, trimmed = query.trim();
    if (!force) {
      if (trimmed.isNotEmpty && inFlightQuery == query) return;
      final visible = page;
      if (trimmed.isNotEmpty &&
          visible != null &&
          visible.query.trim() == trimmed &&
          !loading &&
          !failed &&
          !invalid) {
        return;
      }
    }
    inFlightQuery = trimmed.isEmpty ? null : query;
    setState(() {
      loading = trimmed.isNotEmpty;
      failed = false;
      invalid = false;
      if (trimmed.isEmpty) {
        page = null;
        if (reader != null) unavailable = false;
      }
    });
    try {
      // Watching retains the auto-dispose reader while this picker is mounted.
      var pinned = reader;
      pinned ??= await ref.read(catalogueReaderProvider.future);
      if (!mounted || current != generation || !widget.enabled) return;
      if (pinned == null) {
        inFlightQuery = null;
        setState(() {
          page = null;
          unavailable = true;
          loading = false;
        });
        return;
      }
      reader = pinned;
      search ??= widget.createSearch(pinned);
      if (trimmed.isEmpty) {
        inFlightQuery = null;
        setState(() {
          loading = false;
          unavailable = false;
        });
        return;
      }
      final result = await search!.search(query);
      if (!mounted || current != generation || result == null) return;
      inFlightQuery = null;
      setState(() {
        page = result;
        loading = false;
        unavailable = false;
      });
    } catch (e) {
      if (!mounted || current != generation) return;
      inFlightQuery = null;
      setState(() {
        failed = e is! FormatException;
        invalid = e is FormatException;
        loading = false;
      });
    }
  }

  void submit() {
    if (!widget.enabled) return;
    debounce?.cancel();
    unawaited(runSearch());
  }

  void clear() {
    if (!widget.enabled) return;
    widget.query.clear();
    focus.requestFocus();
  }

  void restart() {
    debounce?.cancel();
    generation++;
    inFlightQuery = null;
    page = null;
    loading = widget.enabled && hasQuery;
    if (!widget.enabled || widget.query.text.trim().isEmpty) {
      unawaited(runSearch(force: true));
      return;
    }
    debounce = Timer(catalogueSearchDebounce, () => unawaited(runSearch()));
  }

  Future<void> retry() async {
    // Failed source loading is cached by Riverpod until invalidated. An existing
    // session remains pinned to its verified release even if the active pointer
    // has changed; retrying its bounded read must not switch the selection.
    if (reader == null) ref.invalidate(catalogueReaderProvider);
    await runSearch(force: true);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogueReaderProvider);
    final t = AppLocalizations.of(context);
    final query = widget.query.text.trim();
    // Only the reply for the current query may be shown or selected. An older
    // page is retained for a stable in-place refresh but never rendered.
    final result = page != null && page!.query.trim() == query ? page : null;
    final renderedGeneration = generation;
    final status = unavailable
        ? t.catalogueUnavailable
        : invalid
        ? t.catalogueQueryLimit
        : failed
        ? t.catalogueSearchFailure
        : loading || (query.isNotEmpty && result == null && widget.enabled)
        ? t.catalogueSearching
        : result == null
        ? t.catalogueStart
        : result.needsRefinement
        ? t.catalogueRefine
        : result.products.isEmpty
        ? t.catalogueNoMatch(result.query)
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.catalogue),
        Text(t.catalogueHelp),
        const SizedBox(height: 12),
        LabelledInput(
          label: t.catalogueSearch,
          controller: widget.query,
          focusNode: focus,
          enabled: widget.enabled,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => submit(),
        ),
        if (widget.enabled && hasQuery)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VitalButton.secondary(
              key: const ValueKey('catalogue-query-clear'),
              onPressed: clear,
              child: Text(t.catalogueClear),
            ),
          ),
        Semantics(liveRegion: true, child: Text(status)),
        if (failed)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VitalButton.secondary(
              onPressed: widget.enabled ? retry : null,
              child: Text(t.retry),
            ),
          ),
        if (result != null) ...[
          Text(
            t.catalogueRelease(
              result.manifest.sourceId,
              result.manifest.version,
              result.manifest.releaseDate,
            ),
          ),
          Text(t.catalogueAttribution(result.manifest.attribution)),
          Text(t.catalogueLicence(result.manifest.licence)),
          for (final p in result.products)
            Padding(
              key: ValueKey(
                '${result.manifest.version}:${p.conceptClass}:${p.code}',
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    t.catalogueProduct(
                      p.name,
                      p.form.isEmpty ? t.catalogueMissing : p.form,
                      p.strength.isEmpty ? t.catalogueMissing : p.strength,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    label: t.catalogueSelectContext(p.name, p.form, p.strength),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: VitalButton.secondary(
                        onPressed: widget.enabled
                            ? () {
                                if (!mounted ||
                                    !widget.enabled ||
                                    generation != renderedGeneration ||
                                    !identical(page, result) ||
                                    widget.query.text.trim() !=
                                        result.query.trim()) {
                                  return;
                                }
                                widget.onSelect(
                                  CatalogueSnapshot(
                                    product: p,
                                    manifest: result.manifest,
                                  ),
                                );
                              }
                            : null,
                        child: Text(t.catalogueSelect),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(t.catalogueCustom),
        Text(t.catalogueCustomHelp(widget.query.text)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: VitalButton.secondary(
              onPressed: widget.enabled
                  ? () => widget.onCustom(widget.query.text)
                  : null,
              child: Text(t.catalogueEnter),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
