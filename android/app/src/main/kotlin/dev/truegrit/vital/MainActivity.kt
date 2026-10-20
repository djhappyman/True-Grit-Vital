package dev.truegrit.vital

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val authentication = AppAuthentication(this)
    private var deviceZone: DeviceZone? = null
    private var reminders: Reminders? = null
    private var attachmentHandoffs: AttachmentHandoffs? = null
    private var attachmentPicker: AttachmentPicker? = null
    private var artifactTransfers: ArtifactTransfers? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Fail private before the first Flutter frame or persisted preference read.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        super.onCreate(savedInstanceState)
    }

    override fun onPostResume() {
        super.onPostResume()
        authentication.onPostResume()
        deviceZone?.changed()
        reminders?.acceptIntent(intent)
        reminders?.changed()
    }

    override fun onPause() {
        authentication.onPause()
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        // Flutter must publish its focus/lifecycle state before the auth result.
        super.onWindowFocusChanged(hasFocus)
        authentication.onWindowFocusChanged(hasFocus)
    }

    override fun onDestroy() {
        deviceZone?.dispose()
        deviceZone = null
        reminders?.dispose()
        reminders = null
        attachmentHandoffs?.dispose()
        attachmentHandoffs = null
        attachmentPicker?.dispose()
        attachmentPicker = null
        artifactTransfers?.dispose()
        artifactTransfers = null
        authentication.dispose()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        reminders?.acceptIntent(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (reminders?.permissionResult(requestCode) != true) super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    @Deprecated("Required by the API 24–28 OS credential compatibility path")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!authentication.onActivityResult(requestCode, resultCode) && attachmentPicker?.activityResult(requestCode, resultCode, data) != true) {
            if (artifactTransfers?.activityResult(requestCode, resultCode, data) != true) super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceZone?.dispose()
        deviceZone = DeviceZone(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        reminders?.dispose()
        reminders = Reminders(this, flutterEngine.dartExecutor.binaryMessenger)
        reminders?.acceptIntent(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "true_grit_vital/app_auth")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "availability" -> result.success(authentication.availability())
                        "authenticate" -> authentication.authenticate(result)
                        "setPrivacyEnabled" -> {
                            val enabled = call.argument<Boolean>("enabled")
                            if (enabled == null) {
                                result.error("invalid_arguments", null, null)
                            } else {
                                if (enabled) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                                else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                                if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(!enabled)
                                result.success(true)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("auth_unavailable", null, null)
                }
            }
        attachmentHandoffs?.dispose()
        attachmentHandoffs = AttachmentHandoffs(this, flutterEngine.dartExecutor.binaryMessenger)
        attachmentPicker?.dispose()
        attachmentPicker = AttachmentPicker(this, flutterEngine.dartExecutor.binaryMessenger)
        artifactTransfers?.dispose()
        artifactTransfers = ArtifactTransfers(this, flutterEngine.dartExecutor.binaryMessenger)
        val storage = SecureStorage(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.truegrit.vital/storage",
            io.flutter.plugin.common.StandardMethodCodec.INSTANCE,
            flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "prepare" -> {
                        val location = storage.prepare()
                        try {
                            result.success(location)
                        } finally {
                            (location["key"] as ByteArray).fill(0)
                        }
                    }
                    "activate" -> {
                        storage.activate(call.argument<String>("path"))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: StorageFailure) {
                result.error(error.code, null, null)
            } catch (_: org.json.JSONException) {
                result.error("storage_recovery_required", null, null)
            } catch (_: android.security.keystore.KeyPermanentlyInvalidatedException) {
                result.error("storage_recovery_required", null, null)
            } catch (_: java.security.UnrecoverableKeyException) {
                result.error("storage_recovery_required", null, null)
            } catch (_: Exception) {
                // No native exception message, path or secret crosses into logs/UI.
                result.error("protected_storage_unavailable", null, null)
            }
        }
    }
}
