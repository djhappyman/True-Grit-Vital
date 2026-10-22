import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/reminders.dart';
import '../../app/settings_toggle_row.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart' show Heading;
import '../stock/stock_providers.dart';
import '../stock/stock_widgets.dart';
import 'reminder_pages.dart' show reminderStateLabel;

/// Default-off opt-in for native low/refill notices. It applies only to
/// containers already configured with a low threshold or refill notice; the
/// stored choice survives reopening and never creates a stock movement.
class StockAlertSettings extends ConsumerStatefulWidget {
  const StockAlertSettings({super.key});
  @override
  ConsumerState<StockAlertSettings> createState() => _StockAlertSettingsState();
}

class _StockAlertSettingsState extends ConsumerState<StockAlertSettings> {
  bool busy = false;
  String? error;
  ({String command, bool enabled, int revision})? pending;

  Future<void> save(bool enabled) async {
    if (busy) return;
    final saved = ref.read(stockAlertPreferenceProvider).value;
    if (saved == null) return;
    final action = pending ??= (
      command: newCommandId(),
      enabled: enabled,
      revision: saved.revision,
    );
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      await store.setStockAlerts(
        commandId: action.command,
        enabled: action.enabled,
        expectedRevision: action.revision,
      );
      pending = null;
      ref.invalidate(stockAlertPreferenceProvider);
      ref.read(remindersProvider.notifier).refresh();
    } catch (e) {
      if (e is CommandConflict) pending = null;
      if (mounted) {
        setState(
          () => error = e is CommandConflict
              ? AppLocalizations.of(context).conflictFailure
              : AppLocalizations.of(context).saveFailure,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final preference = ref.watch(stockAlertPreferenceProvider);
    final supported =
        ref.watch(remindersProvider).report.capabilities?.supported == true;
    final enabled = preference.value?.enabled == true;
    final projection = ref.watch(remindersProvider).report.projection;
    final notices = <String, StockNoticeReminder>{
      for (final notice in [
        ...?projection?.stockNotices,
        ...?projection?.stockNoticeAttention,
      ])
        notice.requestToken: notice,
    }.values.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsToggleRow(
          label: t.stockAlerts,
          description: supported ? t.stockAlertsHelp : t.reminderUnsupported,
          value: enabled,
          enabled: supported && !busy && preference.hasValue,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          onChanged: save,
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(error!)),
        ],
        if (enabled) ...[
          const SizedBox(height: 16),
          Heading(t.stockNotices),
          if (projection == null)
            Text(t.loadingRecords)
          else if (notices.isEmpty)
            Text(t.stockAlertNone)
          else
            for (final notice in notices) ...[
              const SizedBox(height: 12),
              Text(notice.itemName),
              Text(notice.label),
              Text(
                notice.condition == StockNoticeState.refill
                    ? t.stockRefillDue
                    : t.stockLow,
              ),
              if (notice.balance != null)
                Text(
                  t.stockBalance(
                    stockAmountText(t, notice.balance!, notice.unit),
                  ),
                ),
              Text(
                t.reminderRepairReason(
                  reminderStateLabel(t, notice.repairState),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: VitalButton.secondary(
                  onPressed: () => context.push(
                    '/stock/${Uri.encodeComponent(notice.personId)}'
                    '?item=${Uri.encodeQueryComponent(notice.itemId)}',
                  ),
                  child: Text(t.stockAlertOpen),
                ),
              ),
            ],
        ],
      ],
    );
  }
}
