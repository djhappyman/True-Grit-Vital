import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../plans/interval_clock.dart';
import '../plans/plan_providers.dart';
import '../plans/interval_review.dart';
import '../products/product_widgets.dart';
import '../profiles/profile_pages.dart';
import '../stock/stock_widgets.dart';
import '../stock/stock_providers.dart';
import 'record_pages.dart';

final combinedLookupProvider = StreamProvider.autoDispose
    .family<CombinedUseResult?, ({String personId, String actionId})>((
      ref,
      target,
    ) async* {
      final store = await ref.watch(recordStoreProvider.future);
      // The records stream supplies invalidation after corrections and Undo.
      await for (final _ in store.watchRecords(
        scope: FeedScope.person(target.personId),
      )) {
        yield await store.combinedById(
          actionId: target.actionId,
          personId: target.personId,
        );
      }
    });
final siteLabelsProvider = FutureProvider.autoDispose
    .family<List<String>, String>(
      (ref, person) async =>
          (await ref.watch(recordStoreProvider.future))
              .siteHistory(personId: person),
    );
final combinedWriterProvider =
    Provider<Future<CombinedUseResult> Function(CombinedUseCommand)>(
      (ref) =>
          (command) async =>
              (await ref.read(recordStoreProvider.future))
                  .recordCombined(command),
    );
final combinedCorrectionWriterProvider =
    Provider<Future<CombinedUseResult> Function(CombinedCorrectionCommand)>(
      (ref) =>
          (command) async =>
              (await ref.read(recordStoreProvider.future))
                  .correctCombined(command),
    );

class _SourceEntry {
  _SourceEntry({
    required this.itemId,
    required this.itemRevision,
    required this.name,
    required this.unit,
    required this.changed,
    this.label,
    this.record,
  }) {
    amount.addListener(changed);
    site.addListener(changed);
  }
  final String itemId, name;
  final int itemRevision;
  String unit;
  final VoidCallback changed;
  final TextEditingController amount = TextEditingController(),
      site = TextEditingController();
  ProductLabelSnapshot? label;
  UseRecord? record;
  StoredStockContainer? container;
  String? containerId;
  int? containerRevision;
  bool siteOpen = false, sourceOpen = false, planOpen = false;
  DailyRow? intendedRow;
  PhysicalCorrection? physical;
  bool? hasStock;
  bool stockReviewed = false;
  Map<String, Object?> toJson() => {
    'item': itemId,
    'revision': itemRevision,
    'name': name,
    'unit': unit,
    'amount': amount.text,
    'site': site.text,
    'siteOpen': siteOpen,
    'sourceOpen': sourceOpen,
    'container': container?.id ?? containerId,
    'containerRevision': container?.revision ?? containerRevision,
    'label': label?.toJson(),
    'record': record?.id,
    'physical': physical?.name,
    'planOpen': planOpen,
    'intendedRow': intendedRow == null ? null : encodeCombinedRow(intendedRow!),
  };
  void dispose() {
    amount.dispose();
    site.dispose();
  }
}

/// One fixed owner and one command, with a frozen reviewed payload for retries.
class CombinedForm extends ConsumerStatefulWidget {
  const CombinedForm({
    super.key,
    required this.personId,
    this.actionId,
    this.initialItemId,
    this.undo = false,
    this.returnLocation,
  });
  final String personId;
  final String? actionId, initialItemId, returnLocation;
  final bool undo;
  @override
  ConsumerState<CombinedForm> createState() => _CombinedFormState();
}

