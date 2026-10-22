import 'dart:async';

import '../../app/device_zone.dart';
import '../../app/display_preferences.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/record_store.dart';
import '../../app/storage.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'stock_providers.dart';
import '../products/product_widgets.dart';

bool stockRecordHasDerivedAmount(UseRecord record) =>
    record.actualUnit != (record.originalUnit ?? record.unit) ||
    record.actualAmount !=
        ExactAmount.parseEntry(record.originalEntry ?? record.enteredAmount);
String stockRecordAmountNumber(AppLocalizations t, UseRecord record) =>
    stockRecordHasDerivedAmount(record)
    ? stockAmountNumber(t, record.actualAmount)
    : record.originalEntry ?? record.enteredAmount;

String stockAmountNumber(AppLocalizations t, ExactAmount value) =>
    stockAmountText(t, value, '').trim();

String stockAmountText(AppLocalizations t, ExactAmount value, String unit) {
  final decimal = value.roundedDecimal();
  final parts = decimal.replaceFirst('-', '').split('.');
  final represented = ExactAmount(
    BigInt.parse(parts.join()) *
        (value.numerator.isNegative ? -BigInt.one : BigInt.one),
    BigInt.from(10).pow(parts.length == 1 ? 0 : parts[1].length),
  );
  final display = decimal.contains('.')
      ? decimal
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '')
      : decimal;
  return represented == value
      ? t.stockQuantity(display, unit)
      : t.stockApproximate(display, unit);
}

class StockBalanceText extends StatelessWidget {
  const StockBalanceText({super.key, required this.container});
  final StoredStockContainer container;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), balance = container.balance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          balance.limitReached
              ? t.stockLimit
              : balance.value == null
              ? t.stockUnknown
              : t.stockBalance(
                  stockAmountText(t, balance.value!, container.unit),
                ),
        ),
        if (balance.isDeficit) Text(t.stockDeficit),
        if (container.needsRefill)
          Text(t.stockRefillDue)
        else if (container.isLow)
          Text(t.stockLow),
      ],
    );
  }
}

/// Optional pack facts kept with the container identity. Expiry is factual and
/// never blocks recording; capacity is descriptive and never caps a balance.
class StockPackFacts extends StatelessWidget {
  const StockPackFacts({
    super.key,
    required this.container,
    this.detailed = false,
  });
  final StoredStockContainer container;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = StitchColors(context);
    final today = CivilDate.fromDateTime(DateTime.now());
    final expiry = container.expiryDate;
    final expiryState = container.expiryState(today);
    final rows = <Widget>[
      if (container.lot case final lot?)
        Text(t.featureStockLotValue(lot), style: StitchType.caption),
      if (expiry != null)
        Text(
          switch (expiryState) {
            StockExpiryState.expired => t.featureStockExpiryExpired(
              expiry.toString(),
            ),
            StockExpiryState.today => t.featureStockExpiryToday,
            _ => t.featureStockExpiryFuture(expiry.toString()),
          },
          style: StitchType.caption.copyWith(
            color: expiryState == StockExpiryState.expired
                ? colors.danger
                : expiryState == StockExpiryState.today
                ? colors.amber
                : colors.muted,
          ),
        ),
      if (container.capacity case final capacity?)
        Text(
          t.featureStockCapacityValue(
            stockAmountText(t, capacity, container.unit),
          ),
          style: StitchType.caption.copyWith(color: colors.muted),
        )
      else if (detailed)
        Text(
          t.featureStockCapacityUnknown,
          style: StitchType.caption.copyWith(color: colors.muted),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }
}

/// A visually bounded exact proportion. Unknown capacity or balance never
/// assumes 100 percent; the full exact values stay in the text.
class StockCapacityProgress extends StatelessWidget {
  const StockCapacityProgress({
    super.key,
    required this.container,
    this.detailed = false,
  });
  final StoredStockContainer container;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final capacity = container.capacity;
    final balance = container.balance;
    if (capacity == null) {
      return detailed
          ? Text(
              t.featureStockCapacityUnknown,
              style: StitchType.caption.copyWith(
                color: StitchColors(context).muted,
              ),
            )
          : const SizedBox.shrink();
    }
    final value = balance.value;
    if (value == null || balance.limitReached) {
      return VitalProgress.unknown(
        label: t.featureStockCapacity,
        annotation: balance.limitReached ? t.stockLimit : t.stockUnknownValue,
      );
    }
    final fraction = stockCapacityFraction(value, capacity);
    final above = value > capacity;
    return VitalProgress(
      label: t.featureStockCapacity,
      valueText: stockAmountText(t, value, container.unit),
      totalText: stockAmountText(t, capacity, container.unit),
      fraction: fraction,
      annotation: above
          ? t.featureStockAboveCapacity
          : balance.isDeficit
          ? t.stockDeficit
          : null,
    );
  }
}

