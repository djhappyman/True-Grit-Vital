import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:true_grit_vital/domain/reminders/reminders.dart';
import 'package:true_grit_vital/platform/reminders.dart';

const capabilities = ReminderCapabilities(
  supported: true,
  notificationPermission: true,
  appEnabled: true,
  channelEnabled: true,
  exactAlarm: true,
  protectedStorageAvailable: true,
  bootIdentityAvailable: true,
  fingerprint: 'test',
);

class HeldCapabilities implements ReminderGateway {
  final pending = Completer<ReminderCapabilities>();
  @override
  Future<ReminderCapabilities> capabilities() => pending.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Unlocked extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

class ReportController extends ReminderController {
  @override
  ReminderState build() => const ReminderState();
  void publish(ReminderRepairReport report) =>
      state = ReminderState(report: report);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'late matching capability read preserves the completed repair evidence',
    () async {
      final gateway = HeldCapabilities();
      final container = ProviderContainer(
        overrides: [
          remindersProvider.overrideWith(ReportController.new),
          reminderGatewayProvider.overrideWithValue(gateway),
          appLockProvider.overrideWith(Unlocked.new),
        ],
      );
      addTearDown(container.dispose);
      final controller =
          container.read(remindersProvider.notifier) as ReportController;
      await controller.refresh();
      controller.publish(
        ReminderRepairReport(
          capabilities: capabilities,
          projection: ReminderProjection(
            generation: 'g',
            namespace: 'ns',
            sequence: 1,
            desired: const [],
            obsoleteTokens: const [],
            complete: true,
            coverage: const [],
          ),
          convergence: ReminderConvergence.converged,
          revision: 1,
          passes: 2,
          epochRecovered: true,
        ),
      );
      gateway.pending.complete(capabilities);
      await Future<void>.delayed(Duration.zero);
      final report = container.read(remindersProvider).report;
      expect(report.convergence, ReminderConvergence.converged);
      expect(report.passes, 2);
      expect(report.epochRecovered, isTrue);
    },
  );
}
