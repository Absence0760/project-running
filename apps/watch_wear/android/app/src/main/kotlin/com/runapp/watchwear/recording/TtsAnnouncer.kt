package com.runapp.watchwear.recording

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale

/// Thin wrapper around `android.speech.tts.TextToSpeech` used by
/// `RunRecordingService` to speak split announcements and pace alerts.
///
/// Ported in spirit from `apps/mobile_android/lib/audio_cues.dart` —
/// same phrasing ("1 kilometre, pace 5 minutes 30 seconds") so the
/// runner hears the same cues from the watch as from the phone. Engine
/// init is async; calls made before ready are silently dropped rather
/// than queued, because by the time TTS is live the relevant cue has
/// already moved on (worst case: the first km split is silent).
///
/// Safe to call from any thread — `TextToSpeech.speak` is internally
/// thread-safe. The service calls from its Default-dispatcher scope.
class TtsAnnouncer(context: Context) {
    private var tts: TextToSpeech? = null
    @Volatile private var ready: Boolean = false

    init {
        // Construct lazily — the engine init spawns a thread and
        // doesn't block the caller.
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                tts?.setSpeechRate(0.5f)
                ready = true
            }
        }
    }

    fun announceStart() = speak("Run started")

    fun announceFinish(distanceM: Double, durationS: Int) {
        val km = distanceM / 1000.0
        val mins = durationS / 60
        speak("Run complete. %.2f kilometres in %d minutes.".format(km, mins))
    }

    /// Announce a split at the end of kilometre [km], pacing reported
    /// in seconds-per-km. Mirrors the Android wording so a runner
    /// carrying both devices doesn't hear two different dialects.
    fun announceSplit(km: Int, paceSecPerKm: Double?) {
        val unitWord = if (km == 1) "kilometre" else "kilometres"
        val paceTail = formatPace(paceSecPerKm)
        speak("$km $unitWord. $paceTail")
    }

    fun announcePaceAlert(tooSlow: Boolean) {
        speak(if (tooSlow) "Pick up the pace" else "Slow down")
    }

    fun shutdown() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Throwable) { /* best-effort */ }
        tts = null
        ready = false
    }

    private fun speak(phrase: String) {
        if (!ready) return
        try {
            tts?.speak(phrase, TextToSpeech.QUEUE_FLUSH, null, null)
        } catch (_: Throwable) { /* best-effort */ }
    }

    private fun formatPace(secondsPerKm: Double?): String {
        if (secondsPerKm == null || secondsPerKm <= 0) return ""
        val m = (secondsPerKm / 60).toInt()
        val s = (secondsPerKm % 60).toInt()
        return "Pace $m minutes $s seconds per kilometre"
    }
}
