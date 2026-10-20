package dev.truegrit.vital

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest

fun main() {
    var passed = 0
    fun test(name: String, body: (File) -> Unit) {
        val root = Files.createTempDirectory("vital-artifact-test-").toFile()
        try {
            body(root)
            passed++
            println("PASS $name")
        } catch (e: Throwable) {
            throw AssertionError("FAIL $name", e)
        } finally {
            root.deleteRecursively()
        }
    }

    val bytes = "synthetic generated artifact".toByteArray()
    val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    fun stage(files: ArtifactTransferFiles, id: String, expiry: Long = 5000) {
        files.begin(id, "vital-summary.pdf", "application/pdf", bytes.size.toLong(), expiry)
        files.append(id, 0, bytes)
        files.publish(id, bytes.size.toLong(), hash)
    }

    test("partial copies never become readable and offsets are idempotent") { root ->
        val files = ArtifactTransferFiles(root, { 1000 })
        files.begin("one", "vital-summary.pdf", "application/pdf", bytes.size.toLong(), 5000)
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
        val files = ArtifactTransferFiles(root, { clock })
        stage(files, "one")
        files.offerTo("one") { }
        stage(files, "two")
        files.offerTo("two") { }
        check(!files.cancel("one"))
        val reopened = ArtifactTransferFiles(root, { clock })
        check(reopened.readable("one").readBytes().contentEquals(bytes))
        clock = 5001
        check(runCatching { reopened.readable("one") }.isFailure)
        // The failed read already removed the expired copy it was asked for.
        check(reopened.cleanup(null).toSet() == setOf("two"))
        check(root.listFiles().orEmpty().isEmpty())
    }

    test("cancellation deletes only a known unoffered artifact") { root ->
        val files = ArtifactTransferFiles(root, { 1000 })
        val unrelated = File(root, "unknown-file").apply { writeText("preserve") }
        files.begin("one", "vital-summary.pdf", "application/pdf", bytes.size.toLong(), 5000)
        files.append("one", 0, bytes)
        check(files.cancel("one"))
        check(unrelated.readText() == "preserve")
        check(files.cleanup(null).isEmpty())
    }

    test("hostile names, declared sizes and chunk overflow fail closed") { root ->
        val files = ArtifactTransferFiles(root, { 1000 })
        check(runCatching { files.begin("../outside", "vital-summary.pdf", "application/pdf", 1, 5000) }.isFailure)
        check(runCatching { files.begin("one", "../alice.pdf", "application/pdf", 1, 5000) }.isFailure)
        check(runCatching { files.begin("one", "Alice report.pdf", "application/pdf", 1, 5000) }.isFailure)
        check(runCatching { files.begin("one", "vital-summary.pdf", "pdf", 1, 5000) }.isFailure)
        check(runCatching { files.begin("one", "vital-summary.pdf", "application/pdf", 0, 5000) }.isFailure)
        check(runCatching { files.begin("one", "vital-summary.pdf", "application/pdf", ArtifactTransferFiles.MAX_BYTES + 1, 5000) }.isFailure)
        files.begin("one", "vital-summary.pdf", "application/pdf", ArtifactTransferFiles.MAX_BYTES, 5000)
        check(runCatching { files.append("one", 0, ByteArray(ArtifactTransferFiles.CHUNK_BYTES + 1)) }.isFailure)
        check(runCatching { files.append("one", ArtifactTransferFiles.MAX_BYTES, ByteArray(1)) }.isFailure)
    }

    test("retained offered copies bound capacity until expiry") { root ->
        var clock = 1000L
        val files = ArtifactTransferFiles(root, { clock })
        stage(files, "one"); files.offerTo("one") { }
        stage(files, "two"); files.offerTo("two") { }
        check(runCatching { stage(files, "three", 5000) }.isFailure)
        check(files.cleanup("three").isEmpty())
        clock = 5001
        check(files.cleanup(null).toSet() == setOf("one", "two"))
    }

    test("explicit discard removes offered copies after dataset replacement") { root ->
        val files = ArtifactTransferFiles(root, { 1000 })
        stage(files, "one"); files.offerTo("one") { }
        check(files.cleanup(null).isEmpty())
        check(files.cleanup(null, true).toSet() == setOf("one"))
        check(root.listFiles().orEmpty().isEmpty())
    }

    test("startup cleanup removes unpublished and unoffered copies but preserves the active id") { root ->
        val partialRoot = File(root, "partial").apply { mkdirs() }
        val partial = ArtifactTransferFiles(partialRoot, { 1000 })
        partial.begin("partial", "vital-export.csv", "text/csv", 64, 5000)
        partial.append("partial", 0, ByteArray(32))
        check(partial.cleanup(null).toSet() == setOf("partial"))
        check(partialRoot.listFiles().orEmpty().isEmpty())

        val readyRoot = File(root, "ready").apply { mkdirs() }
        val ready = ArtifactTransferFiles(readyRoot, { 1000 })
        stage(ready, "ready")
        check(ready.cleanup("ready").isEmpty())
        check(ready.readable("ready").readBytes().contentEquals(bytes))
        check(ready.cleanup(null).toSet() == setOf("ready"))
        check(readyRoot.listFiles().orEmpty().isEmpty())
    }
}
