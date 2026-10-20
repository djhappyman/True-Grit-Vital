import '../../ui/vital_ui.dart';

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../app/settings_toggle_row.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';
import '../products/product_widgets.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key, required this.personId, this.itemId});
  final String personId;
  final String? itemId;
  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        q = (personId: widget.personId, itemId: widget.itemId, offset: offset);
    final people = ref.watch(profilesProvider);
    final owner = people.value
        ?.where((p) => p.id == widget.personId)
        .firstOrNull;
    if (people.isLoading) return EntryPage(children: [Text(t.loadingRecords)]);
    if (people.hasError) {
      return EntryPage(
        children: [
          LoadFailure(onRetry: () => ref.invalidate(profilesProvider)),
        ],
      );
    }
    if (owner == null) return EntryPage(children: [Text(t.profileUnavailable)]);
    return EntryPage(
      children: [
        Heading(t.stock),
        Text(t.profileOwner(ownerLabel(ref, t, owner.id))),
        if (owner.isArchived) Text(t.archivedHelp),
        Text(t.stockLocalNoticeHelp),
        const SizedBox(height: 16),
        if (widget.itemId != null && !owner.isArchived)
          VitalButton(
            onPressed: () =>
                context.push('/stock/${owner.id}/create?item=${widget.itemId}'),
            child: Text(t.create),
          ),
        ref
            .watch(stockContainersProvider(q))
            .when(
              loading: () => Text(t.loadingRecords),
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(stockContainersProvider(q)),
              ),
              data: (rows) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rows.isEmpty) Text(t.stockEmpty),
                  for (final c in rows.take(50))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: VitalSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            VitalRecordHeader(
                              title: c.label,
                              icon: LucideIcons.archive,
                            ),
                            StockItemName(itemId: c.itemId),
                            if (c.productLabel != null)
                              ProductLabelView(label: c.productLabel!)
                            else
                              Text(t.stockStrengthValue(c.strength.label)),
                            if (c.strength.mgPerMl != null)
                              Text(
                                stockAmountText(
                                  t,
                                  c.strength.mgPerMl!,
                                  'mg/ml',
                                ),
                              ),
                            StockBalanceText(container: c),
                            if (!owner.isArchived) ...[
                              const SizedBox(height: 12),
                              VitalButton.secondary(
                                onPressed: () => context.push(
                                  '/stock/${owner.id}/adjust/${c.id}',
                                ),
                                child: Text(t.stockAdjustAction),
                              ),
                              StockNoticeSettings(
                                key: ValueKey(c.id),
                                container: c,
                                personRevision: owner.revision,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (offset > 0)
                        VitalButton.secondary(
                          onPressed: () => setState(() => offset -= 50),
                          child: Text(t.previous),
                        ),
                      if (rows.length > 50)
                        VitalButton.secondary(
                          onPressed: () => setState(() => offset += 50),
                          child: Text(t.next),
                        ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class StockContainerForm extends ConsumerStatefulWidget {
  const StockContainerForm({
    super.key,
    required this.personId,
    required this.itemId,
  });
  final String personId, itemId;
  @override
  ConsumerState<StockContainerForm> createState() => _StockContainerFormState();
}

class _StockContainerFormState extends DurableFormState<StockContainerForm> {
  final label = TextEditingController(),
      strength = TextEditingController(),
      concentration = TextEditingController(),
      opening = TextEditingController(),
      threshold = TextEditingController();
  ProductLabelSnapshot? productLabel;
  late final productEditor = ProductEditorData(entryChanged);
  String unit = 'ml';
  bool knownStrength = false,
      knownOpening = false,
      refill = false,
      initialised = false;
  AdultProfile? owner;
  SubstanceItem? item;
  String? invalid;
  @override
  DraftKind get entryKind => DraftKind.stockContainer;
  @override
  String? get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.itemId;
  @override
  int? get entryTargetRevision => item?.revision;
  @override
  Map<String, String> captureEntry() => {
    'label': label.text,
    'unit': unit,
    'strength': strength.text,
    'strengthKnown': '$knownStrength',
    'concentration': concentration.text,
    'opening': opening.text,
    'openingKnown': '$knownOpening',
    'threshold': threshold.text,
    'refill': '$refill',
    'productLabel': productLabel == null
        ? ''
        : jsonEncode(productLabel!.toJson()),
    'productComponents': productEditor.encode(),
  };
  @override
  void restoreEntry(Map<String, String> f) {
    productLabel = f['productLabel']?.isNotEmpty == true
        ? ProductLabelSnapshot.fromJson(
            jsonDecode(f['productLabel']!) as Map<String, dynamic>,
          )
        : productLabel;
    if (f['productComponents'] case final encoded?) {
      productEditor.restore(encoded);
    }
    label.text = f['label'] ?? '';
    strength.text = f['strength'] ?? '';
    concentration.text = f['concentration'] ?? '';
    opening.text = f['opening'] ?? '';
    threshold.text = f['threshold'] ?? '';
    unit = f['unit'] ?? 'ml';
    knownStrength = f['strengthKnown'] == 'true';
    knownOpening = f['openingKnown'] == 'true';
    refill = f['refill'] == 'true';
  }

  @override
  void initState() {
    super.initState();
    for (final c in [label, strength, concentration, opening, threshold]) {
      c.addListener(entryChanged);
    }
  }

  @override
  void dispose() {
    productEditor.dispose();
    for (final c in [label, strength, concentration, opening, threshold]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (label.text.trim().isEmpty ||
        (productLabel == null && strength.text.trim().isEmpty)) {
      setState(() {
        invalid = 'label';
        error = t.stockLabelRequired;
      });
      return;
    }
    ExactAmount? c, o, low;
    try {
      if (productLabel == null && knownStrength) {
        c = ExactAmount.parseEntry(stockDecimal(concentration.text));
      }
    } catch (_) {
      setState(() {
        invalid = 'concentration';
        error = t.stockAmountInvalid;
      });
      return;
    }
    try {
      if (knownOpening) o = stockMeasurement(opening.text);
    } catch (_) {
      setState(() {
        invalid = 'opening';
        error = t.stockMeasurementInvalid;
      });
      return;
    }
    try {
      if (threshold.text.trim().isNotEmpty) {
        low = stockMeasurement(threshold.text);
      }
    } catch (_) {
      setState(() {
        invalid = 'threshold';
        error = t.stockMeasurementInvalid;
      });
      return;
    }
    ProductLabelSnapshot? sourceLabel;
    if (productLabel != null) {
      try {
        sourceLabel = ProductLabelSnapshot(
          personId: widget.personId,
          itemId: widget.itemId,
          revision: productLabel!.revision,
          components: productEditor.components(),
        );
      } catch (_) {
        setState(() => error = t.productIngredientInvalid);
        return;
      }
    }
    invalid = null;
    await commit((command) async {
      final store = await ref.read(recordStoreProvider.future);
      await store.createStockContainer(
        commandId: command,
        expectedGeneration: capturedGeneration!,
        personId: widget.personId,
        expectedPersonRevision: capturedPersonRevision!,
        itemId: widget.itemId,
        label: label.text.trim(),
        unit: unit,
        strength: LabelledStrength(
          ingredientId: widget.itemId,
          label: productLabel == null ? strength.text.trim() : item!.name,
          mgPerMl: c,
        ),
        opening: o,
        lowThreshold: low,
        refillEnabled: refill,
        productLabel: sourceLabel,
      );
    }, successPath: '/stock/${widget.personId}?item=${widget.itemId}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider),
        current = ref.watch(itemLookupProvider(widget.itemId));
    if (people.hasError || current.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(itemLookupProvider(widget.itemId));
            },
          ),
        ],
      );
    }
    if (!people.hasValue || !current.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final currentProduct = ref.watch(
      productLabelProvider((personId: widget.personId, itemId: widget.itemId)),
    );
    if (currentProduct.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () => ref.invalidate(
              productLabelProvider((
                personId: widget.personId,
                itemId: widget.itemId,
              )),
            ),
          ),
        ],
      );
    }
    if (!currentProduct.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final liveOwner = people.value!
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    if (liveOwner == null ||
        current.value == null ||
        current.value!.personId != widget.personId) {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!initialised) {
      owner = liveOwner;
      item = current.value;
      unit = item!.unit;
      productLabel = currentProduct.value;
      if (productLabel != null) {
        productEditor.initialise(productLabel!.components);
      }
      initialised = true;
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        !liveOwner.isArchived &&
        liveOwner.revision == capturedPersonRevision &&
        current.value!.revision == capturedTargetRevision;
    final enabled = valid && !busy && !uncertain;
    return wrap([
      Heading(t.stockCreate),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(item!.name),
      if (!valid) Text(t.conflictFailure),
      LabelledInput(
        label: t.stockLabel,
        controller: label,
        enabled: enabled,
        error: invalid == 'label' ? error : null,
      ),
      if (productLabel != null) ...[
        Text(t.productSourceHelp),
        ProductComponentEditor(
          data: productEditor,
          enabled: enabled,
          error: error == t.productIngredientInvalid ? error : null,
          onChanged: () => setState(() {}),
        ),
      ],
      if (productLabel == null)
        LabelledInput(
          label: t.stockStrength,
          controller: strength,
          enabled: enabled,
        ),
      if (productLabel == null)
        SettingsToggleRow(
          label: t.stockKnownStrength,
          description: t.stockKnownStrengthHelp,
          value: knownStrength,
          enabled: enabled,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          onChanged: (v) => setState(() {
            knownStrength = v;
            entryChanged();
          }),
        ),
      if (productLabel == null && knownStrength)
        LabelledInput(
          label: t.stockConcentration,
          controller: concentration,
          helper: t.stockDecimalHelp,
          enabled: enabled,
          error: invalid == 'concentration' ? error : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      Text(t.unitLabel),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final u in ['mg', 'ml', 'count'])
            Semantics(
              selected: unit == u,
              child: VitalButton.secondary(
                multiline: true,
                onPressed: enabled && productLabel == null
                    ? () => setState(() {
                        unit = u;
                        entryChanged();
                      })
                    : null,
                child: Text(u),
              ),
            ),
        ],
      ),
      SettingsToggleRow(
        label: t.stockKnownOpening,
        description: t.stockOpeningHelp,
        value: knownOpening,
        enabled: enabled,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        onChanged: (v) => setState(() {
          knownOpening = v;
          entryChanged();
        }),
      ),
      if (knownOpening)
        LabelledInput(
          label: t.stockOpening,
          controller: opening,
          helper: t.stockDecimalHelp,
          enabled: enabled,
          error: invalid == 'opening' ? error : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      LabelledInput(
        label: t.stockThreshold,
        controller: threshold,
        helper: t.stockThresholdHelp,
        enabled: enabled,
        error: invalid == 'threshold' ? error : null,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
      SettingsToggleRow(
        label: t.stockRefill,
        description: t.stockRefillHelp,
        value: refill,
        enabled: enabled,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        onChanged: (v) => setState(() {
          refill = v;
          entryChanged();
        }),
      ),
      Text(t.stockLocalNoticeHelp),
      ?failure(),
      VitalButton(
        onPressed: !busy && (uncertain || (valid && !conflict)) ? save : null,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.create,
        ),
      ),
    ]);
  }
}

class StockAdjustmentForm extends ConsumerStatefulWidget {
  const StockAdjustmentForm({
    super.key,
    required this.personId,
    required this.containerId,
    this.notices = false,
  });
  final String personId, containerId;
  final bool notices;
  @override
  ConsumerState<StockAdjustmentForm> createState() =>
      _StockAdjustmentFormState();
}

class _StockAdjustmentFormState extends DurableFormState<StockAdjustmentForm> {
  final amount = TextEditingController(), reason = TextEditingController();
  StockMovementKind? kind;
  bool unknown = false,
      noticesMode = false,
      initialised = false,
      clearThreshold = false;
  AdultProfile? owner;
  StoredStockContainer? container;
  @override
  DraftKind get entryKind => DraftKind.stockAdjustment;
  @override
  String? get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.containerId;
  @override
  int? get entryTargetRevision => container?.revision;
  @override
  Map<String, String> captureEntry() => {
    'kind': noticesMode ? 'notices' : kind?.name ?? '',
    'amount': amount.text,
    'unknown': '$unknown',
    'reason': reason.text,
    'clearThreshold': '$clearThreshold',
  };
  @override
  void restoreEntry(Map<String, String> f) {
    noticesMode = f['kind'] == 'notices';
    clearThreshold = f['clearThreshold'] == 'true';
    kind = StockMovementKind.values
        .where((v) => v.name == f['kind'])
        .firstOrNull;
    amount.text = f['amount'] ?? '';
    reason.text = f['reason'] ?? '';
    unknown = f['unknown'] == 'true';
  }

  @override
  void initState() {
    super.initState();
    amount.addListener(entryChanged);
    reason.addListener(entryChanged);
  }

  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final t = AppLocalizations.of(context);
    if (noticesMode) {
      ExactAmount? low;
      try {
        low = amount.text.trim().isEmpty
            ? (clearThreshold ? null : container!.lowThreshold)
            : stockMeasurement(amount.text);
      } catch (_) {
        setState(() => error = t.stockMeasurementInvalid);
        return;
      }
      await commit((command) async {
        final store = await ref.read(recordStoreProvider.future);
        await store.configureStockNotices(
          commandId: command,
          personId: widget.personId,
          expectedPersonRevision: capturedPersonRevision!,
          expectedGeneration: capturedGeneration!,
          containerId: widget.containerId,
          expectedContainerRevision: capturedTargetRevision!,
          lowThreshold: low,
          refillEnabled: container!.refillEnabled,
        );
      }, successPath: '/stock/${widget.personId}?item=${container!.itemId}');
      return;
    }
    if (kind == null) {
      setState(() => error = t.stockChooseKind);
      return;
    }
    EnteredStockAmount? entered;
    ExactAmount? measured;
    try {
      if (kind == StockMovementKind.reconciliation) {
        if (!unknown) measured = stockMeasurement(amount.text);
      } else {
        entered = EnteredStockAmount(
          stockDecimal(amount.text),
          container!.unit,
        );
      }
    } catch (_) {
      setState(
        () => error = kind == StockMovementKind.reconciliation
            ? t.stockMeasurementInvalid
            : t.stockAmountInvalid,
      );
      return;
    }
    await commit((command) async {
      final store = await ref.read(recordStoreProvider.future);
      await store.addStockMovement(
        commandId: command,
        personId: widget.personId,
        expectedGeneration: capturedGeneration!,
        expectedPersonRevision: capturedPersonRevision!,
        containerId: widget.containerId,
        expectedContainerRevision: capturedTargetRevision!,
        kind: kind!,
        amount: entered,
        measured: measured,
        reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
      );
    }, successPath: '/stock/${widget.personId}?item=${container!.itemId}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider),
        result = ref.watch(
          stockContainerProvider((
            personId: widget.personId,
            containerId: widget.containerId,
          )),
        );
    if (people.hasError || result.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(
                stockContainerProvider((
                  personId: widget.personId,
                  containerId: widget.containerId,
                )),
              );
            },
          ),
        ],
      );
    }
    if (!people.hasValue || !result.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final live = people.value!
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    if (live == null || result.value == null) {
      dirty = false;
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    owner ??= live;
    container ??= result.value;
    if (!initialised) {
      initialised = true;
      noticesMode = widget.notices;
      if (noticesMode) amount.text = '';
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        !live.isArchived &&
        live.revision == capturedPersonRevision &&
        result.value!.revision == capturedTargetRevision;
    final enabled = valid && !busy && !uncertain;
    return wrap([
      Heading(noticesMode ? t.stockNotices : t.stockAdjust),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(container!.label),
      if (container!.productLabel != null)
        ProductLabelView(label: container!.productLabel!)
      else
        Text(t.stockStrengthValue(container!.strength.label)),
      StockBalanceText(container: result.value!),
      if (!valid) Text(t.conflictFailure),
      if (noticesMode && container!.lowThreshold != null)
        Text(
          t.stockThresholdValue(
            stockAmountText(t, container!.lowThreshold!, container!.unit),
          ),
        ),
      if (noticesMode)
        LabelledInput(
          label: t.stockThreshold,
          controller: amount,
          helper: clearThreshold
              ? t.stockThresholdCleared
              : t.stockThresholdEditHelp,
          enabled: enabled,
          error: error == t.stockMeasurementInvalid ? error : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      if (noticesMode)
        VitalButton.secondary(
          onPressed: enabled
              ? () => setState(() {
                  clearThreshold = true;
                  amount.clear();
                  entryChanged();
                })
              : null,
          child: Text(t.catalogueClear),
        ),
      if (!noticesMode)
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (k, name) in [
              (StockMovementKind.restock, t.stockRestock),
              (StockMovementKind.waste, t.stockWaste),
              (StockMovementKind.reconciliation, t.stockMeasure),
            ])
              Semantics(
                selected: kind == k,
                child: VitalButton.secondary(
                  multiline: true,
                  onPressed: enabled
                      ? () => setState(() {
                          kind = k;
                          entryChanged();
                        })
                      : null,
                  child: Text(name),
                ),
              ),
          ],
        ),
      if (!noticesMode && kind != null) ...[
        Text(
          kind == StockMovementKind.restock
              ? t.stockRestockHelp
              : kind == StockMovementKind.waste
              ? t.stockWasteHelp
              : t.stockMeasureHelp,
        ),
        if (kind == StockMovementKind.reconciliation)
          SettingsToggleRow(
            label: t.stockUnknownMeasure,
            description: t.stockUnknownMeasureHelp,
            value: unknown,
            enabled: enabled,
            reduceMotion: MediaQuery.disableAnimationsOf(context),
            onChanged: (v) => setState(() {
              unknown = v;
              entryChanged();
            }),
          ),
        if (kind != StockMovementKind.reconciliation || !unknown) ...[
          LabelledInput(
            label: t.amountLabel,
            controller: amount,
            helper: t.stockDecimalHelp,
            enabled: enabled,
            error:
                error == t.stockMeasurementInvalid ||
                    error == t.stockAmountInvalid
                ? error
                : null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          Text(container!.unit),
        ],
        LabelledInput(
          label: t.stockReason,
          controller: reason,
          enabled: enabled,
        ),
      ],
      ?failure(),
      VitalButton(
        onPressed: !busy && (uncertain || (valid && !conflict)) ? save : null,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.save,
        ),
      ),
      const SizedBox(height: 24),
      StockMovementHistory(
        personId: widget.personId,
        containerId: widget.containerId,
        unit: container!.unit,
      ),
    ]);
  }
}

