package dev.truegrit.vital

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.KeyStore
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class StorageFailure(val code: String) : Exception()

/**
 * Single-dataset bootstrap. All personal files live in credential-encrypted
 * noBackupFilesDir. No key regeneration, destructive recovery, or PIN binding.
 */
internal class SecureStorage(private val context: Context) {
    companion object {
        private const val ALIAS = "dev.truegrit.vital.dataset.v1"
        private const val ENVELOPE = "key-envelope.json"
        private const val INTENT = "initializing"
        private const val READY = "active"
        private const val DATABASE = "records.sqlite"
        private val monitor = Any()
    }

    private val directory get() = File(context.noBackupFilesDir, "vital")

    private fun <T> locked(block: (File) -> T): T = synchronized(monitor) {
        if (Build.VERSION.SDK_INT >= 24 && context.isDeviceProtectedStorage) {
            throw StorageFailure("protected_storage_unavailable")
        }
        val dir = directory
        if (!dir.isDirectory && !dir.mkdirs()) {
            throw StorageFailure("protected_storage_unavailable")
        }
        RandomAccessFile(File(dir, ".bootstrap.lock"), "rw").use { lockFile ->
            lockFile.channel.lock().use { block(dir) }
        }
    }

    fun prepare(): Map<String, Any> = locked { dir ->
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val envelope = File(dir, ENVELOPE)
        val db = File(dir, DATABASE)
        val intent = File(dir, INTENT)
        val ready = File(dir, READY)
        val files = dir.list()?.filter { it != ".bootstrap.lock" }
            ?: throw StorageFailure("protected_storage_unavailable")
        if (files.isEmpty() && !keyStore.containsAlias(ALIAS)) {
            val id = UUID.randomUUID().toString()
            // Durable intent precedes key creation: interrupted setup fails closed.
            publish(dir, INTENT, id.toByteArray(Charsets.UTF_8))
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(256)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .setUserAuthenticationRequired(false)
                    .build(),
            )
            val wrappingKey = generator.generateKey()
            val secret = ByteArray(32).also { SecureRandom().nextBytes(it) }
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, wrappingKey)
                cipher.updateAAD(aad(id))
                val wrapped = cipher.doFinal(secret)
                val json = JSONObject().put("version", 1).put("dataset", id)
                    .put("nonce", hex(cipher.iv)).put("wrapped", hex(wrapped))
                publish(dir, ENVELOPE, json.toString().toByteArray(Charsets.UTF_8))
                mapOf("path" to db.absolutePath, "key" to secret.copyOf(), "isNew" to true)
            } finally {
                secret.fill(0)
            }
        } else {
            if (files.any { it.endsWith(".pending") } || !intent.isFile || !envelope.isFile ||
                !db.isFile || db.length() < 512 || !keyStore.containsAlias(ALIAS)) {
                throw StorageFailure("storage_recovery_required")
            }
            val id = boundedRead(intent, 64).toString(Charsets.UTF_8)
            val json = JSONObject(boundedRead(envelope, 1024).toString(Charsets.UTF_8))
            if (json.getInt("version") != 1 || json.getString("dataset") != id ||
                (ready.exists() && boundedRead(ready, 64).toString(Charsets.UTF_8) != id)) {
                throw StorageFailure("storage_recovery_required")
            }
            val key = keyStore.getKey(ALIAS, null) as? SecretKey
                ?: throw StorageFailure("storage_recovery_required")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, unhex(json.getString("nonce"), 12)))
            cipher.updateAAD(aad(id))
            val secret = try {
                cipher.doFinal(unhex(json.getString("wrapped"), 48))
            } catch (_: java.security.GeneralSecurityException) {
                throw StorageFailure("storage_recovery_required")
            }
            if (secret.size != 32) {
                secret.fill(0)
                throw StorageFailure("storage_recovery_required")
            }
            mapOf("path" to db.absolutePath, "key" to secret, "isNew" to false)
        }
    }

    /** Only the caller that has validated the encrypted database may activate it. */
    fun activate(path: String?) = locked { dir ->
        val db = File(dir, DATABASE)
        if (path != db.absolutePath || !db.isFile || db.length() < 512) {
            throw StorageFailure("storage_recovery_required")
        }
        val id = boundedRead(File(dir, INTENT), 64)
        val ready = File(dir, READY)
        if (ready.exists()) {
            if (!boundedRead(ready, 64).contentEquals(id)) throw StorageFailure("storage_recovery_required")
        } else {
            publish(dir, READY, id)
        }
    }

    private fun boundedRead(file: File, limit: Int): ByteArray {
        if (!file.isFile || file.length() !in 1..limit.toLong()) throw StorageFailure("storage_recovery_required")
        return file.readBytes()
    }

    private fun aad(id: String) = "Vital database envelope v1:$id".toByteArray(Charsets.UTF_8)

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun unhex(value: String, size: Int): ByteArray {
        if (value.length != size * 2 || !value.matches(Regex("[0-9a-f]+"))) {
            throw StorageFailure("storage_recovery_required")
        }
        return ByteArray(size) { value.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }

    private fun publish(dir: File, name: String, bytes: ByteArray) {
        val target = File(dir, name)
        if (target.exists()) throw StorageFailure("storage_recovery_required")
        val pending = File(dir, "$name.pending")
        if (!pending.createNewFile()) throw StorageFailure("storage_recovery_required")
        FileOutputStream(pending).use { output -> output.write(bytes); output.fd.sync() }
        Os.rename(pending.absolutePath, target.absolutePath)
        val descriptor = Os.open(dir.absolutePath, OsConstants.O_RDONLY, 0)
        try { Os.fsync(descriptor) } finally { Os.close(descriptor) }
    }
}
