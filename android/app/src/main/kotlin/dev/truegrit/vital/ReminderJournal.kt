package dev.truegrit.vital

import android.content.Context
import android.os.UserManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.ByteArrayOutputStream
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Same CE/no-backup, non-auth-bound Keystore policy as the protected dataset.
 * No clinical identifiers, database key, arbitrary body or owner link enter this file.
 */
internal class EncryptedReminderJournal(private val context: Context) : ReminderJournal {
    companion object {
        private const val ALIAS = "dev.truegrit.vital.reminders.v1"
        private val AAD = "Vital opaque reminder journal v1".toByteArray(Charsets.UTF_8)
        private const val LIMIT = 8 * 1024 * 1024
    }
    private val directory get() = File(context.noBackupFilesDir, "reminders-v1")
    private fun directory(): File {
        if (context.isDeviceProtectedStorage || !(context.getSystemService(Context.USER_SERVICE) as UserManager).isUserUnlocked) {
            throw ReminderFailure("protected_storage_unavailable")
        }
        val dir = directory
        if (!dir.isDirectory && !dir.mkdirs()) throw ReminderFailure("protected_storage_unavailable")
        return dir
    }
    private fun store() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun key(): SecretKey = store().getKey(ALIAS, null) as? SecretKey
        ?: throw ReminderFailure("journal_recovery_required")
    override fun read(): ReminderLedger {
        val dir = directory()
        val file = AtomicFile(File(dir, "journal.enc"))
        if (!file.baseFile.exists() && !File(dir, "journal.enc.bak").exists()) {
            val marker = File(dir, "initialized")
            if (marker.exists() || store().containsAlias(ALIAS)) throw ReminderFailure("journal_recovery_required")
            // Intent precedes key creation. An interrupted first setup never replaces a key.
            if (!marker.createNewFile()) throw ReminderFailure("journal_recovery_required")
            FileOutputStream(marker).use { it.fd.sync() }
            sync(dir)
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).setUserAuthenticationRequired(false).build())
            generator.generateKey()
            val initial = ReminderLedger(installation = UUID.randomUUID().toString())
            save(initial)
            return initial
        }
        val bytes = file.openRead().use {
            val output = ByteArrayOutputStream()
            val chunk = ByteArray(8192)
            var remaining = LIMIT + 1
            while (remaining > 0) {
                val count = it.read(chunk, 0, minOf(chunk.size, remaining))
                if (count < 0) break
                output.write(chunk, 0, count)
                remaining -= count
            }
            val buffer = output.toByteArray()
            if (buffer.size !in 29..LIMIT) throw ReminderFailure("journal_recovery_required")
            buffer
        }
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            cipher.updateAAD(AAD)
            val clear = cipher.doFinal(bytes.copyOfRange(12, bytes.size))
            return try { decode(JSONObject(clear.toString(Charsets.UTF_8))) } finally { clear.fill(0) }
        } catch (e: ReminderFailure) { throw e }
        catch (_: Exception) { throw ReminderFailure("journal_recovery_required") }
        finally { bytes.fill(0) }
    }
    override fun save(state: ReminderLedger) {
        val dir = directory()
        val clear = encode(state).toString().toByteArray(Charsets.UTF_8)
        if (clear.size > LIMIT - 28) { clear.fill(0); throw ReminderFailure("journal_capacity") }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(AAD)
        val encrypted = try { cipher.iv + cipher.doFinal(clear) } finally { clear.fill(0) }
        val file = AtomicFile(File(dir, "journal.enc"))
        val output = file.startWrite()
        try {
            output.write(encrypted)
            output.fd.sync()
            file.finishWrite(output)
            sync(dir)
        } catch (e: Exception) { file.failWrite(output); throw e }
        finally { encrypted.fill(0) }
    }
    private fun sync(dir: File) {
        val fd = Os.open(dir.absolutePath, OsConstants.O_RDONLY, 0)
        try { Os.fsync(fd) } finally { Os.close(fd) }
    }
    private fun encode(s: ReminderLedger): JSONObject = JSONObject().put("version", 1)
        .put("installation", s.installation).put("epoch", s.epoch ?: JSONObject.NULL)
        .put("sequence", s.sequence).put("snapshot", s.snapshot).put("boot", s.boot ?: JSONObject.NULL)
        .put("repairReason", s.repairReason ?: JSONObject.NULL).put("retired", JSONArray(s.retired.toList()))
        .put("acknowledged", JSONArray(s.acknowledged.toList()))
        .put("eligible", JSONArray(s.eligible.toList()))
        .put("entries", JSONArray(s.entries.values.map { e ->
            val r = e.request
            JSONObject().put("epoch", r.epoch).put("requestToken", r.requestToken)
                .put("takenToken", r.takenToken).put("snoozeToken", r.snoozeToken).put("skipToken", r.skipToken)
                .put("purpose", r.purpose).put("clock", r.clock).put("deadline", r.deadlineMilliseconds).put("boot", r.bootId ?: JSONObject.NULL)
                .put("state", e.state).put("reason", e.reason ?: JSONObject.NULL)
        })).put("actions", JSONArray(s.actions.map { a -> JSONObject().put("id", a.envelopeId)
            .put("epoch", a.epoch).put("request", a.requestToken).put("token", a.actionToken).put("action", a.action) }))
    private fun decode(j: JSONObject): ReminderLedger {
        if (j.getInt("version") != 1) throw ReminderFailure("journal_recovery_required")
        val entries = j.getJSONArray("entries")
        val actions = j.getJSONArray("actions")
        if (entries.length() > 8192 || actions.length() > 32) throw ReminderFailure("journal_recovery_required")
        val ledger = ReminderLedger(installation = j.getString("installation"), epoch = nullable(j, "epoch"),
            sequence = j.getLong("sequence"), snapshot = j.getString("snapshot"), boot = nullable(j, "boot"),
            repairReason = nullable(j, "repairReason"), retired = strings(j.getJSONArray("retired"), 1024),
            acknowledged = strings(j.getJSONArray("acknowledged"), 8192),
            eligible = strings(j.getJSONArray("eligible"), 256),
            entries = (0 until entries.length()).map { i ->
                val e = entries.getJSONObject(i)
                val r = ReminderRequest(e.getString("epoch"), e.getString("requestToken"), e.getString("takenToken"),
                    e.getString("snoozeToken"), e.getString("skipToken"), e.getString("clock"), e.getLong("deadline"), nullable(e, "boot"), e.optString("purpose", "ordinary"))
                r.requestToken to ReminderEntry(r, e.getString("state"), nullable(e, "reason"))
            }.also { pairs -> if (pairs.map { it.first }.distinct().size != pairs.size) throw ReminderFailure("journal_recovery_required") }.toMap(), actions = (0 until actions.length()).map { i -> val a = actions.getJSONObject(i)
                ReminderAction(a.getString("id"), a.getString("epoch"), a.getString("request"), a.getString("token"), a.getString("action")) })
        ReminderEngine.token(ledger.installation)
        ledger.epoch?.let { ReminderEngine.token(it) }
        if (ledger.sequence < -1 || ledger.snapshot.length > 1024 * 1024 || (ledger.boot?.length ?: 0) > 256 ||
            (ledger.repairReason?.length ?: 0) > 128 || ledger.epoch in ledger.retired ||
            ledger.actions.map { it.envelopeId }.distinct().size != ledger.actions.size) throw ReminderFailure("journal_recovery_required")
        (ledger.retired + ledger.acknowledged + ledger.eligible).forEach { ReminderEngine.token(it) }
        ledger.entries.values.forEach { e ->
            val r = e.request
            listOf(r.epoch, r.requestToken, r.takenToken, r.snoozeToken, r.skipToken).forEach { ReminderEngine.token(it) }
            if (r.purpose !in setOf("ordinary", "eventEnd") || (r.purpose == "eventEnd" && r.clock != "wall") ||
                r.clock !in setOf("wall", "elapsed") || r.deadlineMilliseconds <= 0 || (r.bootId?.length ?: 0) > 256 ||
                e.state !in setOf("accepted", "consumed", "cancelled", "postUncertain", "failed", "unknown") ||
                (e.reason?.length ?: 0) > 128) throw ReminderFailure("journal_recovery_required")
        }
        ledger.actions.forEach { a ->
            listOf(a.envelopeId, a.epoch, a.requestToken, a.actionToken).forEach { ReminderEngine.token(it) }
            if ((ledger.entries[a.requestToken]?.request?.purpose == "eventEnd" && a.action != "open") || a.action !in setOf("open", "taken", "snooze", "skip")) throw ReminderFailure("journal_recovery_required")
        }
        return ledger
    }
    private fun nullable(j: JSONObject, key: String): String? = if (j.isNull(key)) null else j.getString(key)
    private fun strings(a: JSONArray, limit: Int): Set<String> {
        if (a.length() > limit) throw ReminderFailure("journal_recovery_required")
        val values = (0 until a.length()).map { a.getString(it) }
        if (values.distinct().size != values.size) throw ReminderFailure("journal_recovery_required")
        return values.toSet()
    }
}
