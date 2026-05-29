package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guard for the rotary bezel / crown scroll wiring on the
/// Wear OS scrollable list screens (persona samsung #32). Galaxy Watch
/// users expect the physical bezel to scroll; Pixel Watch users expect
/// the crown. `Modifier.rotaryScrollable` + a focused `FocusRequester`
/// is what routes those events into the `ScalingLazyColumn`. Compose UI
/// wiring isn't host-JVM-testable without Robolectric (which this module
/// avoids), so this pins the call sites with a source grep — drop the
/// modifier and this fires instead of the bezel silently going dead.
///
/// Mirrors the `RoutesBridgeWiringTest` / `TtsAudioFocusWiringTest`
/// pattern.
class RotaryScrollWiringTest {

    private val src: String =
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()

    @Test
    fun `rotaryScrollable is imported and used`() {
        assertTrue(
            "RunWatchApp must import androidx.wear.compose.foundation.rotary.rotaryScrollable",
            src.contains("import androidx.wear.compose.foundation.rotary.rotaryScrollable"),
        )
    }

    @Test
    fun `every content-scroll list wires rotaryScrollable with a focus requester`() {
        // The two pure-scroll list screens (BatteryInstructions + the
        // route picker) each attach rotaryScrollable; the sign-in screen
        // is intentionally excluded because its FocusRequester belongs to
        // the text inputs, not the list (auto-focusing the list would
        // steal focus from typing).
        val rotaryCount = Regex("""\.rotaryScrollable\(""").findAll(src).count()
        assertTrue(
            "expected >= 2 rotaryScrollable call sites (BatteryInstructions + RoutePicker), " +
                "found $rotaryCount",
            rotaryCount >= 2,
        )
        // Each rotaryScrollable must be paired with a requestFocus() so it
        // actually receives rotary events.
        val requestFocusCount = Regex("""rotaryFocus\.requestFocus\(\)""").findAll(src).count()
        assertEquals(
            "each rotary list needs its FocusRequester focused",
            rotaryCount,
            requestFocusCount,
        )
    }
}