/// Conditional run-out estimate shared by the stock inventory, container
/// notices and the substance summary. It always names its assumption.
class StockForecastLine extends ConsumerStatefulWidget {
  const StockForecastLine({
    super.key,
    required this.container,
    this.detailed = false,
  });
  final StoredStockContainer container;
  final bool detailed;

  @override
  ConsumerState<StockForecastLine> createState() => _StockForecastLineState();
}

class _StockForecastLineState extends ConsumerState<StockForecastLine> {
  late DateTime _asOf = _roundedNow();
  Timer? _timer;

  static DateTime _roundedNow() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _asOf = _roundedNow());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _reason(
    AppLocalizations t,
    StockRunOutForecast forecast,
  ) => switch (forecast.reason) {
    StockForecastReason.asNeeded => t.featureStockRunOutAsNeeded,
    StockForecastReason.unscheduled => t.featureStockRunOutUnscheduled,
    StockForecastReason.paused => t.featureStockRunOutPaused,
    StockForecastReason.unknownBalance => t.featureStockRunOutUnknown,
    StockForecastReason.deficit => t.featureStockRunOutDeficit,
    StockForecastReason.emptyBalance => t.featureStockRunOutEmpty,
    StockForecastReason.aggregateLimit => t.featureStockRunOutLimit,
    StockForecastReason.missingAmount => t.featureStockRunOutMissingAmount,
    StockForecastReason.incompatibleUnits => t.featureStockRunOutIncompatible,
    StockForecastReason.unresolvedZone => t.featureStockRunOutZone,
    StockForecastReason.unresolvedClock => t.featureStockRunOutClock,
    StockForecastReason.unsupportedSchedule => t.featureStockRunOutUnsupported,
    StockForecastReason.intervalSchedule => t.featureStockRunOutInterval,
    StockForecastReason.planEndsFirst => t.featureStockRunOutPlanEnds(
      forecast.throughDate?.toString() ?? '',
    ),
    StockForecastReason.completeAfterHorizon => t.featureStockRunOutHorizon,
    StockForecastReason.noPlannedUse => t.featureStockRunOutNoPlanned,
    null => '',
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
    final query = (
      personId: widget.container.personId,
      containerId: widget.container.id,
      asOf: _asOf,
      zone: zone,
    );
    return ref
        .watch(stockForecastProvider(query))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.featureStockRunOutUnavailable, style: StitchType.caption),
              VitalButton.secondary(
                onPressed: () => ref.invalidate(stockForecastProvider(query)),
                child: Text(t.retry),
              ),
            ],
          ),
          data: (forecast) {
            if (forecast == null) return const SizedBox.shrink();
            final colors = StitchColors(context);
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (forecast.isAvailable) ...[
                    Text(
                      t.featureStockRunOut,
                      style: StitchType.caption.copyWith(
                        color: colors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      t.featureStockRunOutEstimate(forecast.date.toString()),
                      style: StitchType.body.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      t.featureStockRunOutHelp,
                      style: StitchType.caption.copyWith(color: colors.muted),
                    ),
                  ] else ...[
                    Text(
                      t.featureStockRunOutUnavailable,
                      style: StitchType.caption.copyWith(
                        color: colors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _reason(t, forecast),
                      style: StitchType.caption.copyWith(color: colors.muted),
                    ),
                  ],
                ],
              ),
            );
          },
        );
  }
}

class StockNotices extends ConsumerStatefulWidget {
  const StockNotices({super.key, required this.scope});
  final FeedScope scope;
  @override
  ConsumerState<StockNotices> createState() => _StockNoticesState();
}

