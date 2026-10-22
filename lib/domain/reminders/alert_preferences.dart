import 'dart:convert';

/// Optional sound and vibration for reminder notifications.
///
/// Both default to on, matching the legacy notification channel that existed
/// before these choices were exposed. A platform adapter maps the choice to its
/// own channel identity; this value never claims the system will honour it.
final class ReminderAlertPreferences {
  const ReminderAlertPreferences({this.sound = true, this.vibration = true});

  /// The original channel behaviour: system sound and vibration.
  static const legacy = ReminderAlertPreferences();

  final bool sound, vibration;

  bool get isLegacy => sound && vibration;

  ReminderAlertPreferences copyWith({bool? sound, bool? vibration}) =>
      ReminderAlertPreferences(
        sound: sound ?? this.sound,
        vibration: vibration ?? this.vibration,
      );

  Map<String, Object?> toMap() => {'sound': sound, 'vibration': vibration};

  String encode() => jsonEncode(toMap());

  /// Reads the closed settings record. An absent key keeps the legacy default;
  /// a present key must be a boolean, so a damaged record is not silently
  /// replaced with a choice the person did not make.
  static ReminderAlertPreferences decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('reminder_alerts');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('reminder_alerts');
    }
    final data = decoded;
    bool read(String key) {
      final value = data[key];
      if (value == null) return true;
      if (value is! bool) throw const FormatException('reminder_alerts');
      return value;
    }

    return ReminderAlertPreferences(
      sound: read('sound'),
      vibration: read('vibration'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderAlertPreferences &&
      other.sound == sound &&
      other.vibration == vibration;

  @override
  int get hashCode => Object.hash(sound, vibration);

  @override
  String toString() =>
      'ReminderAlertPreferences(sound: $sound, vibration: $vibration)';
}
