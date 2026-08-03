package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Locale

/// Pure decomposition contract for the watch's voice cues. The audible
/// wording now lives in `res/values*/strings.xml` (assembled by
/// `TtsAnnouncer` against the device locale) — same dialect as
/// `apps/mobile_android/lib/l10n/app_*.arb`. What stays pure here is the
/// numeric decomposition: minute/second truncation and the
/// locale-independent spoken distance. The translated phrases themselves are
/// covered by `L10nResourceParityTest` (every locale declares every key).
class TtsPhrasesTest {

    // ─────────────────── paceMinSec ───────────────────

    @Test fun `pace 5 min 30 sec per km`() {
        assertEquals(5 to 30, paceMinSec(330.0))
    }

    @Test fun `pace truncates seconds floor (not round-half-up)`() {
        // 5:45.7 = 345.7 sec → 5 min 45 sec, not 5 min 46 sec.
        assertEquals(5 to 45, paceMinSec(345.7))
    }

    @Test fun `pace under 1 min has zero minutes`() {
        assertEquals(0 to 45, paceMinSec(45.0))
    }

    @Test fun `pace null returns null (caller omits the tail)`() {
        assertNull(paceMinSec(null))
    }

    @Test fun `pace zero returns null`() {
        assertNull(paceMinSec(0.0))
    }

    @Test fun `pace negative returns null`() {
        // Defensive: a negative pace would otherwise speak "minus 5
        // minutes", a synth-glitch read-out. Suppress to null.
        assertNull(paceMinSec(-30.0))
    }

    // ─────────────────── finishMinutes ───────────────────

    @Test fun `finish minutes truncate (not round-half-up)`() {
        // 89 sec = 1.48 min → 1 minute, not 2.
        assertEquals(1, finishMinutes(89))
        assertEquals(27, finishMinutes(1_620))
        assertEquals(0, finishMinutes(0))
    }

    // ─────────────────── paceMinSecFor ───────────────────

    @Test fun `pace for km is the recorder value untouched`() {
        assertEquals(5 to 30, paceMinSecFor(330.0, DistanceUnit.KM))
    }

    @Test fun `pace for mi scales the per-km value to the mile`() {
        // 5:00/km = 300 s/km → 300 × 1.609344 = 482.8 s/mi → 8:02.
        assertEquals(8 to 2, paceMinSecFor(300.0, DistanceUnit.MI))
    }

    @Test fun `pace for mi is always slower-sounding than the km figure`() {
        // The regression this closes: a mi-mode runner used to hear the
        // *kilometre* pace under a kilometre label. Both halves move.
        val km = paceMinSecFor(270.0, DistanceUnit.KM)!!
        val mi = paceMinSecFor(270.0, DistanceUnit.MI)!!
        assertEquals(4 to 30, km)
        assertEquals(7 to 14, mi)
    }

    @Test fun `pace null or non-positive stays null in both units`() {
        assertNull(paceMinSecFor(null, DistanceUnit.MI))
        assertNull(paceMinSecFor(0.0, DistanceUnit.MI))
        assertNull(paceMinSecFor(-30.0, DistanceUnit.MI))
        assertNull(paceMinSecFor(null, DistanceUnit.KM))
    }

    // ─────────────────── finishDistanceSpoken ───────────────────

    @Test fun `finish distance uses period decimal regardless of locale`() {
        // A comma would TTS-read as the word "comma" — the spoken figure
        // must always use a period even on a German-locale watch.
        val def = Locale.getDefault()
        try {
            Locale.setDefault(Locale.GERMANY)
            assertEquals("5.32", finishDistanceSpoken(5_323.0, DistanceUnit.KM))
            assertEquals("0.00", finishDistanceSpoken(0.0, DistanceUnit.KM))
            assertEquals("0.10", finishDistanceSpoken(100.0, DistanceUnit.KM))
        } finally {
            Locale.setDefault(def)
        }
    }

    @Test fun `finish distance converts to miles for a mi runner`() {
        // A 10 km run is 6.21 mi — the run-complete phrase must not read
        // "10.00 miles".
        assertEquals("6.21", finishDistanceSpoken(10_000.0, DistanceUnit.MI))
        assertEquals("1.00", finishDistanceSpoken(1_609.344, DistanceUnit.MI))
        assertEquals("0.00", finishDistanceSpoken(0.0, DistanceUnit.MI))
    }
}