class _CombinedFormState extends DurableFormState<CombinedForm> {
  AdultProfile? owner;
  final entries = <_SourceEntry>[];
  final date = TextEditingController(), time = TextEditingController();
  bool initialised = false,
      choosing = false,
      reviewing = false,
      preparing = false;
  int itemOffset = 0;
  DateTime? instant;
  CombinedUseCommand? frozen;
  CombinedCorrectionCommand? frozenCorrection;
  List<UseRecord> originals = [];
  @override
  DraftKind get entryKind => widget.actionId == null
      ? DraftKind.combinedDose
      : DraftKind.combinedCorrection;
  @override
  String get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.actionId;
  @override
  Map<String, String> captureEntry() => {
    'components': jsonEncode(entries.map((e) => e.toJson()).toList()),
    'date': date.text,
    'time': time.text,
    'instant': instant?.toIso8601String() ?? '',
    'voided': '${widget.undo}',
    'frozen': frozen != null
        ? jsonEncode(encodeCombinedUse(frozen!))
        : frozenCorrection != null
        ? jsonEncode(encodeCombinedCorrection(frozenCorrection!))
        : '',
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    for (final e in entries) {
      e.dispose();
    }
    entries.clear();
    for (final raw in jsonDecode(fields['components'] ?? '[]') as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final e = _SourceEntry(
        itemId: m['item'] as String,
        itemRevision: m['revision'] as int,
        name: m['name'] as String,
        unit: m['unit'] as String,
        changed: changed,
        label: m['label'] == null
            ? null
            : ProductLabelSnapshot.fromJson(
                Map<String, dynamic>.from(m['label'] as Map),
              ),
        record: originals.where((r) => r.id == m['record']).firstOrNull,
      );
      e.amount.text = m['amount'] as String;
      e.site.text = m['site'] as String;
      e.siteOpen = m['siteOpen'] == true;
      e.sourceOpen = m['sourceOpen'] == true;
      e.containerId = m['container'] as String?;
      e.containerRevision = m['containerRevision'] as int?;
      e.planOpen = m['planOpen'] == true;
      e.intendedRow = m['intendedRow'] == null
          ? null
          : decodeCombinedRow(
              Map<String, dynamic>.from(m['intendedRow'] as Map),
            );
      e.physical = PhysicalCorrection.values
          .where((v) => v.name == m['physical'])
          .firstOrNull;
      entries.add(e);
    }
    date.text = fields['date'] ?? '';
    time.text = fields['time'] ?? '';
    instant = DateTime.tryParse(fields['instant'] ?? '');
    final encoded = fields['frozen'];
    if (encoded != null && encoded.isNotEmpty) {
      if (widget.actionId == null) {
        frozen = decodeCombinedUse(jsonDecode(encoded) as Map<String, dynamic>);
      } else {
        frozenCorrection = decodeCombinedCorrection(
          jsonDecode(encoded) as Map<String, dynamic>,
        );
      }
      reviewing = true;
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    date.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    time.text =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    date.addListener(changed);
    time.addListener(changed);
  }

  void changed() {
    if (!busy && !uncertain) {
      frozen = null;
      frozenCorrection = null;
      instant = null;
      reviewing = false;
    }
    entryChanged();
    if (mounted && draftReady) setState(() {});
  }

  @override
  void dispose() {
    for (final e in entries) {
      e.dispose();
    }
    date.dispose();
    time.dispose();
    super.dispose();
  }

  Future<void> add(SubstanceItem item) async {
    final store = await ref.read(recordStoreProvider.future);
    final label = await store.productLabel(
      personId: widget.personId,
      itemId: item.id,
    );
    if (!mounted) return;
    final e = _SourceEntry(
      itemId: item.id,
      itemRevision: item.revision,
      name: item.name,
      unit: item.unit,
      changed: changed,
      label: label,
    );
    setState(() {
      entries.add(e);
      choosing = false;
    });
    changed();
  }

  DateTime? actual() {
    if (instant != null) return instant;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$')
        .firstMatch('${date.text.trim()} ${time.text.trim()}');
    if (m == null) return null;
    final values = [for (var i = 1; i <= 5; i++) int.parse(m[i]!)];
    final local = DateTime.utc(
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
    );
    if (local.year != values[0] ||
        local.month != values[1] ||
        local.day != values[2] ||
        local.hour != values[3] ||
        local.minute != values[4]) {
      return null;
    }
    final choices = ref.read(actualTimeResolverProvider)(local);
    return choices.length == 1 ? choices.single : null;
  }

  Future<void> review() async {
    if (preparing || busy || uncertain) return;
    final t = AppLocalizations.of(context);
    setState(() => preparing = true);
    try {
      final at = actual();
      if (at == null || entries.length < 2 || entries.length > 16) {
        throw const FormatException('combined');
      }
      for (final e in entries) {
        if (e.site.text.length > 500) {
          setState(() => error = t.combinedSiteInvalid);
          return;
        }
        if (e.record != null && e.amount.text.trim().isEmpty) continue;
        ExactAmount.parseEntry(stockDecimal(e.amount.text));
      }
      if (widget.actionId != null &&
          entries.any((e) => e.hasStock == true && e.physical == null)) {
        setState(() => error = t.combinedPhysicalRequired);
        return;
      }
      commandId ??= newCommandId();
      final sample = await captureIntervalClock(ref);
      if (!mounted) return;
      instant = at;
      if (widget.actionId == null) {
        frozen = CombinedUseCommand(
          commandId: commandId!,
          expectedGeneration: capturedGeneration!,
          personId: widget.personId,
          expectedPersonRevision: capturedPersonRevision!,
          actualAt: at,
          components: [
            for (final e in entries)
              CombinedUseComponent(
                itemId: e.itemId,
                expectedItemRevision: e.itemRevision,
                enteredAmount: stockDecimal(e.amount.text),
                intendedRow: e.intendedRow,
                siteLabel: e.site.text.trim().isEmpty ? null : e.site.text,
                intervalClockSample: sample,
                productUse: e.label == null
                    ? null
                    : ProductUseInput(
                        expectedGeneration: capturedGeneration!,
                        label: e.label!,
                        expectedItemRevision: e.itemRevision,
                        enteredVolume: EnteredStockAmount(
                          stockDecimal(e.amount.text),
                          'ml',
                        ),
                        containerId: e.container?.id,
                        expectedContainerRevision: e.container?.revision,
                        sourceLabel: e.container?.productLabel,
                      ),
                stockUse: e.label != null || e.container == null
                    ? null
                    : StockUseInput(
                        expectedGeneration: capturedGeneration!,
                        containerId: e.container!.id,
                        expectedContainerRevision: e.container!.revision,
                        entered: EnteredStockAmount(
                          stockDecimal(e.amount.text),
                          e.unit,
                        ),
                      ),
              ),
          ],
        );
      } else {
        final components = <CombinedCorrectionComponent>[];
        for (final e in entries) {
          final reviews = await reviewIntervalMutation(
            context,
            ref,
            e.record!,
            actualAt: widget.undo ? null : at,
            voided: widget.undo,
            proposedAmount: widget.undo || e.amount.text.trim().isEmpty
                ? null
                : stockDecimal(e.amount.text),
            intervalClockSample: sample,
            captureClockIfMissing: false,
          );
          if (reviews == null || !mounted) return;
          components.add(
            CombinedCorrectionComponent(
              recordId: e.record!.id,
              expectedRevision: e.record!.revision,
              enteredAmount: widget.undo || e.amount.text.trim().isEmpty
                  ? null
                  : stockDecimal(e.amount.text),
              physicalCorrection: e.physical,
              siteLabel: e.site.text.trim().isEmpty ? null : e.site.text,
              intervalReviews: reviews,
            ),
          );
        }
        frozenCorrection = CombinedCorrectionCommand(
          commandId: commandId!,
          actionId: widget.actionId!,
          personId: widget.personId,
          expectedPersonRevision: capturedPersonRevision!,
          expectedGeneration: capturedGeneration!,
          actualAt: widget.undo ? null : at,
          voided: widget.undo,
          components: components,
        );
      }
      setState(() {
        reviewing = true;
        error = null;
      });
      persistEntry();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is CommandConflict
              ? t.conflictFailure
              : t.combinedInvalid,
        );
      }
    } finally {
      if (mounted) setState(() => preparing = false);
    }
  }

  Future<void> save() async {
    if (frozen == null && frozenCorrection == null) return;
    await commit(
      (_) async {
        final result = frozen != null
            ? await ref.read(combinedWriterProvider)(frozen!)
            : await ref.read(combinedCorrectionWriterProvider)(
                frozenCorrection!,
              );
        ref.read(savedRecordProvider.notifier).set(result.records.first);
      },
      successPath:
          widget.returnLocation ?? '/person-history/${widget.personId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider);
    final group = widget.actionId == null
        ? const AsyncData<CombinedUseResult?>(null)
        : ref.watch(
            combinedLookupProvider((
              personId: widget.personId,
              actionId: widget.actionId!,
            )),
          );
    if (people.hasError || group.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(combinedLookupProvider);
            },
          ),
        ],
      );
    }
    if (!people.hasValue || !group.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final live = people.value!
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    if (live == null || (widget.actionId != null && group.value == null)) {
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!initialised) {
      owner = live;
      originals = group.value?.records ?? [];
      for (final r in originals) {
        final e = _SourceEntry(
          itemId: r.itemId,
          itemRevision: 1,
          name: r.name,
          unit: r.actualUnit,
          changed: changed,
          label: r.product?.label,
          record: r,
        );
        e.amount.text = stockRecordHasDerivedAmount(r)
            ? ''
            : r.originalEntry ?? r.enteredAmount;
        e.site.text = r.siteLabel ?? '';
        e.siteOpen = e.site.text.isNotEmpty;
        entries.add(e);
      }
      if (originals.isNotEmpty) {
        final at = originals.first.actualAt.toLocal();
        date.text =
            '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
        time.text =
            '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
        instant = originals.first.actualAt;
      }
      initialised = true;
      if (widget.initialItemId != null) {
        Future<void>(() async {
          final item = await (await ref.read(recordStoreProvider.future))
              .itemById(widget.initialItemId!);
          if (item != null && item.personId == widget.personId && mounted) {
            await add(item);
          }
        });
      }
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        !live.isArchived &&
        live.revision == capturedPersonRevision &&
        originals.every((r) => !r.isVoided);
    final enabled =
        valid && !busy && !uncertain && !conflict && !reviewing && !preparing;
    // Reopening resolves captured sources without replacing their reviewed revisions.
    for (final e in entries) {
      if (e.record != null) {
        final movement = ref.watch(
          stockUseProvider((personId: widget.personId, recordId: e.record!.id)),
        );
        if (!movement.hasValue) {
          return EntryPage(children: [Text(t.loadingRecords)]);
        }
        e.hasStock = movement.value != null;
        e.stockReviewed = movement.value?.reviewedCorrection != null;
      }
      if (e.containerId != null && e.container == null && !uncertain) {
        final source = ref.watch(
          stockContainerProvider((
            personId: widget.personId,
            containerId: e.containerId!,
          )),
        );
        if (!source.hasValue) {
          return EntryPage(children: [Text(t.loadingRecords)]);
        }
        if (source.value == null ||
            source.value!.revision != e.containerRevision) {
          conflict = true;
          return wrap([Text(t.conflictFailure)]);
        }
        e.container = source.value;
      }
    }
    return wrap([
      Heading(
        reviewing
            ? t.combinedReview
            : widget.actionId == null
            ? t.combinedHeading
            : t.combinedCorrection,
      ),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(
        widget.undo
            ? t.combinedUndoHelp
            : reviewing
            ? t.combinedReviewHelp
            : t.combinedHelp,
      ),
      if (!valid) Text(t.conflictFailure),
      const SizedBox(height: 20),
      if (!reviewing) ...[
        LabelledInput(
          label: t.actualDateLabel,
          controller: date,
          enabled: enabled,
        ),
        LabelledInput(
          label: t.actualTimeLabel,
          controller: time,
          enabled: enabled,
          error: error == t.combinedInvalid ? error : null,
        ),
      ] else
        Text(t.actualStamp(displayStamp(context, ref, instant!))),
      for (var i = 0; i < entries.length; i++)
        sourceWidget(entries[i], i, enabled),
      if (reviewing) ...reviewTotals(),
      if (widget.actionId == null && !reviewing) ...[
        Text(t.combinedCount),
        if (entries.length < 16)
          VitalButton.secondary(
            onPressed: enabled
                ? () => setState(() => choosing = !choosing)
                : null,
            child: Text(t.add),
          ),
        if (choosing) ...itemChoices(enabled),
      ],
      ?failure(),
      const SizedBox(height: 20),
      if (reviewing && !uncertain)
        VitalButton.secondary(
          onPressed: busy
              ? null
              : () {
                  setState(() {
                    reviewing = false;
                    frozen = null;
                    frozenCorrection = null;
                  });
                  persistEntry();
                },
          child: Text(t.cancel),
        ),
      VitalButton(
        onPressed: busy || preparing || conflict || (!valid && !uncertain)
            ? null
            : reviewing || uncertain
            ? save
            : review,
        child: Text(
          busy || preparing
              ? t.saving
              : uncertain
              ? t.retry
              : reviewing
              ? t.save
              : t.review,
        ),
      ),
    ]);
  }

  List<Widget> itemChoices(bool enabled) {
    final t = AppLocalizations.of(context),
        query = (scope: FeedScope.person(widget.personId), offset: itemOffset);
    return [
      ref
          .watch(scopedItemsPageProvider(query))
          .when(
            data: (items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items.take(50))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(item.name),
                        Text(t.itemDetails(item.form, item.type, item.unit)),
                        VitalButton.secondary(
                          key: ValueKey('combine-add-${item.id}'),
                          onPressed: enabled ? () => add(item) : null,
                          child: Text(t.combinedChoose),
                        ),
                      ],
                    ),
                  ),
                if (itemOffset > 0)
                  VitalButton.secondary(
                    onPressed: () => setState(() => itemOffset -= 50),
                    child: Text(t.previous),
                  ),
                if (items.length > 50)
                  VitalButton.secondary(
                    onPressed: () => setState(() => itemOffset += 50),
                    child: Text(t.next),
                  ),
              ],
            ),
            error: (_, _) => LoadFailure(
              onRetry: () => ref.invalidate(scopedItemsPageProvider(query)),
            ),
            loading: () => Text(t.loadingRecords),
          ),
    ];
  }

  Widget sourceWidget(_SourceEntry e, int index, bool enabled) {
    final t = AppLocalizations.of(context);
    ExactAmount? volume;
    try {
      volume = ExactAmount.parseEntry(stockDecimal(e.amount.text));
    } catch (_) {}
    final quantity = volume == null ? null : stockAmountText(t, volume, e.unit);
    final outflow = sourceOutflow(e);
    return Padding(
      key: ValueKey('combined-source-$index'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Heading(t.combinedSource(index + 1)),
          Text(e.name),
          if (reviewing)
            Text(
              quantity ??
                  (e.record != null
                      ? stockAmountText(
                          t,
                          e.record!.actualAmount,
                          e.record!.actualUnit,
                        )
                      : e.amount.text),
            )
          else
            LabelledInput(
              label: t.amountLabel,
              semanticLabel: t.combinedAmountLabel(e.name, e.unit),
              controller: e.amount,
              helper: e.record != null && stockRecordHasDerivedAmount(e.record!)
                  ? t.stockCorrectionKeep
                  : null,
              enabled: enabled && !widget.undo,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          if (!reviewing) Text(e.unit),
          if (!reviewing &&
              e.record == null &&
              e.label == null &&
              e.container != null &&
              const {'mg', 'ml'}.contains(e.unit))
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final unit in ['mg', 'ml'])
                  Semantics(
                    selected: e.unit == unit,
                    child: VitalButton.secondary(
                      multiline: true,
                      onPressed: enabled
                          ? () {
                              setState(() => e.unit = unit);
                              changed();
                            }
                          : null,
                      child: Text(unit),
                    ),
                  ),
              ],
            ),
          if (e.label != null)
            ProductLabelView(
              label: e.container?.productLabel ?? e.label!,
              volume: volume,
            ),
          if (e.record == null && !reviewing) ...[
            Semantics(
              label: t.combinedSourceLabel(index + 1, e.name),
              selected: e.sourceOpen,
              child: VitalButton.secondary(
                key: ValueKey('combined-stock-$index'),
                onPressed: enabled
                    ? () => setState(() => e.sourceOpen = !e.sourceOpen)
                    : null,
                child: Text(t.stock),
              ),
            ),
            if (e.sourceOpen)
              StockSourcePicker(
                personId: widget.personId,
                itemId: e.itemId,
                selectedId: e.container?.id,
                productOnly: e.label != null,
                enabled: enabled,
                onSelected: (c) {
                  setState(() {
                    e.container = c;
                    e.containerId = null;
                    e.containerRevision = null;
                  });
                  changed();
                },
              ),
          ],
          if (e.container != null) ...[
            Text(e.container!.label),
            Text(t.stockStrengthValue(e.container!.strength.label)),
          ],
          if (e.record == null) ...[
            if (!reviewing)
              VitalButton.secondary(
                onPressed: enabled
                    ? () => setState(() => e.planOpen = !e.planOpen)
                    : null,
                child: Text(t.schedule),
              ),
            if (!reviewing && e.planOpen) ...plannedChoices(e, enabled),
            if (e.intendedRow != null) ...[
              Text(t.planTime),
              if (e.intendedRow!.expectation.instant != null)
                Text(
                  t.actualStamp(
                    displayStamp(
                      context,
                      ref,
                      e.intendedRow!.expectation.instant!,
                    ),
                  ),
                ),
              Text(
                t.stockQuantity(
                  e.intendedRow!.expectation.amount.enteredText,
                  e.intendedRow!.expectation.amount.unit,
                ),
              ),
            ],
            if (e.intendedRow == null) Text(t.intervalExtraHelp),
          ],
          if (e.record == null)
            Text(
              e.container == null
                  ? t.combinedNoStock
                  : outflow == null
                  ? t.combinedStockUnknown
                  : t.combinedOutflow(
                      stockAmountText(t, outflow, e.container!.unit),
                    ),
            ),
          if (e.record != null) ...[
            ProductRecordDetails(record: e.record!),
            StockRecordEffect(record: e.record!),
            if (!reviewing && e.hasStock == true) ...[
              Text(t.stockPhysicalRequired),
              Semantics(
                label: t.combinedKeepLabel(e.name),
                selected: e.physical == PhysicalCorrection.retainPhysicalEffect,
                child: VitalButton.secondary(
                  onPressed: enabled
                      ? () {
                          setState(
                            () => e.physical =
                                PhysicalCorrection.retainPhysicalEffect,
                          );
                          changed();
                        }
                      : null,
                  child: Text(t.combinedKeep),
                ),
              ),
              Text(e.stockReviewed ? t.stockReviewedKeep : t.combinedKeepHelp),
              if (!e.stockReviewed) ...[
                Semantics(
                  label: t.combinedRestoreLabel(e.name),
                  selected:
                      e.physical == PhysicalCorrection.reverseRecordedEffect,
                  child: VitalButton.secondary(
                    onPressed: enabled
                        ? () {
                            setState(
                              () => e.physical =
                                  PhysicalCorrection.reverseRecordedEffect,
                            );
                            changed();
                          }
                        : null,
                    child: Text(t.combinedReverse),
                  ),
                ),
                Text(t.combinedReverseHelp),
              ],
            ],
            if (e.physical != null)
              Text(
                e.physical == PhysicalCorrection.retainPhysicalEffect
                    ? t.combinedRetainEffect
                    : t.combinedRestoreEffect,
              ),
          ],
          if (!reviewing)
            VitalButton.secondary(
              onPressed: enabled
                  ? () => setState(() {
                      e.siteOpen = !e.siteOpen;
                      entryChanged();
                    })
                  : null,
              child: Text(t.combinedSiteAction),
            ),
          if (reviewing && e.site.text.isNotEmpty)
            Text(t.combinedSiteValue(e.site.text)),
          if (!reviewing && e.siteOpen) ...[
            LabelledInput(
              label: t.combinedSite,
              semanticLabel: t.combinedSiteLabel(e.name),
              helper: t.combinedSiteHelp,
              controller: e.site,
              enabled: enabled,
            ),
            for (final label
                in ref.watch(siteLabelsProvider(widget.personId)).value ??
                    <String>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label),
                    VitalButton.secondary(
                      onPressed: enabled ? () => e.site.text = label : null,
                      child: Text(t.combinedChoose),
                    ),
                  ],
                ),
              ),
          ],
          if (e.record == null && !reviewing)
            Semantics(
              label: t.combinedRemoveLabel(index + 1, e.name),
              selected: null,
              child: VitalButton.secondary(
                onPressed: enabled
                    ? () {
                        setState(() => entries.remove(e));
                        e.dispose();
                        changed();
                      }
                    : null,
                child: Text(t.combinedRemove),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> plannedChoices(_SourceEntry e, bool enabled) {
    final t = AppLocalizations.of(context),
        rows = ref.watch(dailyFeedProvider(FeedScope.person(widget.personId)));
    return [
      VitalButton.secondary(
        onPressed: enabled
            ? () {
                setState(() => e.intendedRow = null);
                changed();
              }
            : null,
        child: Text(t.extra),
      ),
      rows.when(
        data: (result) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in result.rows.where(
              (r) => r.expectation.itemId == e.itemId && !r.isResolved,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(row.itemName),
                    Text(
                      t.stockQuantity(
                        row.expectation.amount.enteredText,
                        row.expectation.amount.unit,
                      ),
                    ),
                    if (row.expectation.instant != null)
                      Text(
                        t.actualStamp(
                          displayStamp(context, ref, row.expectation.instant!),
                        ),
                      ),
                    VitalButton.secondary(
                      onPressed: enabled
                          ? () {
                              setState(() => e.intendedRow = row);
                              changed();
                            }
                          : null,
                      child: Text(t.combinedChoose),
                    ),
                  ],
                ),
              ),
            if (!result.complete) Text(t.planIncomplete),
          ],
        ),
        error: (_, _) =>
            LoadFailure(onRetry: () => ref.invalidate(dailyFeedProvider)),
        loading: () => Text(t.loadingRecords),
      ),
    ];
  }

  ExactAmount? sourceOutflow(_SourceEntry e) {
    if (e.container == null) return null;
    try {
      final amount = ExactAmount.parseEntry(stockDecimal(e.amount.text)),
          c = e.container!;
      return e.unit == c.unit
          ? amount
          : c.strength.equivalent(amount, from: e.unit, to: c.unit);
    } catch (_) {
      return null;
    }
  }

  List<Widget> reviewTotals() {
    final t = AppLocalizations.of(context),
        sources = <String, StoredStockContainer>{};
    final folded = combineStockOutflows([
      for (final e in entries.where((e) => e.container != null))
        CombinedStockOutflow(
          containerId: e.container!.id,
          personId: e.container!.personId,
          itemId: e.container!.itemId,
          unit: e.container!.unit,
          expectedRevision: e.container!.revision,
          amount: sourceOutflow(e),
        ),
    ]);
    for (final e in entries.where((e) => e.container != null)) {
      sources[e.container!.id] = e.container!;
    }
    final totals = {
      for (final outflow in folded) outflow.containerId: outflow.amount,
    };
    return [
      for (final id in totals.keys) ...[
        Text(
          t.combinedTotal(
            sources[id]!.label,
            totals[id] == null
                ? t.stockUnknown
                : stockAmountText(t, totals[id]!, sources[id]!.unit),
          ),
        ),
        if (totals[id] != null && sources[id]!.balance.value != null)
          Text(
            t.combinedRemaining(
              stockAmountText(
                t,
                sources[id]!.balance.value! - totals[id]!,
                sources[id]!.unit,
              ),
            ),
          ),
      ],
    ];
  }
}

