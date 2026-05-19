package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/// Unit tests for `RaceSessionClient`.
///
/// The actual HTTP fetches need a live PostgREST stack (covered by the
/// race-mode wire-level tests in `services_integration_test.dart` on
/// the mobile side, when the watch race-mode flow grows one). What's
/// pinned here is the pure URL-value encoding contract that the
/// `fetchActive` two-hop flow depends on, because the bug it guards
/// against is silent — `fetchActive` returns `null` when the encoding
/// is wrong, which looks identical to "no armed race".
///
/// ### The bug this file pins against
///
/// `fetchActive` does two query hops:
///
/// 1. `GET /event_attendees?...&instance_start=gte.X` — reads RSVPs
///    within a ±12h window. PostgREST returns each row's
///    `instance_start` as a JSON string in timestamptz form, e.g.
///    `"2026-05-22T18:00:00+00:00"` — note the explicit `+00:00`.
/// 2. `GET /race_sessions?...&instance_start=eq.<value from step 1>`
///    — looks up the matching race_sessions row.
///
/// If the second query interpolates the raw string straight into the
/// URL, the `+` arrives at PostgREST and gets decoded as a SPACE per
/// `application/x-www-form-urlencoded` rules. The filter then asks for
/// `instance_start = '2026-05-22T18:00:00 00:00'` which is unparseable
/// and the row never matches. fetchActive returns null, and the watch's
/// race banner stays hidden on the day-of for every armed race the user
/// has an RSVP for.
///
/// URL-encoding the value (`%2B` for `+`) makes PostgREST round-trip
/// it back to a literal `+` and the comparison succeeds. These tests
/// pin that the encoder does exactly that.
class RaceSessionClientTest {

    // ───────────── encoder contract ─────────────

    @Test
    fun `encoder percent-encodes the plus sign (the critical case)`() {
        // The single most important assertion in this file: a `+`
        // in a PostgREST timestamptz becomes `%2B`. A regression to
        // a raw passthrough (or to a homebrew "only encode high
        // chars" encoder) would let the `+` through and silently
        // break race detection.
        val raw = "2026-05-22T18:00:00+00:00"
        val encoded = RaceSessionClient.encodeQueryValue(raw)
        assertTrue(
            "the `+` MUST become `%2B`: got `$encoded`",
            encoded.contains("%2B"),
        )
        assertFalse(
            "a raw `+` must not survive encoding: got `$encoded`",
            // Allow the encoded form to contain `%2B`, but NOT a
            // bare `+` (which would be the bug).
            encoded.replace("%2B", "").contains("+"),
        )
    }

    @Test
    fun `encoder leaves a Z-form timestamp URL-safe`() {
        // PostgREST's `to_jsonb(timestamptz)` mostly emits `+00:00`
        // form, but a Postgres / PostgREST version drift could yield
        // `Z` form instead. The encoder must handle both — Z stays
        // alphanumeric so the value is byte-identical pre/post encode.
        val raw = "2026-05-22T18:00:00Z"
        val encoded = RaceSessionClient.encodeQueryValue(raw)
        // Z + dash + colon-encoded characters all round-trip
        // correctly through java.net.URLDecoder.
        val roundTrip = java.net.URLDecoder.decode(encoded, "UTF-8")
        assertEquals(raw, roundTrip)
    }

    @Test
    fun `encoder round-trips the offset form via URLDecoder`() {
        // Belt-and-braces for the bug case: when PostgREST receives
        // the encoded value, it decodes via the same rules
        // URLDecoder follows. Pin that the round-trip yields the
        // EXACT input so the eq.<value> filter matches on the row.
        val raw = "2026-05-22T18:00:00+00:00"
        val encoded = RaceSessionClient.encodeQueryValue(raw)
        val roundTrip = java.net.URLDecoder.decode(encoded, "UTF-8")
        assertEquals(raw, roundTrip)
    }

    @Test
    fun `encoder round-trips a Postgres microsecond-precision timestamp`() {
        // Some PostgREST versions emit microseconds (`.123456`). The
        // dot itself is URL-safe but the encoder must still pass it
        // through unchanged so a strict equality compare on the
        // PostgREST side matches.
        val raw = "2026-05-22T18:00:00.123456+00:00"
        val encoded = RaceSessionClient.encodeQueryValue(raw)
        val roundTrip = java.net.URLDecoder.decode(encoded, "UTF-8")
        assertEquals(raw, roundTrip)
        assertTrue(
            "the `+` in offset must still become `%2B` regardless of " +
                "the microsecond field",
            encoded.contains("%2B"),
        )
    }

    @Test
    fun `encoder round-trips a UUID untouched`() {
        // Defensive: encoding a UUID (no special chars) should not
        // mangle it. PostgREST's PK comparison is byte-exact.
        val uuid = "1f4a8c3d-9b2e-4a3f-8d7c-2e6f9a1b0c4d"
        val encoded = RaceSessionClient.encodeQueryValue(uuid)
        // URLEncoder leaves alphanumerics + `-` alone; the encoded
        // form should be byte-identical to the input.
        assertEquals(uuid, encoded)
    }

    @Test
    fun `encoder treats space as plus per form-urlencoded rules`() {
        // java.net.URLEncoder uses `+` for space (the
        // application/x-www-form-urlencoded encoding PostgREST also
        // expects). A status value with a space would be rare in
        // practice but pin the contract — `armed running` would
        // encode as `armed+running` which PostgREST decodes back to
        // `armed running`. The opposite encoding (`%20`) would also
        // decode correctly but isn't the contract.
        val raw = "armed running"
        val encoded = RaceSessionClient.encodeQueryValue(raw)
        assertEquals("armed+running", encoded)
    }

    // ───────────── source-level fix guard ─────────────

    @Test
    fun `fetchActive interpolations route through enc helper`() {
        // Source-level guard: the bug was raw `$instance` /
        // `$eventId` / `$userId` interpolation. The fix wraps every
        // value with `enc(...)`. Pin that the listener can't quietly
        // regress to a raw `$varname` (which would compile clean +
        // pass every other test in this file but reintroduce the
        // bug). The string `"=eq.$instance"` is the exact regression
        // shape — its absence is the canary.
        val src = File(
            "src/main/kotlin/com/runapp/watchwear/RaceSessionClient.kt"
        ).readText()
        // The fix uses `enc(instance)` — assert the encoded form is
        // present AND no `=eq.$instance` raw form sneaked back in.
        assertTrue(
            "fetchActive must interpolate `instance` via enc(...) — " +
                "got source with no `enc(instance)` call",
            src.contains("enc(instance)"),
        )
        assertFalse(
            "raw `=eq.\$instance` interpolation regressed the fix",
            src.contains("=eq.\$instance"),
        )
        // Same for eventId — covers the second-hop and the title fetch.
        assertTrue(
            "fetchActive must interpolate `eventId` via enc(...)",
            src.contains("enc(eventId)"),
        )
        assertFalse(
            "raw `=eq.\$eventId` interpolation regressed the fix",
            src.contains("=eq.\$eventId"),
        )
    }
}
