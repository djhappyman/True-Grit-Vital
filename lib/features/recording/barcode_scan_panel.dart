import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../data/barcode/barcode_links.dart';
import '../../data/record_store.dart';
import '../../domain/barcode/gtin.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/barcode_camera.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import 'record_pages.dart' show Heading, LabelledInput;
import '../substances/substance_profile_editor.dart'
    show SubstanceProfileSummary;

/// Production camera builder. Widget tests replace this provider with a fixture
/// that emits synthetic frames without opening hardware.
final barcodeCameraBuilderProvider = Provider<BarcodeCameraBuilder>(
  (ref) => buildBarcodeCamera,
);

typedef BarcodeItemQuery = ({String search, int offset});

/// Bounded search of the saved local collection for the explicit link step.
final barcodeItemSearchProvider = FutureProvider.autoDispose
    .family<List<SubstanceItem>, BarcodeItemQuery>(retry: (_, _) => null, (
      ref,
      query,
    ) async {
      final store = await ref.watch(recordStoreProvider.future);
      return store.items(search: query.search, limit: 21, offset: query.offset);
    });

enum _Stage {
  camera,
  manual,
  codes,
  ambiguous,
  review,
  linkChoose,
  linkReview,
  conflict,
  problem,
}

enum _Problem {
  permission,
  unavailable,
  invalidCode,
  unsupportedCode,
  linksUnavailable,
  notFound,
  linkFailed,
  linkLimit,
  locked,
  staleDataset,
  paused,
}

/// An in-sheet pack scanner with explicit, reviewed local associations.
///
/// The camera is mounted only while [_Stage.camera] is visible. A camera frame
/// never writes a record, creates an item or changes stock. The person must
/// review the current saved name, form and strength and press one command.
class BarcodeScanPanel extends ConsumerStatefulWidget {
  const BarcodeScanPanel({
    super.key,
    required this.onUse,
    required this.onClose,
  });

  /// Returns false when the parent route guard refused the navigation.
  final bool Function(SubstanceItem item) onUse;
  final VoidCallback onClose;

  @override
  ConsumerState<BarcodeScanPanel> createState() => _BarcodeScanPanelState();
}

