package dev.truegrit.vital

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.UserManager
import android.provider.OpenableColumns
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.security.MessageDigest

/** SAF owns the original. Only an opaque job and URI digest persist in app metadata. */
internal class AttachmentPicker(private val activity: Activity, messenger: BinaryMessenger) {
    companion object { private val jobLock = Any(); private val identity = Regex("[A-Za-z0-9_-]{1,128}") }
    private val channel = MethodChannel(messenger, "true_grit_vital/attachment_picker", io.flutter.plugin.common.StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
    private val handler = Handler(Looper.getMainLooper())
    private val resultWorker = java.util.concurrent.Executors.newSingleThreadExecutor()
    @Volatile private var pending: MethodChannel.Result? = null
    @Volatile private var disposed = false
    private var stream: InputStream? = null
    private var streamJob: String? = null
    private var streamOffset = 0L
    private data class Job(val id: String, val code: Int, val digest: String = "", val state: String = "pending")
    private fun store(): AtomicFile {
        if (activity.isDeviceProtectedStorage || !(activity.getSystemService(Activity.USER_SERVICE) as UserManager).isUserUnlocked) throw HandoffFailure("protected_storage_unavailable")
        val directory = File(activity.noBackupFilesDir, "vital-picker-v1")
        val created = !directory.isDirectory && directory.mkdirs()
        if (!directory.isDirectory) throw HandoffFailure("attachment_picker_unavailable")
        directory.setReadable(false, false); directory.setWritable(false, false); directory.setExecutable(false, false)
        directory.setReadable(true, true); directory.setWritable(true, true); directory.setExecutable(true, true)
        if (created) {
            val counter = AtomicFile(File(directory, "counter"))
            val out = counter.startWrite()
            try {
                val data = java.io.DataOutputStream(out)
                data.writeInt(ActivityRequestCodes.FIRST_PICKER - 1); data.flush(); out.fd.sync()
                counter.finishWrite(out); HandoffStorage.syncDirectory(directory)
            } catch (failure: Exception) { counter.failWrite(out); throw failure }
        }
        return AtomicFile(File(directory, "job.json"))
    }
    private fun read(): Job? = try {
        readUnchecked().also { job ->
            val directory = requireNotNull(store().baseFile.parentFile)
            if (job == null && listOf("grant.digest", "grant.digest.bak", "grant.digest.new").any { File(directory, it).exists() }) clearInventory()
        }
    } catch (failure: HandoffFailure) {
        if (failure.code != "attachment_picker_recovery") throw failure
        clearInventory()
        pending?.error("attachment_picker_interrupted", null, null); pending = null
        null
    }
    private fun readUnchecked(): Job? {
        val file = store()
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return null
        return try { file.openRead().use { input ->
            val buffer = ByteArray(1025)
            var length = 0
            while (length < buffer.size) {
                val count = input.read(buffer, length, buffer.size - length)
                if (count < 0) break
                if (count == 0) throw HandoffFailure("attachment_picker_recovery")
                length += count
            }
            val bytes = buffer.copyOf(length)
            if (bytes.size > 1024) throw HandoffFailure("attachment_picker_recovery")
            val data = JSONObject(bytes.toString(Charsets.UTF_8))
            Job(data.getString("id"), data.getInt("code"), data.getString("digest"), data.getString("state")).also {
                if (!identity.matches(it.id) || !ActivityRequestCodes.ownsPicker(it.code) || it.state !in setOf("pending", "selected", "cancelled") ||
                    (it.digest.isNotEmpty() && !Regex("[a-f0-9]{64}").matches(it.digest))) throw HandoffFailure("attachment_picker_recovery")
            }
        } } catch (e: HandoffFailure) { throw e } catch (_: Exception) { throw HandoffFailure("attachment_picker_recovery") }
    }
    private fun save(job: Job) {
        val file = store(); val out = file.startWrite()
        try {
            file.baseFile.setReadable(false, false); file.baseFile.setWritable(false, false)
            file.baseFile.setReadable(true, true); file.baseFile.setWritable(true, true)
            out.write(JSONObject().put("id", job.id).put("code", job.code).put("digest", job.digest).put("state", job.state).toString().toByteArray(Charsets.UTF_8))
            out.fd.sync(); file.finishWrite(out); syncDirectory(requireNotNull(file.baseFile.parentFile))
        } catch (e: Exception) { file.failWrite(out); throw e }
    }
    private fun releaseDigest(value: String) {
        activity.contentResolver.persistedUriPermissions.filter { it.isReadPermission && digest(it.uri) == value }.forEach {
            try { activity.contentResolver.releasePersistableUriPermission(it.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            catch (_: SecurityException) {
                // A provider may revoke the grant concurrently. Retain the ledger
                // for retry if this app still has the recorded read permission.
                if (activity.contentResolver.persistedUriPermissions.any { grant -> grant.isReadPermission && digest(grant.uri) == value }) {
                    throw HandoffFailure("attachment_picker_unavailable")
                }
            }
        }
    }
    private fun clearInventory(job: Job? = null) {
        stream?.close(); stream = null; streamJob = null; streamOffset = 0
        val directory = requireNotNull(store().baseFile.parentFile)
        PickerInventoryFiles(directory).clear(job?.digest, ::releaseDigest)
        syncDirectory(directory)
    }
    private fun saveGrantDigest(value: String) {
        val inventory = store()
        val file = AtomicFile(File(inventory.baseFile.parentFile, "grant.digest"))
        val out = file.startWrite()
        try {
            file.baseFile.setReadable(false, false); file.baseFile.setWritable(false, false)
            file.baseFile.setReadable(true, true); file.baseFile.setWritable(true, true)
            out.write(value.toByteArray(Charsets.US_ASCII)); out.fd.sync(); file.finishWrite(out)
            syncDirectory(requireNotNull(file.baseFile.parentFile))
        } catch (failure: Exception) { file.failWrite(out); throw failure }
    }
    private fun syncDirectory(directory: File) = HandoffStorage.syncDirectory(directory)
    private fun nextCode(): Int {
        val file = AtomicFile(File(store().baseFile.parentFile, "counter"))
        val recovery = AtomicFile(File(file.baseFile.parentFile, "counter-recovery-used"))
        fun reserveRecovery() {
            if (recovery.baseFile.exists() || File(recovery.baseFile.path + ".bak").exists()) return
            val out = recovery.startWrite()
            try {
                out.write(byteArrayOf(1)); out.fd.sync(); recovery.finishWrite(out)
                syncDirectory(requireNotNull(recovery.baseFile.parentFile))
            } catch (failure: Exception) { recovery.failWrite(out); throw failure }
        }
        val prior = try {
            if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) file.openRead().use {
                val data = java.io.DataInputStream(it)
                data.readInt().also {
                    if (data.read() != -1 || it !in (ActivityRequestCodes.FIRST_PICKER - 1)..ActivityRequestCodes.LAST_PICKER) throw HandoffFailure("attachment_picker_recovery")
                }
            } else if (recovery.baseFile.exists() || File(recovery.baseFile.path + ".bak").exists()) {
                throw HandoffFailure("attachment_picker_capacity")
            } else throw HandoffFailure("attachment_picker_recovery")
        } catch (failure: Exception) {
            val safePrior = ActivityRequestCodes.recoveredCounterPrior(recovery.baseFile.exists() || File(recovery.baseFile.path + ".bak").exists())
            // Never reset a corrupt legacy counter and reuse a result code.
            // Reserve a previously unused range before making its first request.
            reserveRecovery()
            safePrior
        }
        val next = ActivityRequestCodes.nextPicker(prior)
        if (next > ActivityRequestCodes.LEGACY_LAST_PICKER) reserveRecovery()
        val out = file.startWrite()
        try { val data = java.io.DataOutputStream(out); data.writeInt(next); data.flush(); out.fd.sync(); file.finishWrite(out); syncDirectory(requireNotNull(file.baseFile.parentFile)) }
        catch (e: Exception) { file.failWrite(out); throw e }
        return next
    }
    private fun digest(uri: Uri) = MessageDigest.getInstance("SHA-256").digest(uri.toString().toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    private fun uri(job: Job): Uri = activity.contentResolver.persistedUriPermissions.firstOrNull {
        it.isReadPermission && digest(it.uri) == job.digest
    }?.uri ?: throw HandoffFailure("attachment_picker_source_unavailable")
    private fun requireJob(id: String): Job = read()?.takeIf { it.id == id } ?: throw HandoffFailure("attachment_picker_context")
    private fun selection(job: Job): Map<String, Any?> {
        if (job.state != "selected") return mapOf("jobId" to job.id, "state" to job.state)
        val uri = uri(job)
        var name = activity.getString(R.string.attachment_default_name); var size: Long? = null
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val ni = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME); val si = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (ni >= 0 && !cursor.isNull(ni)) name = cursor.getString(ni).take(255)
                if (si >= 0 && !cursor.isNull(si)) size = cursor.getLong(si)
            }
        }
        if (size != null && size > AttachmentHandoffFiles.MAX_BYTES) throw HandoffFailure("attachment_byte_limit")
        return mapOf("jobId" to job.id, "state" to job.state, "name" to name, "byteCount" to (size ?: -1L))
    }
    init { channel.setMethodCallHandler { call, result ->
        synchronized(jobLock) {
            try {
                if (disposed) throw HandoffFailure("attachment_picker_interrupted")
                if (call.method == "pending") { result.success(read()?.id); return@setMethodCallHandler }
                val id = call.argument<String>("jobId")
                if (id == null || !identity.matches(id)) throw HandoffFailure("attachment_identity")
                when (call.method) {
                    "pick" -> {
                        if (pending != null) throw HandoffFailure("attachment_picker_busy")
                        // With no live callback, finish only this picker's known inventory.
                        read()?.let { clearInventory(it) }
                        val job = Job(id, nextCode()); save(job); pending = result
                        val photo = call.argument<Boolean>("photoOnly") == true
                        handler.post { try {
                            if (disposed) throw HandoffFailure("attachment_picker_interrupted")
                            synchronized(jobLock) {
                            if (pending !== result || read()?.let { it.id == job.id && it.code == job.code && it.state == "pending" } != true) return@post
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE); type = if (photo) "image/*" else "*/*"
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }, job.code)
                            }
                        } catch (_: Exception) { synchronized(jobLock) {
                            save(job.copy(state = "cancelled")); pending?.error("attachment_picker_unavailable", null, null); pending = null
                        } } }
                    }
                    "recover" -> result.success(selection(requireJob(id)))
                    "read" -> {
                        val job = requireJob(id)
                        if (job.state != "selected") throw HandoffFailure("attachment_picker_context")
                        val offset = call.argument<Number>("offset")?.toLong() ?: throw HandoffFailure("attachment_picker_input")
                        if (offset < 0 || offset > AttachmentHandoffFiles.MAX_BYTES) throw HandoffFailure("attachment_byte_limit")
                        if (streamJob != id || offset == 0L) {
                            stream?.close(); stream = activity.contentResolver.openInputStream(uri(job)) ?: throw HandoffFailure("attachment_picker_source_unavailable")
                            streamJob = id; streamOffset = 0
                        }
                        if (offset != streamOffset) throw HandoffFailure("attachment_picker_context")
                        val buffer = ByteArray(AttachmentHandoffFiles.CHUNK_BYTES)
                        val count = stream!!.read(buffer)
                        if (count == 0) throw HandoffFailure("attachment_picker_source_unavailable")
                        if (count < 0) { stream?.close(); stream = null; streamJob = null; result.success(null) }
                        else {
                            if (count.toLong() > AttachmentHandoffFiles.MAX_BYTES - streamOffset) throw HandoffFailure("attachment_byte_limit")
                            streamOffset += count; result.success(buffer.copyOf(count)); buffer.fill(0)
                        }
                    }
                    "finish" -> {
                        val existing = read()
                        if (existing == null) { result.success(null); return@setMethodCallHandler }
                        val job = existing.takeIf { it.id == id } ?: throw HandoffFailure("attachment_picker_context")
                        clearInventory(job)
                        pending?.success(mapOf("jobId" to id, "state" to "cancelled")); pending = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: HandoffFailure) { result.error(e.code, null, null) }
            catch (_: Exception) { result.error("attachment_picker_unavailable", null, null) }
        }
    } }
    fun activityResult(request: Int, result: Int, data: Intent?): Boolean {
        if (!ActivityRequestCodes.ownsPicker(request) || disposed) return false
        val owned = synchronized(jobLock) {
            try {
                val job = read()
                ActivityRequestCodes.acceptsPicker(request, job?.code, job?.state)
            }
            catch (_: Exception) { false }
        }
        if (!owned) return false
        resultWorker.execute { synchronized(jobLock) {
        try {
            val job = read() ?: return@synchronized
            if (request != job.code || job.state != "pending") return@synchronized
            val selected = data?.data
            val updated = if (result == Activity.RESULT_OK && selected != null) {
                val selectedJob = job.copy(digest = digest(selected), state = "selected")
                // The digest precedes the OS grant: interruption cannot leave an unattributed grant.
                save(selectedJob)
                saveGrantDigest(selectedJob.digest)
                activity.contentResolver.takePersistableUriPermission(selected, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                selectedJob
            } else job.copy(state = "cancelled")
            save(updated)
            pending?.success(selection(updated)); pending = null
        } catch (e: HandoffFailure) { pending?.error(e.code, null, null); pending = null }
        catch (_: Exception) { pending?.error("attachment_picker_unavailable", null, null); pending = null }
        } }
        return true
    }
    fun dispose() {
        disposed = true; pending = null; channel.setMethodCallHandler(null)
        resultWorker.execute { synchronized(jobLock) { stream?.close(); stream = null; streamJob = null } }
        resultWorker.shutdown()
    }
}
