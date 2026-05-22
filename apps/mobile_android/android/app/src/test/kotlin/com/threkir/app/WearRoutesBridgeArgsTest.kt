package com.threkir.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Pure-JVM unit tests for [parseWearRoutesPushArgs] — the arg
/// parser extracted from [WearRoutesBridge.onMethodCall]. The
/// Method-channel + Wearable Data Layer surfaces can't run on a
/// host JVM (DataClient is a Google Play Services type that needs
/// the GMS runtime), so the testable seam is the arg parser. These
/// pin the input-tolerance contract that production callers — the
/// Dart `WearRoutesBridge` writer — depend on.
class WearRoutesBridgeArgsTest {

    private val nowMs = 1_700_000_000_000L

    @Test
    fun `null args returns null — bridge surfaces as bad_args error`() {
        assertNull(parseWearRoutesPushArgs(null, nowMs))
    }

    @Test
    fun `empty args produces both fallbacks`() {
        // The bridge MUST tolerate empty maps — a future Dart writer
        // that forgets to include either key shouldn't crash the
        // native handler. The empty payload "[]" still produces a
        // valid (empty) DataItem on the watch.
        val parsed = parseWearRoutesPushArgs(emptyMap(), nowMs)
        assertNotNull(parsed)
        assertEquals("[]", parsed!!.routesJson)
        assertEquals(nowMs, parsed.updatedAtMs)
    }

    @Test
    fun `routes_json passes through verbatim when set`() {
        val parsed = parseWearRoutesPushArgs(
            mapOf("routes_json" to """[{"id":"r-1","name":"X"}]"""),
            nowMs,
        )
        assertEquals("""[{"id":"r-1","name":"X"}]""", parsed!!.routesJson)
    }

    @Test
    fun `routes_json that's not a String falls back to empty array`() {
        // Defensive — a buggy Dart writer that puts a List or Map
        // instead of a String shouldn't crash the bridge.
        val parsed = parseWearRoutesPushArgs(
            mapOf("routes_json" to listOf("not", "a", "string")),
            nowMs,
        )
        assertEquals("[]", parsed!!.routesJson)
    }

    @Test
    fun `updated_at_ms accepts Long`() {
        val parsed = parseWearRoutesPushArgs(
            mapOf("updated_at_ms" to 1_500_000_000_000L),
            nowMs,
        )
        assertEquals(1_500_000_000_000L, parsed!!.updatedAtMs)
    }

    @Test
    fun `updated_at_ms accepts Int (Dart sends small enough values)`() {
        // Dart's int can be either int or long over the MethodChannel
        // boundary depending on the value. Long-form is canonical;
        // Int-form must still work for short-lived dev session
        // timestamps.
        val parsed = parseWearRoutesPushArgs(
            mapOf("updated_at_ms" to 42),
            nowMs,
        )
        assertEquals(42L, parsed!!.updatedAtMs)
    }

    @Test
    fun `updated_at_ms accepts Double — coerces to Long via Number_toLong`() {
        // Older Dart-to-Kotlin MethodChannel codecs sometimes
        // present integer values as Double. The Number cast +
        // toLong() catches this path.
        val parsed = parseWearRoutesPushArgs(
            mapOf("updated_at_ms" to 1_500_000_000_000.0),
            nowMs,
        )
        assertEquals(1_500_000_000_000L, parsed!!.updatedAtMs)
    }

    @Test
    fun `updated_at_ms missing falls back to nowMs`() {
        val parsed = parseWearRoutesPushArgs(
            mapOf("routes_json" to "[]"),
            nowMs,
        )
        assertEquals(nowMs, parsed!!.updatedAtMs)
    }

    @Test
    fun `updated_at_ms that's not a Number falls back to nowMs`() {
        val parsed = parseWearRoutesPushArgs(
            mapOf("updated_at_ms" to "not a number"),
            nowMs,
        )
        assertEquals(nowMs, parsed!!.updatedAtMs)
    }

    @Test
    fun `both fields present produces the canonical happy-path output`() {
        val parsed = parseWearRoutesPushArgs(
            mapOf(
                "routes_json" to """[{"id":"r-1"}]""",
                "updated_at_ms" to 1_700_000_000_500L,
            ),
            nowMs,
        )
        assertEquals("""[{"id":"r-1"}]""", parsed!!.routesJson)
        assertEquals(1_700_000_000_500L, parsed.updatedAtMs)
    }

    @Test
    fun `unrelated extra keys are silently ignored`() {
        // Forward-compat: a future Dart writer might add a key the
        // current Kotlin bridge doesn't understand. The bridge must
        // not crash; just ignore the extra fields.
        val parsed = parseWearRoutesPushArgs(
            mapOf(
                "routes_json" to "[]",
                "updated_at_ms" to 100L,
                "future_field" to mapOf("nested" to "value"),
                "another_one" to 42,
            ),
            nowMs,
        )
        assertEquals("[]", parsed!!.routesJson)
        assertEquals(100L, parsed.updatedAtMs)
    }

    @Test
    fun `WearRoutesPushArgs data-class equality is by-value`() {
        val a = WearRoutesPushArgs("[]", 100L)
        val b = WearRoutesPushArgs("[]", 100L)
        val c = WearRoutesPushArgs("[]", 101L)
        assertEquals(a, b)
        assertTrue("differing timestamp", a != c)
    }

    @Test
    fun `PATH constant matches the watch-side RoutesBridge contract`() {
        // The DataLayer path is one of the two cross-language
        // wire-format constants (the other is the channel name).
        // Drift here means the watch's listener never fires.
        // Pinning the value as a Kotlin-readable constant defends
        // against an accidental rename.
        assertEquals("/saved_routes", WearRoutesBridge.PATH)
    }
}
