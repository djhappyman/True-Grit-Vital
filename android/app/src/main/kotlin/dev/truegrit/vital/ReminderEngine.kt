package dev.truegrit.vital

/** Opaque-only ledger. Call every operation on the adapter's single serial executor. */
internal data class ReminderRequest(
    val epoch: String, val requestToken: String, val takenToken: String,
    val snoozeToken: String, val skipToken: String, val clock: String,
    val deadlineMilliseconds: Long, val bootId: String?, val purpose: String = "ordinary",
)
internal data class ReminderEntry(val request: ReminderRequest, val state: String, val reason: String? = null)
internal data class ReminderAction(val envelopeId: String, val epoch: String, val requestToken: String,
    val actionToken: String, val action: String)
internal data class ReminderLedger(
    val installation: String, val epoch: String? = null, val sequence: Long = -1,
    val snapshot: String = "", val boot: String? = null, val repairReason: String? = null,
    val retired: Set<String> = emptySet(), val entries: Map<String, ReminderEntry> = emptyMap(),
    val eligible: Set<String> = emptySet(),
    val actions: List<ReminderAction> = emptyList(), val acknowledged: Set<String> = emptySet(),
    val alert: ReminderAlert = ReminderAlert.LEGACY,
)
internal interface ReminderJournal {
    fun read(): ReminderLedger
    fun save(state: ReminderLedger)
}
internal interface ReminderEffects {
    fun nowWall(): Long
    fun nowElapsed(): Long
    fun bootId(installation: String): String?
    fun unavailableReason(alert: ReminderAlert): String?
    fun alertChangeAllowed(current: ReminderAlert): Boolean
    fun schedule(request: ReminderRequest)
    fun cancel(request: ReminderRequest)
    fun post(request: ReminderRequest, alert: ReminderAlert)
    fun pending(request: ReminderRequest): Boolean
    fun visible(request: ReminderRequest): Boolean
}
internal class ReminderFailure(val code: String) : Exception()