class _StockNoticesState extends ConsumerState<StockNotices> {
  int offset = 0;
  @override
  void didUpdateWidget(covariant StockNotices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) offset = 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        query = (scope: widget.scope, offset: offset);
    return ref
        .watch(stockNoticeProvider(query))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => LoadFailure(
            onRetry: () => ref.invalidate(stockNoticeProvider(query)),
          ),
          data: (page) {
            if (page.rows.isEmpty && offset == 0 && !page.hasMore) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Heading(t.stockNotices),
                for (final row in page.rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: VitalSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            t.stockNoticeTarget(
                              ownerLabel(ref, t, row.container.personId),
                              row.container.label,
                            ),
                          ),
                          Text(row.itemName),
                          Text(
                            t.stockStrengthValue(row.container.strength.label),
                          ),
                          StockBalanceText(container: row.container),
                          VitalButton.secondary(
                            onPressed: () => context.push(
                              '/stock/${row.container.personId}?item=${row.container.itemId}',
                            ),
                            child: Text(t.review),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (page.hasMore) Text(t.stockMore),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (offset > 0)
                      VitalButton.secondary(
                        onPressed: () => setState(() => offset -= 50),
                        child: Text(t.previous),
                      ),
                    if (page.hasMore)
                      VitalButton.secondary(
                        onPressed: () => setState(() => offset += 50),
                        child: Text(t.next),
                      ),
                  ],
                ),
              ],
            );
          },
        );
  }
}

/// The caller owns the captured selection and persists it in its ordinary draft.
class StockSourcePicker extends ConsumerStatefulWidget {
  const StockSourcePicker({
    super.key,
    required this.personId,
    required this.itemId,
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
    this.productOnly = false,
  });
  final String personId, itemId;
  final String? selectedId;
  final ValueChanged<StoredStockContainer?> onSelected;
  final bool enabled, productOnly;
  @override
  ConsumerState<StockSourcePicker> createState() => _StockSourcePickerState();
}

class _StockSourcePickerState extends ConsumerState<StockSourcePicker> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        q = (
          personId: widget.personId,
          itemId: widget.itemId as String?,
          offset: offset,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.stockSource),
        Text(t.stockOptional),
        Semantics(
          selected: widget.selectedId == null,
          child: VitalButton.secondary(
            multiline: true,
            onPressed: widget.enabled ? () => widget.onSelected(null) : null,
            child: Text(t.stockNone),
          ),
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
                  for (final c
                      in rows
                          .take(50)
                          .where(
                            (c) =>
                                (c.productLabel != null) == widget.productOnly,
                          ))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(c.label),
                          if (c.productLabel != null)
                            ProductLabelView(label: c.productLabel!)
                          else
                            Text(t.stockStrengthValue(c.strength.label)),
                          StockBalanceText(container: c),
                          Semantics(
                            selected: widget.selectedId == c.id,
                            label: t.stockNoticeTarget(
                              ownerLabel(ref, t, c.personId),
                              c.label,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: VitalButton.secondary(
                                multiline: true,
                                key: ValueKey('choose-${c.id}'),
                                onPressed: widget.enabled
                                    ? () => widget.onSelected(c)
                                    : null,
                                child: Text(
                                  widget.selectedId == c.id
                                      ? t.stockSelected
                                      : t.stockChoose,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (offset > 0)
                        VitalButton.secondary(
                          onPressed: widget.enabled
                              ? () => setState(() => offset -= 50)
                              : null,
                          child: Text(t.previous),
                        ),
                      if (rows.length > 50)
                        VitalButton.secondary(
                          onPressed: widget.enabled
                              ? () => setState(() => offset += 50)
                              : null,
                          child: Text(t.next),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class StockPhysicalChoice extends StatelessWidget {
  const StockPhysicalChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.reviewed = false,
  });
  final PhysicalCorrection? value;
  final ValueChanged<PhysicalCorrection> onChanged;
  final bool enabled, reviewed;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.stockPhysical),
        Text(reviewed ? t.stockAlreadyReviewed : t.stockPhysicalHelp),
        Text(reviewed ? t.stockReviewedKeep : t.stockRetainHelp),
        Semantics(
          selected: value == PhysicalCorrection.retainPhysicalEffect,
          child: VitalButton.secondary(
            multiline: true,
            onPressed: enabled
                ? () => onChanged(PhysicalCorrection.retainPhysicalEffect)
                : null,
            child: Text(reviewed ? t.stockKeepBalance : t.stockRetain),
          ),
        ),
        if (!reviewed) ...[
          Text(t.stockReverseHelp),
          Semantics(
            selected: value == PhysicalCorrection.reverseRecordedEffect,
            child: VitalButton.secondary(
              multiline: true,
              onPressed: enabled
                  ? () => onChanged(PhysicalCorrection.reverseRecordedEffect)
                  : null,
              child: Text(t.stockReverse),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

Future<PhysicalCorrection?> choosePhysicalCorrection(
  BuildContext context,
  StoredStockMovement movement, {
  required String personName,
  required String itemName,
  required String quantity,
  required String containerLabel,
}) async {
  final t = AppLocalizations.of(context);
  return showVitalDialog<PhysicalCorrection>(
    context: context,
    builder: (context) => VitalDialog(
      title: Text(t.stockPhysical),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.profileOwner(personName)),
            Text(itemName),
            Text(quantity),
            Text(containerLabel),
            Text(
              movement.reviewedCorrection == null
                  ? t.stockPhysicalHelp
                  : t.stockAlreadyReviewed,
            ),
            Text(
              movement.reviewedCorrection != null
                  ? t.stockReviewedKeep
                  : t.stockRetainHelp,
            ),
            VitalButton.secondary(
              multiline: true,
              onPressed: () =>
                  Navigator.of(context)
                      .pop(PhysicalCorrection.retainPhysicalEffect),
              child: Text(
                movement.reviewedCorrection != null
                    ? t.stockKeepBalance
                    : t.stockRetain,
              ),
            ),
            if (movement.reviewedCorrection == null) ...[
              Text(t.stockReverseHelp),
              VitalButton.secondary(
                multiline: true,
                onPressed: () =>
                    Navigator.of(context)
                        .pop(PhysicalCorrection.reverseRecordedEffect),
                child: Text(t.stockReverse),
              ),
            ],
          ],
        ),
      ),
      actions: [
        VitalButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
      ],
    ),
  );
}

class StockRecordEffect extends ConsumerWidget {
  const StockRecordEffect({super.key, required this.record});
  final UseRecord record;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        q = (personId: record.personId, recordId: record.id);
    return ref
        .watch(stockUseProvider(q))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) =>
              LoadFailure(onRetry: () => ref.invalidate(stockUseProvider(q))),
          data: (movement) {
            if (movement == null) return const SizedBox.shrink();
            final target = (
              personId: record.personId,
              containerId: movement.containerId,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.stockStrengthValue(movement.strength.label)),
                if (movement.enteredText != null)
                  Text(
                    t.stockEntered(
                      movement.enteredText!,
                      movement.enteredUnit!,
                    ),
                  ),
                ref
                    .watch(stockContainerProvider(target))
                    .when(
                      loading: () => Text(t.loadingRecords),
                      error: (_, _) => LoadFailure(
                        onRetry: () =>
                            ref.invalidate(stockContainerProvider(target)),
                      ),
                      data: (c) => c == null
                          ? Text(t.stockUnavailable)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(c.label),
                                StockBalanceText(container: c),
                                if (c.balance.isDeficit) Text(t.stockMismatch),
                                VitalButton.secondary(
                                  onPressed: () => context.push(
                                    '/stock/${c.personId}?item=${c.itemId}',
                                  ),
                                  child: Text(t.review),
                                ),
                              ],
                            ),
                    ),
              ],
            );
          },
        );
  }
}

