import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/reminders.dart';

/// The live native reminder adapter. Unsupported hosts stay callable so the
/// reminder surfaces can report honest capability state.
final reminderGatewayProvider = Provider<ReminderGateway>(
  (ref) => Platform.isAndroid
      ? const AndroidReminders()
      : const UnsupportedReminders(),
);
