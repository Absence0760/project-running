package com.runapp.watchwear

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guard for the TTS audio-focus ducking wiring (persona
/// android + samsung #12). `TtsAnnouncer` builds an
/// `android.media.AudioAttributes` and calls `TextToSpeech.setAudioAttributes`
/// so a split / pace cue ducks the runner's music instead of hard-
/// interrupting it. The init runs inside the engine-ready callback,
/// which needs a real `TextToSpeech` engine (no host-JVM path without
/// Robolectric, which this module avoids), so the behaviour is pinned
/// with a source grep: drop the ducking config and this fires.
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
}
