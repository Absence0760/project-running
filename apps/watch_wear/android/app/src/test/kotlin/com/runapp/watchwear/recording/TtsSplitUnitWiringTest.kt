package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guard for the miles-runner voice cue (issue #664). The pure
/// halves — the split cadence and the pace/distance conversion — are pinned
/// in `UnitFormatTest` / `TtsPhrasesTest`; what can't be exercised on the
/// host JVM is the wiring between them: the service must feed its stamped
/// `preferredUnit` into BOTH the split *trigger* and the spoken phrase, and
/// the announcer must pick the `_mi` resources when it does. Neither is
/// reachable without Robolectric (a Service + a Resources lookup), so it's
/// pinned with a source grep per the module's convention (see
/// `StopTeardownWiringTest`).
class TtsSplitUnitWiringTest {

    private val service: String =
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt").readText()

    private val announcer: String =
        File("src/main/kotlin/com/runapp/watchwear/recording/TtsAnnouncer.kt").readText()

    private val strings: String = File("src/main/res/values/strings.xml").readText()

    @Test
    fun `the split trigger is unit-aware, not a hardcoded kilometre`() {
        assertTrue(
            "the split cue must fire off completedSplits(distance, preferredUnit)",
            Regex("""completedSplits\(\s*newDistance\s*,\s*preferredUnit\s*\)""")
                .containsMatchIn(service),
        )
        assertFalse(
            "no bare /1000 split trigger — that cues a mi runner every kilometre",
            Regex("""(?i)val\s+current\w*\s*=\s*\(\s*newDistance\s*/\s*1000""")
                .containsMatchIn(service),
        )
    }

    @Test
    fun `both spoken cues are handed the run's preferred unit`() {
        assertTrue(
            "announceSplit must receive preferredUnit",
            Regex("""announceSplit\([^)]*preferredUnit""").containsMatchIn(service),
        )
        assertTrue(
            "announceFinish must receive preferredUnit",
            Regex("""announceFinish\([^)]*preferredUnit""").containsMatchIn(service),
        )
    }

    @Test
    fun `the announcer selects the mi resources for a mi runner`() {
        for (key in listOf("tts_split_unit", "tts_pace_tail", "tts_run_complete")) {
            assertTrue(
                "$key must have a MI branch in TtsAnnouncer",
                announcer.contains("DistanceUnit.MI -> R.${resourceType(key)}.${key}_mi"),
            )
            assertTrue(
                "$key must have a KM branch in TtsAnnouncer",
                announcer.contains("DistanceUnit.KM -> R.${resourceType(key)}.${key}_km"),
            )
        }
    }

    @Test
    fun `no unit-less spoken resource survives in the default strings`() {
        // A leftover `tts_pace_tail` (no suffix) would compile and speak
        // "per kilometre" to a miles runner — exactly the defect.
        for (key in listOf("tts_split_unit", "tts_pace_tail", "tts_run_complete")) {
            assertEquals(
                "$key must exist only as ${key}_km / ${key}_mi",
                emptyList<String>(),
                Regex("""name="$key"""").findAll(strings).map { it.value }.toList(),
            )
            assertTrue("${key}_km missing from values/strings.xml", strings.contains("""name="${key}_km""""))
            assertTrue("${key}_mi missing from values/strings.xml", strings.contains("""name="${key}_mi""""))
        }
    }

    private fun resourceType(key: String): String =
        if (key == "tts_split_unit") "plurals" else "string"
}
