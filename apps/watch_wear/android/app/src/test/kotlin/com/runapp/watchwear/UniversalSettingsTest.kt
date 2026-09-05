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
        assertEquals(UniversalSettings(defaultActivityType = null, privacyDefault = null), out)
    }

    @Test
    fun `null prefs falls back to no default`() {
        val out = parseUniversalSettings("""[{"prefs":null}]""")
        assertEquals(UniversalSettings(defaultActivityType = null, privacyDefault = null), out)
    }

    @Test
    fun `prefs object with missing default_activity_type returns null`() {
        // Other prefs present but no default_activity_type. Same
        // outcome as no key at all — and same for privacy_default
        // when only the other field is set. (Pick a key the wrist
        // doesn't consume — `voice_feedback_enabled` is a phone/web
        // pref with no wrist reader, so it never lands on
        // `UniversalSettings`.)
        val out = parseUniversalSettings(
            """[{"prefs":{"voice_feedback_enabled":true}}]""",
        )
        assertEquals(null, out?.defaultActivityType)
        assertEquals(null, out?.privacyDefault)
    }

    @Test
    fun `valid run value round-trips`() {
        val out = parseUniversalSettings("""[{"prefs":{"default_activity_type":"run"}}]""")
        assertEquals(UniversalSettings(defaultActivityType = "run", privacyDefault = null), out)
    }

    @Test
    fun `body_weight_kg parses in range and rejects out-of-range (persona #34)`() {
        val ok = parseUniversalSettings("""[{"prefs":{"body_weight_kg":68.5}}]""")
        assertEquals(68.5, ok?.bodyWeightKg)
        // Out of the [20, 400] sanity range → dropped.
        assertNull(parseUniversalSettings("""[{"prefs":{"body_weight_kg":5}}]""")?.bodyWeightKg)
        assertNull(parseUniversalSettings("""[{"prefs":{"body_weight_kg":900}}]""")?.bodyWeightKg)
        // Absent → null (default applies downstream).
        assertNull(parseUniversalSettings("""[{"prefs":{"default_activity_type":"run"}}]""")?.bodyWeightKg)
    }

    @Test
    fun `preferred_unit parses km and mi, rejects rogue values`() {
        assertEquals("mi", parseUniversalSettings("""[{"prefs":{"preferred_unit":"mi"}}]""")?.preferredUnit)
        assertEquals("km", parseUniversalSettings("""[{"prefs":{"preferred_unit":"km"}}]""")?.preferredUnit)
        // Rogue / future value → null (kilometres applies downstream).
        assertNull(parseUniversalSettings("""[{"prefs":{"preferred_unit":"miles"}}]""")?.preferredUnit)
        // Absent → null.
        assertNull(parseUniversalSettings("""[{"prefs":{"default_activity_type":"run"}}]""")?.preferredUnit)
    }

    @Test
    fun `show_calories hides the wrist figure only on an explicit false`() {
        // The pref is a harm-reduction opt-out for weight-conscious
        // runners, so an explicit false must reach the wrist too — not
        // just web + phone run-detail.
        assertEquals(false, parseUniversalSettings("""[{"prefs":{"show_calories":false}}]""")?.showCalories)
        // Negative control: everything else leaves the default (on)
        // intact, mirroring web's `!== false`. If the parse were
        // inverted or defaulted-off, these would flip.
        assertEquals(true, parseUniversalSettings("""[{"prefs":{"show_calories":true}}]""")?.showCalories)
        assertEquals(true, parseUniversalSettings("""[{"prefs":{"default_activity_type":"run"}}]""")?.showCalories)
        assertEquals(true, parseUniversalSettings("""[{"prefs":{"show_calories":"nonsense"}}]""")?.showCalories)
        assertEquals(true, parseUniversalSettings("""[{"prefs":{}}]""")?.showCalories)
        // No settings row at all → default on.
        assertEquals(true, parseUniversalSettings("""[]""")?.showCalories)
    }

    @Test
    fun `walk hike cycle all accepted`() {
        for (kind in listOf("walk", "hike", "cycle")) {
            val out = parseUniversalSettings("""[{"prefs":{"default_activity_type":"$kind"}}]""")
            assertEquals(
                "expected $kind round-trip",
                UniversalSettings(defaultActivityType = kind, privacyDefault = null),
                out,
            )
        }
    }

    @Test
    fun `rogue activity value falls back to null rather than poisoning the picker`() {
        // A future client could add 'swim' before the watch ships
        // its picker. The wrist refuses to display a value it
        // doesn't have a chip for — the rule is "either show one
        // of the four chips, or stay on the run default".
        val out = parseUniversalSettings(
            """[{"prefs":{"default_activity_type":"swim"}}]""",
        )
        assertEquals(UniversalSettings(defaultActivityType = null, privacyDefault = null), out)
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
        assertEquals(UniversalSettings(defaultActivityType = null, privacyDefault = null), out)
    }

    @Test
    fun `activity allowlist matches the picker chips`() {
        // The pre-run picker cycles run / walk / hike / cycle (see
        // ui/RunWatchApp.kt). The parser's allowlist must agree —
        // a chip without a matching universal value (or vice
        // versa) would silently desync the two surfaces.
        assertEquals(setOf("run", "walk", "hike", "cycle"), UNIVERSAL_ACTIVITY_TYPES)
    }

    // ---- privacy_default --------------------------------------------------

    @Test
    fun `privacy_default public round-trips`() {
        val out = parseUniversalSettings("""[{"prefs":{"privacy_default":"public"}}]""")
        assertEquals(
            UniversalSettings(defaultActivityType = null, privacyDefault = "public"),
            out,
        )
    }

    @Test
    fun `privacy_default followers and private round-trip`() {
        for (v in listOf("followers", "private")) {
            val out = parseUniversalSettings("""[{"prefs":{"privacy_default":"$v"}}]""")
            assertEquals(
                "expected $v round-trip",
                UniversalSettings(defaultActivityType = null, privacyDefault = v),
                out,
            )
        }
    }

    @Test
    fun `rogue privacy_default value is sanitised away`() {
        // Future / typo / corrupt cells fall through to null so the
        // wrist defaults the row to is_public=false (DB default).
        val out = parseUniversalSettings(
            """[{"prefs":{"privacy_default":"unlisted"}}]""",
        )
        assertEquals(
            UniversalSettings(defaultActivityType = null, privacyDefault = null),
            out,
        )
    }

    @Test
    fun `both fields decoded independently`() {
        // Two prefs in the same bag — neither should suppress the
        // other. Pins the cross-field independence the wire path
        // relies on.
        val out = parseUniversalSettings(
            """[{"prefs":{"default_activity_type":"hike","privacy_default":"public"}}]""",
        )
        assertEquals(
            UniversalSettings(defaultActivityType = "hike", privacyDefault = "public"),
            out,
        )
    }

    @Test
    fun `privacy allowlist matches the documented schema`() {
        // docs/backend/settings.md pins the editor as {public, followers,
        // private}. Drift here = bag values the wrist silently
        // ignores. If a future migration adds a value, extend both
        // this test and `UNIVERSAL_PRIVACY_DEFAULTS` together.
        assertEquals(setOf("public", "followers", "private"), UNIVERSAL_PRIVACY_DEFAULTS)
    }

    // ---- hr_zones + zone math ---------------------------------------------

    @Test
    fun `valid hr_zones round-trip as a 5-int list`() {
        val out = parseUniversalSettings(
            """[{"prefs":{"hr_zones":{"z1":114,"z2":133,"z3":152,"z4":171,"z5":190}}}]""",
        )
        assertEquals(listOf(114, 133, 152, 171, 190), out?.hrZones)
    }

    @Test
    fun `hr_zones with a missing key is rejected`() {
        // Pre-fix: parsing would have returned a 4-element list. The
        // wrist would then crash or render Z5 for every bpm above
        // cutoff[3]. Forcing all-or-nothing keeps the contract clear.
        val out = parseUniversalSettings(
            """[{"prefs":{"hr_zones":{"z1":114,"z2":133,"z3":152,"z4":171}}}]""",
        )
        assertNull(out?.hrZones)
    }

    @Test
    fun `hr_zones not strictly ascending is rejected`() {
        // Catches the "z3 < z2" misconfiguration that an older client
        // could have produced. The Z calculator would otherwise pick
        // a misleading zone.
        val out = parseUniversalSettings(
            """[{"prefs":{"hr_zones":{"z1":114,"z2":133,"z3":152,"z4":152,"z5":190}}}]""",
        )
        assertNull(out?.hrZones)
    }

    @Test
    fun `hr_zones out-of-range entries are rejected`() {
        // 300 bpm is past the human ceiling; 20 is well below
        // resting. Either should sanitize the whole bag away.
        val outHigh = parseUniversalSettings(
            """[{"prefs":{"hr_zones":{"z1":114,"z2":133,"z3":152,"z4":171,"z5":300}}}]""",
        )
        assertNull(outHigh?.hrZones)
        val outLow = parseUniversalSettings(
            """[{"prefs":{"hr_zones":{"z1":20,"z2":133,"z3":152,"z4":171,"z5":190}}}]""",
        )
        assertNull(outLow?.hrZones)
    }

    @Test
    fun `resting and max hr round-trip with valid range`() {
        val out = parseUniversalSettings(
            """[{"prefs":{"resting_hr_bpm":52,"max_hr_bpm":195}}]""",
        )
        assertEquals(52, out?.restingHrBpm)
        assertEquals(195, out?.maxHrBpm)
    }

    @Test
    fun `out-of-range resting and max hr are sanitised`() {
        // resting in [25, 120], max in [100, 240]. Anything outside
        // is treated as a corrupt write and zeroed.
        val out = parseUniversalSettings(
            """[{"prefs":{"resting_hr_bpm":15,"max_hr_bpm":80}}]""",
        )
        assertNull(out?.restingHrBpm)
        assertNull(out?.maxHrBpm)
    }

    @Test
    fun `date_of_birth round-trips when shaped correctly`() {
        val out = parseUniversalSettings(
            """[{"prefs":{"date_of_birth":"1990-04-15"}}]""",
        )
        assertEquals("1990-04-15", out?.dateOfBirth)
    }

    @Test
    fun `malformed date_of_birth is sanitised away`() {
        // The consumer parses via java.time.LocalDate later; we
        // gate obvious garbage here so the DOB read path can't
        // surface a parser exception.
        for (bad in listOf("not-a-date", "1990-13-99", "90-04-15", "1990/04/15", "1990-04")) {
            val out = parseUniversalSettings(
                """[{"prefs":{"date_of_birth":"$bad"}}]""",
            )
            // We only require the shape gate, not full calendar
            // validation. `1990-13-99` passes the shape gate
            // (10 chars, hyphens at 4/7, digits) so it's caught
            // in `ageBasedMaxHr`'s try/catch. The other four
            // fail the shape gate.
            if (bad == "1990-13-99") {
                assertEquals(bad, out?.dateOfBirth)
            } else {
                assertNull("expected $bad to be rejected at parse time", out?.dateOfBirth)
            }
        }
    }

    @Test
    fun `hrZoneOf maps each band correctly with explicit cutoffs`() {
        val c = listOf(114, 133, 152, 171, 190)
        // Boundary on the upper edge of each band is "in" that band
        // (≤ cutoff). One above goes to the next.
        assertEquals(1, hrZoneOf(80, c))
        assertEquals(1, hrZoneOf(114, c))
        assertEquals(2, hrZoneOf(115, c))
        assertEquals(2, hrZoneOf(133, c))
        assertEquals(3, hrZoneOf(150, c))
        assertEquals(4, hrZoneOf(170, c))
        assertEquals(5, hrZoneOf(191, c))
        assertEquals(5, hrZoneOf(220, c))
    }

    @Test
    fun `hrZoneOf returns null when cutoffs missing or malformed`() {
        assertNull(hrZoneOf(150, null))
        assertNull(hrZoneOf(150, emptyList()))
        assertNull(hrZoneOf(150, listOf(100, 110, 120, 130))) // 4 entries
    }

    @Test
    fun `resolveZoneCutoffs prefers explicit hr_zones`() {
        val s = UniversalSettings(
            defaultActivityType = null,
            privacyDefault = null,
            hrZones = listOf(110, 120, 130, 140, 150),
            maxHrBpm = 195, // ignored because hr_zones win
        )
        assertEquals(listOf(110, 120, 130, 140, 150), resolveZoneCutoffs(s, 0L))
    }

    @Test
    fun `resolveZoneCutoffs derives from max_hr_bpm when hr_zones missing`() {
        // 60/70/80/90/100% of 200 = 120/140/160/180/200.
        val s = UniversalSettings(
            defaultActivityType = null,
            privacyDefault = null,
            maxHrBpm = 200,
        )
        assertEquals(listOf(120, 140, 160, 180, 200), resolveZoneCutoffs(s, 0L))
    }

    @Test
    fun `resolveZoneCutoffs derives from dob via Tanaka 208 minus 0_7 age`() {
        // Born 1990-01-01; "now" of 2026-01-01 → 36 years old.
        // Tanaka: 208 − 0.7×36 = 182.8 → round → 183 max.
        val s = UniversalSettings(
            defaultActivityType = null,
            privacyDefault = null,
            dateOfBirth = "1990-01-01",
        )
        val now2026 = java.time.LocalDate.of(2026, 1, 1)
            .atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
        // round(183 × 60/70/80/90/100%) = 110, 128, 146, 165, 183.
        assertEquals(listOf(110, 128, 146, 165, 183), resolveZoneCutoffs(s, now2026))
    }

    @Test
    fun `resolveZoneCutoffs returns null when no signal available`() {
        // Empty bag → no zones to show. This is the one place the three
        // hr_zones rails differ on purpose: web and Dart end their ladder at
        // the legacy 190 cutoffs, the watch shows nothing rather than a
        // stranger's zones (decisions § 1245).
        val s = UniversalSettings(defaultActivityType = null, privacyDefault = null)
        assertNull(resolveZoneCutoffs(s, 0L))
    }

    // `max_hr_bpm` is a jsonb prefs key with no CHECK and the web preferences
    // page writes it as a bare parseInt, so an out-of-range value really does
    // reach here. Applying it flat gave the same run different zones on the
    // watch and the phone.
    @Test
    fun `resolveZoneCutoffs ignores a max_hr_bpm outside the usable range`() {
        for (bpm in listOf(300, 79, 0, -1)) {
            val s = UniversalSettings(
                defaultActivityType = null,
                privacyDefault = null,
                maxHrBpm = bpm,
            )
            assertNull(resolveZoneCutoffs(s, 0L))
        }
    }

    @Test
    fun `resolveZoneCutoffs falls through an out-of-range max_hr_bpm to age`() {
        // Born 1990-01-01, "now" 2026-01-01 → 36 → Tanaka 183.
        val s = UniversalSettings(
            defaultActivityType = null,
            privacyDefault = null,
            maxHrBpm = 300,
            dateOfBirth = "1990-01-01",
        )
        val now2026 = java.time.LocalDate.of(2026, 1, 1)
            .atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
        assertEquals(listOf(110, 128, 146, 165, 183), resolveZoneCutoffs(s, now2026))
    }

    @Test
    fun `resolveZoneCutoffs accepts both ends of the usable range`() {
        for (bpm in listOf(80, 240)) {
            val s = UniversalSettings(
                defaultActivityType = null,
                privacyDefault = null,
                maxHrBpm = bpm,
            )
            assertEquals(bpm, resolveZoneCutoffs(s, 0L)?.last())
        }
    }
}
