package dev.truegrit.vital

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.UserManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** One process-wide executor serializes activity, receiver and journal effects. */
internal object ReminderRuntime {
    val executor = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "vital-reminders") }
    fun engine(context: Context) = ReminderEngine(EncryptedReminderJournal(context.applicationContext), AndroidReminderEffects(context.applicationContext))
}

internal class AndroidReminderEffects(private val context: Context) : ReminderEffects {
    companion object { const val CHANNEL = ReminderChannels.LEGACY_ID; const val ACTION = "dev.truegrit.vital.REMINDER" }
    private val alarms get() = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val notifications get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    override fun nowWall() = System.currentTimeMillis()
    override fun nowElapsed() = SystemClock.elapsedRealtime()
    override fun bootId(installation: String): String? = try {
        val count = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
        if (count < 0) null else "$installation-$count"
    } catch (_: Exception) { null }
    fun channel() = ensureChannel(ReminderAlert.LEGACY)
    private fun channelName(alert: ReminderAlert): Int = when {
        alert.legacy -> R.string.reminder_channel
        alert.sound -> R.string.reminder_channel_sound
        alert.vibration -> R.string.reminder_channel_vibration
        else -> R.string.reminder_channel_silent
    }
    /** Only creates the variant needed by this choice. Existing channels are
     * never edited or deleted, so OS-owned channel settings stay authoritative. */
    fun ensureChannel(alert: ReminderAlert) {
        if (Build.VERSION.SDK_INT >= 26) {
            val configuration = ReminderChannels.configuration(alert)
            val channel = NotificationChannel(ReminderChannels.id(alert), context.getString(channelName(alert)),
                NotificationManager.IMPORTANCE_DEFAULT)
            if (!configuration.legacy) {
                if (!configuration.sound) channel.setSound(null, null)
                channel.enableVibration(configuration.vibration)
            }
            notifications.createNotificationChannel(channel)
        }
    }
    fun permission(): Boolean = Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    fun exact(): Boolean = Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()
    fun appEnabled(): Boolean = notifications.areNotificationsEnabled()
    fun channelEnabled(alert: ReminderAlert): Boolean = Build.VERSION.SDK_INT < 26 ||
        ReminderChannels.enabled(notifications.getNotificationChannel(ReminderChannels.id(alert))?.importance)
    fun channelExists(alert: ReminderAlert): Boolean = Build.VERSION.SDK_INT < 26 ||
        notifications.getNotificationChannel(ReminderChannels.id(alert)) != null
    override fun alertChangeAllowed(current: ReminderAlert): Boolean =
        ReminderChannels.changeAllowed(appEnabled(),
            if (Build.VERSION.SDK_INT >= 26) notifications.getNotificationChannel(ReminderChannels.id(current))?.importance else null)
    fun protected(): Boolean = !context.isDeviceProtectedStorage && (context.getSystemService(Context.USER_SERVICE) as UserManager).isUserUnlocked
    override fun unavailableReason(alert: ReminderAlert): String? = when {
        !protected() -> "protected_storage_unavailable"
        !permission() -> "notification_permission"
        !appEnabled() -> "notifications_blocked"
        !channelEnabled(alert) -> "channel_blocked"
        !exact() -> "exact_alarm_denied"
        else -> null
    }
    private fun alarmIntent(r: ReminderRequest) = Intent(context, ReminderAlarmReceiver::class.java).apply {
        action = ACTION
        data = Uri.Builder().scheme("vital-reminder").authority("alarm").appendPath(r.epoch).appendPath(r.requestToken).build()
    }
    private fun pending(r: ReminderRequest, create: Boolean): PendingIntent? = PendingIntent.getBroadcast(context, 0,
        alarmIntent(r), PendingIntent.FLAG_IMMUTABLE or (if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE))
    override fun schedule(request: ReminderRequest) {
        if (!exact()) throw ReminderFailure("exact_alarm_denied")
        // Recheck here to avoid creating a past alarm after a slow journal/capability call.
        if (request.purpose != "stockLow" && request.deadlineMilliseconds <=
            if (request.clock == "elapsed") nowElapsed() else nowWall()) throw ReminderFailure("deadline_expired")
        val scheduledAt = if (request.purpose == "stockLow") maxOf(request.deadlineMilliseconds, nowWall())
            else request.deadlineMilliseconds
        alarms.setExactAndAllowWhileIdle(if (request.clock == "elapsed") AlarmManager.ELAPSED_REALTIME_WAKEUP else AlarmManager.RTC_WAKEUP,
            scheduledAt, requireNotNull(pending(request, true)))
    }
    override fun cancel(request: ReminderRequest) {
        pending(request, false)?.let { alarms.cancel(it); it.cancel() }
        notifications.cancel(request.requestToken, 1)
    }
    override fun pending(request: ReminderRequest) = pending(request, false) != null
    override fun visible(request: ReminderRequest) = notifications.activeNotifications.any { it.tag == request.requestToken && it.id == 1 }
    private fun activity(r: ReminderRequest, action: String, token: String): PendingIntent = requireNotNull(PendingIntent.getActivity(context, 0,
        Intent(context, MainActivity::class.java).apply {
            this.action = ACTION
            data = Uri.Builder().scheme("vital-reminder").authority("action").appendPath(r.epoch)
                .appendPath(r.requestToken).appendPath(action).appendPath(token).build()
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
    override fun post(request: ReminderRequest, alert: ReminderAlert) {
        ensureChannel(alert)
        val channelId = ReminderChannels.id(alert)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId) else {
            @Suppress("DEPRECATION") Notification.Builder(context)
        }
        builder.setSmallIcon(R.drawable.ic_reminder)
        if (request.purpose == "stockLow") {
            builder.setContentTitle(context.getString(R.string.stock_notice_title))
                .setContentText(context.getString(R.string.stock_notice_body))
        } else {
            builder.setContentTitle(context.getString(R.string.reminder_title))
                .setContentText(context.getString(R.string.reminder_body))
        }
        builder.setVisibility(Notification.VISIBILITY_PRIVATE)
            .setCategory(Notification.CATEGORY_REMINDER).setAutoCancel(true)
            .setContentIntent(activity(request, "open", request.requestToken))
        for ((kind, token, label) in (if (request.purpose != "ordinary") emptyList() else listOf(Triple("taken", request.takenToken, R.string.reminder_taken),
            Triple("snooze", request.snoozeToken, R.string.reminder_snooze), Triple("skip", request.skipToken, R.string.reminder_skip)))) {
            val action = Notification.Action.Builder(null, context.getString(label), activity(request, kind, token))
            if (Build.VERSION.SDK_INT >= 31) action.setAuthenticationRequired(true)
            builder.addAction(action.build())
        }
        notifications.notify(request.requestToken, 1, builder.build())
    }
}

class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val uri = intent.data ?: return
        if (intent.action != AndroidReminderEffects.ACTION || uri.scheme != "vital-reminder" || uri.authority != "alarm" || uri.pathSegments.size != 2) return
        val epoch = uri.pathSegments[0]; val token = uri.pathSegments[1]
        try { ReminderEngine.token(epoch); ReminderEngine.token(token) } catch (_: Exception) { return }
        val pending = goAsync()
        ReminderRuntime.executor.execute {
            try { ReminderRuntime.engine(context).fire(epoch, token) } catch (_: Exception) { /* Fail private, never log payloads. */ }
            finally { pending.finish() }
        }
    }
}

