package com.runapp.watchwear.recording

import org.junit.Assert.assertEquals
import org.junit.Test

/// Pinned phrasing for the watch's voice cues. Same dialect as
/// `apps/mobile_android/lib/audio_cues.dart` — a runner carrying
/// both devices must hear the same words from each, otherwise the
/// brain mishears one as a correction of the other.
///
/// Why these tests matter: TTS engines mispronounce wrong-form
/// strings distinctively enough that the user notices ("1
/// kilometres" pronounced with the wrong S-elision is jarring).
/// A copy-edit that breaks a phrasing fails a test before it ships
/// to a paired-device user who hears the divergence on their next
/// long run.
class TtsPhrasesTest {

    // ─────────────────── formatPaceTail ───────────────────

    @Test fun `pace tail at 5 min 30 sec per km`() {
        assertEquals(
            "Pace 5 minutes 30 seconds per kilometre",
            formatPaceTail(330.0),
        )
    }

    @Test fun `pace tail truncates seconds floor (5_45 reads as 5_45)`() {
        // Integer truncation: 5:45.7 = 345.7 sec → "5 minutes 45
        // seconds", not "5 minutes 46 seconds". Pin so a refactor
        // doesn't switch to round-half-up.
        assertEquals(
            "Pace 5 minutes 45 seconds per kilometre",
            formatPaceTail(345.7),
        )
    }

    @Test fun `pace tail under 1 min sec only`() {
        assertEquals(
            "Pace 0 minutes 45 seconds per kilometre",
            formatPaceTail(45.0),
        )
    }

    @Test fun `pace tail null returns empty (caller appends unconditionally)`() {
        // The split-announce path appends the pace tail to a
        // sentence. When pace is unknown (no stabilisation gate
        // met), an empty tail lets the caller emit only the
        // kilometre count.
        assertEquals("", formatPaceTail(null))
    }

    @Test fun `pace tail zero returns empty`() {
        assertEquals("", formatPaceTail(0.0))
    }

    @Test fun `pace tail negative returns empty`() {
        // Defensive: if a stale buffer or arithmetic bug ever
        // produced a negative pace, we'd say "Pace -5 minutes
        // -30 seconds" which sounds like a synth-glitch. Pin
        // empty-string suppression.
        assertEquals("", formatPaceTail(-30.0))
    }

    // ─────────────────── formatSplitPhrase ───────────────────

    @Test fun `split phrase 1 km uses singular kilometre`() {
        // Singular: "1 kilometre" (no S). English TTS engines
        // mispronounce "1 kilometres" distinctively enough that the
        // runner notices.
        assertEquals(
            "1 kilometre. Pace 5 minutes 0 seconds per kilometre",
            formatSplitPhrase(1, 300.0),
        )
    }

    @Test fun `split phrase 2+ km uses plural kilometres`() {
        assertEquals(
            "2 kilometres. Pace 5 minutes 30 seconds per kilometre",
            formatSplitPhrase(2, 330.0),
        )
        assertEquals(
            "10 kilometres. Pace 4 minutes 15 seconds per kilometre",
            formatSplitPhrase(10, 255.0),
        )
    }

    @Test fun `split phrase with null pace omits the pace tail`() {
        // The unit-word + period + space + empty tail comes through
        // as "1 kilometre. " (trailing space). Caller's speak()
        // tolerates trailing whitespace; TTS engines elide it.
        assertEquals(
            "1 kilometre. ",
            formatSplitPhrase(1, null),
        )
    }

    // ─────────────────── formatFinishPhrase ───────────────────

    @Test fun `finish phrase rounds km to 2 decimals`() {
        assertEquals(
            "Run complete. 5.32 kilometres in 27 minutes.",
            formatFinishPhrase(distanceM = 5_323.0, durationS = 1_620),
        )
    }

    @Test fun `finish phrase minutes truncate (not round-half-up)`() {
        // 89 sec = 1.48 min → "1 minutes" (not "1.5" or "2").
        assertEquals(
            "Run complete. 0.10 kilometres in 1 minutes.",
            formatFinishPhrase(distanceM = 100.0, durationS = 89),
        )
    }

    @Test fun `finish phrase zero-distance edge case`() {
        // Pause-at-start, stop immediately → 0 km / 0 min. Should
        // produce a coherent (if odd) sentence rather than crash.
        assertEquals(
            "Run complete. 0.00 kilometres in 0 minutes.",
            formatFinishPhrase(distanceM = 0.0, durationS = 0),
        )
    }

    @Test fun `finish phrase locale-independent decimal separator`() {
        // .format("%.2f") on a Double uses the default locale's
        // decimal separator. The watch ships with US locale on
        // TtsAnnouncer init — pin that the formatter doesn't pick
        // up a localised "5,32" (comma) which would TTS-read as
        // "5 comma 32".
        val out = formatFinishPhrase(distanceM = 5_323.0, durationS = 1_620)
        assertEquals(
            "Decimal must be a period — '5,32' would mispronounce on US-English TTS.",
            true,
            out.contains("5.32"),
        )
    }

    // ─────────────────── formatPaceAlert ───────────────────

    @Test fun `pace alert tooSlow=true says pick up the pace`() {
        assertEquals("Pick up the pace", formatPaceAlert(true))
    }

    @Test fun `pace alert tooSlow=false says slow down`() {
        assertEquals("Slow down", formatPaceAlert(false))
    }

    // ─────────────────── RUN_STARTED_PHRASE ───────────────────

    @Test fun `run-started phrase is pinned to 'Run started'`() {
        // The runner's muscle memory associates this exact wording
        // with the end of the 3-2-1 countdown.
        assertEquals("Run started", RUN_STARTED_PHRASE)
    }

    // ─────────────────── end-to-end realistic splits ───────────────────

    @Test fun `realistic 5K splits sound natural`() {
        // Sweep through what a 5K runner hears: 5 km splits at
        // varied paces. The combination of singular/plural + pace
        // tail should read naturally each time.
        val expected = listOf(
            "1 kilometre. Pace 5 minutes 0 seconds per kilometre",
            "2 kilometres. Pace 4 minutes 55 seconds per kilometre",
            "3 kilometres. Pace 5 minutes 5 seconds per kilometre",
            "4 kilometres. Pace 4 minutes 50 seconds per kilometre",
            "5 kilometres. Pace 4 minutes 40 seconds per kilometre",
        )
        val actual = listOf(
            formatSplitPhrase(1, 300.0),
            formatSplitPhrase(2, 295.0),
            formatSplitPhrase(3, 305.0),
            formatSplitPhrase(4, 290.0),
            formatSplitPhrase(5, 280.0),
        )
        assertEquals(expected, actual)
    }
}
