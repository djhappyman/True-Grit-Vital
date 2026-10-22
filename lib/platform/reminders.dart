import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/reminders/alert_preferences.dart';
import '../domain/reminders/reminders.dart';
export '../domain/reminders/alert_preferences.dart'
    show ReminderAlertPreferences;
export '../domain/reminders/reminders.dart' show ReminderClockSample;

enum ReminderNativeClock { wall, elapsed }

enum NativeReminderPurpose { ordinary, eventEnd, stockLow }

enum NativeReminderState {
  accepted,
  consumed,
  cancelled,
  postUncertain,
  failed,
  unknown,
}

enum NativeReminderActionKind { open, taken, snooze, skip }

final class ReminderCapabilities {
  const ReminderCapabilities({
    required this.supported,
    required this.notificationPermission,
    required this.appEnabled,
    required this.channelEnabled,
    required this.exactAlarm,
    required this.protectedStorageAvailable,
    required this.bootIdentityAvailable,
    required this.fingerprint,
    this.alertChoicesAvailable = false,
    this.repairReason,
    this.installedEpoch,
  });
  final bool supported,
      notificationPermission,
      appEnabled,
      channelEnabled,
      exactAlarm;
  final bool protectedStorageAvailable, bootIdentityAvailable;

  /// Whether this host can apply a sound/vibration choice to a real
  /// notification channel. False on hosts without that contract.
  final bool alertChoicesAvailable;
  final String fingerprint;
  final String? repairReason;

  /// The epoch the adapter currently holds, when it can report one. A dataset
  /// replacement (restore) changes the durable namespace, so the reconciler
  /// must hand the old epoch over explicitly instead of being rejected.
  final String? installedEpoch;
  factory ReminderCapabilities.fromMap(Map<Object?, Object?> map) =>
      ReminderCapabilities(
        supported: map['supported'] == true,
        notificationPermission: map['notificationPermission'] == true,
        appEnabled: map['appEnabled'] == true,
        channelEnabled: map['channelEnabled'] == true,
        exactAlarm: map['exactAlarm'] == true,
        protectedStorageAvailable: map['protectedStorageAvailable'] == true,
        bootIdentityAvailable: map['bootIdentityAvailable'] == true,
        alertChoicesAvailable: map['alertChoicesAvailable'] == true,
        fingerprint: map['fingerprint'] as String? ?? 'unsupported',
        repairReason: map['repairReason'] as String?,
        installedEpoch: map['installedEpoch'] as String?,
      );
}

final class NativeReminderRequest {
  const NativeReminderRequest({
    required this.epoch,
    required this.requestToken,
    required this.takenToken,
    required this.snoozeToken,
    required this.skipToken,
    required this.clock,
    required this.deadlineMilliseconds,
    this.bootId,
    this.purpose = NativeReminderPurpose.ordinary,
  });
  final NativeReminderPurpose purpose;
  final String epoch, requestToken, takenToken, snoozeToken, skipToken;
  final ReminderNativeClock clock;
  final int deadlineMilliseconds;
  final String? bootId;
  Map<String, Object?> toMap() => {
    'epoch': epoch,
    'purpose': purpose.name,
    'requestToken': requestToken,
    'takenToken': takenToken,
    'snoozeToken': snoozeToken,
    'skipToken': skipToken,
    'clock': clock.name,
    'deadlineMilliseconds': deadlineMilliseconds,
    'bootId': bootId,
  };
}

final class NativeReminderReceipt {
  const NativeReminderReceipt({
    required this.requestToken,
    required this.state,
    this.reason,
    this.pendingIntentPresent,
    this.notificationVisible,
  });
  final String requestToken;
  final NativeReminderState state;
  final String? reason;
  final bool? pendingIntentPresent, notificationVisible;
  factory NativeReminderReceipt.fromMap(Map<Object?, Object?> map) =>
      NativeReminderReceipt(
        requestToken: map['requestToken']! as String,
        state: NativeReminderState.values.byName(map['state']! as String),
        reason: map['reason'] as String?,
        pendingIntentPresent: map['pendingIntentPresent'] as bool?,
        notificationVisible: map['notificationVisible'] as bool?,
      );
}

