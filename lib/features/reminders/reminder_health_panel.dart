import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/display_preferences.dart';
import '../../app/reminder_health.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart' show Heading;

/// Reusable reminder health and limit disclosure.
///
/// T08 and the lead embed this in Settings/Help instead of building a second
/// reminder-health surface. Every claim comes from [reminderHealthProvider];
/// this widget adds no behaviour and no reminder engine.
class ReminderHealthPanel extends ConsumerWidget {
  const ReminderHealthPanel({
    super.key,
    this.scopeLabel,
    this.showLimits = true,
    this.showBlockers = true,
  });

  /// Resolves plan/person/event scope identifiers to authored labels.
  final String Function(String scope)? scopeLabel;
  final bool showLimits;
  final bool showBlockers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final health = ref.watch(reminderHealthProvider);
    final label = scopeLabel ?? (scope) => _fallbackLabel(t, scope);
    String scopeText(String scope) => label(scope);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final blocker
            in showBlockers ? health.blockers : const <ReminderBlocker>[]) ...[
          const SizedBox(height: 8),
          Text(_blockerText(t, blocker)),
          if (blocker == ReminderBlocker.notificationPermission ||
              blocker == ReminderBlocker.appDisabled ||
              blocker == ReminderBlocker.channelDisabled ||
              blocker == ReminderBlocker.exactAlarm)
            Text(t.reminderBlocked),
        ],
        if (health.scopes.isEmpty && health.blockers.isEmpty)
          Text(t.reminderUnprepared(t.reminders)),
        if (health.capacity.deferred > 0) ...[
          const SizedBox(height: 12),
          // Per-plan capacity rows stay in the plan view, so the combined
          // health surface states the displaced total once.
          Text(t.reminderStateCapacity),
          Text(t.reminderExcludedCount(health.capacity.deferred)),
        ],
        for (final scope in health.scopes.where(
          (s) => !s.scope.startsWith('plan:'),
        )) ...[
          const SizedBox(height: 12),
          if (scope.state == ReminderScopeState.blocked)
            Text(t.reminderUnprepared(scopeText(scope.scope)))
          else if (scope.state == ReminderScopeState.attention)
            Semantics(liveRegion: true, child: Text(t.reminderAttention))
          else if (scope.deferred > 0) ...[
            Text(t.reminderStateCapacity),
            Text(t.reminderExcludedCount(scope.deferred)),
          ] else if (scope.preparedThrough == null)
            Text(t.reminderUnprepared(scopeText(scope.scope)))
          else
            Text(
              t.reminderCoverage(
                displayStamp(context, ref, scope.preparedThrough!),
                scopeText(scope.scope),
              ),
            ),
          if (scope.state == ReminderScopeState.attention ||
              scope.state == ReminderScopeState.partial)
            Text(t.reminderIncomplete),
          if (scope.checkedAt != null)
            Text(
              t.reminderChecked(displayStamp(context, ref, scope.checkedAt!)),
            ),
          if (scope.basis != null)
            Text(
              t.planObserved(
                scope.basis == 'observed_zone_unavailable'
                    ? t.planZoneUnknown
                    : scope.basis!,
              ),
            ),
        ],
        if (health.pendingCancellations > 0 ||
            health.unconfirmedCancellations > 0) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(t.reminderIncomplete)),
        ],
        if (showLimits) ...[
          const SizedBox(height: 20),
          Heading(t.reminderLimits),
          Text(t.reminderLimitsBody),
          const SizedBox(height: 8),
          Text(t.reminderHelp),
        ],
      ],
    );
  }

  static String _fallbackLabel(AppLocalizations t, String scope) {
    if (scope == 'everyone') return t.reminders;
    if (scope.startsWith('event:')) return t.events;
    if (scope.startsWith('person:')) return t.reminders;
    if (scope.startsWith('plan:')) return t.substances;
    return t.schedule;
  }

  static String _blockerText(AppLocalizations t, ReminderBlocker blocker) =>
      switch (blocker) {
        ReminderBlocker.unsupportedHost => t.reminderUnsupported,
        ReminderBlocker.protectedStorage => t.reminderProtected,
        ReminderBlocker.notificationPermission => t.reminderPermission,
        ReminderBlocker.appDisabled => t.reminderBlocked,
        ReminderBlocker.channelDisabled => t.reminderBlocked,
        ReminderBlocker.exactAlarm => t.reminderExact,
        ReminderBlocker.bootIdentity => t.reminderClock,
      };
}
