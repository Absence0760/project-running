package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// A sensor the runner declined must cost that sensor, and nothing else.
///
/// `RunRecordingService` collects three device streams inside
/// `scope.launch { ... }`. A `SupervisorJob` stops a failing child from
/// cancelling its siblings; it does NOT stop an unhandled exception in a
/// `launch` reaching the thread's uncaught handler, which on Android is
/// the process. So a throw from any of the three took down the run —
/// GPS trace, elapsed clock and all — from inside an auxiliary layer, the
/// exact inversion `docs/architecture/conventions.md` § Layered resilience
/// forbids.
///
/// It was reachable without any device fault. `permissionLauncher` gates
/// the countdown on ACCESS_FINE_LOCATION alone, so a runner who grants
/// location and declines BODY_SENSORS starts a run whose
/// `registerMeasureCallback` raises `SecurityException` immediately;
/// `apps/watch_wear/local_testing.md` documented the resulting crash as a
/// known first-launch symptom and attributed it to a gate that does not
/// exist.
///
/// Compose and Health Services are not host-JVM-drivable (this module
/// deliberately carries no Robolectric), so these are source-level guards
/// in the same idiom as `RotaryScrollWiringTest` and
/// `TtsAudioFocusWiringTest`. Both files live under `src/main/kotlin`, so
/// Gradle tracks them as test inputs through the compile task and a
/// mutation re-runs this without `--rerun-tasks`.
class SensorStreamResilienceTest {

    private val serviceSource: String by lazy {
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt")
            .readText()
    }

    private val hrSource: String by lazy {
        File("src/main/kotlin/com/runapp/watchwear/HeartRateMonitor.kt").readText()
    }

    /// Drop whole-line `//` comments so a rationale written between the
    /// stream and its `.catch` does not read as a missing `.catch`. Only
    /// lines that are entirely a comment are removed, so a `//` inside a
    /// string literal is untouched.
    private fun withoutCommentLines(src: String): String =
        src.lineSequence()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

    @Test
    fun `every device stream the recording service collects is guarded`() {
        // Derived from the source, not listed: a fourth sensor added
        // tomorrow is covered by this without anyone remembering to add it.
        val src = withoutCommentLines(serviceSource)
        val streams = Regex("""(\w+)\.stream\(\)""").findAll(src).map { it.value }.toList()
        assertTrue(
            "no `<x>.stream()` collection parsed out of RunRecordingService — " +
                "the guard is reading nothing and would pass on anything",
            streams.size >= 3,
        )
        val unguarded = Regex("""(\w+)\.stream\(\)(?!\s*\.catch)""")
            .findAll(src)
            .map { it.groupValues[1] }
            .sorted()
            .toList()
        assertEquals(
            "collected in RunRecordingService without a `.catch`, so a throw " +
                "from the sensor reaches the uncaught handler and ends the " +
                "run: $unguarded",
            emptyList<String>(),
            unguarded,
        )
    }

    @Test
    fun `heart-rate registration reports its failure instead of going quiet`() {
        // `MeasureCallback.onRegistrationFailed` has an empty default body.
        // Not overriding it is not "no failure" — it is a failure nobody is
        // told about: no samples, no error, avg_bpm null.
        assertTrue(
            "HeartRateMonitor must override onRegistrationFailed and close " +
                "the flow — an unimplemented default turns a refusal into silence",
            Regex("""override\s+fun\s+onRegistrationFailed\s*\([^)]*\)\s*\{[^}]*close\(\)""")
                .containsMatchIn(hrSource),
        )
    }

    @Test
    fun `heart-rate registration cannot throw out of the flow`() {
        // The synchronous half: SecurityException when BODY_SENSORS was
        // declined, IllegalStateException on a watch with no Health Services.
        assertTrue(
            "client.registerMeasureCallback must sit inside a try whose catch " +
                "closes the flow",
            Regex(
                """try\s*\{[^{}]*client\.registerMeasureCallback\([^()]*\)[^{}]*\}\s*catch\s*\([^)]*\)\s*\{[^{}]*close\(\)""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(hrSource),
        )
        assertEquals(
            "exactly one registration call site, or the guard above covers " +
                "one of several",
            1,
            Regex("""client\.registerMeasureCallback""").findAll(hrSource).count(),
        )
    }
}
