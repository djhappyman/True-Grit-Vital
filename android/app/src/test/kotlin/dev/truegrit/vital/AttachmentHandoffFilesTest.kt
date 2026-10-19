package dev.truegrit.vital

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest

fun main() {
    var passed = 0
    fun test(name: String, body: (File) -> Unit) {
        val root = Files.createTempDirectory("vital-handoff-test-").toFile()
        try { body(root); passed++; println("PASS $name") }
        catch (e: Throwable) { throw AssertionError("FAIL $name", e) }
        finally { root.deleteRecursively() }
    }
    val bytes = "synthetic original".toByteArray()
    val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    fun stage(files: AttachmentHandoffFiles, id: String, expiry: Long = 5000) {
        files.begin(id, "Original.pdf", "application/pdf", expiry)
        files.append(id, 0, bytes); files.publish(id, bytes.size.toLong(), hash)
    }
    test("partial copies never become readable and offsets are idempotent") { root ->
        val files = AttachmentHandoffFiles(root, { 1000 })
        files.begin("one", "Original.pdf", "application/pdf", 5000)
        check(runCatching { files.readable("one") }.isFailure)
        check(files.append("one", 0, bytes) == bytes.size.toLong())
        check(files.append("one", 0, bytes) == bytes.size.toLong())
        check(runCatching { files.append("one", 0, "wrong".toByteArray()) }.isFailure)
        check(runCatching { files.publish("one", bytes.size.toLong(), "0".repeat(64)) }.isFailure)
        files.publish("one", bytes.size.toLong(), hash)
        check(files.readable("one").readBytes().contentEquals(bytes))
        check(runCatching { files.publish("one", bytes.size.toLong(), "0".repeat(64)) }.isFailure)
    }
    test("a second share preserves the first receiver and process restart") { root ->
        var clock = 1000L
        val files = AttachmentHandoffFiles(root, { clock })
        stage(files, "one"); files.offer("one")
        stage(files, "two"); files.offer("two")
        check(!files.cancel("one"))
        val reopened = AttachmentHandoffFiles(root, { clock })
        check(reopened.readable("one").readBytes().contentEquals(bytes))
        clock = 5001
        check(runCatching { reopened.readable("one") }.isFailure)
        check(reopened.cleanup().toSet() == setOf("two"))
        check(root.listFiles().orEmpty().isEmpty())
    }
    test("cancellation deletes only a known unoffered artifact") { root ->
        val files = AttachmentHandoffFiles(root, { 1000 })
        val unrelated = File(root, "unknown-file").apply { writeText("preserve") }
        files.begin("one", "Original.pdf", "application/pdf", 5000)
        files.append("one", 0, bytes)
        check(files.cancel("one"))
        check(unrelated.readText() == "preserve")
        check(files.cleanup().isEmpty())
    }
    test("hostile names, chunk overflow and fifth retained copy fail closed") { root ->
        val files = AttachmentHandoffFiles(root, { 1000 })
        check(runCatching { files.begin("../outside", "file", "text/plain", 5000) }.isFailure)
        check(runCatching { files.begin("one", "../records.sqlite", "text/plain", 5000) }.isFailure)
        check(runCatching { files.begin("one", "file", "text/plain", 1000 + AttachmentHandoffFiles.LIFETIME + 1) }.isFailure)
        repeat(4) { stage(files, "item$it") }
        check(runCatching { stage(files, "fifth") }.isFailure)
        check(runCatching { files.append("item0", AttachmentHandoffFiles.MAX_BYTES, bytes) }.isFailure)
    }
    test("expiry cleans interrupted staging and preserves unknown files") { root ->
        var clock = 1000L
        val files = AttachmentHandoffFiles(root, { clock })
        files.begin("one", "Original.pdf", "application/pdf", 5000)
        files.append("one", 0, bytes)
        val unknown = File(root, "unrelated.bin").apply { writeText("preserve") }
        clock = 5001
        check(AttachmentHandoffFiles(root, { clock }).cleanup() == listOf("one"))
        check(unknown.readText() == "preserve")
    }
    test("every picker allocation is disjoint from guarded credentials") { _ ->
        var code = ActivityRequestCodes.FIRST_PICKER - 1
        repeat(ActivityRequestCodes.LAST_PICKER - ActivityRequestCodes.FIRST_PICKER + 1) {
            code = ActivityRequestCodes.nextPicker(code)
            check(code != ActivityRequestCodes.CREDENTIAL)
            check(ActivityRequestCodes.ownsPicker(code))
            check(!ActivityRequestCodes.acceptsCredential(code, true, true))
        }
        check(runCatching { ActivityRequestCodes.nextPicker(code) }.isFailure)
        check(!ActivityRequestCodes.acceptsCredential(ActivityRequestCodes.CREDENTIAL, false, true))
        check(!ActivityRequestCodes.acceptsCredential(ActivityRequestCodes.CREDENTIAL, true, false))
        check(ActivityRequestCodes.acceptsCredential(ActivityRequestCodes.CREDENTIAL, true, true))
        // A durable picker from before the fix remains its own picker result.
        check(!ActivityRequestCodes.acceptsPicker(0x4000, null, null))
        check(!ActivityRequestCodes.acceptsPicker(0x4000, 0x4001, "pending"))
        check(!ActivityRequestCodes.acceptsPicker(0x4000, 0x4000, "selected"))
        check(!ActivityRequestCodes.acceptsPicker(0x4000, 0x4000, "cancelled"))
        check(ActivityRequestCodes.acceptsPicker(0x4000, 0x4000, "pending"))
        check(ActivityRequestCodes.nextPicker(ActivityRequestCodes.recoveredCounterPrior(false)) == 0x8000)
        check(runCatching { ActivityRequestCodes.recoveredCounterPrior(true) }.isFailure)
        check(ActivityRequestCodes.ownsPicker(0x5649))
        check(!ActivityRequestCodes.acceptsCredential(0x5649, true, true))
    }
    test("failed dispatch withdraws a new offer but preserves an earlier receiver") { root ->
        val files = AttachmentHandoffFiles(root, { 1000 })
        stage(files, "new")
        check(runCatching { files.offerTo("new") { throw IllegalStateException("no handler") } }.isFailure)
        check(files.cancel("new"))
        check(files.cancel("never-created"))
        stage(files, "old"); files.offerTo("old") { check(files.readable("old").readBytes().contentEquals(bytes)) }
        check(runCatching { files.offerTo("old") { throw IllegalStateException("no handler") } }.isFailure)
        check(!files.cancel("old"))
        check(files.readable("old").readBytes().contentEquals(bytes))
    }
    test("known corrupt and post-rename inventories release capacity without sweeping") { root ->
        val files = AttachmentHandoffFiles(root, { 1000 })
        files.begin("rename", "Original.pdf", "application/pdf", 5000)
        files.append("rename", 0, bytes)
        check(File(root, "rename.part").renameTo(File(root, "rename.bin")))
        File(root, "corrupt.meta").writeText("broken")
        File(root, "corrupt.bin").writeBytes(bytes)
        File(root, "orphan.next").writeText("interrupted metadata")
        val unknown = File(root, "unknown.bin").apply { writeText("preserve") }
        check(files.cleanup().toSet() == setOf("rename", "corrupt", "orphan"))
        check(!File(root, "orphan.next").exists())
        check(unknown.readText() == "preserve")
        repeat(4) { stage(files, "repaired$it") }
    }
    test("picker repair releases only recorded grants and known metadata") { root ->
        val grant = "a".repeat(64)
        File(root, "job.json").writeText("broken inventory")
        File(root, "job.json.bak").writeText("broken backup")
        File(root, "grant.digest").writeText(grant)
        val counter = File(root, "counter").apply { writeText("preserve allocation fence") }
        val unknown = File(root, "other").apply { writeText("preserve") }
        val released = mutableListOf<String>()
        PickerInventoryFiles(root).clear(release = { released.add(it) })
        check(released == listOf(grant))
        check(!File(root, "job.json").exists())
        check(!File(root, "grant.digest").exists())
        check(counter.readText() == "preserve allocation fence")
        check(unknown.readText() == "preserve")
        PickerInventoryFiles(root).clear(release = { error("no remaining known grant") })
    }
    test("picker grant-release failure retains known inventory for retry") { root ->
        File(root, "job.json").writeText("known job")
        File(root, "grant.digest").writeText("b".repeat(64))
        check(runCatching { PickerInventoryFiles(root).clear(release = { throw IllegalStateException("retry") }) }.isFailure)
        check(File(root, "job.json").exists())
        check(File(root, "grant.digest").exists())
        PickerInventoryFiles(root).clear(release = {})
        check(!File(root, "job.json").exists())
    }
    println("$passed attachment handoff tests passed")
}
