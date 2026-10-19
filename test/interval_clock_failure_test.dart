import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:true_grit_vital/features/plans/interval_clock.dart';
import 'package:true_grit_vital/platform/reminders.dart';

class UnavailableClock implements ReminderGateway {
  UnavailableClock(this.failure, {this.failCapabilities = false});
  final Object failure;
  final bool failCapabilities;
  @override
  Future<ReminderCapabilities> capabilities() async {
    if (failCapabilities) throw failure;
    return const ReminderCapabilities(
      supported: true,
      notificationPermission: true,
      appEnabled: true,
      channelEnabled: true,
      exactAlarm: true,
      protectedStorageAvailable: true,
      bootIdentityAvailable: true,
      fingerprint: 'synthetic',
    );
  }

  @override
  Future<ReminderClockSample> sampleClock() async => throw failure;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final failure in <Object>[
    PlatformException(code: 'clock_unavailable'),
    MissingPluginException(),
    TimeoutException('synthetic clock timeout'),
  ]) {
    for (final atCapabilities in [false, true]) {
      testWidgets(
        '${failure.runtimeType} at ${atCapabilities ? 'capabilities' : 'sample'} leaves record submission possible without clock readiness',
        (tester) async {
          late WidgetRef reference;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                reminderGatewayProvider.overrideWithValue(
                  UnavailableClock(failure, failCapabilities: atCapabilities),
                ),
              ],
              child: Consumer(
                builder: (context, ref, child) {
                  reference = ref;
                  return const SizedBox.shrink();
                },
              ),
            ),
          );
          // Null is the repository's explicit missing-clock path. A fabricated
          // sample would falsely advertise native readiness; throwing here
          // prevents the ordinary durable command from being submitted at all.
          expect(await captureIntervalClock(reference), isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
