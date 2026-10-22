import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
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
  bool configure = false, expanded = false, editing = false;

  Future<void> _edit(DosePreset preset) async {
    if (editing ||
        !widget.enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final owner = widget.owner;
    final state = ref.read(dosePresetsProvider(owner));
    final controller = ref.read(dosePresetsProvider(owner).notifier);
    final authority = controller.authority;
    final store = ref.read(recordStoreProvider).value;
    if (store == null || !controller.actionCurrent(authority)) return;
    final units = widget.allowedUnits;
    editing = true;
    try {
      await showVitalDialog<void>(
        context: context,
        builder: (dialog) {
          final route = ModalRoute.of(dialog);
          bool current() =>
              mounted &&
              dialog.mounted &&
              widget.owner == owner &&
              route?.isCurrent != false &&
              controller.actionCurrent(authority) &&
              identical(ref.read(recordStoreProvider).value, store);
          return DosePresetEditDialog(
            initial: preset,
            allowedUnits: units,
            otherIdentities: {
              for (final value in state.values)
                if (value.identity != preset.identity) value.identity,
            },
            onSave: (next) => controller.replace(
              preset,
              next,
              allowedUnits: units,
              canCommit: current,
            ),
          );
        },
      );
    } finally {
      if (mounted) editing = false;
    }
  }

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
                              label: t.batch15T05PresetEditSemantic(
                                preset.text,
                                preset.unit,
                              ),
                              child: StitchButton(
                                key: ValueKey(
                                  'dose-preset-edit-${preset.identity}',
                                ),
                                quiet: true,
                                onPressed: editable
                                    ? () => _edit(preset)
                                    : null,
                                child: ExcludeSemantics(child: Text(t.edit)),
                              ),
                            ),
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

/// Edits one saved exact amount in place. The dialog owns only temporary text
/// and a failing write keeps the stored preset intact for an honest retry.
class DosePresetEditDialog extends ConsumerStatefulWidget {
  const DosePresetEditDialog({
    super.key,
    required this.initial,
    required this.allowedUnits,
    required this.otherIdentities,
    required this.onSave,
  });
  final DosePreset initial;
  final Set<String> allowedUnits, otherIdentities;
  final Future<bool> Function(DosePreset value) onSave;
  @override
  ConsumerState<DosePresetEditDialog> createState() =>
      _DosePresetEditDialogState();
}

class _DosePresetEditDialogState extends ConsumerState<DosePresetEditDialog> {
  late final _amount = TextEditingController(text: widget.initial.text);
  late final _unit = TextEditingController(text: widget.initial.unit);
  bool touched = false, saving = false, failed = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_changed);
    _unit.addListener(_changed);
  }

  @override
  void dispose() {
    _amount.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      touched = true;
      failed = false;
    });
  }

  String? _error(AppLocalizations t) {
    final unit = _unit.text.trim();
    if (!widget.allowedUnits.contains(unit)) {
      final units = widget.allowedUnits.toList()..sort();
      return t.batch15T05PresetUnitUnsupported(units.join(', '));
    }
    final DosePreset next;
    try {
      next = DosePreset(_amount.text, unit);
    } catch (_) {
      return t.batch15T05PresetAmountInvalid;
    }
    if (widget.otherIdentities.contains(next.identity)) {
      return t.batch15T05PresetDuplicate;
    }
    return null;
  }

  void _dismiss() {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final error = _error(t);
    if (error != null) {
      setState(() => touched = true);
      return;
    }
    if (saving) return;
    final next = DosePreset(_amount.text, _unit.text.trim());
    setState(() {
      touched = true;
      saving = true;
      failed = false;
    });
    bool saved;
    try {
      saved = await widget.onSave(next);
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    if (saved) {
      _dismiss();
    } else {
      setState(() {
        saving = false;
        failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final error = _error(t);
    ref.listen(appLockProvider.select((state) => state.locked), (_, locked) {
      if (locked) _dismiss();
    });
    ref.listen(recordStoreProvider, (previous, next) {
      if (previous != null && !identical(previous.value, next.value)) {
        _dismiss();
      }
    });
    final canSave = !saving && error == null;
    return VitalDialog(
      key: const ValueKey('dose-preset-edit-dialog'),
      title: Text(t.batch15T05PresetEditTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.batch15T05PresetEditHelp, style: StitchType.caption),
          const SizedBox(height: 12),
          Text(t.batch15T05PresetAmountLabel, style: StitchType.label),
          const SizedBox(height: 4),
          Semantics(
            label: t.batch15T05PresetAmountLabel,
            child: TextField(
              key: const ValueKey('dose-preset-edit-amount'),
              controller: _amount,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 12),
          Text(t.batch15T05PresetUnitLabel, style: StitchType.label),
          const SizedBox(height: 4),
          Semantics(
            label: t.batch15T05PresetUnitLabel,
            child: TextField(
              key: const ValueKey('dose-preset-edit-unit'),
              controller: _unit,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (touched && error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  key: const ValueKey('dose-preset-edit-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.destructive,
                  ),
                ),
              ),
            ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  t.featurePresetSaveFailed,
                  key: const ValueKey('dose-preset-edit-failed'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.destructive,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        StitchButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        StitchButton(
          key: const ValueKey('dose-preset-edit-save'),
          primary: true,
          onPressed: canSave ? _submit : null,
          child: Text(t.save),
        ),
      ],
    );
  }
}
