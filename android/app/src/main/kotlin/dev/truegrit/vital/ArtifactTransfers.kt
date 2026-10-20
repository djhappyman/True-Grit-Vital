package dev.truegrit.vital

import android.app.Activity
import android.content.ClipData
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.UserManager
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.Executors

internal object ArtifactStorage {
    private var instance: ArtifactTransferFiles? = null
    @Synchronized
    fun files(context: Context): ArtifactTransferFiles {
        if (context.isDeviceProtectedStorage ||
            !(context.getSystemService(Context.USER_SERVICE) as UserManager).isUserUnlocked) {
            throw HandoffFailure("artifact_transfer_storage_unavailable")
        }
        return instance ?: ArtifactTransferFiles(
            File(context.noBackupFilesDir, "vital-artifacts-v1"),
            System::currentTimeMillis,
            syncDirectory = ::syncDirectory,
            protectFile = { file, folder -> Os.chmod(file.path, if (folder) 0x1c0 else 0x180) },
        ).also { instance = it }
    }

    /** Public Android APIs preserve the directory-only check before syncing metadata. */
    fun syncDirectory(directory: File) {
        val descriptor = Os.open(directory.path, OsConstants.O_RDONLY, 0)
        try {
            if (!OsConstants.S_ISDIR(Os.fstat(descriptor).st_mode)) {
                throw HandoffFailure("artifact_transfer_storage")
            }
            Os.fsync(descriptor)
        } finally {
            Os.close(descriptor)
        }
    }

    fun uri(context: Context, id: String): Uri = Uri.Builder()
        .scheme("content")
        .authority("${context.packageName}.artifact_transfer")
        .appendPath(id)
        .build()
}

/** No storage permission, persistent recipient, writable grant or silent destination. */
internal class ArtifactTransfers(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        /** Disjoint from CREDENTIAL (0x3001) and picker (0x4000–0xbfff). */
        const val SAVE_REQUEST = 0x2f01
    }

    private val channel = MethodChannel(
        messenger,
        "true_grit_vital/artifact_transfer",
        io.flutter.plugin.common.StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue(),
    )
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val saveLock = Any()
    @Volatile private var pendingSave: MethodChannel.Result? = null
    @Volatile private var pendingId: String? = null
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                if (disposed) throw HandoffFailure("artifact_transfer_interrupted")
                val files = ArtifactStorage.files(activity.applicationContext)
                fun text(key: String) = call.argument<String>(key) ?: throw HandoffFailure("artifact_transfer_input")
                fun number(key: String) = call.argument<Number>(key)?.toLong() ?: throw HandoffFailure("artifact_transfer_input")
                when (call.method) {
                    "begin" -> {
                        files.begin(text("id"), text("name"), text("mime"), number("bytes"), number("expiresAt"))
                        result.success(null)
                    }
                    "append" -> {
                        val bytes = call.argument<ByteArray>("bytes") ?: throw HandoffFailure("artifact_transfer_input")
                        try {
                            result.success(files.append(text("id"), number("offset"), bytes))
                        } finally {
                            bytes.fill(0)
                        }
                    }
                    "publish" -> {
                        files.publish(text("id"), number("bytes"), text("sha256"))
                        result.success(null)
                    }
                    "cancel" -> result.success(files.cancel(text("id")))
                    "cleanup" -> result.success(files.cleanup(call.argument<String>("preserve"), call.argument<Boolean>("includeOffered") == true))
                    "save" -> save(files, text("id"), text("name"), text("mime"), result)
                    "share" -> share(files, text("id"), text("name"), text("mime"), result)
                    else -> result.notImplemented()
                }
            } catch (e: HandoffFailure) {
                result.error(e.code, null, null)
            } catch (_: java.io.IOException) {
                result.error("artifact_transfer_storage", null, null)
            } catch (_: Exception) {
                result.error("artifact_transfer_unavailable", null, null)
            }
        }
    }

    private fun save(
        files: ArtifactTransferFiles,
        id: String,
        name: String,
        mime: String,
        result: MethodChannel.Result,
    ) {
        val metadata = files.metadata(id)
        if (!metadata.ready) throw HandoffFailure("artifact_transfer_incomplete")
        if (metadata.name != name || metadata.mime != mime) throw HandoffFailure("artifact_transfer_conflict")
        files.readable(id)
        synchronized(saveLock) {
            if (pendingSave != null) throw HandoffFailure("artifact_transfer_busy")
            pendingSave = result
            pendingId = id
        }
        handler.post {
            try {
                if (disposed) throw HandoffFailure("artifact_transfer_interrupted")
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime
                    putExtra(Intent.EXTRA_TITLE, name)
                    addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                activity.startActivityForResult(intent, SAVE_REQUEST)
            } catch (_: Exception) {
                clearPending()
                handler.post { result.error("artifact_transfer_save_unavailable", null, null) }
            }
        }
    }

    private fun share(
        files: ArtifactTransferFiles,
        id: String,
        name: String,
        mime: String,
        result: MethodChannel.Result,
    ) {
        val metadata = files.metadata(id)
        if (!metadata.ready) throw HandoffFailure("artifact_transfer_incomplete")
        if (metadata.name != name || metadata.mime != mime) throw HandoffFailure("artifact_transfer_conflict")
        files.readable(id)
        val uri = ArtifactStorage.uri(activity, id)
        activity.runOnUiThread {
            try {
                files.offerTo(id) {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = mime
                        putExtra(Intent.EXTRA_STREAM, uri)
                        clipData = ClipData.newRawUri(name, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    activity.startActivity(
                        Intent.createChooser(send, null).apply { addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) },
                    )
                }
                result.success(true)
            } catch (_: Exception) {
                result.error("artifact_transfer_share_unavailable", null, null)
            }
        }
    }

    /** Returns true when this request code belongs to the artifact bridge. */
    fun activityResult(request: Int, result: Int, data: Intent?): Boolean {
        if (request != SAVE_REQUEST || disposed) return false
        val id: String?
        val pending: MethodChannel.Result?
        synchronized(saveLock) {
            id = pendingId
            pending = pendingSave
            pendingId = null
            pendingSave = null
        }
        if (id == null) return true
        val destination = data?.data
        if (result != Activity.RESULT_OK || destination == null) {
            handler.post { pending?.success(false) }
            return true
        }
        worker.execute {
            var failure: String? = null
            try {
                val files = ArtifactStorage.files(activity.applicationContext)
                val source = files.readable(id)
                val output = activity.applicationContext.contentResolver.openOutputStream(destination, "w")
                    ?: throw HandoffFailure("artifact_transfer_save_unavailable")
                source.inputStream().use { input ->
                    output.use { out ->
                        val buffer = ByteArray(ArtifactTransferFiles.CHUNK_BYTES)
                        try {
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                out.write(buffer, 0, count)
                            }
                            out.flush()
                        } finally {
                            buffer.fill(0)
                        }
                    }
                }
            } catch (e: HandoffFailure) {
                failure = e.code
            } catch (_: java.io.IOException) {
                failure = "artifact_transfer_storage"
            } catch (_: Exception) {
                failure = "artifact_transfer_save_failed"
            }
            val code = failure
            handler.post {
                if (code == null) pending?.success(true)
                else pending?.error(code, null, null)
            }
        }
        return true
    }

    private fun clearPending() {
        synchronized(saveLock) {
            pendingId = null
            pendingSave = null
        }
    }

    fun dispose() {
        disposed = true
        val pending: MethodChannel.Result?
        synchronized(saveLock) {
            pending = pendingSave
            pendingId = null
            pendingSave = null
        }
        pending?.error("artifact_transfer_interrupted", null, null)
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
}

