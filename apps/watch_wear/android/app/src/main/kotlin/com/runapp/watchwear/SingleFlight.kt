package com.runapp.watchwear

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/// Coalesces concurrent calls into one execution: the first caller runs the
/// block, every caller that arrives while it is in flight awaits the same
/// result instead of starting its own.
///
/// Needed for the Supabase token refresh. GoTrue rotates the refresh token,
/// so the second of two concurrent refreshes spends a token the first has
/// already consumed and fails — signing the watch out mid-run. Cold start
/// alone can fire two (the cached-session restore and the phone-bridge
/// restore), and a drain-triggered 401 refresh can land on top of either.
/// Serialising with a plain mutex would not help: the second caller would
/// still POST, just later, with the now-dead token.
class SingleFlight<T> {
    private val mutex = Mutex()
    private var inFlight: CompletableDeferred<Result<T>>? = null

    suspend fun run(block: suspend () -> T): T {
        val slot = CompletableDeferred<Result<T>>()
        val joined = mutex.withLock {
            val existing = inFlight
            if (existing == null) {
                inFlight = slot
                null
            } else {
                existing
            }
        }
        if (joined != null) return joined.await().getOrThrow()

        val result = runCatching { block() }
        mutex.withLock { inFlight = null }
        slot.complete(result)
        return result.getOrThrow()
    }
}