internal class ReminderEngine(private val journal: ReminderJournal, private val effects: ReminderEffects) {
    companion object {
        const val FINGERPRINT = "vital-android-reminders-v1"
        private val tokenPattern = Regex("[A-Za-z0-9_-]{1,128}")
        private val terminals = setOf("consumed", "cancelled", "postUncertain")
        fun token(value: String): String {
            if (!tokenPattern.matches(value)) throw ReminderFailure("invalid_arguments")
            return value
        }
    }
    private fun state(): ReminderLedger {
        val original = journal.read()
        val boot = effects.bootId(original.installation)
        if (original.boot == boot) return original
        val updated = original.copy(boot = boot, repairReason = if (original.boot == null && original.entries.isEmpty()) null else "device_restarted",
            entries = original.entries.mapValues { (_, e) ->
                if (e.state in terminals) e else e.copy(state = "unknown", reason = "device_restarted")
            })
        journal.save(updated)
        // OS alarms are cleared by boot. Never reconstruct elapsed requests here.
        return updated
    }
    fun clock(): Map<String, Any> {
        val s = state()
        val boot = effects.bootId(s.installation) ?: throw ReminderFailure("clock_unavailable")
        return mapOf("utcMilliseconds" to effects.nowWall(), "elapsedMilliseconds" to effects.nowElapsed(), "bootId" to boot)
    }
    fun repairReason(): String? = state().repairReason
    fun bootAvailable(): Boolean { val s = state(); return effects.bootId(s.installation) != null }
    /** The alert choice used when a prepared reminder is posted. */
    fun alert(): ReminderAlert = state().alert
    /** Persists the choice before the adapter creates or selects a channel. */
    fun applyAlert(alert: ReminderAlert): Boolean {
        val current = state()
        // Enforce the OS mute at the native boundary as well as in the UI.
        // Restore/startup and a stale capability read can also reach here.
        if (current.alert != alert && !effects.alertChangeAllowed(current.alert)) {
            throw ReminderFailure("channel_blocked")
        }
        journal.save(current.copy(alert = alert))
        return true
    }
    /** The epoch currently installed, so a restored dataset can hand it over. */
    fun installedEpoch(): String? = state().epoch
    fun apply(epoch: String, sequence: Long, desired: List<ReminderRequest>, obsolete: List<String>): Map<String, Any?> {
        token(epoch)
        if (sequence < 0 || desired.size > 264 || obsolete.size > 512 || desired.map { it.requestToken }.distinct().size != desired.size) {
            throw ReminderFailure("invalid_arguments")
        }
        if (desired.count { it.purpose == "eventEnd" } > 8 || desired.count { it.purpose == "stockLow" } > 8 ||
            desired.count { it.purpose == "ordinary" } > 248) throw ReminderFailure("invalid_arguments")
        desired.forEach { validate(it); if (it.epoch != epoch) throw ReminderFailure("invalid_arguments") }
        obsolete.forEach { token(it) }
        if (desired.any { it.requestToken in obsolete }) throw ReminderFailure("invalid_arguments")
        var s = state()
        val fingerprint = (desired.sortedBy { it.requestToken }.joinToString(";") { it.toString() } + "|" + obsolete.sorted().joinToString(","))
        fun reject(reason: String) = snapshot(s, false, desired.map { receipt(it.requestToken, s.entries[it.requestToken], reason) }, reason)
        if (epoch in s.retired || (s.epoch != null && s.epoch != epoch)) return reject("epoch_rejected")
        if (sequence < s.sequence) return reject("sequence_rejected")
        if (sequence == s.sequence && fingerprint != s.snapshot) return reject("sequence_conflict")
        if (desired.any { s.entries[it.requestToken]?.request?.let { old -> old != it } == true }) return reject("token_conflict")
        val tokenOwners = mutableMapOf<String, String>()
        for (r in (s.entries.values.map { it.request } + desired).distinct()) {
            for (opaque in listOf(r.requestToken, r.takenToken, r.snoozeToken, r.skipToken)) {
                val priorOwner = tokenOwners.put(opaque, r.requestToken)
                if (priorOwner != null && priorOwner != r.requestToken) return reject("token_conflict")
            }
        }
        if ((s.entries.keys + desired.map { it.requestToken }).size > 8192) return reject("journal_capacity")
        // Atomic durable fence precedes every OS effect, including cancellation.
        s = s.copy(epoch = epoch, sequence = sequence, snapshot = fingerprint, eligible = desired.map { it.requestToken }.toSet())
        journal.save(s)
        val wanted = desired.map { it.requestToken }.toSet()
        val cancel = (obsolete + s.entries.filter { (_, e) -> e.request.epoch == epoch && e.request.requestToken !in wanted && e.state !in terminals }.keys).distinct()
        s = cancelWithState(s, cancel)
        for (request in desired) {
            val prior = s.entries[request.requestToken]
            if (prior?.state in terminals) continue
            val invalid = when {
                request.clock == "elapsed" && (request.bootId == null || request.bootId != effects.bootId(s.installation)) -> "snooze_interrupted"
                request.deadlineMilliseconds <= (if (request.clock == "elapsed") effects.nowElapsed() else effects.nowWall()) -> "deadline_expired"
                else -> effects.unavailableReason(s.alert)
            }
            if (invalid != null) {
                s = put(s, ReminderEntry(request, "failed", invalid))
                try { effects.cancel(request) } catch (_: Exception) { /* Receipt remains unavailable. */ }
                continue
            }
            if (prior?.state == "accepted" && effects.pending(request)) continue
            s = put(s, ReminderEntry(request, "unknown", "registration_pending"))
            val entry = try { effects.schedule(request); ReminderEntry(request, "accepted") }
                catch (e: ReminderFailure) { ReminderEntry(request, "failed", e.code) }
                catch (_: Exception) { ReminderEntry(request, "unknown", "registration_unknown") }
            s = put(s, entry)
        }
        s = s.copy(repairReason = null)
        journal.save(s)
        return snapshot(s, true, desired.map { receipt(it.requestToken, s.entries[it.requestToken]) } +
            cancel.filter { it !in wanted }.map { receipt(it, s.entries[it]) })
    }
    private fun validate(r: ReminderRequest) {
        listOf(r.epoch, r.requestToken, r.takenToken, r.snoozeToken, r.skipToken).forEach { token(it) }
        if (listOf(r.requestToken, r.takenToken, r.snoozeToken, r.skipToken).distinct().size != 4 ||
            r.purpose !in setOf("ordinary", "eventEnd", "stockLow") ||
            ((r.purpose == "eventEnd" || r.purpose == "stockLow") && r.clock != "wall") ||
            r.clock !in setOf("wall", "elapsed") || r.deadlineMilliseconds <= 0 || (r.bootId?.length ?: 0) > 256) {
            throw ReminderFailure("invalid_arguments")
        }
    }
    private fun put(s: ReminderLedger, entry: ReminderEntry): ReminderLedger {
        val next = s.copy(entries = s.entries + (entry.request.requestToken to entry))
        journal.save(next)
        return next
    }
    private fun cancelWithState(initial: ReminderLedger, tokens: List<String>): ReminderLedger {
        var s = initial
        for (token in tokens) {
            val old = s.entries[token] ?: continue
            // A consumed receipt must retain its meaning; cancellation still dismisses its card.
            if (old.state !in terminals) s = put(s, old.copy(state = "cancelled", reason = null))
            try {
                effects.cancel(old.request)
                if (s.entries[token]?.reason == "cancellation_unknown") s = put(s, s.entries.getValue(token).copy(reason = null))
            }
            catch (_: Exception) { s = put(s, s.entries.getValue(token).copy(reason = "cancellation_unknown")) }
        }
        return s
    }
    fun cancel(tokens: List<String>): List<Map<String, Any?>> {
        if (tokens.size > 512) throw ReminderFailure("invalid_arguments")
        tokens.forEach { token(it) }
        val s = cancelWithState(state(), tokens)
        return tokens.map { receipt(it, s.entries[it]) }
    }
    fun invalidate(old: String, new: String): Boolean {
        token(old); token(new)
        if (old == new) return false
        var s = state()
        if (s.epoch == new && old in s.retired) {
            cancelWithState(s, s.entries.filterValues { it.request.epoch == old }.keys.toList())
            return true
        }
        if (s.epoch != old || new in s.retired || s.retired.size >= 1024) return false
        s = s.copy(epoch = new, sequence = -1, snapshot = "", eligible = emptySet(), retired = s.retired + old,
            actions = s.actions.filter { it.epoch != old }, repairReason = "dataset_changed")
        journal.save(s)
        cancelWithState(s, s.entries.filterValues { it.request.epoch == old }.keys.toList())
        return true
    }
    fun fire(epoch: String, token: String) {
        var s = state()
        val entry = s.entries[token] ?: return
        val r = entry.request
        if (s.epoch != epoch || r.epoch != epoch || epoch in s.retired || token !in s.eligible || entry.state != "accepted") return
        if (r.clock == "elapsed" && r.bootId != effects.bootId(s.installation)) return
        if (r.deadlineMilliseconds > if (r.clock == "elapsed") effects.nowElapsed() else effects.nowWall()) return
        // postUncertain is the durable consumed fence, even if notify or the final save crashes.
        s = put(s, entry.copy(state = "postUncertain", reason = "presentation_uncertain"))
        if (effects.unavailableReason(s.alert) != null) return
        try { effects.post(r, s.alert) } catch (_: Exception) { return }
        put(s, entry.copy(state = "consumed"))
    }
    fun inspect(tokens: List<String>): List<Map<String, Any?>> {
        if (tokens.size > 512) throw ReminderFailure("invalid_arguments")
        tokens.forEach { token(it) }
        val s = state()
        return tokens.map { key ->
            val e = s.entries[key]
            receipt(key, e) + mapOf("pendingIntentPresent" to (e?.let { effects.pending(it.request) } ?: false),
                "notificationVisible" to (e?.let { effects.visible(it.request) } ?: false))
        }
    }
    fun capture(epoch: String, requestToken: String, actionToken: String, action: String): Boolean {
        val s = state()
        val e = s.entries[requestToken] ?: return false
        if (epoch != s.epoch || epoch != e.request.epoch || epoch in s.retired || e.state == "cancelled") return false
        if (requestToken !in s.eligible || (e.request.purpose != "ordinary" && action != "open")) return false
        val expected = when (action) { "open" -> requestToken; "taken" -> e.request.takenToken
            "snooze" -> e.request.snoozeToken; "skip" -> e.request.skipToken; else -> return false }
        if (expected != actionToken) return false
        val envelope = ReminderAction(actionToken, epoch, requestToken, actionToken, action)
        if (actionToken in s.acknowledged || s.actions.any { it.envelopeId == actionToken }) return true
        if (s.actions.size >= 32) {
            journal.save(s.copy(repairReason = "action_capacity"))
            return false
        }
        journal.save(s.copy(actions = s.actions + envelope))
        return true
    }
    fun initialAction(): Map<String, String>? = state().actions.firstOrNull()?.let { mapOf(
        "envelopeId" to it.envelopeId, "epoch" to it.epoch, "requestToken" to it.requestToken,
        "actionToken" to it.actionToken, "action" to it.action) }
    fun acknowledge(id: String) {
        token(id)
        val s = state()
        if (s.actions.none { it.envelopeId == id }) return
        if (s.acknowledged.size >= 8192) throw ReminderFailure("journal_capacity")
        journal.save(s.copy(actions = s.actions.filter { it.envelopeId != id }, acknowledged = s.acknowledged + id))
    }
    fun invalidateEvidence(reason: String) {
        val s = state()
        journal.save(s.copy(repairReason = reason, entries = s.entries.mapValues { (_, e) ->
            if (e.state in terminals) e else e.copy(state = "unknown", reason = reason)
        }))
    }
    private fun receipt(token: String, entry: ReminderEntry?, reason: String? = null): Map<String, Any?> = mapOf(
        "requestToken" to token, "state" to (entry?.state ?: "unknown"), "reason" to (reason ?: entry?.reason))
    private fun snapshot(s: ReminderLedger, accepted: Boolean, receipts: List<Map<String, Any?>>, reason: String? = null): Map<String, Any?> = mapOf(
        "accepted" to accepted, "epoch" to s.epoch, "sequence" to s.sequence, "receipts" to receipts,
        "fingerprint" to FINGERPRINT, "reason" to reason)
}
