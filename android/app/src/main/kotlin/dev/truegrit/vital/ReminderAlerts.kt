package dev.truegrit.vital

/** Sound and vibration intent for reminder notifications. */
internal data class ReminderAlert(val sound: Boolean = true, val vibration: Boolean = true) {
    companion object { val LEGACY = ReminderAlert() }
    val legacy: Boolean get() = sound && vibration
}

/** The channel contract derived from one alert choice. */
internal data class ReminderChannelConfiguration(
    val sound: Boolean,
    val vibration: Boolean,
    val legacy: Boolean,
)

internal object ReminderChannels {
    /** The pre-existing channel id. Its OS-owned settings stay authoritative. */
    const val LEGACY_ID = "vital_reminders_v1"

    /** The legacy combination keeps the original id; other choices get a
     * stable, explicit variant so an existing channel is never mutated. */
    fun id(alert: ReminderAlert): String = when {
        alert.legacy -> LEGACY_ID
        else -> buildString {
            append(LEGACY_ID)
            append("_s")
            append(if (alert.sound) '1' else '0')
            append("v")
            append(if (alert.vibration) '1' else '0')
        }
    }

    fun configuration(alert: ReminderAlert) = ReminderChannelConfiguration(
        sound = alert.sound,
        vibration = alert.vibration,
        legacy = alert.legacy,
    )

    /** A channel that does not exist is unknown, never "known enabled". */
    fun enabled(importance: Int?): Boolean = importance != null && importance != 0
}

/** Closed, forward-compatible storage record for the opaque journal. */
internal object ReminderAlertCodec {
    fun encode(alert: ReminderAlert): Map<String, Boolean> = mapOf(
        "sound" to alert.sound,
        "vibration" to alert.vibration,
    )

    /** Missing keys keep the legacy default; only an explicit false disables. */
    fun decode(sound: Boolean?, vibration: Boolean?): ReminderAlert =
        ReminderAlert(sound = sound ?: true, vibration = vibration ?: true)
}
