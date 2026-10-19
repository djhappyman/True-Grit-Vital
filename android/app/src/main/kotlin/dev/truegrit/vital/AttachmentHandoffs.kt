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
import android.os.ParcelFileDescriptor
import android.os.UserManager
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException

internal object HandoffStorage {
    private var instance: AttachmentHandoffFiles? = null
    @Synchronized fun files(context: Context): AttachmentHandoffFiles {
        if (context.isDeviceProtectedStorage || !(context.getSystemService(Context.USER_SERVICE) as UserManager).isUserUnlocked) throw HandoffFailure("protected_storage_unavailable")
        return instance ?: AttachmentHandoffFiles(File(context.noBackupFilesDir, "vital-handoff-v1"), System::currentTimeMillis, syncDirectory = ::syncDirectory, protectFile = { file, folder -> Os.chmod(file.path, if (folder) 0x1c0 else 0x180) }).also { instance = it }
    }
    /** Public Android APIs preserve the directory-only check before syncing metadata. */
    fun syncDirectory(directory: File) {
        val descriptor = Os.open(directory.path, OsConstants.O_RDONLY, 0)
        try {
            if (!OsConstants.S_ISDIR(Os.fstat(descriptor).st_mode)) {
                throw HandoffFailure("attachment_handoff_unavailable")
            }
            Os.fsync(descriptor)
        } finally {
            Os.close(descriptor)
        }
    }
    fun uri(context: Context, id: String): Uri = Uri.Builder().scheme("content").authority("${context.packageName}.attachment_handoff").appendPath(id).build()
}

/** No storage permission, persistent recipient, writable grant or silent destination. */
internal class AttachmentHandoffs(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "true_grit_vital/attachment_handoff", io.flutter.plugin.common.StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
    init { channel.setMethodCallHandler { call, result ->
        try {
            val files = HandoffStorage.files(activity.applicationContext)
            fun text(key: String) = call.argument<String>(key) ?: throw HandoffFailure("attachment_handoff_input")
            fun number(key: String) = call.argument<Number>(key)?.toLong() ?: throw HandoffFailure("attachment_handoff_input")
            when (call.method) {
                "begin" -> { files.begin(text("id"), text("name"), text("mime"), number("expiresAt")); result.success(null) }
                "append" -> { val bytes = call.argument<ByteArray>("bytes") ?: throw HandoffFailure("attachment_handoff_input")
                    try { result.success(files.append(text("id"), number("offset"), bytes)) } finally { bytes.fill(0) } }
                "publish" -> { files.publish(text("id"), number("bytes"), text("sha256")); result.success(null) }
                "cancel" -> result.success(files.cancel(text("id")))
                "cleanup" -> result.success(files.cleanup())
                "share" -> {
                    val id = text("id")
                    files.readable(id)
                    val uri = HandoffStorage.uri(activity, id)
                    activity.runOnUiThread {
                        try {
                            files.offerTo(id) { metadata ->
                                val send = Intent(Intent.ACTION_SEND).apply {
                                    type = metadata.mime
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    clipData = ClipData.newRawUri(metadata.name, uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                activity.startActivity(Intent.createChooser(send, null).apply { addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) })
                            }
                            result.success(true)
                        } catch (_: Exception) { result.error("attachment_handoff_unavailable", null, null) }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: HandoffFailure) { result.error(e.code, null, null) }
        catch (_: Exception) { result.error("attachment_handoff_unavailable", null, null) }
    } }
    fun dispose() { channel.setMethodCallHandler(null) }
}

/** Android grants this provider only to the receiver selected in the OS sheet. */
class AttachmentHandoffProvider : ContentProvider() {
    override fun onCreate() = true
    private fun id(uri: Uri): String {
        val context = context ?: throw FileNotFoundException()
        if (uri.scheme != "content" || uri.authority != "${context.packageName}.attachment_handoff" || uri.pathSegments.size != 1 || uri.query != null || uri.fragment != null) throw FileNotFoundException()
        return uri.pathSegments.single()
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException()
        try { return ParcelFileDescriptor.open(HandoffStorage.files(requireNotNull(context)).readable(id(uri)), ParcelFileDescriptor.MODE_READ_ONLY) }
        catch (_: Exception) { throw FileNotFoundException() }
    }
    override fun getType(uri: Uri): String? = try {
        val files = HandoffStorage.files(requireNotNull(context)); val id = id(uri)
        files.readable(id); files.metadata(id).mime
    } catch (_: Exception) { null }
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        return try {
            val files = HandoffStorage.files(requireNotNull(context)); val id = id(uri)
            val source = files.readable(id); val metadata = files.metadata(id)
            val columns = (projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)).filter { it == OpenableColumns.DISPLAY_NAME || it == OpenableColumns.SIZE }
            MatrixCursor(columns.toTypedArray(), 1).apply { addRow(columns.map<String, Any> { if (it == OpenableColumns.DISPLAY_NAME) metadata.name else source.length() }.toTypedArray()) }
        } catch (_: Exception) { null }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw SecurityException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = throw SecurityException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = throw SecurityException()
}