class _BarcodeScanPanelState extends ConsumerState<BarcodeScanPanel>
    with WidgetsBindingObserver {
  final manual = TextEditingController();
  final search = TextEditingController();
  _Stage stage = _Stage.camera;
  _Problem? problem;
  List<Gtin> codes = const [];
  List<BarcodeLink> ambiguous = const [];
  Gtin? code;
  BarcodeLink? existingLink;
  BarcodeItemReview? review;
  BarcodeItemReview? candidate;
  BarcodeLink? conflict;
  BarcodeItemReview? conflictReview;
  bool busy = false;
  bool justLinked = false;
  bool identityChanged = false;
  bool staleLink = false;
  int offset = 0;
  int epoch = 0;
  String? fieldError;
  String? notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    search.addListener(_searchChanged);
    manual.addListener(_manualChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) {
      epoch++;
      stage = _Stage.problem;
      problem = _Problem.paused;
      review = null;
      candidate = null;
      busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || state == AppLifecycleState.resumed) return;
    epoch++;
    setState(() {
      stage = _Stage.problem;
      problem = _Problem.paused;
      busy = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    epoch++;
    search.removeListener(_searchChanged);
    manual.removeListener(_manualChanged);
    search.dispose();
    manual.dispose();
    super.dispose();
  }

  void _searchChanged() {
    if (!mounted) return;
    setState(() {
      offset = 0;
      notice = null;
    });
  }

  void _manualChanged() {
    if (fieldError != null && mounted) setState(() => fieldError = null);
  }

  void _resetToCamera() {
    epoch++;
    setState(() {
      stage = _Stage.camera;
      problem = null;
      codes = const [];
      ambiguous = const [];
      code = null;
      existingLink = null;
      review = null;
      candidate = null;
      conflict = null;
      conflictReview = null;
      busy = false;
      justLinked = false;
      identityChanged = false;
      staleLink = false;
      offset = 0;
      fieldError = null;
      notice = null;
    });
  }

  void _detected(List<String> payloads) {
    if (!mounted || stage != _Stage.camera || busy) return;
    if (ref.read(appLockProvider).locked) {
      setState(() {
        stage = _Stage.problem;
        problem = _Problem.locked;
      });
      return;
    }
    final result = BarcodeDetectionResult.analyze(payloads);
    if (result.codes.isEmpty) {
      setState(() {
        stage = _Stage.problem;
        problem = result.sawInvalidCheckDigit
            ? _Problem.invalidCode
            : _Problem.unsupportedCode;
      });
      return;
    }
    if (result.codes.length > 1) {
      setState(() {
        stage = _Stage.codes;
        codes = result.codes;
        busy = false;
      });
      return;
    }
    unawaited(_select(result.codes.single));
  }

  void _cameraFailed(BarcodeCameraFailure failure) {
    if (!mounted || stage != _Stage.camera) return;
    setState(() {
      stage = _Stage.problem;
      problem = failure == BarcodeCameraFailure.permissionDenied
          ? _Problem.permission
          : _Problem.unavailable;
    });
  }

  Future<BarcodeItemReview?> _loadReview(
    RecordStore store,
    String itemId,
  ) async {
    final item = await store.itemById(itemId, personId: meId);
    if (item == null) return null;
    final detail = await store.itemDetail(itemId, personId: meId);
    return barcodeItemReview(item, detail);
  }

  Future<void> _select(Gtin selected) async {
    final token = ++epoch;
    setState(() {
      busy = true;
      code = selected;
      problem = null;
      review = null;
      candidate = null;
      existingLink = null;
      conflict = null;
      identityChanged = false;
      staleLink = false;
      justLinked = false;
      notice = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      final index = await BarcodeLinkRepository(store).load();
      if (!mounted || token != epoch) return;
      final links = index.forGtin(selected);
      if (links.length > 1) {
        setState(() {
          stage = _Stage.ambiguous;
          ambiguous = links;
          busy = false;
        });
        return;
      }
      if (links.length == 1) {
        final link = links.single;
        final current = await _loadReview(store, link.itemId);
        if (!mounted || token != epoch) return;
        if (current == null) {
          setState(() {
            stage = _Stage.problem;
            problem = _Problem.notFound;
            existingLink = link;
            staleLink = true;
            busy = false;
          });
          return;
        }
        setState(() {
          stage = _Stage.review;
          review = current;
          existingLink = link;
          identityChanged = _linkDiffers(link, current);
          busy = false;
        });
        return;
      }
      setState(() {
        stage = _Stage.linkChoose;
        offset = 0;
        search.clear();
        busy = false;
      });
    } on BarcodeLinkFailure catch (error) {
      if (!mounted || token != epoch) return;
      setState(() {
        stage = _Stage.problem;
        problem = error.code == 'barcode_link_unavailable'
            ? _Problem.linksUnavailable
            : _Problem.linkFailed;
        busy = false;
      });
    } catch (_) {
      if (!mounted || token != epoch) return;
      setState(() {
        stage = _Stage.problem;
        problem = _Problem.linksUnavailable;
        busy = false;
      });
    }
  }

  bool _linkDiffers(BarcodeLink link, BarcodeItemReview current) =>
      link.reviewedName != current.name ||
      link.reviewedForm != current.form ||
      link.reviewedStrength != current.strength;

  Future<void> _chooseAmbiguous(BarcodeLink link) async {
    final token = ++epoch;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      final current = await _loadReview(store, link.itemId);
      if (!mounted || token != epoch) return;
      if (current == null) {
        setState(() {
          stage = _Stage.problem;
          problem = _Problem.notFound;
          existingLink = link;
          staleLink = true;
          busy = false;
        });
        return;
      }
      setState(() {
        stage = _Stage.review;
        review = current;
        existingLink = link;
        identityChanged = _linkDiffers(link, current);
        busy = false;
      });
    } catch (_) {
      if (!mounted || token != epoch) return;
      setState(() {
        stage = _Stage.problem;
        problem = _Problem.linksUnavailable;
        busy = false;
      });
    }
  }

  void _chooseCode(Gtin selected) => unawaited(_select(selected));

  void _openManual() {
    epoch++;
    setState(() {
      stage = _Stage.manual;
      problem = null;
      busy = false;
      fieldError = null;
      notice = null;
    });
  }

  void _submitManual() {
    final parsed = Gtin.tryParse(manual.text);
    if (parsed == null) {
      setState(() => fieldError = 'invalid');
      return;
    }
    unawaited(_select(parsed));
  }

  void _startLink() {
    epoch++;
    setState(() {
      stage = _Stage.linkChoose;
      offset = 0;
      search.clear();
      candidate = null;
      conflict = null;
      conflictReview = null;
      busy = false;
      notice = null;
    });
  }

  void _chooseItem(SubstanceItem item) {
    unawaited(_loadCandidate(item));
  }

  Future<void> _loadCandidate(SubstanceItem item) async {
    final token = ++epoch;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      final current = await _loadReview(store, item.id);
      if (!mounted || token != epoch) return;
      if (current == null) {
        setState(() {
          stage = _Stage.problem;
          problem = _Problem.notFound;
          busy = false;
        });
        return;
      }
      setState(() {
        stage = _Stage.linkReview;
        candidate = current;
        conflict = null;
        conflictReview = null;
        busy = false;
      });
    } catch (_) {
      if (!mounted || token != epoch) return;
      setState(() {
        stage = _Stage.problem;
        problem = _Problem.linksUnavailable;
        busy = false;
      });
    }
  }

  bool _canCommit(RecordStore store, String generation) {
    if (!mounted) return false;
    if (ref.read(appLockProvider).locked) return false;
    if (!identical(ref.read(recordStoreProvider).value, store)) return false;
    if (store.generation != generation) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    return true;
  }

  Future<void> _link({required bool replace}) async {
    final target = candidate;
    final selected = code;
    if (target == null || selected == null || busy) return;
    final token = ++epoch;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      final generation = store.generation;
      if (!_canCommit(store, generation)) {
        setState(() {
          stage = _Stage.problem;
          problem = _Problem.locked;
          busy = false;
        });
        return;
      }
      final repository = BarcodeLinkRepository(store);
      if (!replace && !staleLink) {
        final index = await repository.load();
        final other = index
            .forGtin(selected)
            .where((link) => link.itemId != target.itemId);
        if (other.isNotEmpty) {
          final current = await _loadReview(store, other.first.itemId);
          if (!mounted || token != epoch) return;
          setState(() {
            stage = _Stage.conflict;
            conflict = other.first;
            conflictReview = current;
            busy = false;
          });
          return;
        }
      }
      await repository.link(
        code: selected,
        itemId: target.itemId,
        expectedItemRevision: target.itemRevision,
        expectedDetailRevision: target.detailRevision,
        replace: replace || staleLink,
        canCommit: () => token == epoch && _canCommit(store, generation),
      );
      if (!mounted || token != epoch) return;
      setState(() {
        stage = _Stage.review;
        review = target;
        candidate = null;
        existingLink = null;
        conflict = null;
        conflictReview = null;
        staleLink = false;
        identityChanged = false;
        justLinked = true;
        busy = false;
        notice = null;
      });
    } on BarcodeLinkFailure catch (error) {
      if (!mounted || token != epoch) return;
      final next = switch (error.code) {
        'barcode_link_limit' || 'barcode_link_item_limit' => _Problem.linkLimit,
        'barcode_link_locked' => _Problem.locked,
        'barcode_link_item_missing' => _Problem.notFound,
        'barcode_link_unavailable' => _Problem.linksUnavailable,
        'barcode_link_changed' || 'barcode_link_stale' => _Problem.staleDataset,
        _ => _Problem.linkFailed,
      };
      setState(() {
        stage = _Stage.problem;
        problem = next;
        busy = false;
        if (next == _Problem.staleDataset) {
          notice = AppLocalizations.of(context).finishR04ReviewChanged;
        }
      });
    } catch (_) {
      if (!mounted || token != epoch) return;
      setState(() {
        stage = _Stage.problem;
        problem = _Problem.linkFailed;
        busy = false;
      });
    }
  }

  Future<void> _use() async {
    final shown = review;
    if (shown == null || busy) return;
    final t = AppLocalizations.of(context);
    final token = ++epoch;
    setState(() => busy = true);
    try {
      final store = await ref.read(recordStoreProvider.future);
      if (!mounted || token != epoch) return;
      final generation = store.generation;
      if (!_canCommit(store, generation)) {
        setState(() {
          stage = _Stage.problem;
          problem = _Problem.locked;
          busy = false;
        });
        return;
      }
      final current = await _loadReview(store, shown.itemId);
      if (!mounted || token != epoch) return;
      if (current == null) {
        setState(() {
          stage = _Stage.problem;
          problem = _Problem.notFound;
          busy = false;
        });
        return;
      }
      if (!_sameReview(shown, current)) {
        setState(() {
          review = current;
          identityChanged = true;
          notice = t.finishR04ReviewChanged;
          busy = false;
        });
        return;
      }
      if (!_canCommit(store, generation)) return;
      final accepted = widget.onUse(current.item);
      if (!mounted || token != epoch) return;
      if (!accepted) {
        setState(() {
          busy = false;
          notice = t.finishR04ReviewChanged;
        });
      }
    } catch (_) {
      if (!mounted || token != epoch) return;
      setState(() {
        stage = _Stage.problem;
        problem = _Problem.staleDataset;
        busy = false;
      });
    }
  }

  bool _sameReview(BarcodeItemReview a, BarcodeItemReview b) =>
      a.itemId == b.itemId &&
      a.itemRevision == b.itemRevision &&
      a.detailRevision == b.detailRevision &&
      a.name == b.name &&
      a.form == b.form &&
      a.strength == b.strength;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locked = ref.watch(appLockProvider.select((state) => state.locked));
    ref.listen(appLockProvider, (previous, next) {
      if (!mounted ||
          previous == null ||
          !previous.ready ||
          !next.ready ||
          previous.locked == next.locked) {
        return;
      }
      epoch++;
      setState(() {
        stage = _Stage.problem;
        problem = next.locked ? _Problem.locked : _Problem.paused;
        review = null;
        candidate = null;
        busy = false;
      });
    });
    ref.listen(recordStoreProvider.select((value) => value.value?.generation), (
      previous,
      next,
    ) {
      if (!mounted || previous == null || next == null || previous == next) {
        return;
      }
      epoch++;
      setState(() {
        stage = _Stage.problem;
        problem = _Problem.staleDataset;
        review = null;
        candidate = null;
        conflict = null;
        conflictReview = null;
        existingLink = null;
        busy = false;
        notice = null;
      });
    });
    if (locked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _problemBody(t, _Problem.locked),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice case final text?) ...[
          Semantics(liveRegion: true, child: Text(text)),
          const SizedBox(height: 8),
        ],
        ..._stageBody(t),
      ],
    );
  }

  List<Widget> _stageBody(AppLocalizations t) => switch (stage) {
    _Stage.camera => _cameraBody(t),
    _Stage.manual => _manualBody(t),
    _Stage.codes => _codesBody(t),
    _Stage.ambiguous => _ambiguousBody(t),
    _Stage.review => _reviewBody(t),
    _Stage.linkChoose => _linkChooseBody(t),
    _Stage.linkReview => _linkReviewBody(t),
    _Stage.conflict => _conflictBody(t),
    _Stage.problem => _problemBody(t, problem ?? _Problem.unavailable),
  };

  List<Widget> _cameraBody(AppLocalizations t) {
    final camera = ref.watch(barcodeCameraBuilderProvider);
    final cameraEpoch = epoch;
    final height = math.min(MediaQuery.sizeOf(context).height * .42, 360.0);
    return [
      Heading(t.finishR04ScanHeading),
      Text(t.finishR04ScanHelp),
      const SizedBox(height: 12),
      Semantics(
        label: t.finishR04ScanHelp,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VitalLayout.sectionRadius),
          child: ColoredBox(
            color: Colors.black,
            child: SizedBox(
              height: height,
              child: camera(
                onDetected: (values) {
                  if (mounted && cameraEpoch == epoch) _detected(values);
                },
                onFailure: (failure) {
                  if (mounted && cameraEpoch == epoch) _cameraFailed(failure);
                },
                loading: Center(
                  child: Text(
                    t.finishR04CameraLoading,
                    style: StitchType.caption.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(t.finishR04ScanPrivacy, style: StitchType.caption),
      const SizedBox(height: 12),
      VitalButton.secondary(
        leading: const Icon(LucideIcons.keyboard),
        onPressed: busy ? null : _openManual,
        child: Text(t.finishR04Enter),
      ),
      const SizedBox(height: 8),
      VitalButton.secondary(
        onPressed: busy ? null : widget.onClose,
        child: Text(t.cancel),
      ),
    ];
  }

  List<Widget> _manualBody(AppLocalizations t) => [
    Heading(t.finishR04ScanHeading),
    Text(t.finishR04CodeHelp),
    const SizedBox(height: 12),
    LabelledInput(
      label: t.finishR04CodeLabel,
      controller: manual,
      enabled: !busy,
      helper: t.finishR04CodeHint,
      error: fieldError == null ? null : t.finishR04InvalidHeading,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submitManual(),
    ),
    const SizedBox(height: 12),
    VitalButton(
      onPressed: busy ? null : _submitManual,
      child: Text(t.finishR04Check),
    ),
    const SizedBox(height: 8),
    VitalButton.secondary(
      leading: const Icon(LucideIcons.scanBarcode),
      onPressed: busy ? null : _resetToCamera,
      child: Text(t.finishR04Camera),
    ),
    const SizedBox(height: 8),
    VitalButton.secondary(
      onPressed: busy ? null : widget.onClose,
      child: Text(t.cancel),
    ),
  ];

  List<Widget> _codesBody(AppLocalizations t) => [
    Heading(t.finishR04MultipleHeading),
    Text(t.finishR04MultipleHelp),
    const SizedBox(height: 12),
    for (final value in codes) ...[
      VitalButton.secondary(
        multiline: true,
        onPressed: busy ? null : () => _chooseCode(value),
        child: Text(t.finishR04Code(value.printed)),
      ),
      const SizedBox(height: 8),
    ],
    VitalButton.secondary(
      onPressed: busy ? null : _resetToCamera,
      child: Text(t.finishR04Rescan),
    ),
    const SizedBox(height: 8),
    VitalButton.secondary(
      onPressed: busy ? null : widget.onClose,
      child: Text(t.cancel),
    ),
  ];

  List<Widget> _ambiguousBody(AppLocalizations t) => [
    Heading(t.finishR04AmbiguousHeading),
    Text(t.finishR04AmbiguousHelp),
    if (code case final value?) ...[
      const SizedBox(height: 4),
      Text(t.finishR04Code(value.printed), style: StitchType.caption),
    ],
    const SizedBox(height: 12),
    for (final link in ambiguous) ...[
      VitalButton.secondary(
        multiline: true,
        onPressed: busy ? null : () => _chooseAmbiguous(link),
        child: Text(
          t.catalogueProduct(
            link.reviewedName,
            link.reviewedForm.isEmpty ? t.catalogueMissing : link.reviewedForm,
            link.reviewedStrength.isEmpty
                ? t.catalogueMissing
                : link.reviewedStrength,
          ),
        ),
      ),
      const SizedBox(height: 8),
    ],
    VitalButton.secondary(
      onPressed: busy ? null : widget.onClose,
      child: Text(t.cancel),
    ),
  ];

  Widget _identity(AppLocalizations t, BarcodeItemReview value) =>
      StitchSurface(
        inset: true,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.catalogueProduct(
                value.name,
                value.form.isEmpty ? t.catalogueMissing : value.form,
                value.strength.isEmpty ? t.catalogueMissing : value.strength,
              ),
              style: StitchType.body,
            ),
            if (value.profile case final profile?)
              SubstanceProfileSummary(profile: profile),
          ],
        ),
      );

  List<Widget> _reviewBody(AppLocalizations t) {
    final shown = review;
    if (shown == null) return _problemBody(t, _Problem.staleDataset);
    return [
      Heading(t.finishR04ReviewHeading),
      Text(t.finishR04ReviewHelp),
      if (code case final value?) ...[
        const SizedBox(height: 4),
        Text(t.finishR04Code(value.printed), style: StitchType.caption),
      ],
      const SizedBox(height: 12),
      _identity(t, shown),
      if (identityChanged) ...[
        const SizedBox(height: 8),
        Text(t.finishR04Changed, style: StitchType.caption),
      ],
      if (justLinked) ...[
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text(t.finishR04Linked)),
      ],
      const SizedBox(height: 16),
      VitalButton(onPressed: busy ? null : _use, child: Text(t.finishR04Use)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          VitalButton.secondary(
            onPressed: busy ? null : _resetToCamera,
            child: Text(t.finishR04Rescan),
          ),
          VitalButton.secondary(
            onPressed: busy ? null : _startLink,
            child: Text(t.finishR04Change),
          ),
          VitalButton.secondary(
            onPressed: busy ? null : widget.onClose,
            child: Text(t.cancel),
          ),
        ],
      ),
    ];
  }

  List<Widget> _linkChooseBody(AppLocalizations t) {
    final query = (search: search.text.trim(), offset: offset);
    final items = ref.watch(barcodeItemSearchProvider(query));
    return [
      Heading(t.finishR04NotLinkedHeading),
      Text(t.finishR04NotLinkedHelp),
      if (code case final value?) ...[
        const SizedBox(height: 4),
        Text(t.finishR04Code(value.printed), style: StitchType.caption),
      ],
      const SizedBox(height: 12),
      LabelledInput(
        label: t.finishR04SearchItems,
        controller: search,
        enabled: !busy,
      ),
      const SizedBox(height: 8),
      if (items.isLoading)
        Text(t.finishR04LoadingItems, style: StitchType.caption)
      else if (items.hasError)
        Text(t.catalogueSearchFailure, style: StitchType.caption)
      else ...[
        for (final item in items.requireValue.take(20)) ...[
          VitalButton.secondary(
            multiline: true,
            alignment: AlignmentDirectional.centerStart,
            onPressed: busy ? null : () => _chooseItem(item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name),
                if (item.form.isNotEmpty)
                  Text(item.form, style: StitchType.caption),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (items.requireValue.isEmpty)
          Text(t.finishR04NoItems, style: StitchType.caption),
        if (items.requireValue.length > 20)
          VitalButton.secondary(
            onPressed: () => setState(() => offset += 20),
            child: Text(t.more),
          ),
        if (offset > 0)
          VitalButton.secondary(
            onPressed: () => setState(() => offset = math.max(0, offset - 20)),
            child: Text(t.back),
          ),
      ],
      const SizedBox(height: 12),
      VitalButton.secondary(
        onPressed: busy ? null : widget.onClose,
        child: Text(t.cancel),
      ),
    ];
  }

  List<Widget> _linkReviewBody(AppLocalizations t) {
    final shown = candidate;
    if (shown == null) return _problemBody(t, _Problem.staleDataset);
    return [
      Heading(t.finishR04ReviewHeading),
      Text(t.finishR04LinkHelp),
      if (code case final value?) ...[
        const SizedBox(height: 4),
        Text(t.finishR04Code(value.printed), style: StitchType.caption),
      ],
      const SizedBox(height: 12),
      _identity(t, shown),
      const SizedBox(height: 16),
      VitalButton(
        onPressed: busy ? null : () => _link(replace: false),
        child: Text(t.finishR04Link),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          VitalButton.secondary(
            onPressed: busy ? null : _startLink,
            child: Text(t.back),
          ),
          VitalButton.secondary(
            onPressed: busy ? null : widget.onClose,
            child: Text(t.cancel),
          ),
        ],
      ),
    ];
  }

  List<Widget> _conflictBody(AppLocalizations t) {
    final named = conflict;
    return [
      Heading(t.finishR04AlreadyLinkedHeading),
      if (named != null) Text(t.finishR04AlreadyLinkedHelp(named.reviewedName)),
      if (conflictReview case final other?) ...[
        const SizedBox(height: 12),
        _identity(t, other),
      ],
      const SizedBox(height: 16),
      VitalButton(
        onPressed: busy ? null : () => _link(replace: true),
        child: Text(t.replace),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          VitalButton.secondary(
            onPressed: busy ? null : _startLink,
            child: Text(t.back),
          ),
          VitalButton.secondary(
            onPressed: busy ? null : widget.onClose,
            child: Text(t.cancel),
          ),
        ],
      ),
    ];
  }

  List<Widget> _problemBody(AppLocalizations t, _Problem value) {
    final (heading, help) = switch (value) {
      _Problem.permission => (
        t.finishR04PermissionHeading,
        t.finishR04PermissionHelp,
      ),
      _Problem.unavailable => (
        t.finishR04UnavailableHeading,
        t.finishR04UnavailableHelp,
      ),
      _Problem.invalidCode => (
        t.finishR04InvalidHeading,
        t.finishR04InvalidHelp,
      ),
      _Problem.unsupportedCode => (
        t.finishR04UnsupportedCodeHeading,
        t.finishR04UnsupportedCodeHelp,
      ),
      _Problem.linksUnavailable => (
        t.finishR04LinksUnavailableHeading,
        t.finishR04LinksUnavailableHelp,
      ),
      _Problem.notFound => (
        t.finishR04NotFoundHeading,
        t.finishR04NotFoundHelp,
      ),
      _Problem.linkFailed => (
        t.finishR04LinkFailedHeading,
        t.finishR04LinkFailedHelp,
      ),
      _Problem.linkLimit => (
        t.finishR04LinkLimitHeading,
        t.finishR04LinkLimitHelp,
      ),
      _Problem.locked => (t.finishR04LockedHeading, t.finishR04LockedHelp),
      _Problem.staleDataset => (
        t.finishR04DatasetHeading,
        t.finishR04DatasetHelp,
      ),
      _Problem.paused => (t.finishR04PausedHeading, t.finishR04PausedHelp),
    };
    return [
      Heading(heading),
      Text(help),
      const SizedBox(height: 12),
      if (value == _Problem.notFound) ...[
        VitalButton(
          onPressed: busy ? null : _startLink,
          child: Text(t.finishR04Link),
        ),
        const SizedBox(height: 8),
      ] else if (value == _Problem.linkFailed) ...[
        VitalButton(
          onPressed: busy || candidate == null
              ? null
              : () => _link(replace: staleLink),
          child: Text(t.retry),
        ),
        const SizedBox(height: 8),
      ] else if (value != _Problem.locked) ...[
        VitalButton.secondary(
          leading: const Icon(LucideIcons.keyboard),
          onPressed: busy ? null : _openManual,
          child: Text(t.finishR04Enter),
        ),
        const SizedBox(height: 8),
      ],
      if (value == _Problem.invalidCode ||
          value == _Problem.unsupportedCode ||
          value == _Problem.staleDataset ||
          value == _Problem.paused)
        VitalButton.secondary(
          onPressed: busy ? null : _resetToCamera,
          child: Text(t.finishR04Rescan),
        ),
      if (value == _Problem.invalidCode ||
          value == _Problem.unsupportedCode ||
          value == _Problem.staleDataset ||
          value == _Problem.paused)
        const SizedBox(height: 8),
      if (value == _Problem.linksUnavailable)
        Text(t.finishR04SearchManual, style: StitchType.caption),
      if (value == _Problem.linksUnavailable) const SizedBox(height: 8),
      VitalButton.secondary(
        onPressed: busy ? null : widget.onClose,
        child: Text(t.cancel),
      ),
    ];
  }
}
