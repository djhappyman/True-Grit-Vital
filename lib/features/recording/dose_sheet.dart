import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/stock/stored_stock.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_presenters.dart';
import '../stock/stock_providers.dart' show sameStockStrength, stockDecimal;
import '../stock/stock_widgets.dart' show stockAmountText;

/// The reference sheet geometry, composed on top of the shared Stitch surface.
///
/// The canonical route supplies modal geometry. The compatibility page uses
/// the same composition while retaining its draft, lock and Back behaviour.
class DoseSheet extends StatelessWidget implements VitalTaskContent {
  const DoseSheet({super.key, required this.children, this.taskFooter});
  final List<Widget> children;
  @override
  final Widget? taskFooter;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    if (VitalTaskScope.contains(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => StitchSurface(
        radius: VitalLayout.sheetRadius,
        padding: EdgeInsets.fromLTRB(
          constraints.maxWidth >= 600 ? 24 : 16,
          8,
          constraints.maxWidth >= 600 ? 24 : 16,
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: c.line.withValues(alpha: .8),
                  borderRadius: BorderRadius.circular(VitalLayout.pillRadius),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...children,
            ?taskFooter,
          ],
        ),
      ),
    );
  }
}

class DoseSheetHeader extends StatelessWidget {
  const DoseSheetHeader({
    super.key,
    required this.title,
    required this.timestamp,
    required this.editLabel,
    required this.onEdit,
  });
  final String title, timestamp, editLabel;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    final largeText = MediaQuery.textScalerOf(context).scale(20) > 30;
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: StitchType.heading.copyWith(color: c.ink),
            ),
          ),
        ),
      ],
    );
    final moment = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(LucideIcons.clock3, size: 15, color: c.muted),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            timestamp,
            style: StitchType.caption.copyWith(color: c.muted),
          ),
        ),
      ],
    );
    final edit = StitchButton(
      compact: true,
      icon: LucideIcons.pencil,
      onPressed: onEdit,
      child: Text(editLabel),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (largeText) ...[
          heading,
          const SizedBox(height: 6),
          moment,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: edit),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 2), moment],
                ),
              ),
              const SizedBox(width: 12),
              edit,
            ],
          ),
      ],
    );
  }
}

/// Complete product identity. No PRN badge: PRN belongs to a plan, not an item.
class DoseProductCard extends StatelessWidget {
  const DoseProductCard({
    super.key,
    required this.name,
    required this.subtitle,
  });
  final String name, subtitle;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return StitchSurface(
      inset: true,
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StitchIcon(LucideIcons.pill),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: StitchType.name.copyWith(color: c.ink)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: StitchType.caption.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DoseSectionHeading extends StatelessWidget {
  const DoseSectionHeading(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              label.toUpperCase(),
              style: StitchType.small.copyWith(
                color: c.muted,
                letterSpacing: .9,
              ),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// A missing capability stays explicit and never writes example data.
class DosePreviewPanel extends StatelessWidget {
  const DosePreviewPanel({
    super.key,
    required this.title,
    required this.description,
    this.action,
  });
  final String title, description;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return StitchSurface(
      inset: true,
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: DoseSectionHeading(title)),
              StitchBadge(AppLocalizations.of(context).screenRecordPreview),
            ],
          ),
          const SizedBox(height: 6),
          Text(description, style: StitchType.caption.copyWith(color: c.muted)),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

enum DoseStockBalanceState { known, unknown, limit, notCalculated }

final class DoseStockConsequence {
  const DoseStockConsequence({
    required this.state,
    this.deducted,
    this.remaining,
  });
  const DoseStockConsequence.notCalculated()
    : state = DoseStockBalanceState.notCalculated,
      deducted = null,
      remaining = null;
  final DoseStockBalanceState state;
  final ExactAmount? deducted, remaining;
}

/// The same conversion used by the stock command, evaluated without writing.
///
/// The returned deduction is in the container's own unit. A null deduction
/// means the entered quantity cannot be converted for this source.
DoseStockConsequence? doseStockConsequence({
  required String enteredText,
  required String enteredUnit,
  required StoredStockContainer container,
  StoredStockContainer? base,
  FixedReplacementAmount? keep,
}) {
  late final EnteredStockAmount entered;
  try {
    entered = EnteredStockAmount(stockDecimal(enteredText), enteredUnit);
  } catch (_) {
    return null;
  }
  ExactAmount? physical;
  if (base != null &&
      base.id != container.id &&
      !sameStockStrength(base.strength, container.strength)) {
    if (keep == null) return const DoseStockConsequence.notCalculated();
    final result = ReplacementAmounts.calculate(
      entered: entered,
      oldStrength: base.strength,
      newStrength: container.strength,
      keep: keep,
    );
    if (result == null) return const DoseStockConsequence.notCalculated();
    physical = switch (container.unit) {
      'mg' => result.milligrams,
      'ml' => result.millilitres,
      _ => null,
    };
  } else {
    physical = container.strength.equivalent(
      entered.value,
      from: enteredUnit,
      to: container.unit,
    );
  }
  if (physical == null) return const DoseStockConsequence.notCalculated();
  if (container.balance.limitReached) {
    return DoseStockConsequence(
      state: DoseStockBalanceState.limit,
      deducted: physical,
    );
  }
  final balance = container.balance.value;
  if (balance == null) {
    return DoseStockConsequence(
      state: DoseStockBalanceState.unknown,
      deducted: physical,
    );
  }
  return DoseStockConsequence(
    state: DoseStockBalanceState.known,
    deducted: physical,
    remaining: balance - physical,
  );
}

class DoseStockEffect extends StatelessWidget {
  const DoseStockEffect({
    super.key,
    required this.consequence,
    required this.container,
  });
  final DoseStockConsequence consequence;
  final StoredStockContainer container;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final deducted = consequence.deducted == null
        ? null
        : stockAmountText(t, consequence.deducted!, container.unit);
    final remaining = consequence.remaining == null
        ? null
        : stockAmountText(t, consequence.remaining!, container.unit);
    final low =
        consequence.state == DoseStockBalanceState.known &&
        consequence.remaining != null &&
        container.lowThreshold != null &&
        consequence.remaining! <= container.lowThreshold!;
    final deficit =
        consequence.remaining != null &&
        consequence.remaining! < ExactAmount.zero;
    final summary = switch (consequence.state) {
      DoseStockBalanceState.limit => t.screenRecordStockLimitPreview,
      DoseStockBalanceState.unknown => t.screenRecordStockUnknownDeduction(
        deducted ?? '',
      ),
      DoseStockBalanceState.notCalculated => t.screenRecordStockNotCalculated,
      DoseStockBalanceState.known => t.screenRecordStockDeducts(
        deducted ?? '',
        remaining ?? '',
      ),
    };
    final warning = low || deficit;
    return StitchSurface(
      inset: true,
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (warning ? c.amber : c.accent).withValues(alpha: .14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              warning ? LucideIcons.triangleAlert : LucideIcons.box,
              size: 18,
              color: warning ? c.amber : c.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary, style: StitchType.label.copyWith(color: c.ink)),
                if (low && container.lowThreshold != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      t.screenRecordStockLow(
                        stockAmountText(
                          t,
                          container.lowThreshold!,
                          container.unit,
                        ),
                      ),
                      style: StitchType.caption.copyWith(color: c.amber),
                    ),
                  ),
                if (deficit)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      t.screenRecordStockDeficitPreview,
                      style: StitchType.caption.copyWith(color: c.amber),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
