import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:true_grit_vital/platform/reminders.dart';

// Run only inside the snapshot-protected emulator harness, separately from the
// full app fixture. This synthetic epoch must never activate over a live journal.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('owned Android alarms, receipts, cancellation and durable fences', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
    );
    await tester.runAsync(() async {
      const adapter = AndroidReminders();
      String opaque() => List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final epoch = opaque();
      final clock = await adapter.sampleClock();
      final capabilities = await adapter.capabilities();
      expect(capabilities.supported, true);
      expect(capabilities.protectedStorageAvailable, true);
      expect(capabilities.bootIdentityAvailable, true);
      expect(
        capabilities.notificationPermission,
        true,
        reason: 'Harness must explicitly grant notification permission inside its AVD snapshot.',
      );
      expect(
        capabilities.exactAlarm,
        true,
        reason: 'Harness must explicitly grant exact alarm access inside its AVD snapshot.',
      );
      expect(capabilities.appEnabled && capabilities.channelEnabled, true);
      NativeReminderRequest request(ReminderNativeClock basis, int deadline) =>
          NativeReminderRequest(
            epoch: epoch,
            requestToken: opaque(),
            takenToken: opaque(),
            snoozeToken: opaque(),
            skipToken: opaque(),
            clock: basis,
            deadlineMilliseconds: deadline,
            bootId: basis == ReminderNativeClock.elapsed ? clock.bootId : null,
          );
      final ordinary = request(
        ReminderNativeClock.wall,
        clock.utcMilliseconds + 8000,
      );
      final snooze = request(
        ReminderNativeClock.elapsed,
        clock.elapsedMilliseconds + 14000,
      );
      final future = request(
        ReminderNativeClock.wall,
        clock.utcMilliseconds + 120000,
      );
      final desired = [ordinary, snooze, future];
      final first = await adapter.applySnapshot(
        epoch: epoch,
        sequence: 1,
        desired: desired,
        obsoleteTokens: [],
      );
      expect(
        first.accepted,
        true,
        reason: 'This fixture requires the pre-reminder baseline journal, restored by the harness.',
      );
      expect(
        first.receipts.map((r) => r.state),
        everyElement(NativeReminderState.accepted),
      );
      final observed = await adapter.inspect(
        desired.map((r) => r.requestToken).toList(),
      );
      expect(observed.map((r) => r.pendingIntentPresent), everyElement(true));
      expect(observed.map((r) => r.notificationVisible), everyElement(false));
      debugPrint('VITAL_REMINDER_STEP:registered');
      final deadline = DateTime.now().add(const Duration(seconds: 75));
      List<NativeReminderReceipt> fired = [];
      while (DateTime.now().isBefore(deadline)) {
        fired = await adapter.inspect([
          ordinary.requestToken,
          snooze.requestToken,
        ]);
        if (fired.every((r) => r.state == NativeReminderState.consumed)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(
        fired.map((r) => r.state),
        everyElement(NativeReminderState.consumed),
      );
      expect(fired.map((r) => r.notificationVisible), everyElement(true));
      debugPrint('VITAL_REMINDER_STEP:generic-fired');
      debugPrint(
        'VITAL_REMINDER_ACTION:${jsonEncode({'epoch': epoch, 'requestToken': ordinary.requestToken, 'actionToken': ordinary.snoozeToken, 'action': 'snooze'})}',
      );
      NativeReminderAction? action;
      final actionDeadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(actionDeadline)) {
        action = await adapter.getInitialAction();
        if (action != null) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(action?.epoch, epoch);
      expect(action?.requestToken, ordinary.requestToken);
      expect(action?.actionToken, ordinary.snoozeToken);
      expect(action?.action, NativeReminderActionKind.snooze);
      expect(
        (await adapter.getInitialAction())?.envelopeId,
        action?.envelopeId,
      );
      await adapter.acknowledgeAction(action!.envelopeId);
      expect(await adapter.getInitialAction(), null);
      debugPrint('VITAL_REMINDER_STEP:action-acknowledged');
      // Dismiss the cards with the adapter, then replay the identical desired
      // snapshot: durable consumption must survive dismissal and prevent rearm.
      await adapter.cancel([ordinary.requestToken, snooze.requestToken]);
      final replay = await adapter.applySnapshot(
        epoch: epoch,
        sequence: 1,
        desired: desired,
        obsoleteTokens: [],
      );
      expect(
        replay.receipts
            .where((r) => r.requestToken != future.requestToken)
            .map((r) => r.state),
        everyElement(NativeReminderState.consumed),
      );
      final dismissed = await adapter.inspect([
        ordinary.requestToken,
        snooze.requestToken,
      ]);
      expect(dismissed.map((r) => r.notificationVisible), everyElement(false));
      expect(dismissed.map((r) => r.pendingIntentPresent), everyElement(false));
      final cancelled = await adapter.applySnapshot(
        epoch: epoch,
        sequence: 2,
        desired: [],
        obsoleteTokens: desired.map((r) => r.requestToken).toList(),
      );
      expect(cancelled.accepted, true);
      expect(
        (await adapter.inspect([future.requestToken])).single.state,
        NativeReminderState.cancelled,
      );
      expect(
        (await adapter.applySnapshot(
          epoch: epoch,
          sequence: 1,
          desired: desired,
          obsoleteTokens: [],
        )).accepted,
        false,
      );
      final next = opaque();
      expect(
        await adapter.invalidateEpoch(oldEpoch: epoch, newEpoch: next),
        true,
      );
      expect(
        await adapter.invalidateEpoch(oldEpoch: epoch, newEpoch: next),
        true,
      );
      expect(
        await adapter.invalidateEpoch(oldEpoch: next, newEpoch: epoch),
        false,
      );
      expect(
        (await adapter.applySnapshot(
          epoch: epoch,
          sequence: 99,
          desired: desired,
          obsoleteTokens: [],
        )).accepted,
        false,
      );
      debugPrint('VITAL_REMINDER_STEP:cancelled-and-fenced');
    });
  });
}
