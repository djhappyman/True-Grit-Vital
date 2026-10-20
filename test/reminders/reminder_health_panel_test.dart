import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/reminder_health.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart'
    show ReminderConvergence;
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/reminders/reminder_health_panel.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/platform/reminders.dart';

const _capabilities = ReminderCapabilities(
  supported: true,
  notificationPermission: true,
  appEnabled: true,
  channelEnabled: true,
  exactAlarm: true,
  protectedStorageAvailable: true,
  bootIdentityAvailable: true,
  fingerprint: 'test-adapter',
);

ReminderProjection _projection({
  required List<ReminderCoverage> coverage,
  bool complete = true,
  List<ReminderExclusion> exclusions = const [],
  List<DesiredReminder> attention = const [],
}) => ReminderProjection(
  generation: 'g1',
  namespace: 'ns1',
  sequence: 1,
  desired: const [],
  obsoleteTokens: const [],
  complete: complete,
  coverage: coverage,
  exclusions: exclusions,
  attention: attention,
);

ReminderCoverage _coverage(
  String scope, {
  bool complete = true,
  DateTime? through,
  String? reason,
}) => ReminderCoverage(
  scope: scope,
  generation: 'g1',
  basis: 'Europe/London',
  adapterFingerprint: 'test-adapter',
  checkedAt: DateTime.utc(2026, 10, 19, 8),
  complete: complete,
  preparedThrough: through,
  reason: reason,
);

Future<void> _pump(WidgetTester tester, ReminderHealthSummary summary) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reminderHealthProvider.overrideWithValue(summary),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReminderHealthPanel(
              scopeLabel: (scope) => switch (scope) {
                'everyone' => 'Everyone',
                _ => 'Person',
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ReminderHealthSummary _summary({
  ReminderCapabilities? capabilities = _capabilities,
  ReminderProjection? projection,
  ReminderConvergence convergence = ReminderConvergence.converged,
  bool failed = false,
  int pending = 0,
}) => summariseReminderHealth(
  capabilities: capabilities,
  projection: projection,
  convergence: convergence,
  failed: failed,
  pendingCancellations: pending,
);

void main() {
  testWidgets('prepared coverage is shown with its no-delivery qualifier', (
    tester,
  ) async {
    await _pump(
      tester,
      _summary(
        projection: _projection(
          coverage: [
            _coverage('everyone', through: DateTime.utc(2026, 10, 20, 9)),
          ],
        ),
      ),
    );
    expect(find.textContaining('Prepared through'), findsOneWidget);
    expect(find.textContaining('does not confirm delivery'), findsOneWidget);
    expect(find.text('Limits'), findsOneWidget);
    expect(find.textContaining('force stop'), findsOneWidget);
  });

  testWidgets('blocked storage says so and claims no coverage', (tester) async {
    await _pump(
      tester,
      _summary(
        capabilities: const ReminderCapabilities(
          supported: true,
          notificationPermission: true,
          appEnabled: true,
          channelEnabled: true,
          exactAlarm: true,
          protectedStorageAvailable: false,
          bootIdentityAvailable: true,
          fingerprint: 'test-adapter',
        ),
        projection: _projection(
          coverage: [
            _coverage('everyone', through: DateTime.utc(2026, 10, 20, 9)),
          ],
        ),
        convergence: ReminderConvergence.blocked,
      ),
    );
    expect(
      find.textContaining('Protected storage is unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Prepared through'), findsNothing);
  });

  testWidgets('capacity shows the exact displaced count for the scope', (
    tester,
  ) async {
    await _pump(
      tester,
      _summary(
        projection: _projection(
          coverage: [_coverage('plan:p2', complete: false)],
          complete: false,
          exclusions: const [
            ReminderExclusion(scope: 'plan:p2', reason: 'capacity', count: 4),
          ],
        ),
        convergence: ReminderConvergence.deferred,
      ),
    );
    expect(find.textContaining('Preparation limit reached'), findsOneWidget);
    expect(find.textContaining('Entries outside coverage: 4.'), findsOneWidget);
  });

  testWidgets('an interrupted alert is announced instead of prepared-through', (
    tester,
  ) async {
    final row = DailyRow(
      generation: 'g1',
      personRevision: 1,
      planRevision: 1,
      personName: 'Ada',
      itemName: 'Synthetic',
      revision: 0,
      expectation: DailyExpectation(
        identity: DailyIdentity(
          personId: 'ada',
          planId: 'p1',
          originalDate: CivilDate(2026, 10, 19),
          slotId: 'am',
        ),
        itemId: 'i1',
        versionId: 'v1',
        zoneId: 'Europe/London',
        amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        resolution: DailyResolution.exact,
        calculatorVersion: 'daily-v1',
        timezoneDataVersion: '2026',
        originalTime: WallTime(9, 0),
        effectiveTime: WallTime(9, 0),
        instant: DateTime.utc(2026, 10, 19, 9),
        clockCandidates: [DateTime.utc(2026, 10, 19, 9)],
      ),
      actions: const [],
      takenCount: 0,
      skippedCount: 0,
    );
    final interrupted = DesiredReminder(
      requestToken: 'r1',
      takenToken: 't1',
      snoozeToken: 's1',
      skipToken: 'k1',
      generation: 'g1',
      namespace: 'ns1',
      target: ReminderTarget(row: row, snoozeRevision: 0),
      kind: ReminderKind.snooze,
      trigger: ReminderTrigger.elapsed,
      deadlineMilliseconds: 4500000,
      intentRevision: 1,
      repairState: ReminderRepairState.interrupted,
      sample: const ReminderClockSample(
        utcMilliseconds: 1792400400000,
        elapsedMilliseconds: 3600000,
        bootId: 'b1',
      ),
      delayMinutes: 15,
    );
    await _pump(
      tester,
      _summary(
        projection: _projection(
          coverage: [
            _coverage('everyone', through: DateTime.utc(2026, 10, 20, 9)),
          ],
          attention: [interrupted],
        ),
      ),
    );
    expect(find.text('Reminders need attention'), findsOneWidget);
    expect(find.textContaining('Prepared through'), findsNothing);
  });
}
