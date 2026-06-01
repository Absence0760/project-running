package com.runapp.watchwear

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guard for the TTS audio-focus ducking wiring (persona
/// android + samsung #12, persona round-5 samsung-watch). `TtsAnnouncer`
/// builds an `android.media.AudioAttributes`, calls
/// `TextToSpeech.setAudioAttributes`, and explicitly requests
/// `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` audio focus around each
/// utterance so a split / pace cue ducks the runner's music instead of
/// hard-interrupting / pausing it (the attribute alone is unreliable on
/// Samsung One UI). Focus is abandoned when the utterance completes.
/// The init + focus calls run against real Android media APIs (no
/// host-JVM path without Robolectric, which this module avoids), so the
/// behaviour is pinned with a source grep: drop the ducking config and
/// this fires.
///
/// Mirrors the `RoutesBridgeWiringTest` / `RouteMiniMapWiringTest`
/// pattern.
class TtsAudioFocusWiringTest {

    private fun read(rel: String): String =
        File("src/main/kotlin/com/runapp/watchwear/$rel").readText()

    @Test
    fun `TtsAnnouncer sets navigation-guidance audio attributes`() {
        val src = read("recording/TtsAnnouncer.kt")
        assertTrue(
            "TtsAnnouncer must call setAudioAttributes so cues request " +
                "audio focus (and duck other audio) — persona #12",
            src.contains("setAudioAttributes("),
        )
        assertTrue(
            "TtsAnnouncer must use USAGE_ASSISTANCE_NAVIGATION_GUIDANCE so " +
                "the platform ducks music instead of pausing it",
            src.contains("USAGE_ASSISTANCE_NAVIGATION_GUIDANCE"),
        )
    }

    @Test
    fun `TtsAnnouncer requests transient ducking audio focus around cues`() {
        val src = read("recording/TtsAnnouncer.kt")
        assertTrue(
            "TtsAnnouncer must request AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK so " +
                "Samsung One UI ducks music instead of pausing it — persona " +
                "round-5 samsung-watch",
            src.contains("AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK"),
        )
        assertTrue(
            "TtsAnnouncer must actually request focus before speaking",
            src.contains("requestAudioFocus("),
        )
        assertTrue(
            "TtsAnnouncer must abandon focus when the cue completes so the " +
                "duck releases and music returns to full volume",
            src.contains("abandonAudioFocusRequest("),
        )
        assertTrue(
            "TtsAnnouncer must hook utterance completion to drive focus " +
                "release (abandon on done/error, never leak focus)",
            src.contains("UtteranceProgressListener"),
        )
    }
}
