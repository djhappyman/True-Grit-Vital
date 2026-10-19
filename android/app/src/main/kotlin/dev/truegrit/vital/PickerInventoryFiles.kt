package dev.truegrit.vital

import java.io.File

/** Bounded repair of this picker's fixed metadata names, never selected originals. */
internal class PickerInventoryFiles(private val directory: File) {
    private val digestPattern = Regex("[a-f0-9]{64}")
    fun clear(knownDigest: String? = null, release: (String) -> Unit) {
        val ledger = File(directory, "grant.digest")
        val digests = mutableSetOf<String>()
        if (knownDigest != null && digestPattern.matches(knownDigest)) digests.add(knownDigest)
        // AtomicFile may leave a recoverable backup after interrupted replacement.
        for (name in listOf("grant.digest", "grant.digest.bak")) {
            val source = File(directory, name)
            if (source.isFile && source.length() == 64L) {
                val value = source.readText(Charsets.US_ASCII)
                if (digestPattern.matches(value)) digests.add(value)
            }
        }
        digests.forEach(release)
        for (name in listOf("job.json", "job.json.bak", "job.json.new", "grant.digest", "grant.digest.bak", "grant.digest.new")) {
            val source = File(directory, name)
            if (source.exists() && !source.delete()) throw HandoffFailure("attachment_picker_unavailable")
        }
    }
}
