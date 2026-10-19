package dev.truegrit.vital

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** One bounded OS challenge, with no app PIN or authentication secret. */
class AppAuthentication(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var cancellation: CancellationSignal? = null
    private var legacyInFlight = false
    private var resumed = false
    private var focused = false
    private var awaitingResume: MethodChannel.Result? = null
    private var timeout: Runnable? = null

    fun availability(): String {
        if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_SECURE_LOCK_SCREEN)) {
            return "unsupported"
        }
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            ?: return "temporarilyUnavailable"
        return if (keyguard.isDeviceSecure) "available" else "setupRequired"
    }

    fun authenticate(result: MethodChannel.Result) {
        if (pending != null || legacyInFlight) {
            result.success("busy")
            return
        }
        if (!resumed || !focused || activity.isFinishing || activity.isDestroyed || availability() != "available") {
            result.success("unavailable")
            return
        }
        pending = result
        timeout = Runnable {
            if (pending === result) {
                val signal = cancellation
                finish(result, "failed")
                signal?.cancel()
            }
        }.also { handler.postDelayed(it, 120_000) }
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                showBiometricPrompt(result)
            } else {
                showLegacyCredential(result)
            }
        } catch (_: Exception) {
            legacyInFlight = false
            val signal = cancellation
            finish(result, "unavailable")
            signal?.cancel()
        }
    }

    @Suppress("DEPRECATION")
    private fun showLegacyCredential(result: MethodChannel.Result) {
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val intent = keyguard.createConfirmDeviceCredentialIntent(
            activity.getString(R.string.auth_title),
            activity.getString(R.string.auth_description),
        )
        if (intent == null) {
            finish(result, "unavailable")
            return
        }
        legacyInFlight = true
        activity.startActivityForResult(intent, ActivityRequestCodes.CREDENTIAL)
    }

    @Suppress("DEPRECATION")
    private fun showBiometricPrompt(result: MethodChannel.Result) {
        val builder = BiometricPrompt.Builder(activity)
            .setTitle(activity.getString(R.string.auth_title))
            .setDescription(activity.getString(R.string.auth_description))
        if (Build.VERSION.SDK_INT >= 30) {
            builder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        } else {
            // API 29's framework API supports a device PIN/pattern/password fallback.
            builder.setDeviceCredentialAllowed(true)
        }
        val signal = CancellationSignal()
        cancellation = signal
        builder.build().authenticate(signal, activity.mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(value: BiometricPrompt.AuthenticationResult) {
                    acceptSuccess(result)
                }

                override fun onAuthenticationError(code: Int, message: CharSequence) {
                    val status = when (code) {
                        BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED -> "cancelled"
                        BiometricPrompt.BIOMETRIC_ERROR_CANCELED,
                        BiometricPrompt.BIOMETRIC_ERROR_HW_UNAVAILABLE,
                        BiometricPrompt.BIOMETRIC_ERROR_HW_NOT_PRESENT,
                        BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS,
                        BiometricPrompt.BIOMETRIC_ERROR_NO_DEVICE_CREDENTIAL,
                        BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT,
                        BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT_PERMANENT -> "unavailable"
                        else -> "failed"
                    }
                    // OS messages never become logs or app-auth error payloads.
                    finish(result, status)
                }

                // A failed biometric match is not terminal: the OS owns retries/limits.
                override fun onAuthenticationFailed() = Unit
            },
        )
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (!ActivityRequestCodes.acceptsCredential(requestCode, legacyInFlight, pending != null)) {
            // A timed-out legacy challenge may still return; it cannot unlock,
            // but its completion releases the native in-flight fence.
            if (requestCode == ActivityRequestCodes.CREDENTIAL && pending == null) legacyInFlight = false
            return false
        }
        val result = pending ?: return false
        legacyInFlight = false
        if (resultCode == Activity.RESULT_OK) acceptSuccess(result)
        else finish(result, "cancelled")
        return true
    }

    private fun acceptSuccess(result: MethodChannel.Result) {
        if (pending !== result) return
        // Credential Activities return a result before the host's resume callback.
        awaitingResume = result
        if (resumed && focused) dispatchSuccess(result)
        handler.postDelayed({
            if (awaitingResume === result) finish(result, "cancelled")
        }, 1_000)
    }

    private fun dispatchSuccess(result: MethodChannel.Result) {
        handler.post {
            if (pending === result && awaitingResume === result) {
                if (resumed && focused) finish(result, "authenticated")
            }
        }
    }

    fun onPostResume() {
        resumed = true
        if (focused) awaitingResume?.let { dispatchSuccess(it) }
    }

    fun onWindowFocusChanged(hasFocus: Boolean) {
        focused = hasFocus
        if (resumed && focused) awaitingResume?.let { dispatchSuccess(it) }
    }

    fun onPause() {
        resumed = false
        // A new pause after success must never retain a later unlock token.
        awaitingResume?.let { finish(it, "cancelled") }
    }

    fun dispose() {
        val signal = cancellation
        pending?.let { finish(it, "cancelled") }
        signal?.cancel()
        handler.removeCallbacksAndMessages(null)
    }

    private fun finish(result: MethodChannel.Result, status: String) {
        if (pending !== result) return
        pending = null
        awaitingResume = null
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null
        cancellation = null
        result.success(status)
    }

}
