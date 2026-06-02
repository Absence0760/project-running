package com.runapp.watchwear

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guard for the TTS localization wiring. The spoken cues must
/// (a) speak in the device locale, not a hard-coded US English voice, and
/// (b) read their phrasing from `strings.xml` resources so the words match
/// the UI language. Both are bound to real Android APIs (TextToSpeech +
/// Resources) with no host-JVM path without Robolectric, which this module
/// avoids — so the behaviour is pinned with a source grep, mirroring
/// `TtsAudioFocusWiringTest`.
class TtsLocaleWiringTest {

    private fun read(rel: String): String =
        File("src/main/kotlin/com/runapp/watchwear/$rel").readText()

    @Test
    fun `TtsAnnouncer follows the device locale`() {
        val src = read("recording/TtsAnnouncer.kt")
        assertTrue(
            "TtsAnnouncer must set the TTS language to Locale.getDefault() so " +
                "cues are spoken in the device language",
            src.contains("Locale.getDefault()"),
        )
        assertFalse(
            "TtsAnnouncer must NOT hard-code Locale.US for the spoken language " +
                "— that would speak English cues on a German watch",
            src.contains("tts?.language = Locale.US"),
        )
    }

    @Test
    fun `TtsAnnouncer assembles phrases from string resources`() {
        val src = read("recording/TtsAnnouncer.kt")
        assertTrue(
            "TtsAnnouncer must read the run-started phrase from resources",
            src.contains("R.string.tts_run_started"),
        )
        assertTrue(
            "TtsAnnouncer must read the run-complete phrase from resources",
            src.contains("R.string.tts_run_complete"),
        )
        assertTrue(
            "TtsAnnouncer must read the pace-alert phrases from resources",
            src.contains("R.string.tts_pace_alert_fast") &&
                src.contains("R.string.tts_pace_alert_slow"),
        )
        assertTrue(
            "TtsAnnouncer must use a plural resource for the split km unit so " +
                "singular/plural reads correctly per locale",
            src.contains("R.plurals.tts_split_unit"),
        )
    }
}
