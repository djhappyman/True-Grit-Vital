import 'package:flutter/services.dart' show TextCapitalization, TextInputAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../domain/scheduling/daily_plan.dart' show CivilDate;
import '../../domain/history/display_time.dart' show DisplayTime;
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';

final _civilDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Parses an exact History date, rejecting malformed, impossible and
/// out-of-range values instead of normalising them to another day.
CivilDate? parseHistoryJumpDate(String value) {
  final text = value.trim();
  if (!_civilDatePattern.hasMatch(text)) return null;
  try {
    final date = CivilDate.parse(text);
    // History filters require an exclusive next-day bound in the civil range.
    date.addDays(1);
    return date;
  } catch (_) {
    return null;
  }
}

/// Opens the short exact-date dialog. The calendar only changes when the
/// person confirms a valid date; Cancel, Escape and Back return no date.
Future<CivilDate?> showHistoryDateJump(
  BuildContext context, {
  required String zone,
  CivilDate? initialDate,
}) => showVitalDialog<CivilDate>(
  context: context,
  builder: (_) => HistoryDateJumpDialog(zone: zone, initialDate: initialDate),
);

/// Compact calendar command that opens the exact-date dialog in History.
class HistoryDateJumpButton extends ConsumerStatefulWidget {
  const HistoryDateJumpButton({
    super.key,
    required this.zone,
    required this.selected,
    required this.onSelected,
  });

  final String zone;
  final CivilDate? selected;
  final ValueChanged<CivilDate> onSelected;

  @override
  ConsumerState<HistoryDateJumpButton> createState() =>
      _HistoryDateJumpButtonState();
}

class _HistoryDateJumpButtonState extends ConsumerState<HistoryDateJumpButton> {
  final focus = FocusNode(debugLabel: 'history-date-jump');
  bool opening = false;

  Future<void> open() async {
    if (opening || ref.read(appLockProvider).locked) return;
    opening = true;
    final zone = widget.zone;
    final CivilDate? date;
    try {
      date = await showHistoryDateJump(
        context,
        zone: zone,
        initialDate: widget.selected,
      );
    } finally {
      opening = false;
    }
    if (!mounted || ref.read(appLockProvider).locked) return;
    focus.requestFocus();
    if (widget.zone != zone) return;
    if (date != null) widget.onSelected(date);
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Semantics(
      key: const ValueKey('history-date-jump'),
      button: true,
      label: t.historyDateJump,
      onTap: open,
      excludeSemantics: true,
      child: StitchButton(
        quiet: true,
        compact: true,
        icon: LucideIcons.calendarDays,
        focusNode: focus,
        onPressed: open,
        child: Text(t.historyDateJumpCommand),
      ),
    );
  }
}

/// Short dialog with a persistently labelled exact-date field.
class HistoryDateJumpDialog extends ConsumerStatefulWidget {
  const HistoryDateJumpDialog({
    super.key,
    required this.zone,
    this.initialDate,
  });

  final String zone;
  final CivilDate? initialDate;

  @override
  ConsumerState<HistoryDateJumpDialog> createState() =>
      _HistoryDateJumpDialogState();
}

class _HistoryDateJumpDialogState extends ConsumerState<HistoryDateJumpDialog> {
  late final controller = TextEditingController(
    text: widget.initialDate?.toString() ?? '',
  );
  final focus = FocusNode(debugLabel: 'history-date-jump-field');
  String? error;

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  void submit() {
    if (ref.read(appLockProvider).locked) {
      Navigator.of(context).pop();
      return;
    }
    final date = parseHistoryJumpDate(controller.text);
    if (date == null) {
      setState(() => error = AppLocalizations.of(context).historyDateJumpError);
      focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(date);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final muted = Theme.of(context).colorScheme.mutedForeground;
    final entered = parseHistoryJumpDate(controller.text);
    final effectiveZone = entered == null
        ? widget.zone
        : DisplayTime().dayBounds(entered, widget.zone).zoneId;
    // A privacy lock covers or removes the dialog before its date can be
    // confirmed. The dialog returns no date, so nothing changes underneath.
    ref.listen(appLockProvider.select((state) => state.locked), (_, locked) {
      if (locked && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      }
    });
    return VitalDialog(
      key: const ValueKey('history-date-jump-dialog'),
      leading: const Icon(LucideIcons.calendarDays),
      title: Text(t.historyDateJump),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.historyDateJumpLabel, style: VitalType.label),
          const SizedBox(height: 8),
          Semantics(
            label: t.historyDateJumpLabel,
            child: TextField(
              key: const ValueKey('history-date-jump-field'),
              controller: controller,
              focusNode: focus,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                setState(() => error = null);
              },
              onSubmitted: (_) => submit(),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.destructive,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            t.historyDateJumpHelp(effectiveZone),
            style: VitalType.metadata.copyWith(color: muted),
          ),
        ],
      ),
      actions: [
        VitalButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        VitalButton(onPressed: submit, child: Text(t.historyDateJumpAction)),
      ],
    );
  }
}
