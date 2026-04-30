package com.runapp.watchwear.ui

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level regression guards for the on-watch mini-map wiring.
///
/// Compose widget tests would need androidx.compose.ui:ui-test-junit4
/// and Robolectric, neither of which this module currently sets up.
/// The actual canvas drawing is exercised manually on a real device;
/// what we *can* lock in cheaply is the data-flow pipeline:
///
///   RecordingRepository.Metrics.routeWaypoints (set by the service)
///     → RunViewModel.UiState.routeWaypoints
///     → RunningScreen receives it
///     → mounts RouteMiniMap when non-empty
///
/// If any link in that chain breaks (a refactor renames the field, a
/// cleanup pass removes the `routeWaypoints = m.routeWaypoints` line,
/// the conditional render gets deleted), the mini-map silently
/// disappears at runtime with no compile error. These regex guards
/// fire at test time instead. Mirrors the
/// `apps/mobile_android/test/architecture_guards_test.dart` pattern.
///
/// When one of these fails, read the **why** comment before blindly
/// updating the regex — a failure means a recent change reversed the
/// invariant we deliberately codified.
class RouteMiniMapWiringTest {

    private fun read(rel: String): String {
        // Gradle runs tests with cwd = apps/watch_wear/android/app
        return File("src/main/kotlin/com/runapp/watchwear/$rel").readText()
    }

    @Test
    fun `RecordingRepository_Metrics carries routeWaypoints`() {
        // Why: the service sets this once per run; the ViewModel reads
        // it; the mini-map renders it. Removing the field breaks the
        // map even though distance / pace / off-route still work.
        val src = read("recording/RecordingRepository.kt")
        assertTrue(
            "Metrics.routeWaypoints field missing — mini-map data plumbing broken",
            Regex("""val\s+routeWaypoints:\s*List<RouteMath\.LatLng>""").containsMatchIn(src),
        )
    }

    @Test
    fun `RunRecordingService publishes routeWaypoints into Metrics on start`() {
        // Why: parseRouteWaypoints runs on every start; if the result
        // doesn't flow into the repository, the UiState gets an empty
        // list and the mini-map hides itself.
        val src = read("recording/RunRecordingService.kt")
        assertTrue(
            "RunRecordingService.startRecording must populate Metrics.routeWaypoints",
            Regex("""routeWaypoints\s*=\s*routeWaypoints""").containsMatchIn(src),
        )
    }

    @Test
    fun `RunViewModel_UiState exposes routeWaypoints and latestPoint`() {
        // Why: RunningScreen receives both via UiState. Removing
        // either drops the corresponding visual (the polyline or the
        // position dot) without a compile error at the call site.
        val src = read("RunViewModel.kt")
        assertTrue(
            "UiState.routeWaypoints field missing",
            Regex("""val\s+routeWaypoints:\s*List<.*RouteMath\.LatLng>""").containsMatchIn(src),
        )
        assertTrue(
            "UiState.latestPoint field missing",
            Regex("""val\s+latestPoint:\s*GpsPoint\?""").containsMatchIn(src),
        )
    }

    @Test
    fun `RunViewModel collector copies routeWaypoints and latestPoint from Metrics`() {
        // Why: the propagation lines in collectMetrics are the only
        // thing keeping UiState in sync with the service. A
        // copy-paste cleanup that removes them would keep the field
        // declarations but freeze both at their initial values.
        val src = read("RunViewModel.kt")
        assertTrue(
            "RunViewModel must copy m.routeWaypoints into _state",
            Regex("""routeWaypoints\s*=\s*m\.routeWaypoints""").containsMatchIn(src),
        )
        assertTrue(
            "RunViewModel must copy m.latestPoint into _state",
            Regex("""latestPoint\s*=\s*m\.latestPoint""").containsMatchIn(src),
        )
    }

    @Test
    fun `RunningScreen mounts RouteMiniMap conditional on routeWaypoints non-empty`() {
        // Why: mounting unconditionally would render an empty box for
        // free-form runs; mounting always-on would also fail when the
        // bounds collapse (single-point bounds work, but it's not the
        // contract we want — the map is for routes). This conditional
        // is the contract.
        val src = read("ui/RunWatchApp.kt")
        assertTrue(
            "RunningScreen must gate RouteMiniMap on routeWaypoints.isNotEmpty()",
            Regex("""routeWaypoints\.isNotEmpty\(\)\s*\)\s*\{[^}]*RouteMiniMap""", RegexOption.DOT_MATCHES_ALL)
                .containsMatchIn(src),
        )
    }

    @Test
    fun `RouteMiniMap caches bounds via remember to avoid per-tick recomputation`() {
        // Why: `current` updates on every GPS sample (sub-1 Hz today).
        // Without `remember(route, current)` the bounding-box scan
        // would walk the polyline on every recomposition. For a
        // 200-point route that's not free.
        val src = File("src/main/kotlin/com/runapp/watchwear/ui/RouteMiniMap.kt").readText()
        assertTrue(
            "RouteMiniMap must wrap computeBounds in remember(route, current)",
            Regex("""remember\s*\(\s*route\s*,\s*current\s*\)\s*\{[^}]*computeBounds""", RegexOption.DOT_MATCHES_ALL)
                .containsMatchIn(src),
        )
    }
}
