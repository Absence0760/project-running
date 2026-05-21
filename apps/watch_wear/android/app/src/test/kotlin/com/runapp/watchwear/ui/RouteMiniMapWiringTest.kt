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
        // box for an invalid one. The "current" expression accepts
        // either `latestPoint` directly or the `effectiveCurrent`
        // bridge (latestPoint OR fallbackLatLng) used to kill the
        // countdown→running flash — both preserve the contract.
        val src = read("ui/RunWatchApp.kt")
        assertTrue(
            "RunningScreen must gate the mini-map on route OR track OR current",
            Regex(
                """routeWaypoints\.isNotEmpty\(\)\s*\|\|\s*trackOverlayPoints\.size\s*>=\s*2\s*\|\|\s*(?:latestPoint|effectiveCurrent)\s*!=\s*null""",
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
    fun `RouteMiniMap centre is keyed on current and follows it at street zoom`() {
        // Why: two contracts here:
        //   1) The centre must be a `remember(...)` with `current` as a
        //      key, so it re-fits when GPS lands or the runner moves to
        //      a new tile. Drop `current` from the keys and the map
        //      freezes on the initial fix.
        //   2) When `current` is non-null we must follow it at street
        //      zoom (Centre construction) — fitting the whole route
        //      makes the runner's position a single pixel at running
        //      pace. When `current` is null we fall back to fitBounds
        //      so the pre-run preview frames the whole polyline.
        val src = File("src/main/kotlin/com/runapp/watchwear/ui/RouteMiniMap.kt").readText()
        assertTrue(
            "RouteMiniMap must wrap centre derivation in a remember(...) keyed on `current`",
            Regex("""remember\s*\([^)]*current[^)]*\)""").containsMatchIn(src),
        )
        assertTrue(
            "Follow-current branch must construct MercatorTiles.Centre at FOLLOW_ZOOM",
            Regex("""MercatorTiles\.Centre\s*\(""").containsMatchIn(src),
        )
        assertTrue(
            "Pre-run / no-fix fallback must call MercatorTiles.fitBounds",
            Regex("""MercatorTiles\.fitBounds\s*\(""").containsMatchIn(src),
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

    @Test
    fun `RunningScreen controls auto-hide unless paused`() {
        // Why: the running-mode UX hides the pause / lap / stop cluster
        // 5 s after the last interaction so the route takes the
        // foreground. While paused, controls stay visible so the
        // runner doesn't hunt for "Resume" with a hidden tap. If
        // either side of this contract regresses (timer dropped, or
        // paused branch reversed) the screen becomes either always-
        // cluttered or always-empty — both bad.
        val src = read("ui/RunWatchApp.kt")
        assertTrue(
            "RunningScreen must wrap controls in AnimatedVisibility(visible = controlsVisible, ...)",
            Regex("""AnimatedVisibility[^)]*visible\s*=\s*controlsVisible""", RegexOption.DOT_MATCHES_ALL)
                .containsMatchIn(src),
        )
        assertTrue(
            "RunningScreen must keep controls visible while paused (paused short-circuit on the auto-hide effect)",
            Regex("""if\s*\(paused\)\s*return@LaunchedEffect""").containsMatchIn(src),
        )
    }

    @Test
    fun `RunViewModel pre-fetches tiles when a route is selected`() {
        // Why: the whole point of the pre-fetch is "user picks a route
        // while connected → tiles available even if the watch goes
        // off-grid mid-run". Dropping the prefetch call would compile
        // and ship a feature that silently doesn't work — the failure
        // mode only surfaces in the field, when the runner is already
        // on the course. Look for the call within ~800 chars of the
        // function declaration (negated-class can't span the body's
        // nested try/catch braces).
        val src = File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()
        assertTrue(
            "RunViewModel.selectRoute must call tileSource.prefetch(...)",
            Regex(
                """fun\s+selectRoute[\s\S]{0,800}tileSource\.prefetch\s*\(""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(src),
        )
    }

    @Test
    fun `RunRecordingService pushes tile updates on every stage transition`() {
        // Why: the active-run tile is rendered from
        // RecordingRepository.metrics.value at TileService.onTileRequest
        // time. Without an explicit `requestUpdate` on each stage flip,
        // the tile content is whatever the platform last cached — a
        // runner who pauses and swipes to the tile would still see
        // "RUNNING", and the post-stop tile would still show stats from
        // the just-finished run. Each transition (start, pause, resume,
        // stop) must call ActiveRunTileService.requestUpdate so the
        // platform re-binds and re-renders.
        val src = read("recording/RunRecordingService.kt")
        // Match `ActiveRunTileService.requestUpdate(this)` (FQN or
        // import-resolved short form). The regex tolerates either.
        val pattern = Regex("""ActiveRunTileService\.requestUpdate\s*\(""")
        val hits = pattern.findAll(src).count()
        assertTrue(
            "RunRecordingService must call ActiveRunTileService.requestUpdate at " +
                "≥4 stage transitions (start / pause / resume / stop); found $hits",
            hits >= 4,
        )
    }

    @Test
    fun `SupabaseClient_fetchRoutes filters starred-first with a recent fallback`() {
        // Why: the watch picker is gated server-side on `is_starred =
        // true` so a user with 200 saved routes doesn't have to scroll
        // a 1.4-inch screen. But a user who hasn't curated yet would
        // see an empty picker — so when the starred query returns
        // nothing, fetchRoutes falls back to the 10 most-recently-
        // updated owned routes. Either branch alone is a regression:
        // dropping the starred filter floods the picker on power
        // users; dropping the fallback empties it on first launch.
        // Query strings live in `SupabaseUrlBuilders.kt` (moved out
        // of SupabaseClient for unit-testability).
        val src = File("src/main/kotlin/com/runapp/watchwear/SupabaseUrlBuilders.kt").readText()
        assertTrue(
            "FETCH_ROUTES_STARRED_QUERY must filter is_starred=eq.true with limit=30",
            Regex("""is_starred=eq\.true[^"]*limit=30""").containsMatchIn(src),
        )
        assertTrue(
            "FETCH_ROUTES_FALLBACK_QUERY must omit is_starred and cap at limit=10",
            Regex("""order=updated_at\.desc&limit=10""").containsMatchIn(src),
        )
    }

    @Test
    fun `RunViewModel pre-fetches tiles during the start countdown`() {
        // Why: the countdown overlay rides the 3-second wait between
        // permission grant and recording start. Calling
        // prefetchTilesForRunStart() during that window means the
        // first running-screen frame already has tiles in cache, so
        // free-form runs (no planned route) don't show midnight +
        // polyline before the first HTTP fetch lands.
        val viewModelSrc = File("src/main/kotlin/com/runapp/watchwear/RunViewModel.kt").readText()
        assertTrue(
            "RunViewModel must expose prefetchTilesForRunStart()",
            Regex("""fun\s+prefetchTilesForRunStart\s*\(""").containsMatchIn(viewModelSrc),
        )
        val uiSrc = File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()
        assertTrue(
            "RunWatchApp must invoke prefetchTilesForRunStart() when the countdown begins",
            Regex("""prefetchTilesForRunStart\s*\(\s*\)""").containsMatchIn(uiSrc),
        )
    }
}
