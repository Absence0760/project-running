package com.runapp.watchwear.recording

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.runapp.watchwear.R
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger

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

    private val appContext = context.applicationContext

    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // USAGE_ASSISTANCE_NAVIGATION_GUIDANCE asks the platform to duck
    // (briefly lower) other audio rather than pause it. On Samsung One
    // UI the attribute alone is not enough — without an explicit
    // AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK request a cue can fully pause
    // the runner's Spotify (persona round-5 samsung-watch). The same
    // attributes back both the TTS engine and the focus request so they
    // agree on the ducking contract.
    private val audioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

    private val focusRequest =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(audioAttributes)
            // Cues never resume after a duck-and-pause from a higher
            // priority owner; we re-request focus per utterance, so we
            // don't need pause/resume callbacks here.
            .setWillPauseWhenDucked(false)
            .build()

    // Concurrent in-flight utterances. Cues use QUEUE_FLUSH (one at a
    // time) but ref-counting keeps focus held across a rapid
    // start→done→start sequence and guarantees we never abandon focus
    // while audio is still playing, nor leak it on an error path.
    private val pendingUtterances = AtomicInteger(0)
    @Volatile private var holdsFocus = false

    init {
        // Construct lazily — the engine init spawns a thread and
        // doesn't block the caller.
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                // Speak in the device locale so split / pace cues match the
                // UI language. If the engine has no voice data for that
                // locale, setLanguage returns LANG_MISSING_DATA /
                // LANG_NOT_SUPPORTED and the engine keeps its default voice —
                // the cue is still spoken (best-effort), just in another
                // accent, which beats silence.
                tts?.language = Locale.getDefault()
                tts?.setSpeechRate(0.5f)
                tts?.setAudioAttributes(audioAttributes)
                tts?.setOnUtteranceProgressListener(
                    object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}

                        override fun onDone(utteranceId: String?) =
                            releaseFocusIfIdle()

                        @Deprecated("Required override; onError(id, code) is the live path")
                        override fun onError(utteranceId: String?) =
                            releaseFocusIfIdle()

                        override fun onError(utteranceId: String?, errorCode: Int) =
                            releaseFocusIfIdle()
                    },
                )
                ready = true
            }
        }
    }

    fun announceStart() = speak(appContext.getString(R.string.tts_run_started))

    fun announceFinish(distanceM: Double, durationS: Int) =
        speak(
            appContext.getString(
                R.string.tts_run_complete,
                finishDistanceSpoken(distanceM),
                finishMinutes(durationS),
            ),
        )

    /// Announce a split at the end of kilometre [km], pacing reported
    /// in seconds-per-km. Mirrors the Android wording so a runner
    /// carrying both devices doesn't hear two different dialects.
    fun announceSplit(km: Int, paceSecPerKm: Double?) {
        val res = appContext.resources
        val unit = res.getQuantityString(R.plurals.tts_split_unit, km, km)
        val ms = paceMinSec(paceSecPerKm)
        val tail = if (ms == null) {
            ""
        } else {
            appContext.getString(R.string.tts_pace_tail, ms.first, ms.second)
        }
        speak(appContext.getString(R.string.tts_split_phrase, unit, tail))
    }

    fun announcePaceAlert(tooSlow: Boolean) =
        speak(
            appContext.getString(
                if (tooSlow) R.string.tts_pace_alert_fast else R.string.tts_pace_alert_slow,
            ),
        )

    fun shutdown() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Throwable) { /* best-effort */ }
        // Drop any focus we still hold — stop() doesn't fire onDone.
        pendingUtterances.set(0)
        abandonFocus()
        tts = null
        ready = false
    }

    private fun speak(phrase: String) {
        // Allow empty phrases to no-op silently (formatPaceTail
        // returns "" when pace is unknown, which the split caller
        // appends unconditionally).
        if (!ready || phrase.isBlank()) return
        try {
            requestFocus()
            pendingUtterances.incrementAndGet()
            val utteranceId = "cue-${System.nanoTime()}"
            val result =
                tts?.speak(phrase, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
            // speak() returning ERROR means no onDone/onError will
            // fire, so release the count we just took to avoid a leak.
            if (result != TextToSpeech.SUCCESS) {
                if (pendingUtterances.decrementAndGet() <= 0) abandonFocus()
            }
        } catch (_: Throwable) {
            // The speak attempt may have already taken a count above.
            if (pendingUtterances.decrementAndGet() < 0) pendingUtterances.set(0)
            if (pendingUtterances.get() <= 0) abandonFocus()
        }
    }

    private fun releaseFocusIfIdle() {
        if (pendingUtterances.decrementAndGet() <= 0) {
            pendingUtterances.set(0)
            abandonFocus()
        }
    }

    private fun requestFocus() {
        if (holdsFocus) return
        try {
            audioManager.requestAudioFocus(focusRequest)
            holdsFocus = true
        } catch (_: Throwable) { /* best-effort — still speak */ }
    }

    private fun abandonFocus() {
        if (!holdsFocus) return
        holdsFocus = false
        try {
            audioManager.abandonAudioFocusRequest(focusRequest)
        } catch (_: Throwable) { /* best-effort */ }
    }
}