class StockDosePreview extends StatelessWidget {
  const StockDosePreview({
    super.key,
    required this.enteredText,
    required this.enteredUnit,
    required this.selected,
    required this.base,
    required this.keep,
    required this.onKeep,
    required this.onActual,
    this.enabled = true,
  });
  final String enteredText, enteredUnit;
  final StoredStockContainer selected;
  final StoredStockContainer? base;
  final FixedReplacementAmount? keep;
  final ValueChanged<FixedReplacementAmount> onKeep;
  final VoidCallback onActual;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    EnteredStockAmount? entered;
    try {
      entered = EnteredStockAmount(stockDecimal(enteredText), enteredUnit);
    } catch (_) {
      /* The amount field owns validation. */
    }
    final changed =
        base != null &&
        base!.id != selected.id &&
        !sameStockStrength(base!.strength, selected.strength);
    final mg = entered == null
        ? null
        : selected.strength.equivalent(
            entered.value,
            from: enteredUnit,
            to: 'mg',
          );
    final ml = entered == null
        ? null
        : selected.strength.equivalent(
            entered.value,
            from: enteredUnit,
            to: 'ml',
          );
    final replacement = changed && entered != null && keep != null
        ? ReplacementAmounts.calculate(
            entered: entered,
            oldStrength: base!.strength,
            newStrength: selected.strength,
            keep: keep!,
          )
        : null;
    final supported =
        entered != null &&
        base != null &&
        ReplacementAmounts.calculate(
              entered: entered,
              oldStrength: base!.strength,
              newStrength: selected.strength,
              keep: FixedReplacementAmount.milligrams,
            ) !=
            null &&
        ReplacementAmounts.calculate(
              entered: entered,
              oldStrength: base!.strength,
              newStrength: selected.strength,
              keep: FixedReplacementAmount.millilitres,
            ) !=
            null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.stockStrengthValue(selected.strength.label)),
        if (changed) ...[
          Heading(t.stockReplacement),
          Text(t.stockReplacementFrom(base!.strength.label)),
          Text(t.stockReplacementHelp),
          if (supported)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Semantics(
                  selected: keep == FixedReplacementAmount.milligrams,
                  child: VitalButton.secondary(
                    multiline: true,
                    onPressed: enabled
                        ? () => onKeep(FixedReplacementAmount.milligrams)
                        : null,
                    child: Text(t.stockKeepMg),
                  ),
                ),
                Semantics(
                  selected: keep == FixedReplacementAmount.millilitres,
                  child: VitalButton.secondary(
                    multiline: true,
                    onPressed: enabled
                        ? () => onKeep(FixedReplacementAmount.millilitres)
                        : null,
                    child: Text(t.stockKeepMl),
                  ),
                ),
              ],
            )
          else if (entered != null) ...[
            Text(t.stockNoEquivalent),
            VitalButton.secondary(
              onPressed: enabled ? onActual : null,
              child: Text(t.stockEnter),
            ),
          ],
          if (replacement != null) ...[
            Text(
              t.stockNewEquivalent(
                stockAmountText(t, replacement.milligrams, 'mg'),
              ),
            ),
            Text(
              t.stockNewEquivalent(
                stockAmountText(t, replacement.millilitres, 'ml'),
              ),
            ),
          ],
        ] else ...[
          if (mg != null && enteredUnit != 'mg')
            Text(t.stockNewEquivalent(stockAmountText(t, mg, 'mg'))),
          if (ml != null && enteredUnit != 'ml')
            Text(t.stockNewEquivalent(stockAmountText(t, ml, 'ml'))),
          if ((enteredUnit == 'mg' && ml == null) ||
              (enteredUnit == 'ml' && mg == null))
            Text(t.stockNoEquivalent),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

class StockItemName extends ConsumerWidget {
  const StockItemName({super.key, required this.itemId});
  final String itemId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(itemLookupProvider(itemId))
      .when(
        data: (item) => Text(item?.name ?? AppLocalizations.of(context).noItem),
        loading: () => Text(AppLocalizations.of(context).loadingRecords),
        error: (_, _) => LoadFailure(
          onRetry: () => ref.invalidate(itemLookupProvider(itemId)),
        ),
      );
}

class StockMovementHistory extends ConsumerStatefulWidget {
  const StockMovementHistory({
    super.key,
    required this.personId,
    required this.containerId,
    required this.unit,
  });
  final String personId, containerId, unit;
  @override
  ConsumerState<StockMovementHistory> createState() =>
      _StockMovementHistoryState();
}

class _StockMovementHistoryState extends ConsumerState<StockMovementHistory> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        q = (
          personId: widget.personId,
          containerId: widget.containerId,
          offset: offset,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.stockHistory),
        ref
            .watch(stockMovementsProvider(q))
            .when(
              loading: () => Text(t.loadingRecords),
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(stockMovementsProvider(q)),
              ),
              data: (rows) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final movement in rows.take(50))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            t.stockMovementEntry(
                              switch (movement.kind) {
                                StockMovementKind.restock => t.stockRestock,
                                StockMovementKind.waste => t.stockWaste,
                                StockMovementKind.reconciliation =>
                                  t.stockMeasure,
                                StockMovementKind.actualUse => t.recordHeading,
                                StockMovementKind.correction =>
                                  t.correctHeading,
                              },
                              movement.amount == null
                                  ? t.stockUnknownValue
                                  : stockAmountText(
                                      t,
                                      movement.amount!,
                                      widget.unit,
                                    ),
                            ),
                          ),
                          Text(displayStamp(context, ref, movement.recordedAt)),
                          Text(t.stockStrengthValue(movement.strength.label)),
                          if (movement.enteredText != null)
                            Text(
                              t.stockEntered(
                                movement.enteredText!,
                                movement.enteredUnit!,
                              ),
                            ),
                          if (movement.reason != null) Text(movement.reason!),
                          if (movement.physicalCorrection != null)
                            Text(
                              movement.physicalCorrection ==
                                      PhysicalCorrection.reverseRecordedEffect
                                  ? t.stockReverseHelp
                                  : t.stockReviewedKeep,
                            ),
                        ],
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
