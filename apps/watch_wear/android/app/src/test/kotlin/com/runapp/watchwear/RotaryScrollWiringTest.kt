package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level guard for the rotary bezel / crown scroll wiring on the
/// Wear OS scrollable list screens (persona samsung #32). Galaxy Watch
/// users expect the physical bezel to scroll; Pixel Watch users expect
/// the crown. `Modifier.rotaryScrollable` + a focused `FocusRequester`
/// is what routes those events into the scrollable. Compose UI wiring
/// isn't host-JVM-testable without Robolectric (which this module
/// avoids), so this pins the call sites with a source grep — drop the
/// modifier and this fires instead of the bezel silently going dead.
///
/// Mirrors the `RoutesBridgeWiringTest` / `TtsAudioFocusWiringTest`
/// pattern.
class RotaryScrollWiringTest {

    private val src: String =
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()

    /// One top-level function and the source between its header and the next
    /// one. That span is the scope a `remember { FocusRequester() }` lives in,
    /// so it is the unit the pairing has to hold within: a requester focused in
    /// some OTHER composable is not this list's wiring.
    private data class Fn(val name: String, val body: String)

    private fun functions(): List<Fn> {
        val header = Regex("""(?m)^(?:private |internal |public )?fun\s+(\w+)""")
        val hits = header.findAll(src).toList()
        assertTrue("parsed no top-level functions out of RunWatchApp.kt", hits.isNotEmpty())
        return hits.mapIndexed { i, m ->
            val end = if (i + 1 < hits.size) hits[i + 1].range.first else src.length
            Fn(m.groupValues[1], src.substring(m.range.first, end))
        }
    }

    @Test
    fun `rotaryScrollable is imported and used`() {
        assertTrue(
            "RunWatchApp must import androidx.wear.compose.foundation.rotary.rotaryScrollable",
            src.contains("import androidx.wear.compose.foundation.rotary.rotaryScrollable"),
        )
    }

    @Test
    fun `every content-scroll list wires rotaryScrollable with its own focus requester`() {
        // The pure-scroll list screens (BatteryInstructions, the permission
        // screen, the crash-recovery takeover, the route picker) each attach
        // rotaryScrollable; the sign-in screen is intentionally excluded
        // because its FocusRequester belongs to the text inputs, not the list
        // (auto-focusing the list would steal focus from typing).
        val total = RotaryWiring.callSiteCount(src)
        assertTrue(
            "expected >= 2 rotaryScrollable call sites (BatteryInstructions + RoutePicker), " +
                "found $total",
            total >= 2,
        )

        // Each call site is checked against the requester IT NAMES, in the
        // function it sits in — not against a hardcoded variable name, which
        // failed a correctly-wired list called anything else and passed two
        // lists sharing one requester (decisions § 1205).
        var covered = 0
        for (fn in functions()) {
            if (!fn.body.contains(".rotaryScrollable(")) continue
            RotaryWiring.assertPaired(fn.body, fn.name)
            covered += RotaryWiring.callSiteCount(fn.body)
        }
        // Without this the guard can only get weaker: a call site the function
        // splitter fails to attribute would be checked by nobody and reported
        // by nobody.
        assertEquals(
            "every rotaryScrollable call site must fall inside a parsed function",
            total,
            covered,
        )
    }
}