class StockNoticeSettings extends ConsumerStatefulWidget {
  const StockNoticeSettings({
    super.key,
    required this.container,
    required this.personRevision,
  });
  final StoredStockContainer container;
  final int personRevision;
  @override
  ConsumerState<StockNoticeSettings> createState() =>
      _StockNoticeSettingsState();
}

class _StockNoticeSettingsState extends ConsumerState<StockNoticeSettings> {
  bool busy = false;
  String? error;
  ({
    String command,
    String personId,
    String containerId,
    int revision,
    int personRevision,
    bool refill,
    String generation,
    ExactAmount? threshold,
  })?
  pending;
  Future<void> save(bool refill) async {
    if (busy) return;
    final t = AppLocalizations.of(context);
    pending ??= (
      command: newCommandId(),
      personId: widget.container.personId,
      containerId: widget.container.id,
      revision: widget.container.revision,
      personRevision: widget.personRevision,
      refill: refill,
      generation: ref.read(recordStoreProvider).requireValue.generation,
      threshold: widget.container.lowThreshold,
    );
    final action = pending!;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      await store.configureStockNotices(
        commandId: action.command,
        personId: action.personId,
        expectedPersonRevision: action.personRevision,
        containerId: action.containerId,
        expectedContainerRevision: action.revision,
        expectedGeneration: action.generation,
        lowThreshold: action.threshold,
        refillEnabled: action.refill,
      );
      pending = null;
    } catch (e) {
      if (e is CommandConflict) pending = null;
      if (mounted) {
        setState(
          () => error = e is CommandConflict
              ? t.conflictFailure
              : t.stockNoticeFailure,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsToggleRow(
          label: t.stockRefill,
          description: t.stockRefillHelp,
          value: widget.container.refillEnabled,
          enabled: !busy && pending == null,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          onChanged: save,
        ),
        Text(
          widget.container.lowThreshold == null
              ? t.stockThresholdHelp
              : t.stockThresholdValue(
                  stockAmountText(
                    t,
                    widget.container.lowThreshold!,
                    widget.container.unit,
                  ),
                ),
        ),
        VitalButton.secondary(
          onPressed: busy || pending != null
              ? null
              : () => context.push(
                  '/stock/${widget.container.personId}/adjust/${widget.container.id}?notices=true',
                ),
          child: Text(t.edit),
        ),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        if (pending != null)
          VitalButton.secondary(
            onPressed: busy ? null : () => save(pending!.refill),
            child: Text(t.retry),
          ),
      ],
    );
  }
}
