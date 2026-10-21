import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import 'dose_presets.dart';

/// Shared selection controls fill the existing form. Saving a preset never
/// records a dose, picks a source or changes its labelled strength.
class DosePresetPanel extends ConsumerStatefulWidget {
  const DosePresetPanel({
    super.key,
    required this.owner,
    required this.amount,
    required this.unit,
    required this.allowedUnits,
    required this.enabled,
    required this.onSelected,
  });
  final DosePresetOwner owner;
  final String amount, unit;
  final Set<String> allowedUnits;
  final bool enabled;
  final ValueChanged<DosePreset> onSelected;
  @override
  ConsumerState<DosePresetPanel> createState() => _DosePresetPanelState();
}

class _DosePresetPanelState extends ConsumerState<DosePresetPanel> {
  bool configure = false, expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final state = ref.watch(dosePresetsProvider(widget.owner));
    final plans = ref.watch(dosePresetPlanProvider(widget.owner));
    final scheduled = plans.hasError || plans.isLoading
        ? const <DosePreset>[]
        : plans.value
                  ?.expand((saved) => scheduleDosePresets(saved.plan.timing))
                  .toList() ??
              const <DosePreset>[];
    final seen = <String>{};
    final choices = [
      for (final value in [...state.values, ...scheduled])
        if (widget.allowedUnits.contains(value.unit) &&
            seen.add(value.identity))
          value,
    ];
    DosePreset? entered;
    try {
      entered = DosePreset(widget.amount, widget.unit);
    } catch (_) {
      // Invalid/unfinished entry stays in the original field for its validator.
    }
    final editable =
        widget.enabled && !state.loading && !state.saving && !state.failed;
    final duplicate = state.values.any(
      (value) => value.identity == entered?.identity,
    );
    final full = state.values.length >= DosePresetController.limit;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(t.featurePresetHeading, style: StitchType.label),
              StitchButton(
                quiet: true,
                compact: true,
                onPressed: widget.enabled
                    ? () => setState(() => configure = !configure)
                    : null,
                child: Text(configure ? t.done : t.stitchConfigure),
              ),
            ],
          ),
          if (configure)
            Text(
              t.featurePresetHelp,
              style: StitchType.caption.copyWith(color: c.muted),
            ),
          if (state.loading || plans.isLoading)
            Text(t.loadingRecords, style: StitchType.caption),
          if (state.failed) ...[
            Text(
              state.readFailed
                  ? t.featurePresetLoadFailed
                  : t.featurePresetSaveFailed,
            ),
            StitchButton(
              quiet: true,
              onPressed: widget.enabled && !state.saving
                  ? () => ref.invalidate(dosePresetsProvider(widget.owner))
                  : null,
              child: Text(t.retry),
            ),
          ],
          if (plans.hasError) ...[
            Text(t.featurePresetPlanFailed),
            StitchButton(
              quiet: true,
              onPressed: () =>
                  ref.invalidate(dosePresetPlanProvider(widget.owner)),
              child: Text(t.retry),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in choices.take(expanded ? choices.length : 6))
                MergeSemantics(
                  child: Semantics(
                    selected: preset.identity == entered?.identity,
                    label: t.featurePresetSelect(preset.text, preset.unit),
                    child: StitchButton(
                      key: ValueKey('dose-preset-${preset.identity}'),
                      compact: true,
                      primary: preset.identity == entered?.identity,
                      onPressed: widget.enabled && !state.saving
                          ? () => widget.onSelected(preset)
                          : null,
                      child: ExcludeSemantics(
                        child: Text('${preset.text}\u00a0${preset.unit}'),
                      ),
                    ),
                  ),
                ),
              if (choices.length > 6)
                StitchButton(
                  quiet: true,
                  compact: true,
                  onPressed: () => setState(() => expanded = !expanded),
                  child: Text(expanded ? t.featurePresetLess : t.more),
                ),
            ],
          ),
          if (configure) ...[
            const SizedBox(height: 8),
            StitchSurface(
              inset: true,
              radius: VitalLayout.sectionRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.featurePresetManageHelp, style: StitchType.caption),
                  if (full) Text(t.featurePresetLimit),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StitchButton(
                      key: const ValueKey('dose-preset-add'),
                      icon: LucideIcons.plus,
                      onPressed:
                          editable && entered != null && !duplicate && !full
                          ? () => ref
                                .read(
                                  dosePresetsProvider(widget.owner).notifier,
                                )
                                .add(entered!)
                          : null,
                      child: Text(t.add),
                    ),
                  ),
                  for (final preset in state.values)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Text(
                            '${preset.text}\u00a0${preset.unit}',
                            style: StitchType.body,
                          ),
                          MergeSemantics(
                            child: Semantics(
                              label: t.featurePresetRemove(
                                preset.text,
                                preset.unit,
                              ),
                              child: StitchButton(
                                key: ValueKey(
                                  'dose-preset-remove-${preset.identity}',
                                ),
                                quiet: true,
                                onPressed: editable
                                    ? () => ref
                                          .read(
                                            dosePresetsProvider(widget.owner)
                                                .notifier,
                                          )
                                          .remove(preset)
                                    : null,
                                child: ExcludeSemantics(child: Text(t.remove)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
