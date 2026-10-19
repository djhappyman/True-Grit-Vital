import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/reminders.dart';
import '../../domain/reminders/reminders.dart';

/// Unsupported native alerts do not prevent durable substance records.
Future<ReminderClockSample?> captureIntervalClock(WidgetRef ref) async {
  final gateway = ref.read(reminderGatewayProvider);
  try {
    if (!(await gateway.capabilities()).supported) return null;
    return await gateway.sampleClock();
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  } on TimeoutException {
    return null;
  }
}

String encodeIntervalClock(ReminderClockSample? sample) => sample == null
    ? ''
    : jsonEncode({
        'utc': sample.utcMilliseconds,
        'elapsed': sample.elapsedMilliseconds,
        'boot': sample.bootId,
      });
ReminderClockSample? decodeIntervalClock(String? value) {
  if (value == null || value.isEmpty) return null;
  final map = jsonDecode(value) as Map<String, dynamic>;
  return ReminderClockSample(
    utcMilliseconds: map['utc'] as int,
    elapsedMilliseconds: map['elapsed'] as int,
    bootId: map['boot'] as String,
  );
}
