package com.runapp.watchwear.recording

import android.content.Context
import android.media.AudioAttributes
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
                // Navigation-guidance usage makes the platform request
                // transient ducking, so a cue lowers the runner's music
                // / podcast instead of hard-interrupting it. Matches the
                // phone's setAudioAttributesForNavigation path (persona
                // android + samsung #12).
                tts?.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                ready = true
            }
        }
    }

    fun announceStart() = speak(RUN_STARTED_PHRASE)

    fun announceFinish(distanceM: Double, durationS: Int) =
        speak(formatFinishPhrase(distanceM, durationS))

    /// Announce a split at the end of kilometre [km], pacing reported
    /// in seconds-per-km. Mirrors the Android wording so a runner
    /// carrying both devices doesn't hear two different dialects.
    fun announceSplit(km: Int, paceSecPerKm: Double?) =
        speak(formatSplitPhrase(km, paceSecPerKm))

    fun announcePaceAlert(tooSlow: Boolean) =
        speak(formatPaceAlert(tooSlow))

    fun shutdown() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Throwable) { /* best-effort */ }
        tts = null
        ready = false
    }

    private fun speak(phrase: String) {
        // Allow empty phrases to no-op silently (formatPaceTail
        // returns "" when pace is unknown, which the split caller
        // appends unconditionally).
        if (!ready || phrase.isBlank()) return
        try {
            tts?.speak(phrase, TextToSpeech.QUEUE_FLUSH, null, null)
        } catch (_: Throwable) { /* best-effort */ }
    }
}
