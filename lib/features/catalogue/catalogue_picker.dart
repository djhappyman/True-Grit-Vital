import '../../ui/vital_ui.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/catalogue/catalogue_manager.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart' show Heading, LabelledInput;

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
class CataloguePicker extends ConsumerStatefulWidget {
  const CataloguePicker({
    super.key,
    required this.query,
    required this.onSelect,
    required this.onCustom,
    required this.enabled,
  });
  final TextEditingController query;
  final ValueChanged<CatalogueSnapshot> onSelect;
  final ValueChanged<String> onCustom;
  final bool enabled;
  @override
  ConsumerState<CataloguePicker> createState() => _CataloguePickerState();
}

class _CataloguePickerState extends ConsumerState<CataloguePicker> {
  CatalogueSearchSession? session;
  CatalogueSearchPage? page;
  bool loading = true, unavailable = false, failed = false, invalid = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    widget.query.addListener(search);
    unawaited(search());
  }

  @override
  void dispose() {
    generation++;
    widget.query.removeListener(search);
    session?.close();
    super.dispose();
  }

  Future<void> search() async {
    final current = ++generation, query = widget.query.text;
    setState(() {
      loading = true;
      failed = false;
      invalid = false;
      page = null;
    });
    try {
      // Watching retains the auto-dispose reader while this picker is mounted.
      final reader =
          session?.reader ?? await ref.read(catalogueReaderProvider.future);
      if (!mounted || current != generation) return;
      if (reader == null) {
        setState(() {
          unavailable = true;
          loading = false;
        });
        return;
      }
      session ??= CatalogueSearchSession(reader);
      if (query.trim().isEmpty) {
        setState(() {
          loading = false;
          unavailable = false;
        });
        return;
      }
      final result = await session!.search(query);
      if (!mounted || current != generation || result == null) return;
      setState(() {
        page = result;
        loading = false;
        unavailable = false;
      });
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        failed = e is! FormatException;
        invalid = e is FormatException;
        loading = false;
      });
    }
  }

  Future<void> retry() async {
    // Failed source loading is cached by Riverpod until invalidated. An existing
    // session remains pinned to its verified release even if the active pointer
    // has changed; retrying its bounded read must not switch the selection.
    if (session == null) ref.invalidate(catalogueReaderProvider);
    await search();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogueReaderProvider);
    final t = AppLocalizations.of(context), result = page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.catalogue),
        Text(t.catalogueHelp),
        const SizedBox(height: 12),
        LabelledInput(
          label: t.catalogueSearch,
          controller: widget.query,
          enabled: widget.enabled,
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            loading
                ? t.catalogueSearching
                : unavailable
                ? t.catalogueUnavailable
                : invalid
                ? t.catalogueQueryLimit
                : failed
                ? t.catalogueSearchFailure
                : result == null
                ? t.catalogueStart
                : result.needsRefinement
                ? t.catalogueRefine
                : result.products.isEmpty
                ? t.catalogueNoMatch(result.query)
                : '',
          ),
        ),
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
                            ? () => widget.onSelect(
                                CatalogueSnapshot(
                                  product: p,
                                  manifest: result.manifest,
                                ),
                              )
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
