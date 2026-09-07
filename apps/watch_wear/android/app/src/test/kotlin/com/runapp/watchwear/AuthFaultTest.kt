package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/// The wrist's auth vocabulary, evaluated rather than read.
///
/// `authError` carried the same defect § 1490 closed on the sync banner, one
/// screen over: GoTrue's own English error body reached a `caption3` verbatim,
/// and the refresh path wrapped it in a translated frame so half the sentence
/// was localized and the half carrying the meaning was not (decisions § 1492).
///
/// The claim under test is the one thing a status code alone cannot settle:
/// the SAME code means different things on the two grants, and a runner who
/// typed nothing must never be told their password is wrong.
class AuthFaultTest {

    private val transient: List<Pair<String, Throwable>> = listOf(
        "dns" to RuntimeException("Unable to resolve host \"x.supabase.co\""),
        "refused" to RuntimeException("Failed to connect to /10.0.0.1:443"),
        "reset" to RuntimeException("Connection reset"),
        "timeout" to RuntimeException("timeout"),
        "truncated" to RuntimeException("unexpected end of stream"),
    )

    @Test
    fun `a refused password is not a refused session, though the code is the same`() {
        // The whole reason there are two entry points. GoTrue answers 400 to a
        // wrong password and 400 to a spent refresh token; "Email or password
        // is wrong" is a lie in the second case, told to somebody who typed
        // nothing and can only be confused by it.
        for (code in listOf(400, 401, 403, 422)) {
            val e = HttpException(code, "Invalid login credentials")
            assertEquals("$code on the password grant", AuthFault.InvalidCredentials, signInFaultFor(e))
            assertEquals("$code on the refresh grant", AuthFault.SessionExpired, refreshFaultFor(e))
        }
    }

    @Test
    fun `both grants agree about everything that is not the grant being refused`() {
        // Rate limiting, a 5xx and a dead socket are facts about the transport
        // and the server, not about which endpoint was asked — so the two
        // classifiers must not have drifting opinions on them.
        val shared = listOf<Pair<Throwable, AuthFault>>(
            HttpException(429, "over_request_rate_limit") to AuthFault.RateLimited,
            HttpException(500, "internal error") to AuthFault.ServerBusy,
            HttpException(503, "unavailable") to AuthFault.ServerBusy,
        ) + transient.map { it.second to AuthFault.Offline }
        for ((e, expected) in shared) {
            assertEquals("$e via sign-in", expected, signInFaultFor(e))
            assertEquals("$e via refresh", expected, refreshFaultFor(e))
        }
    }

    @Test
    fun `a rate limit is never reported as a wrong password`() {
        // 429 is inside the 4xx band, so a bare "4xx means bad credentials"
        // rule would tell a rate-limited runner to retype — which is the one
        // action that extends the lockout.
        assertEquals(AuthFault.RateLimited, signInFaultFor(HttpException(429, "too many requests")))
    }

    @Test
    fun `a failure below HTTP is never blamed on the runner`() {
        // Nothing reached an auth server, so nothing judged the password.
        // These used to render as `Unable to resolve host "…supabase.co"`.
        for ((name, e) in transient) {
            assertEquals(name, AuthFault.Offline, signInFaultFor(e))
        }
    }

    @Test
    fun `an unrecognised throwable claims nothing it cannot support`() {
        // `SupabaseClient` throws `IllegalStateException("auth response missing
        // access_token")` on a malformed 200 — English developer prose that
        // used to reach the wrist verbatim, and which is neither a credential
        // problem nor an expired session.
        val malformed = IllegalStateException("auth response missing access_token")
        assertEquals(AuthFault.Unknown, signInFaultFor(malformed))
        assertEquals(AuthFault.Unknown, refreshFaultFor(malformed))
        assertEquals(AuthFault.Unknown, signInFaultFor(RuntimeException()))
    }

    @Test
    fun `every fault is reachable from one of the two classifiers`() {
        // A member nothing produces is a sentence translated into seven
        // languages that no runner will ever be shown.
        val reached = buildList {
            addAll(
                listOf(
                    HttpException(400, "bad"),
                    HttpException(429, "slow down"),
                    HttpException(500, "boom"),
                    RuntimeException("Connection reset"),
                    IllegalStateException("?"),
                ).flatMap { listOf(signInFaultFor(it), refreshFaultFor(it)) }
            )
        }.toSet()
        assertEquals(AuthFault.entries.toSet(), reached)
    }

    @Test
    fun `no two faults say the same sentence`() {
        val ids = AuthFault.entries.map { authFaultMessage(it) }
        assertEquals("a fault shares another's string resource", ids.size, ids.toSet().size)
        for (id in ids) assertNotEquals("an unresolved resource id", 0, id)
    }
}
