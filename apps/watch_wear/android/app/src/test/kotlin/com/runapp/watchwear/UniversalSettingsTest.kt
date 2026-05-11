package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/// Pure-parser coverage for the universal-prefs bag the wrist reads
/// on session restore.
///
/// Wire path (not tested here — needs Robolectric / a real HTTP
/// stack): RunViewModel.applySession → SupabaseClient
/// .fetchUniversalSettings → GET
/// /rest/v1/user_settings?user_id=eq.<uid>&select=prefs&limit=1 →
/// parseUniversalSettings(body).
///
/// `parseUniversalSettings` is the only thing the unit suite needs
/// to pin — every branch the watch can encounter (no row, null
/// prefs, missing key, rogue value) is exercised below.
class UniversalSettingsTest {

    @Test
    fun `empty body returns null`() {
        assertNull(parseUniversalSettings(""))
        assertNull(parseUniversalSettings(null))
        assertNull(parseUniversalSettings("   "))
    }

    @Test
    fun `non-array body returns null`() {
        // PostgREST `?limit=1` with no rows returns [], not an object;
        // any other top-level shape is unexpected. Fail closed.
        assertNull(parseUniversalSettings("""{"prefs":{"default_activity_type":"walk"}}"""))
    }

    @Test
    fun `empty array means no user_settings row`() {
        // A signed-in user who has never touched settings → no row in
        // user_settings. The watch keeps the hardcoded "run" default.
        val out = parseUniversalSettings("[]")
        assertEquals(UniversalSettings(defaultActivityType = null), out)
    }

    @Test
    fun `null prefs falls back to no default`() {
        val out = parseUniversalSettings("""[{"prefs":null}]""")
        assertEquals(UniversalSettings(defaultActivityType = null), out)
    }

    @Test
    fun `prefs object with missing default_activity_type returns null`() {
        // Other prefs present but no default_activity_type. Same
        // outcome as no key at all.
        val out = parseUniversalSettings("""[{"prefs":{"resting_hr_bpm":52}}]""")
        assertEquals(UniversalSettings(defaultActivityType = null), out)
    }

    @Test
    fun `valid run value round-trips`() {
        val out = parseUniversalSettings("""[{"prefs":{"default_activity_type":"run"}}]""")
        assertEquals(UniversalSettings(defaultActivityType = "run"), out)
    }

    @Test
    fun `walk hike cycle all accepted`() {
        for (kind in listOf("walk", "hike", "cycle")) {
            val out = parseUniversalSettings("""[{"prefs":{"default_activity_type":"$kind"}}]""")
            assertEquals(
                "expected $kind round-trip",
                UniversalSettings(defaultActivityType = kind),
                out,
            )
        }
    }

    @Test
    fun `rogue value falls back to null rather than poisoning the picker`() {
        // A future client could add 'swim' before the watch ships
        // its picker. The wrist refuses to display a value it
        // doesn't have a chip for — the rule is "either show one
        // of the four chips, or stay on the run default".
        val out = parseUniversalSettings(
            """[{"prefs":{"default_activity_type":"swim"}}]""",
        )
        assertEquals(UniversalSettings(defaultActivityType = null), out)
    }

    @Test
    fun `malformed JSON returns null without crashing`() {
        assertNull(parseUniversalSettings("not json"))
        assertNull(parseUniversalSettings("[{"))
        assertNull(parseUniversalSettings("""[{"prefs":}]"""))
    }

    @Test
    fun `numeric default_activity_type value is sanitised away`() {
        // PostgREST shouldn't produce this, but a corrupt jsonb cell
        // could. Treat as "unknown value" → null.
        val out = parseUniversalSettings(
            """[{"prefs":{"default_activity_type":42}}]""",
        )
        assertEquals(UniversalSettings(defaultActivityType = null), out)
    }

    @Test
    fun `allowlist matches the picker chips`() {
        // The pre-run picker cycles run / walk / hike / cycle (see
        // ui/RunWatchApp.kt). The parser's allowlist must agree —
        // a chip without a matching universal value (or vice
        // versa) would silently desync the two surfaces.
        assertEquals(setOf("run", "walk", "hike", "cycle"), UNIVERSAL_ACTIVITY_TYPES)
    }
}