final class NativeReminderSnapshot {
  const NativeReminderSnapshot({
    required this.accepted,
    required this.epoch,
    required this.sequence,
    required this.receipts,
    required this.fingerprint,
    this.reason,
  });
  final bool accepted;
  final String? epoch, reason;
  final int sequence;
  final List<NativeReminderReceipt> receipts;
  final String fingerprint;
}

final class NativeReminderAction {
  const NativeReminderAction({
    required this.envelopeId,
    required this.epoch,
    required this.requestToken,
    required this.actionToken,
    required this.action,
  });
  final String envelopeId, epoch, requestToken, actionToken;
  final NativeReminderActionKind action;
  factory NativeReminderAction.fromMap(Map<Object?, Object?> map) =>
      NativeReminderAction(
        envelopeId: map['envelopeId']! as String,
        epoch: map['epoch']! as String,
        requestToken: map['requestToken']! as String,
        actionToken: map['actionToken']! as String,
        action: NativeReminderActionKind.values.byName(
          map['action']! as String,
        ),
      );
}

abstract interface class ReminderGateway {
  Future<ReminderCapabilities> capabilities();
  Future<ReminderClockSample> sampleClock();
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  });
  Future<List<NativeReminderReceipt>> inspect(List<String> tokens);
  Future<List<NativeReminderReceipt>> cancel(List<String> tokens);
  Future<bool> invalidateEpoch({
    required String oldEpoch,
    required String newEpoch,
  });
  Future<NativeReminderAction?> getInitialAction();
  Future<void> acknowledgeAction(String envelopeId);
  Future<bool> requestNotifications();
  Future<bool> openExactAlarmSettings();
  Future<bool> openNotificationSettings();
  Stream<void> get changes;
}

/// Applies a persisted sound/vibration choice to the platform's real
/// notification channel contract. A false result is an unapplied choice, not a
/// claim that the system will deliver or honour an effect.
abstract interface class ReminderAlertGateway {
  Future<bool> applyAlertPreferences(ReminderAlertPreferences preferences);
}

final class AndroidReminders implements ReminderGateway, ReminderAlertGateway {
  const AndroidReminders();
  static const channel = MethodChannel('true_grit_vital/reminders');
  static const events = EventChannel('true_grit_vital/reminder_changes');
  Future<T?> _call<T>(String method, [Object? arguments]) => channel
      .invokeMethod<T>(method, arguments)
      .timeout(const Duration(seconds: 5));
  @override
  Future<ReminderCapabilities> capabilities() async =>
      ReminderCapabilities.fromMap(
        (await _call<Map<Object?, Object?>>('capabilities'))!,
      );
  @override
  Future<ReminderClockSample> sampleClock() async {
    final map = (await _call<Map<Object?, Object?>>('sampleClock'))!;
    return ReminderClockSample(
      utcMilliseconds: map['utcMilliseconds']! as int,
      elapsedMilliseconds: map['elapsedMilliseconds']! as int,
      bootId: map['bootId']! as String,
    );
  }

  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async {
    final map = (await _call<Map<Object?, Object?>>('applySnapshot', {
      'epoch': epoch,
      'sequence': sequence,
      'desired': desired.map((r) => r.toMap()).toList(),
      'obsoleteTokens': obsoleteTokens,
    }))!;
    return NativeReminderSnapshot(
      accepted: map['accepted'] == true,
      epoch: map['epoch'] as String?,
      sequence: map['sequence']! as int,
      fingerprint: map['fingerprint']! as String,
      reason: map['reason'] as String?,
      receipts: _receipts(map['receipts']),
    );
  }