/** Android grants this provider only to the receiver selected in the OS sheet. */
class ArtifactTransferProvider : ContentProvider() {
    override fun onCreate() = true

    private fun id(uri: Uri): String {
        val context = context ?: throw FileNotFoundException()
        if (uri.scheme != "content" ||
            uri.authority != "${context.packageName}.artifact_transfer" ||
            uri.pathSegments.size != 1 ||
            uri.query != null ||
            uri.fragment != null) throw FileNotFoundException()
        return uri.pathSegments.single()
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException()
        try {
            return ParcelFileDescriptor.open(
                ArtifactStorage.files(requireNotNull(context)).readable(id(uri)),
                ParcelFileDescriptor.MODE_READ_ONLY,
            )
        } catch (_: Exception) {
            throw FileNotFoundException()
        }
    }

    override fun getType(uri: Uri): String? = try {
        val files = ArtifactStorage.files(requireNotNull(context))
        val id = id(uri)
        files.readable(id)
        files.metadata(id).mime
    } catch (_: Exception) {
        null
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = try {
        val files = ArtifactStorage.files(requireNotNull(context))
        val id = id(uri)
        val source = files.readable(id)
        val metadata = files.metadata(id)
        val columns = (projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE))
            .filter { it == OpenableColumns.DISPLAY_NAME || it == OpenableColumns.SIZE }
        MatrixCursor(columns.toTypedArray(), 1).apply {
            addRow(
                columns.map<String, Any> {
                    if (it == OpenableColumns.DISPLAY_NAME) metadata.name else source.length()
                }.toTypedArray(),
            )
        }
    } catch (_: Exception) {
        null
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw SecurityException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) =
        throw SecurityException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = throw SecurityException()
}
