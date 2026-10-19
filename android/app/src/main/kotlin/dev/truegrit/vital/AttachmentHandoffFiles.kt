package dev.truegrit.vital

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

internal class HandoffFailure(val code: String) : Exception()
internal data class HandoffMetadata(val id: String, val name: String, val mime: String,
    val expiresAt: Long, val ready: Boolean = false, val offered: Boolean = false, val sha256: String = "")

/** Only explicit external copies live here. Originals remain in encrypted storage. */
internal class AttachmentHandoffFiles(private val directory: File, private val now: () -> Long,
    private val syncDirectory: (File) -> Unit = {}, private val protectFile: ((File, Boolean) -> Unit)? = null) {
    companion object {
        const val MAX_BYTES = 16777216L
        const val CHUNK_BYTES = 65536
        const val LIFETIME = 86400000L
        const val MAX_RETAINED = 4
        private val pattern = Regex("[A-Za-z0-9_-]{1,128}")
        private val digestPattern = Regex("[a-f0-9]{64}")
    }
    private fun id(id: String): String {
        if (!pattern.matches(id)) throw HandoffFailure("attachment_identity")
        return id
    }
    private fun file(id: String, suffix: String) = File(directory, "${id(id)}.$suffix")
    private fun protect(file: File, folder: Boolean = false) {
        protectFile?.let { it(file, folder); return }
        if (!file.setReadable(false, false) || !file.setWritable(false, false) ||
            !file.setExecutable(false, false) || !file.setReadable(true, true) ||
            !file.setWritable(true, true) || (folder && !file.setExecutable(true, true))) {
            throw HandoffFailure("attachment_handoff_unavailable")
        }
    }
    private fun prepare() {
        if (!directory.isDirectory && !directory.mkdirs()) throw HandoffFailure("attachment_handoff_unavailable")
        protect(directory, true)
    }
    private fun save(m: HandoffMetadata) {
        prepare()
        val next = file(m.id, "next")
        FileOutputStream(next).use { out ->
            protect(next)
            val data = DataOutputStream(out)
            data.writeInt(0x56483136); data.writeInt(1)
            data.writeUTF(m.id); data.writeUTF(m.name); data.writeUTF(m.mime)
            data.writeLong(m.expiresAt); data.writeBoolean(m.ready); data.writeBoolean(m.offered); data.writeUTF(m.sha256)
            data.flush(); out.fd.sync()
        }
        if (!next.renameTo(file(m.id, "meta"))) throw HandoffFailure("attachment_handoff_unavailable")
        syncDirectory(directory)
    }
    fun metadata(id: String): HandoffMetadata {
        val source = file(id, "meta")
        if (!source.isFile || source.length() > 2048) throw HandoffFailure("attachment_handoff_missing")
        val m = try { DataInputStream(FileInputStream(source)).use { data ->
            if (data.readInt() != 0x56483136 || data.readInt() != 1) throw HandoffFailure("attachment_handoff_invalid")
            HandoffMetadata(data.readUTF(), data.readUTF(), data.readUTF(), data.readLong(), data.readBoolean(), data.readBoolean(), data.readUTF())
                .also { if (data.read() != -1) throw HandoffFailure("attachment_handoff_invalid") }
        } } catch (e: HandoffFailure) { throw e } catch (_: Exception) { throw HandoffFailure("attachment_handoff_invalid") }
        if (m.id != id || m.name.length !in 1..255 || m.mime.length !in 1..128) throw HandoffFailure("attachment_handoff_invalid")
        return m
    }
    @Synchronized fun begin(id: String, name: String, mime: String, expiresAt: Long) {
        id(id); prepare(); cleanup()
        if (name.length !in 1..255 || name.any { it == '/' || it == '\\' || it.code < 32 } ||
            mime.length !in 1..128 || !Regex("[A-Za-z0-9.+_-]+/[A-Za-z0-9.+_-]+").matches(mime) ||
            expiresAt <= now() || expiresAt > now() + LIFETIME) throw HandoffFailure("attachment_handoff_input")
        if (file(id, "meta").exists()) throw HandoffFailure("attachment_handoff_conflict")
        if ((directory.listFiles()?.count { it.name.endsWith(".meta") } ?: 0) >= MAX_RETAINED) throw HandoffFailure("attachment_handoff_capacity")
        // Inventory precedes bytes so interrupted writes remain attributable.
        save(HandoffMetadata(id, name, mime, expiresAt))
        FileOutputStream(file(id, "part")).use { protect(file(id, "part")); it.fd.sync() }
        syncDirectory(directory)
    }
    @Synchronized fun append(id: String, offset: Long, bytes: ByteArray): Long {
        val m = live(id)
        if (m.ready || bytes.isEmpty() || bytes.size > CHUNK_BYTES || offset < 0 || offset > MAX_BYTES - bytes.size) throw HandoffFailure("attachment_handoff_input")
        RandomAccessFile(file(id, "part"), "rw").use { out ->
            if (out.length() != offset) {
                if (offset + bytes.size > out.length()) throw HandoffFailure("attachment_handoff_conflict")
                val prior = ByteArray(bytes.size); out.seek(offset); out.readFully(prior)
                if (!MessageDigest.isEqual(prior, bytes)) throw HandoffFailure("attachment_handoff_conflict")
                return out.length()
            }
            out.seek(offset); out.write(bytes); out.fd.sync()
            return out.length()
        }
    }
    @Synchronized fun publish(id: String, bytes: Long, sha256: String) {
        val m = live(id)
        if (bytes !in 1..MAX_BYTES || !digestPattern.matches(sha256)) throw HandoffFailure("attachment_handoff_input")
        if (m.ready) { if (m.sha256 != sha256 || readable(id).length() != bytes) throw HandoffFailure("attachment_handoff_conflict"); return }
        val part = file(id, "part")
        if (!part.isFile || part.length() != bytes) throw HandoffFailure("attachment_handoff_incomplete")
        val hash = MessageDigest.getInstance("SHA-256")
        FileInputStream(part).use { input -> val buffer = ByteArray(CHUNK_BYTES); while (true) {
            val count = input.read(buffer); if (count < 0) break; hash.update(buffer, 0, count)
        }; buffer.fill(0) }
        val actual = hash.digest().joinToString("") { "%02x".format(it) }
        if (actual != sha256) throw HandoffFailure("attachment_handoff_integrity")
        if (!part.renameTo(file(id, "bin"))) throw HandoffFailure("attachment_handoff_unavailable")
        syncDirectory(directory)
        save(m.copy(ready = true, sha256 = sha256))
    }
    private fun live(id: String): HandoffMetadata = metadata(id).also {
        if (it.expiresAt <= now()) {
            remove(it.id)
            throw HandoffFailure("attachment_handoff_expired")
        }
    }
    @Synchronized fun readable(id: String): File {
        val m = live(id)
        val source = file(id, "bin")
        if (!m.ready || !source.isFile || source.length() !in 1..MAX_BYTES) throw HandoffFailure("attachment_handoff_incomplete")
        return source
    }
    @Synchronized fun offer(id: String): HandoffMetadata {
        val m = live(id); readable(id); save(m.copy(offered = true)); return m
    }
    /** A failed dispatch withdraws only a new offer; earlier receivers retain access. */
    @Synchronized fun offerTo(id: String, launch: (HandoffMetadata) -> Unit) {
        val prior = live(id)
        readable(id)
        save(prior.copy(offered = true))
        try { launch(prior) }
        catch (failure: Exception) {
            if (!prior.offered) remove(id)
            throw failure
        }
    }
    @Synchronized fun cancel(id: String): Boolean {
        id(id)
        if (!directory.exists()) return true
        val m = try { metadata(id) } catch (failure: HandoffFailure) {
            if (failure.code != "attachment_handoff_missing" && failure.code != "attachment_handoff_invalid") throw failure
            remove(id)
            return true
        }
        // Once offered, a receiver may still be opening the stream.
        if (m.offered && m.expiresAt > now()) return false
        remove(m.id); return true
    }
    private fun remove(id: String) {
        var changed = false
        for (suffix in listOf("part", "bin", "next", "meta")) {
            val source = file(id, suffix)
            if (source.exists()) {
                if (!source.delete()) throw HandoffFailure("attachment_handoff_unavailable")
                changed = true
            }
        }
        if (changed) syncDirectory(directory)
    }
    @Synchronized fun cleanup(): List<String> {
        if (!directory.exists()) return emptyList()
        val removed = mutableListOf<String>()
        for (entry in directory.listFiles().orEmpty().filter { it.name.endsWith(".meta") }) {
            val identity = entry.name.removeSuffix(".meta")
            if (!pattern.matches(identity)) continue
            val m = try { metadata(identity) } catch (_: HandoffFailure) {
                remove(identity); removed.add(identity); continue
            }
            // A crash after part -> bin but before ready metadata cannot be replayed.
            if (m.expiresAt <= now() || (!m.ready && !file(identity, "part").isFile)) {
                remove(identity); removed.add(identity)
            }
        }
        // Only this store's reserved .next names are repairable without metadata.
        for (entry in directory.listFiles().orEmpty().filter { it.name.endsWith(".next") }) {
            val identity = entry.name.removeSuffix(".next")
            if (pattern.matches(identity) && !file(identity, "meta").exists()) {
                if (!entry.delete()) throw HandoffFailure("attachment_handoff_unavailable")
                syncDirectory(directory)
                removed.add(identity)
            }
        }
        return removed
    }
}