/** No automatic boot registration: protected truth is reconciled when Vital reopens. */
class ReminderRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) return
        val pending = goAsync()
        ReminderRuntime.executor.execute {
            try { ReminderRuntime.engine(context).invalidateEvidence(when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED -> "device_restarted"
                Intent.ACTION_MY_PACKAGE_REPLACED -> "app_updated"
                else -> "exact_access_changed"
            }) }
            catch (_: Exception) { /* Reopening detects boot independently and remains the repair path. */ }
            finally { pending.finish() }
        }
    }
}

internal class Reminders(private val activity: MainActivity, messenger: BinaryMessenger) {
    companion object { const val PERMISSION_REQUEST = 7107 }
    private val context = activity.applicationContext
    private val methods = MethodChannel(messenger, "true_grit_vital/reminders")
    private val events = EventChannel(messenger, "true_grit_vital/reminder_changes")
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var registered = false
    private var permissionResult: MethodChannel.Result? = null
    private var disposed = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { changed() }
    }
    init {
        AndroidReminderEffects(context).channel()
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT < 33 || AndroidReminderEffects(context).permission()) result.success(true)
                    else if (permissionResult != null) result.error("request_pending", null, null)
                    else {
                        try { permissionResult = result; activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST) }
                        catch (_: Exception) { permissionResult = null; result.error("request_unavailable", null, null) }
                    }
                }
                "openExactAlarmSettings", "openNotificationSettings" -> {
                    try {
                        val intent = if (call.method == "openExactAlarmSettings" && Build.VERSION.SDK_INT >= 31) {
                            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
                        } else if (call.method == "openNotificationSettings" && Build.VERSION.SDK_INT >= 26) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        } else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
                        activity.startActivity(intent); result.success(true)
                    } catch (_: Exception) { result.success(false) }
                }
                else -> ReminderRuntime.executor.execute {
                    try {
                        val engine = ReminderRuntime.engine(context)
                        val answer: Any? = when (call.method) {
                            "capabilities" -> capabilities(engine)
                            "sampleClock" -> engine.clock()
                            "applyAlertPreferences" -> {
                                if (Build.VERSION.SDK_INT < 26) false
                                else {
                                    val alert = ReminderAlert(
                                        sound = call.argument<Boolean>("sound") ?: throw ReminderFailure("invalid_arguments"),
                                        vibration = call.argument<Boolean>("vibration") ?: throw ReminderFailure("invalid_arguments"),
                                    )
                                    val applied = engine.applyAlert(alert)
                                    // The choice is durable in the journal first.
                                    // A channel that could not be created is not an
                                    // accepted native effect: fail so the app can
                                    // show pending and offer Retry.
                                    val effects = AndroidReminderEffects(context)
                                    try { effects.ensureChannel(alert) }
                                    catch (_: Exception) { throw ReminderFailure("alert_channel_unavailable") }
                                    if (!effects.channelExists(alert)) throw ReminderFailure("alert_channel_unavailable")
                                    applied
                                }
                            }
                            "applySnapshot" -> {
                                val epoch = string(call.argument<Any?>("epoch"))
                                val sequence = number(call.argument<Any?>("sequence"))
                                val raw = call.argument<List<Any?>>("desired") ?: throw ReminderFailure("invalid_arguments")
                                if (raw.size > 264) throw ReminderFailure("invalid_arguments")
                                val requests = raw.map { value ->
                                    val m = value as? Map<*, *> ?: throw ReminderFailure("invalid_arguments")
                                    ReminderRequest(string(m["epoch"]), string(m["requestToken"]), string(m["takenToken"]),
                                        string(m["snoozeToken"]), string(m["skipToken"]), string(m["clock"]), number(m["deadlineMilliseconds"]), m["bootId"]?.let { string(it, 256) }, m["purpose"]?.let { string(it) } ?: "ordinary")
                                }
                                engine.apply(epoch, sequence, requests, tokens(call.argument<Any?>("obsoleteTokens")))
                            }
                            "inspect" -> engine.inspect(tokens(call.argument<Any?>("tokens")))
                            "cancel" -> engine.cancel(tokens(call.argument<Any?>("tokens")))
                            "invalidateEpoch" -> engine.invalidate(string(call.argument<Any?>("oldEpoch")), string(call.argument<Any?>("newEpoch")))
                            "getInitialAction", "launchAction" -> engine.initialAction()
                            "acknowledgeAction" -> { engine.acknowledge(string(call.argument<Any?>("envelopeId"))); null }
                            else -> throw ReminderFailure("not_implemented")
                        }
                        main.post { if (!disposed) result.success(answer) }
                    } catch (e: ReminderFailure) { main.post { if (!disposed) result.error(e.code, null, null) } }
                    catch (_: Exception) { main.post { if (!disposed) result.error("reminders_unavailable", null, null) } }
                }
            }
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                unregister(); sink = eventSink
                val filter = IntentFilter().apply { addAction(Intent.ACTION_TIME_CHANGED); addAction(Intent.ACTION_TIMEZONE_CHANGED)
                    if (Build.VERSION.SDK_INT >= 31) addAction(AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED) }
                try {
                    if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    else { @Suppress("DEPRECATION") context.registerReceiver(receiver, filter) }
                    registered = true
                } catch (_: Exception) { sink?.error("reminder_events_unavailable", null, null) }
            }
            override fun onCancel(arguments: Any?) { unregister(); sink = null }
        })
    }
    private fun capabilities(engine: ReminderEngine): Map<String, Any?> {
        val effects = AndroidReminderEffects(context)
        var storage = false; var boot = false; var reason: String? = null; var installed: String? = null
        var alert = ReminderAlert.LEGACY
        try { reason = engine.repairReason(); alert = engine.alert(); boot = engine.bootAvailable(); installed = engine.installedEpoch(); storage = true }
        catch (e: ReminderFailure) { reason = e.code }
        catch (_: Exception) { reason = "protected_storage_unavailable" }
        return mapOf("supported" to true, "notificationPermission" to effects.permission(), "appEnabled" to effects.appEnabled(),
            "channelEnabled" to effects.channelEnabled(alert), "alertChoicesAvailable" to (Build.VERSION.SDK_INT >= 26),
            "exactAlarm" to effects.exact(), "protectedStorageAvailable" to storage,
            "bootIdentityAvailable" to boot, "fingerprint" to ReminderEngine.FINGERPRINT, "repairReason" to reason,
            "installedEpoch" to installed)
    }
    fun acceptIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        if (intent.action != AndroidReminderEffects.ACTION || uri.scheme != "vital-reminder" || uri.authority != "action" || uri.pathSegments.size != 4 || uri.toString().length > 1024) return
        val parts = uri.pathSegments.toList()
        ReminderRuntime.executor.execute {
            try { ReminderRuntime.engine(context).capture(parts[0], parts[1], parts[3], parts[2]); main.post { changed() } }
            catch (_: Exception) { /* Keep the original intent for retry after protected storage recovers. */ }
        }
    }
    fun changed() { if (!disposed) sink?.success(null) }
    fun permissionResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        permissionResult?.success(AndroidReminderEffects(context).permission()); permissionResult = null; changed(); return true
    }
    private fun unregister() { if (registered) { context.unregisterReceiver(receiver); registered = false } }
    fun dispose() {
        disposed = true; unregister(); sink = null
        permissionResult?.error("request_interrupted", null, null); permissionResult = null
        methods.setMethodCallHandler(null); events.setStreamHandler(null)
    }
    private fun string(value: Any?, limit: Int = 128): String = (value as? String)?.takeIf { it.length in 1..limit }
        ?: throw ReminderFailure("invalid_arguments")
    private fun number(value: Any?): Long = when (value) { is Long -> value; is Int -> value.toLong(); else -> throw ReminderFailure("invalid_arguments") }
    private fun tokens(value: Any?): List<String> {
        val list = value as? List<*> ?: throw ReminderFailure("invalid_arguments")
        if (list.size > 512) throw ReminderFailure("invalid_arguments")
        return list.map { string(it) }
    }
}
