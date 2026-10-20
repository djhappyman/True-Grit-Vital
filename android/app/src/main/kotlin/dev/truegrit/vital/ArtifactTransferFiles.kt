package dev.truegrit.vital

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

/**
 * Bounded protected staging for generated artifacts (reports, exports, backups).
 *
 * This is deliberately separate from [AttachmentHandoffFiles]: a generated
 * export is not a saved source attachment and must not consume or overwrite the
 * attachment handoff inventory.
 */
internal class ArtifactTransferFiles(private val directory: File, private val now: () -> Long,
    private val syncDirectory: (File) -> Unit = {}, private val protectFile: ((File, Boolean) -> Unit)? = null) {
    companion object {
        const val MAX_BYTES = 536870912L
        const val CHUNK_BYTES = 65536
        const val LIFETIME = 86400000L
        const val MAX_RETAINED = 2
        const val MAGIC = 0x41543136
        const val VERSION = 1
        private val identity = Regex("[A-Za-z0-9_-]{1,128}")
        private val namePattern = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,79}")
        private val mimePattern = Regex("[A-Za-z0-9.+_-]+/[A-Za-z0-9.+_-]+")
        private val digestPattern = Regex("[a-f0-9]{64}")
    }

    private fun id(id: String): String {
        if (!identity.matches(id) || id.contains("..")) throw HandoffFailure("artifact_transfer_identity")
        return id
    }

    private fun file(id: String, suffix: String) = File(directory, "${id(id)}.$suffix")
    private fun protect(file: File, folder: Boolean = false) {
        protectFile?.let { it(file, folder); return }
        if (!file.setReadable(false, false) || !file.setWritable(false, false) ||
            !file.setExecutable(false, false) || !file.setReadable(true, true) ||
            !file.setWritable(true, true) || (folder && !file.setExecutable(true, true))) {
            throw HandoffFailure("artifact_transfer_storage")
        }
    }

    private fun prepare() {
        if (!directory.isDirectory && !directory.mkdirs()) throw HandoffFailure("artifact_transfer_storage")
        protect(directory, true)
    }

    private fun save(m: ArtifactMetadata) {
        prepare()
        val next = file(m.id, "next")
        FileOutputStream(next).use { out ->
            protect(next)
            val data = DataOutputStream(out)
            data.writeInt(MAGIC); data.writeInt(VERSION)
            data.writeUTF(m.id); data.writeUTF(m.name); data.writeUTF(m.mime)
            data.writeLong(m.byteCount); data.writeLong(m.expiresAt)
            data.writeBoolean(m.ready); data.writeBoolean(m.offered); data.writeUTF(m.sha256)
            data.flush(); out.fd.sync()
        }
        if (!next.renameTo(file(m.id, "meta"))) throw HandoffFailure("artifact_transfer_storage")
        syncDirectory(directory)
    }

    fun metadata(id: String): ArtifactMetadata {
        val source = file(id, "meta")
        if (!source.isFile || source.length() > 2048) throw HandoffFailure("artifact_transfer_missing")
        val m = try {
            DataInputStream(FileInputStream(source)).use { data ->
                if (data.readInt() != MAGIC || data.readInt() != VERSION) throw HandoffFailure("artifact_transfer_incomplete")
                ArtifactMetadata(data.readUTF(), data.readUTF(), data.readUTF(), data.readLong(), data.readLong(),
                    data.readBoolean(), data.readBoolean(), data.readUTF())
                    .also { if (data.read() != -1) throw HandoffFailure("artifact_transfer_incomplete") }
            }
        } catch (e: HandoffFailure) {
            throw e
        } catch (_: Exception) {
            throw HandoffFailure("artifact_transfer_incomplete")
        }
        if (m.id != id || !namePattern.matches(m.name) || m.name.contains("..") ||
            m.mime.length !in 1..128 || !mimePattern.matches(m.mime) ||
            m.byteCount !in 1..MAX_BYTES ||
            (m.ready && !digestPattern.matches(m.sha256))) throw HandoffFailure("artifact_transfer_incomplete")
        return m
    }

    @Synchronized
    fun begin(id: String, name: String, mime: String, byteCount: Long, expiresAt: Long) {
        id(id)
        if (!namePattern.matches(name) || name.contains("..") ||
            mime.length !in 1..128 || !mimePattern.matches(mime) ||
            byteCount !in 1..MAX_BYTES ||
            expiresAt <= now() || expiresAt > now() + LIFETIME) throw HandoffFailure("artifact_transfer_input")
        prepare(); cleanup(id)
        if (file(id, "meta").exists() || file(id, "part").exists()) throw HandoffFailure("artifact_transfer_conflict")
        if ((directory.listFiles()?.count { it.name.endsWith(".meta") } ?: 0) >= MAX_RETAINED) {
            throw HandoffFailure("artifact_transfer_capacity")
        }
        // Inventory precedes bytes so an interrupted write remains attributable.
        save(ArtifactMetadata(id, name, mime, byteCount, expiresAt))
        FileOutputStream(file(id, "part")).use { protect(file(id, "part")); it.fd.sync() }
        syncDirectory(directory)
    }

    @Synchronized
    fun append(id: String, offset: Long, bytes: ByteArray): Long {
        val m = live(id)
        if (m.ready || bytes.isEmpty() || bytes.size > CHUNK_BYTES ||
            offset < 0 || offset > m.byteCount - bytes.size) throw HandoffFailure("artifact_transfer_input")
        RandomAccessFile(file(id, "part"), "rw").use { out ->
            val length = out.length()
            if (length > m.byteCount) throw HandoffFailure("artifact_transfer_incomplete")
            if (offset != length) {
                if (offset > length || offset + bytes.size > length) throw HandoffFailure("artifact_transfer_conflict")
                val prior = ByteArray(bytes.size); out.seek(offset); out.readFully(prior)
                if (!MessageDigest.isEqual(prior, bytes)) throw HandoffFailure("artifact_transfer_conflict")
                return length
            }
            if (offset + bytes.size > MAX_BYTES) throw HandoffFailure("artifact_transfer_input")
            out.seek(offset); out.write(bytes); out.fd.sync()
            return length + bytes.size
        }
    }

    @Synchronized
    fun publish(id: String, byteCount: Long, sha256: String) {
        val m = live(id)
        if (!digestPattern.matches(sha256)) throw HandoffFailure("artifact_transfer_input")
        if (m.ready) {
            if (m.sha256 != sha256 || readable(id).length() != byteCount) throw HandoffFailure("artifact_transfer_conflict")
            return
        }
        if (byteCount != m.byteCount) throw HandoffFailure("artifact_transfer_input")
        val part = file(id, "part")
        if (!part.isFile || part.length() != byteCount) throw HandoffFailure("artifact_transfer_incomplete")
        val hash = MessageDigest.getInstance("SHA-256")
        FileInputStream(part).use { input ->
            val buffer = ByteArray(CHUNK_BYTES)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
            buffer.fill(0)
        }
        val actual = hash.digest().joinToString("") { "%02x".format(it) }
        if (actual != sha256) throw HandoffFailure("artifact_transfer_integrity")
        if (!part.renameTo(file(id, "bin"))) throw HandoffFailure("artifact_transfer_storage")
        syncDirectory(directory)
        save(m.copy(ready = true, sha256 = sha256))
    }

    private fun live(id: String): ArtifactMetadata = metadata(id).also {
        if (it.expiresAt <= now()) {
            remove(it.id)
            throw HandoffFailure("artifact_transfer_expired")
        }
    }

    @Synchronized
    fun readable(id: String): File {
        val m = live(id)
        val source = file(id, "bin")
        if (!m.ready || !source.isFile || source.length() !in 1..MAX_BYTES || source.length() != m.byteCount) {
            throw HandoffFailure("artifact_transfer_incomplete")
        }
        return source
    }

    /** A failed dispatch withdraws only a new offer; earlier receivers retain access. */
    @Synchronized
    fun offerTo(id: String, launch: (ArtifactMetadata) -> Unit) {
        val prior = live(id)
        readable(id)
        save(prior.copy(offered = true))
        try {
            launch(prior)
        } catch (failure: Exception) {
            if (!prior.offered) remove(id)
            throw failure
        }
    }

    @Synchronized
    fun cancel(id: String): Boolean {
        id(id)
        if (!directory.exists()) return true
        val m = try { metadata(id) } catch (failure: HandoffFailure) {
            if (failure.code != "artifact_transfer_missing" && failure.code != "artifact_transfer_incomplete") throw failure
            remove(id)
            return true
        }
        if (m.offered && m.expiresAt > now()) return false
        remove(m.id)
        return true
    }

    private fun remove(id: String) {
        var changed = false
        for (suffix in listOf("part", "bin", "next", "meta")) {
            val source = file(id, suffix)
            if (source.exists()) {
                if (!source.delete()) throw HandoffFailure("artifact_transfer_storage")
                changed = true
            }
        }
        if (changed) syncDirectory(directory)
    }

    @Synchronized
    fun cleanup(preserve: String?, includeOffered: Boolean = false): List<String> {
        if (preserve != null) id(preserve)
        if (!directory.exists()) return emptyList()
        val removed = mutableListOf<String>()
        val entries = directory.listFiles().orEmpty()
        if (entries.size > 64) throw HandoffFailure("artifact_transfer_storage")
        val known = mutableSetOf<String>()
        for (entry in entries.filter { it.name.endsWith(".meta") }) {
            val candidate = entry.name.removeSuffix(".meta")
            if (!ArtifactTransferFiles.identity.matches(candidate)) {
                if (entry.isFile && entry.delete()) removed.add(candidate)
                continue
            }
            known.add(candidate)
            val m = try { metadata(candidate) } catch (_: HandoffFailure) {
                remove(candidate); removed.add(candidate); continue
            }
            if (m.expiresAt <= now() || (!m.ready && candidate != preserve) ||
                (m.ready && candidate != preserve && (includeOffered || !m.offered))) {
                remove(candidate); removed.add(candidate)
            }
        }
        // Only this store's reserved names are reclaimable without metadata.
        for (entry in entries) {
            val suffix = listOf(".part", ".bin", ".next").firstOrNull { entry.name.endsWith(it) } ?: continue
            val candidate = entry.name.removeSuffix(suffix)
            if (known.contains(candidate) || !ArtifactTransferFiles.identity.matches(candidate)) continue
            if (entry.isFile && entry.delete()) {
                syncDirectory(directory)
                removed.add(candidate)
            }
        }
        return removed
    }
}

internal data class ArtifactMetadata(val id: String, val name: String, val mime: String,
    val byteCount: Long, val expiresAt: Long, val ready: Boolean = false,
    val offered: Boolean = false, val sha256: String = "")
