package dev.truegrit.vital

/** Dependency-free JVM behavior suite, compiled with the build's pinned Kotlin compiler. */
private class MemoryJournal : ReminderJournal {
    var value = ReminderLedger("installation")
    var reject: ((ReminderLedger) -> Boolean)? = null
    var afterSave: ((ReminderLedger) -> Unit)? = null
    override fun read() = value
    override fun save(state: ReminderLedger) {
        if (reject?.invoke(state) == true) throw IllegalStateException("simulated durable write failure")
        value = state
        afterSave?.invoke(state)
    }
}
private class Effects : ReminderEffects {
    var wall = 1000L; var elapsed = 100L; var boot: String? = "boot1"; var unavailable: String? = null
    var scheduled = mutableMapOf<String, ReminderRequest>(); var posts = 0; var cancels = 0
    var lastAlert: ReminderAlert? = null
    var allowAlertChange = true
    var scheduleFailure = false; var postFailure = false; var cancelFailure = false
    var beforeSchedule: (() -> Unit)? = null
    override fun nowWall() = wall
    override fun nowElapsed() = elapsed
    override fun bootId(installation: String) = boot
    override fun unavailableReason(alert: ReminderAlert) = unavailable
    override fun alertChangeAllowed(current: ReminderAlert) = allowAlertChange
    override fun schedule(request: ReminderRequest) {
        beforeSchedule?.invoke()
        if (scheduleFailure) throw IllegalStateException()
        scheduled[request.requestToken] = request
    }
    override fun cancel(request: ReminderRequest) { cancels++; if (cancelFailure) throw IllegalStateException(); scheduled.remove(request.requestToken) }
    override fun post(request: ReminderRequest, alert: ReminderAlert) { posts++; lastAlert = alert; if (postFailure) throw IllegalStateException() }
    override fun pending(request: ReminderRequest) = scheduled.containsKey(request.requestToken)
    override fun visible(request: ReminderRequest) = posts > 0
}
private fun request(token: String = "r1", clock: String = "wall", deadline: Long = 2000, epoch: String = "epoch1", boot: String? = "boot1") =
    ReminderRequest(epoch, token, "taken-$token", "snooze-$token", "skip-$token", clock, deadline, boot)
private fun receipt(result: Map<String, Any?>, token: String): String =
    (result.getValue("receipts") as List<*>).map { it as Map<*, *> }.first { it["requestToken"] == token }["state"] as String

