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
    fun `RunningScreen gates the mini-map on having anything to draw`() {
        // Why: the mini-map renders for both planned-route and free-form
        // runs, but it must stay hidden during indoor / no-GPS mode
        // when there's no route, no track, and no current fix — an
        // empty Canvas sitting on screen is a visual bug. The gate
        // composes route OR track OR current; dropping any branch
        // either hides the map for a valid case or shows an empty
        // box for an invalid one.
        val src = read("ui/RunWatchApp.kt")
        assertTrue(
            "RunningScreen must gate the mini-map on route OR track OR current",
            Regex(
                """routeWaypoints\.isNotEmpty\(\)\s*\|\|\s*trackOverlayPoints\.size\s*>=\s*2\s*\|\|\s*latestPoint\s*!=\s*null""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(src),
        )
    }

    @Test
    fun `PreRunScreen mounts RouteMiniMap when a route is selected`() {
        // Why: pre-run preview lets the runner see the route shape
        // before tapping GO. Mounted conditional on
        // selectedRouteWaypoints non-empty (free-form runs render
        // nothing). If the conditional gets dropped, the preview
        // either always renders an empty box or never renders at all.
        val src = read("ui/RunWatchApp.kt")
        assertTrue(
            "PreRunScreen must gate RouteMiniMap on selectedRouteWaypoints.isNotEmpty()",
            Regex("""selectedRouteWaypoints\.isNotEmpty\(\)\s*\)\s*\{[^}]*RouteMiniMap""", RegexOption.DOT_MATCHES_ALL)
                .containsMatchIn(src),
        )
    }

    @Test
    fun `RouteMiniMap caches bounds via remember to avoid per-tick recomputation`() {
        // Why: `current` updates on every GPS sample (sub-1 Hz today).
        // Without `remember(route, current, track)` the bounding-box
        // scan would walk both polylines on every recomposition. For
        // a 200-point route plus a 256-point track that's not free.
        val src = File("src/main/kotlin/com/runapp/watchwear/ui/RouteMiniMap.kt").readText()
        assertTrue(
            "RouteMiniMap must wrap computeBounds in remember(route, current, track)",
            Regex("""remember\s*\(\s*route\s*,\s*current\s*,\s*track\s*\)\s*\{[^}]*computeBounds""", RegexOption.DOT_MATCHES_ALL)
                .containsMatchIn(src),
        )
    }

    @Test
    fun `Metrics carries trackOverlayPoints and service halves on overflow`() {
        // Why: the track-so-far overlay grows by one point per GPS
        // sample. Without the rolling-buffer cap a 4-hour run would
        // queue ~14k points behind the polyline render. The service
        // appends to a private mutable list and republishes a snapshot
        // every tick — losing either side of that contract drops the
        // feature without a compile error.
        val repoSrc = read("recording/RecordingRepository.kt")
        assertTrue(
            "Metrics.trackOverlayPoints field missing",
            Regex("""val\s+trackOverlayPoints:\s*List<RouteMath\.LatLng>""").containsMatchIn(repoSrc),
        )
        val svcSrc = read("recording/RunRecordingService.kt")
        assertTrue(
            "RunRecordingService must call TrackOverlayBuffer.halveIfOverflowing on the rolling buffer",
            Regex("""TrackOverlayBuffer\.halveIfOverflowing\s*\(\s*trackOverlay""")
                .containsMatchIn(svcSrc),
        )
        assertTrue(
            "RunRecordingService must publish trackOverlayPoints into Metrics",
            Regex("""trackOverlayPoints\s*=\s*trackOverlay\.toList\(\)""").containsMatchIn(svcSrc),
        )
    }

    @Test
    fun `RunViewModel_UiState exposes trackOverlayPoints and collector copies it`() {
        // Why: the propagation chain Metrics.trackOverlayPoints →
        // UiState.trackOverlayPoints → RunningScreen → RouteMiniMap.track
        // is what makes the overlay actually render. Cleanups that
        // remove the copy line freeze the field at its initial empty
        // list — the polyline silently disappears.
        val src = read("RunViewModel.kt")
        assertTrue(
            "UiState.trackOverlayPoints field missing",
            Regex("""val\s+trackOverlayPoints:\s*List<.*RouteMath\.LatLng>""").containsMatchIn(src),
        )
        assertTrue(
            "RunViewModel must copy m.trackOverlayPoints into _state",
            Regex("""trackOverlayPoints\s*=\s*m\.trackOverlayPoints""").containsMatchIn(src),
        )
    }

    @Test
    fun `RunningScreen forwards trackOverlayPoints into RouteMiniMap_track`() {
        // Why: the mini-map's `track` parameter defaults to
        // emptyList(), so a missing call-site argument compiles but
        // hides the overlay. Locking the named-arg form makes the
        // omission a test failure instead of a runtime regression.
        val src = read("ui/RunWatchApp.kt")
        assertTrue(
            "RunningScreen must pass track = trackOverlayPoints into RouteMiniMap",
            Regex("""track\s*=\s*[a-zA-Z.]*trackOverlayPoints""").containsMatchIn(src),
        )
    }
}