  static List<NativeReminderReceipt> _receipts(Object? value) =>
      (value! as List<Object?>)
          .map(
            (e) => NativeReminderReceipt.fromMap(e! as Map<Object?, Object?>),
          )
          .toList(growable: false);
  @override
  Future<List<NativeReminderReceipt>> inspect(List<String> tokens) async =>
      _receipts(await _call<Object?>('inspect', {'tokens': tokens}));
  @override
  Future<List<NativeReminderReceipt>> cancel(List<String> tokens) async =>
      _receipts(await _call<Object?>('cancel', {'tokens': tokens}));
  @override
  Future<bool> invalidateEpoch({
    required String oldEpoch,
    required String newEpoch,
  }) async =>
      await _call<bool>('invalidateEpoch', {
        'oldEpoch': oldEpoch,
        'newEpoch': newEpoch,
      }) ??
      false;
  @override
  Future<NativeReminderAction?> getInitialAction() async {
    final map = await _call<Map<Object?, Object?>>('getInitialAction');
    return map == null ? null : NativeReminderAction.fromMap(map);
  }

  @override
  Future<void> acknowledgeAction(String envelopeId) =>
      _call<void>('acknowledgeAction', {'envelopeId': envelopeId});
  @override
  Future<bool> requestNotifications() async =>
      await _call<bool>('requestNotifications') ?? false;
  @override
  Future<bool> openExactAlarmSettings() async =>
      await _call<bool>('openExactAlarmSettings') ?? false;
  @override
  Future<bool> openNotificationSettings() async =>
      await _call<bool>('openNotificationSettings') ?? false;
  @override
  Future<bool> applyAlertPreferences(
    ReminderAlertPreferences preferences,
  ) async =>
      await _call<bool>('applyAlertPreferences', {
        'sound': preferences.sound,
        'vibration': preferences.vibration,
      }) ??
      false;
  @override
  Stream<void> get changes => events.receiveBroadcastStream().map((_) {});
}

/// Desktop reminder delivery has no admitted adapter. Basic recording stays usable.
final class UnsupportedReminders
    implements ReminderGateway, ReminderAlertGateway {
  const UnsupportedReminders();
  @override
  Future<ReminderCapabilities> capabilities() async =>
      const ReminderCapabilities(
        supported: false,
        notificationPermission: false,
        appEnabled: false,
        channelEnabled: false,
        exactAlarm: false,
        protectedStorageAvailable: false,
        bootIdentityAvailable: false,
        fingerprint: 'unsupported',
        repairReason: 'unsupported',
      );
  @override
  Future<ReminderClockSample> sampleClock() =>
      Future.error(UnsupportedError('reminders'));
  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async => NativeReminderSnapshot(
    accepted: false,
    epoch: epoch,
    sequence: sequence,
    receipts: [
      for (final r in desired)
        NativeReminderReceipt(
          requestToken: r.requestToken,
          state: NativeReminderState.failed,
          reason: 'unsupported',
        ),
    ],
    fingerprint: 'unsupported',
    reason: 'unsupported',
  );
  @override
  Future<List<NativeReminderReceipt>> inspect(List<String> tokens) async => [];
  @override
  Future<List<NativeReminderReceipt>> cancel(List<String> tokens) async => [];
  @override
  Future<bool> invalidateEpoch({
    required String oldEpoch,
    required String newEpoch,
  }) async => false;
  @override
  Future<NativeReminderAction?> getInitialAction() async => null;
  @override
  Future<void> acknowledgeAction(String envelopeId) async {}
  @override
  Future<bool> requestNotifications() async => false;
  @override
  Future<bool> openExactAlarmSettings() async => false;
  @override
  Future<bool> openNotificationSettings() async => false;
  @override
  Future<bool> applyAlertPreferences(
    ReminderAlertPreferences preferences,
  ) async => false;
  @override
  Stream<void> get changes => const Stream.empty();
}