fun main() {
    var passed = 0
    fun test(name: String, body: () -> Unit) { try { body(); passed++; println("PASS $name") }
        catch (e: Throwable) { throw AssertionError("FAIL $name", e) } }
    test("durable fence precedes registration and survives engine recreation") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        f.beforeSchedule = { check(j.value.sequence == 4L && j.value.epoch == "epoch1") }
        e.apply("epoch1", 4, listOf(request()), emptyList())
        check(ReminderEngine(j, f).apply("epoch1", 3, listOf(request("old")), emptyList())["accepted"] == false)
        check(f.scheduled.keys == setOf("r1"))
    }
    test("failed fence write performs no OS side effect") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.clock(); j.reject = { it.sequence == 1L }
        check(runCatching { e.apply("epoch1", 1, listOf(request()), emptyList()) }.isFailure)
        check(f.scheduled.isEmpty() && f.cancels == 0)
    }
    test("crash after replacement fence before cancellation cannot post removed request") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        j.afterSave = { if (it.sequence == 2L) error("process dies after durable fence") }
        check(runCatching { e.apply("epoch1", 2, emptyList(), listOf("r1")) }.isFailure)
        j.afterSave = null; f.wall = 2000
        ReminderEngine(j, f).fire("epoch1", "r1"); check(f.posts == 0)
    }
    test("late request cannot cross newer cancellation even after restart") {
        val j = MemoryJournal(); val f = Effects(); var e = ReminderEngine(j, f)
        e.apply("epoch1", 4, listOf(request()), emptyList()); e.apply("epoch1", 5, emptyList(), listOf("r1"))
        e = ReminderEngine(j, f)
        check(e.apply("epoch1", 4, listOf(request()), emptyList())["accepted"] == false)
        e.fire("epoch1", "r1"); check(f.posts == 0 && f.scheduled.isEmpty())
    }
    test("consumed token is not rearmed after dismissal or restart") {
        val j = MemoryJournal(); val f = Effects(); var e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList()); f.wall = 2000; e.fire("epoch1", "r1")
        check(f.posts == 1); f.scheduled.clear(); e = ReminderEngine(j, f)
        check(receipt(e.apply("epoch1", 1, listOf(request()), emptyList()), "r1") == "consumed")
        e.fire("epoch1", "r1"); check(f.posts == 1 && f.scheduled.isEmpty())
    }
    test("claim write failure forbids notify") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList()); f.wall = 2000
        j.reject = { it.entries["r1"]?.state == "postUncertain" }
        check(runCatching { e.fire("epoch1", "r1") }.isFailure); check(f.posts == 0)
    }
    test("claim before post crash retains uncertainty and never retries") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList()); f.wall = 2000; f.postFailure = true
        e.fire("epoch1", "r1"); check(j.value.entries["r1"]?.state == "postUncertain")
        ReminderEngine(j, f).fire("epoch1", "r1"); check(f.posts == 1)
        check(receipt(e.apply("epoch1", 1, listOf(request()), emptyList()), "r1") == "postUncertain")
    }
    test("post before final receipt crash stays uncertain") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList()); f.wall = 2000
        j.reject = { it.entries["r1"]?.state == "consumed" }
        check(runCatching { e.fire("epoch1", "r1") }.isFailure); check(f.posts == 1)
        j.reject = null; ReminderEngine(j, f).fire("epoch1", "r1"); check(f.posts == 1)
    }
    test("pending registration timeout repairs same token and absolute deadline") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        f.scheduleFailure = true
        check(receipt(e.apply("epoch1", 1, listOf(request()), emptyList()), "r1") == "unknown")
        f.scheduleFailure = false; e.apply("epoch1", 1, listOf(request()), emptyList())
        check(f.scheduled["r1"]?.deadlineMilliseconds == 2000L)
    }
    test("unchanged accepted snapshot performs no scheduling churn") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList()); f.beforeSchedule = { error("unnecessary reschedule") }
        e.apply("epoch1", 1, listOf(request()), emptyList())
    }
    test("same sequence different snapshot and same token different identity reject") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        check(e.apply("epoch1", 1, listOf(request("other")), emptyList())["reason"] == "sequence_conflict")
        check(e.apply("epoch1", 2, listOf(request(deadline = 3000)), emptyList())["reason"] == "token_conflict")
    }
    test("action identity cannot collide across different opaque requests") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        val collision = request("other").copy(takenToken = "taken-r1")
        check(e.apply("epoch1", 2, listOf(request(), collision), emptyList())["reason"] == "token_conflict")
        check(f.scheduled.keys == setOf("r1"))
    }
    test("epoch transition retires old epoch durably and requires explicit handshake") {
        val j = MemoryJournal(); val f = Effects(); var e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        check(e.apply("epoch2", 99, listOf(request("new", epoch = "epoch2")), emptyList())["accepted"] == false)
        check(e.invalidate("epoch1", "epoch2")); e = ReminderEngine(j, f)
        check(e.invalidate("epoch1", "epoch2")); check(!e.invalidate("epoch2", "epoch1"))
        check(e.apply("epoch1", 100, listOf(request()), emptyList())["accepted"] == false)
        check(f.scheduled.isEmpty())
    }
    test("cancellations still run when all capabilities are denied") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList()); f.unavailable = "exact_alarm_denied"
        val answer = e.apply("epoch1", 2, listOf(request("new")), listOf("r1"))
        check(f.scheduled.isEmpty() && receipt(answer, "r1") == "cancelled" && receipt(answer, "new") == "failed")
    }
    test("cancel receipt remains terminal when OS cancellation is unknown") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList()); f.cancelFailure = true; e.cancel(listOf("r1"))
        f.wall = 2000; e.fire("epoch1", "r1"); check(f.posts == 0)
        check(receipt(e.apply("epoch1", 2, listOf(request()), emptyList()), "r1") == "cancelled")
        f.cancelFailure = false; e.cancel(listOf("r1"))
        check(j.value.entries["r1"]?.reason == null && j.value.entries["r1"]?.state == "cancelled")
    }
    test("snooze retains elapsed absolute deadline through wall jumps") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        val r = request(clock = "elapsed", deadline = 1000)
        e.apply("epoch1", 1, listOf(r), emptyList()); f.wall = 9999999; f.elapsed = 999; e.fire("epoch1", "r1")
        check(f.posts == 0); f.elapsed = 1000; e.fire("epoch1", "r1"); check(f.posts == 1)
    }
    test("reboot never rearms elapsed snooze while future wall request repairs") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        val r = request(clock = "elapsed", deadline = 1000)
        e.apply("epoch1", 1, listOf(r, request("daily")), emptyList()); f.boot = "boot2"; f.scheduled.clear()
        val answer = ReminderEngine(j, f).apply("epoch1", 1, listOf(r, request("daily")), emptyList())
        check(receipt(answer, "r1") == "failed" && f.scheduled.keys == setOf("daily"))
    }
    test("unknown boot suppresses elapsed but permits ordinary clocks") {
        val j = MemoryJournal(); val f = Effects(); f.boot = null; val e = ReminderEngine(j, f)
        check(runCatching { e.clock() }.exceptionOrNull() is ReminderFailure)
        e.apply("epoch1", 1, listOf(request(clock = "elapsed"), request("daily")), emptyList())
        check(f.scheduled.keys == setOf("daily"))
    }
    test("expired absolute deadline fails without immediate catchup") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        val answer = e.apply("epoch1", 1, listOf(request(deadline = 1000)), emptyList())
        check(receipt(answer, "r1") == "failed" && f.scheduled.isEmpty() && f.posts == 0)
    }
    test("deadline expiring between validation and OS call remains explicit expired failure") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        f.beforeSchedule = { throw ReminderFailure("deadline_expired") }
        val result = e.apply("epoch1", 1, listOf(request()), emptyList())
        check(receipt(result, "r1") == "failed")
        check(j.value.entries["r1"]?.reason == "deadline_expired" && f.scheduled.isEmpty())
    }
    test("durable action retries same envelope until explicit capture acknowledgement") {
        val j = MemoryJournal(); val f = Effects(); var e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        check(e.capture("epoch1", "r1", "taken-r1", "taken")); val first = e.initialAction()
        e = ReminderEngine(j, f); check(e.capture("epoch1", "r1", "taken-r1", "taken"))
        check(e.initialAction() == first && j.value.actions.size == 1)
        e.acknowledge("taken-r1"); e.capture("epoch1", "r1", "taken-r1", "taken"); check(e.initialAction() == null)
        check(!e.capture("epoch1", "r1", "wrong", "taken"))
    }
    test("snapshot and wire bounds reject oversized and malformed input") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        check(runCatching { e.apply("epoch1", 1, List(257) { request("r$it") }, emptyList()) }.isFailure)
        check(runCatching { e.apply("epoch1", 1, listOf(request("../owner")), emptyList()) }.isFailure)
        check(runCatching { e.apply("epoch1", -1, listOf(request()), emptyList()) }.isFailure)
        check(f.scheduled.isEmpty())
    }
    test("event-end opens review only and rejects all dose actions") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        val event = request("event").copy(purpose = "eventEnd")
        e.apply("epoch1", 1, listOf(event), emptyList())
        check(!e.capture("epoch1", "event", event.takenToken, "taken"))
        check(!e.capture("epoch1", "event", event.snoozeToken, "snooze"))
        check(!e.capture("epoch1", "event", event.skipToken, "skip"))
        check(e.capture("epoch1", "event", "event", "open"))
        e.apply("epoch1", 2, emptyList(), listOf("event"))
        check(!e.capture("epoch1", "event", "event", "open"))
    }
    test("reserved event-end capacity rejects ninth and elapsed event requests") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        check(runCatching { e.apply("epoch1", 1, List(9) { request("end$it").copy(purpose = "eventEnd") }, emptyList()) }.isFailure)
        check(runCatching { e.apply("epoch1", 1, listOf(request(clock = "elapsed").copy(purpose = "eventEnd")), emptyList()) }.isFailure)
        check(f.scheduled.isEmpty())
    }
    test("full shared native budget preserves eight reserved event requests") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        val requests = List(248) { request("dose$it") } + List(8) { request("end$it").copy(purpose = "eventEnd") }
        check(e.apply("epoch1", 1, requests, emptyList())["accepted"] == true)
        check(f.scheduled.size == 256)
    }
    test("old request constructor remains ordinary and replacement fences stale open") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        check(request().purpose == "ordinary")
        e.apply("epoch1", 1, listOf(request("event").copy(purpose = "eventEnd")), emptyList())
        e.invalidate("epoch1", "epoch2")
        check(!e.capture("epoch1", "event", "event", "open"))
    }
    test("installed epoch exposes the handover target for a restored dataset") {
        val j = MemoryJournal(); val f = Effects(); var e = ReminderEngine(j, f)
        check(e.installedEpoch() == null)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        check(e.installedEpoch() == "epoch1")
        e = ReminderEngine(j, f)
        check(e.installedEpoch() == "epoch1")
        check(e.apply("epoch2", 1, listOf(request("restored").copy(epoch = "epoch2")), emptyList())["reason"] == "epoch_rejected")
        check(e.installedEpoch() == "epoch1")
        check(e.invalidate("epoch1", "epoch2"))
        check(e.installedEpoch() == "epoch2")
        check(e.apply("epoch2", 1, listOf(request("restored").copy(epoch = "epoch2")), emptyList())["accepted"] == true)
    }
    test("restored record ids cannot resurrect a retired epoch request") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 3, listOf(request()), emptyList())
        check(e.invalidate("epoch1", "epoch2"))
        // An epoch1 request cannot ride in under the new epoch...
        check(runCatching { e.apply("epoch2", 0, listOf(request()), emptyList()) }.isFailure)
        // ...and the retired epoch itself is refused outright.
        check(e.apply("epoch1", 4, listOf(request()), emptyList())["accepted"] == false)
        check(f.scheduled.isEmpty())
    }
    test("unconfirmed cancellation stays terminal and reports its reason once retried") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        f.cancelFailure = true
        val first = e.apply("epoch1", 2, emptyList(), listOf("r1"))
        check((first["receipts"] as List<*>).map { it as Map<*, *> }.first()["reason"] == "cancellation_unknown")
        f.cancelFailure = false
        val second = e.apply("epoch1", 2, emptyList(), listOf("r1"))
        check((second["receipts"] as List<*>).map { it as Map<*, *> }.first()["reason"] == null)
        check(f.scheduled.isEmpty())
    }
    test("alert choices default to the legacy channel and survive reopening") {
        val j = MemoryJournal(); val f = Effects(); var e = ReminderEngine(j, f)
        check(e.alert() == ReminderAlert.LEGACY)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        check(e.applyAlert(ReminderAlert(sound = false, vibration = false)))
        e = ReminderEngine(j, f)
        check(e.alert() == ReminderAlert(sound = false, vibration = false))
        f.wall = 2000; e.fire("epoch1", "r1")
        check(f.posts == 1 && f.lastAlert == ReminderAlert(sound = false, vibration = false))
    }
    test("alert choice changes never cancel or reschedule prepared reminders") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        e.applyAlert(ReminderAlert(sound = false, vibration = true))
        check(j.value.sequence == 1L && j.value.epoch == "epoch1")
        check(f.scheduled.keys == setOf("r1") && f.cancels == 0)
    }
    test("native selection cannot bypass an OS mute during restore or a stale UI read") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        e.apply("epoch1", 1, listOf(request()), emptyList())
        f.allowAlertChange = false
        check(runCatching { e.applyAlert(ReminderAlert(sound = false, vibration = false)) }.isFailure)
        check(e.alert() == ReminderAlert.LEGACY)
        check(f.scheduled.keys == setOf("r1") && f.cancels == 0)
        check(e.applyAlert(ReminderAlert.LEGACY))
        f.allowAlertChange = true
        check(e.applyAlert(ReminderAlert(sound = false, vibration = false)))
    }
    test("missing channels allow repair but blocked channels and apps reject selection") {
        check(ReminderChannels.changeAllowed(true, null))
        check(ReminderChannels.changeAllowed(true, 3))
        check(!ReminderChannels.changeAllowed(true, 0))
        check(!ReminderChannels.changeAllowed(false, null))
        check(!ReminderChannels.changeAllowed(false, 3))
    }
    test("failed alert preference write is not reported as applied") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        j.reject = { it.alert != ReminderAlert.LEGACY }
        check(runCatching { e.applyAlert(ReminderAlert(sound = false, vibration = false)) }.isFailure)
        check(e.alert() == ReminderAlert.LEGACY)
    }
    test("legacy channel identity and variant configuration stay explicit") {
        check(ReminderChannels.id(ReminderAlert.LEGACY) == "vital_reminders_v1")
        check(ReminderChannels.configuration(ReminderAlert.LEGACY) ==
            ReminderChannelConfiguration(sound = true, vibration = true, legacy = true))
        val soundOnly = ReminderAlert(sound = true, vibration = false)
        val vibrationOnly = ReminderAlert(sound = false, vibration = true)
        val silent = ReminderAlert(sound = false, vibration = false)
        check(listOf(soundOnly, vibrationOnly, silent).map { ReminderChannels.id(it) } ==
            listOf("vital_reminders_v1_s1v0", "vital_reminders_v1_s0v1", "vital_reminders_v1_s0v0"))
        check(ReminderChannels.configuration(soundOnly) ==
            ReminderChannelConfiguration(sound = true, vibration = false, legacy = false))
        check(ReminderChannels.configuration(vibrationOnly).sound == false)
        check(ReminderChannels.configuration(vibrationOnly).vibration == true)
        check(ReminderChannels.configuration(silent).let { !it.sound && !it.vibration && !it.legacy })
    }
    test("missing or muted channel is never treated as known enabled") {
        check(!ReminderChannels.enabled(null))
        check(!ReminderChannels.enabled(0))
        check(ReminderChannels.enabled(2))
        check(ReminderChannels.enabled(4))
    }
    test("alert storage keeps legacy for absent fields and explicit false otherwise") {
        check(ReminderAlertCodec.decode(null, null) == ReminderAlert.LEGACY)
        check(ReminderAlertCodec.decode(false, null) == ReminderAlert(sound = false, vibration = true))
        check(ReminderAlertCodec.decode(null, false) == ReminderAlert(sound = true, vibration = false))
        check(ReminderAlertCodec.decode(true, false) == ReminderAlert(sound = true, vibration = false))
        check(ReminderAlertCodec.encode(ReminderAlert(sound = false, vibration = true)) ==
            mapOf("sound" to false, "vibration" to true))
    }
    test("stock notices expose Open only and never dose actions") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        val stock = request("stock").copy(purpose = "stockLow")
        e.apply("epoch1", 1, listOf(stock), emptyList())
        check(!e.capture("epoch1", "stock", stock.takenToken, "taken"))
        check(!e.capture("epoch1", "stock", stock.snoozeToken, "snooze"))
        check(!e.capture("epoch1", "stock", stock.skipToken, "skip"))
        check(e.capture("epoch1", "stock", "stock", "open"))
        f.wall = 2000; e.fire("epoch1", "stock")
        check(f.posts == 1)
        check(receipt(e.apply("epoch1", 2, listOf(stock), emptyList()), "stock") == "consumed")
        e.fire("epoch1", "stock"); check(f.posts == 1)
    }
    test("stock notices reserve eight wall-only slots and reject elapsed") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        check(runCatching { e.apply("epoch1", 1, List(9) { request("stock$it").copy(purpose = "stockLow") }, emptyList()) }.isFailure)
        check(runCatching { e.apply("epoch1", 1, listOf(request(clock = "elapsed").copy(purpose = "stockLow")), emptyList()) }.isFailure)
        val requests = List(248) { request("dose$it") } +
            List(8) { request("end$it").copy(purpose = "eventEnd") } +
            List(8) { request("stock$it").copy(purpose = "stockLow") }
        check(e.apply("epoch1", 1, requests, emptyList())["accepted"] == true)
        check(f.scheduled.size == 264)
    }
    test("stock notice cancellation remains terminal and open is fenced") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        val stock = request("stock").copy(purpose = "stockLow")
        e.apply("epoch1", 1, listOf(stock), emptyList())
        e.apply("epoch1", 2, emptyList(), listOf("stock"))
        check(!e.capture("epoch1", "stock", "stock", "open"))
        check(receipt(e.apply("epoch1", 2, listOf(stock), emptyList()), "stock") == "cancelled")
        f.wall = 2000; e.fire("epoch1", "stock"); check(f.posts == 0)
    }
    test("posted stock Open survives foreground reconciliation until cancelled") {
        for (uncertain in listOf(false, true)) {
        val j = MemoryJournal(); val f = Effects(); var e = ReminderEngine(j, f)
        val stock = request("stock").copy(purpose = "stockLow")
        e.apply("epoch1", 1, listOf(stock), emptyList())
        f.postFailure = uncertain
        f.wall = 2000; e.fire("epoch1", "stock")
        e.apply("epoch1", 2, emptyList(), emptyList())
        e = ReminderEngine(j, f)
        check(e.capture("epoch1", "stock", "stock", "open"))
        check(f.posts == 1)
        e.apply("epoch1", 3, emptyList(), listOf("stock"))
        check(!e.capture("epoch1", "stock", "stock", "open"))
        }
    }
    test("deferred stock uses the same native token after its deadline") {
        val j = MemoryJournal(); val f = Effects(); val e = ReminderEngine(j, f)
        val stock = request("stock").copy(purpose = "stockLow")
        f.wall = 3000
        check(receipt(e.apply("epoch1", 1, listOf(stock), emptyList()), "stock") == "accepted")
        e.fire("epoch1", "stock"); check(f.posts == 1)
        e.apply("epoch1", 2, listOf(stock), emptyList())
        e.fire("epoch1", "stock"); check(f.posts == 1)
    }
    println("$passed reminder engine tests passed")
}
