package dev.truegrit.vital

/** Disjoint lower-16-bit namespaces for Vital's legacy Activity results. */
internal object ActivityRequestCodes {
    const val CREDENTIAL = 0x3001
    const val FIRST_PICKER = 0x4000
    const val LEGACY_LAST_PICKER = 0x7fff
    const val LAST_PICKER = 0xbfff
    fun recoveredCounterPrior(recoveryAlreadyUsed: Boolean): Int {
        if (recoveryAlreadyUsed) throw HandoffFailure("attachment_picker_capacity")
        return LEGACY_LAST_PICKER
    }
    fun nextPicker(prior: Int): Int {
        if (prior !in (FIRST_PICKER - 1) until LAST_PICKER) {
            throw HandoffFailure("attachment_picker_capacity")
        }
        return prior + 1
    }
    fun ownsPicker(request: Int) = request in FIRST_PICKER..LAST_PICKER
    fun acceptsPicker(request: Int, activeCode: Int?, activeState: String?) =
        ownsPicker(request) && request == activeCode && activeState == "pending"
    fun acceptsCredential(request: Int, legacyInFlight: Boolean, hasPending: Boolean) =
        request == CREDENTIAL && legacyInFlight && hasPending
}