/// Site-only corrections never create a dose or a stock movement.
class SiteForm extends ConsumerStatefulWidget {
  const SiteForm({super.key, required this.personId, required this.recordId});
  final String personId, recordId;
  @override
  ConsumerState<SiteForm> createState() => _SiteFormState();
}

class _SiteFormState extends DurableFormState<SiteForm> {
  final site = TextEditingController();
  AdultProfile? owner;
  UseRecord? record;
  @override
  DraftKind get entryKind => DraftKind.siteEdit;
  @override
  String get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String get entryTarget => widget.recordId;
  @override
  int? get entryTargetRevision => record?.revision;
  @override
  Map<String, String> captureEntry() => {'site': site.text};
  @override
  void restoreEntry(Map<String, String> fields) {
    site.text = fields['site'] ?? '';
  }

  @override
  void initState() {
    super.initState();
    site.addListener(entryChanged);
  }

  @override
  void dispose() {
    site.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (site.text.length > 500) {
      setState(() => error = AppLocalizations.of(context).combinedSiteInvalid);
      return;
    }
    await commit(
      (command) async =>
          (await ref.read(recordStoreProvider.future)).updateSite(
            commandId: command,
            personId: widget.personId,
            expectedPersonRevision: capturedPersonRevision!,
            expectedGeneration: capturedGeneration!,
            recordId: widget.recordId,
            expectedRevision: capturedTargetRevision!,
            siteLabel: site.text.trim().isEmpty ? null : site.text,
          ),
      successPath: '/person-history/${widget.personId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider),
        current = ref.watch(
          recordLookupProvider((
            recordId: widget.recordId,
            personId: widget.personId,
          )),
        );
    if (people.hasError || current.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () {
              ref.invalidate(profilesProvider);
              ref.invalidate(recordLookupProvider);
            },
          ),
        ],
      );
    }
    if (!people.hasValue || !current.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final live = people.value!
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    if (live == null || current.value == null) {
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (record == null) {
      owner = live;
      record = current.value;
      site.text = record!.siteLabel ?? '';
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        !live.isArchived &&
        live.revision == capturedPersonRevision &&
        current.value!.revision == capturedTargetRevision;
    final enabled = valid && !busy && !uncertain && !conflict;
    return wrap([
      Heading(t.combinedSites),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(record!.name),
      Text(t.actualStamp(displayStamp(context, ref, record!.actualAt))),
      LabelledInput(
        label: t.combinedSite,
        controller: site,
        helper: t.combinedSiteHelp,
        enabled: enabled,
      ),
      if (!valid) Text(t.conflictFailure),
      ?failure(),
      VitalButton(
        onPressed: !busy && (uncertain || enabled) ? save : null,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.save,
        ),
      ),
    ]);
  }
}
