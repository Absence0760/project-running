package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level regression guards for the watch-side wiring of the
/// phone→watch route push pipeline.
///
/// The `RoutesBridge` itself is testable as a pure JSON parser
/// (`RoutesBridgeJsonTest`), but the integration that consumes it —
/// `RunViewModel.observeRoutesBridge` — touches `DataClient`,
/// `viewModelScope`, and DataStore, none of which run on a host JVM
/// without Robolectric (which this module deliberately avoids). The
/// production wiring is therefore protected by source-grep guards:
/// rename / remove / unwire the load-bearing call sites and these
/// tests fire instead of the wire silently breaking at runtime.
///
/// Mirrors the `ScreenWiringTest` + `RouteMiniMapWiringTest` pattern.
class RoutesBridgeWiringTest {

    private fun read(rel: String): String {
        return File("src/main/kotlin/com/runapp/watchwear/$rel").readText()
    }

    @Test
    fun `RunViewModel calls observeRoutesBridge in init`() {
        // Why: without this, the watch never subscribes to the
        // DataClient listener and every phone push lands but is
        // never consumed. The picker would show stale data even
        // when the phone is online.
        val src = read("RunViewModel.kt")
        assertTrue(
            "RunViewModel must call observeRoutesBridge() in init {} so the " +
                "watch starts listening for phone pushes on construction",
            Regex("""init\s*\{[\s\S]*?observeRoutesBridge\(\)""").containsMatchIn(src),
        )
    }

    @Test
    fun `RunViewModel constructs a RoutesBridge instance`() {
        // Why: the bridge is owned by the ViewModel, not injected.
        // A future refactor that drops the field would mean
        // observeRoutesBridge has nothing to subscribe to.
        val src = read("RunViewModel.kt")
        assertTrue(
            "RunViewModel must construct a RoutesBridge(application)",
            src.contains("RoutesBridge(application)"),
        )
    }

    @Test
    fun `observeRoutesBridge uses both current and events flows`() {
        // Why: two distinct paths.
        //
        // 1. current() — cold-start hydrate. Without it the watch
        //    boots with an empty picker even if the phone pushed a
        //    starred set while the watch was off.
        //
        // 2. events.collect — live updates. Without it stars on
        //    the phone don't propagate while the watch is on.
        val src = read("RunViewModel.kt")
        // Both calls must appear inside the observeRoutesBridge fn.
        // We grep the whole file because the fn body is long.
        assertTrue(
            "observeRoutesBridge must call routesBridge.current()",
            src.contains("routesBridge.current()"),
        )
        assertTrue(
            "observeRoutesBridge must subscribe to routesBridge.events",
            src.contains("routesBridge.events.collect"),
        )
    }

    @Test
    fun `observeRoutesBridge consults shouldApplyRoutesPush before applying`() {
        // Why: out-of-order Wearable Data Layer delivery (rare but
        // possible — DataItem propagation isn't strictly FIFO
        // across watch-reboot reconnects). Without the gate, an
        // older push that arrives after a newer one rolls the
        // watch's starred set back. This is the silent-bug class
        // the gate exists to prevent.
        val src = read("RunViewModel.kt")
        assertTrue(
            "observeRoutesBridge must consult shouldApplyRoutesPush — " +
                "without it, out-of-order pushes silently roll back the " +
                "watch's starred set",
            src.contains("shouldApplyRoutesPush("),
        )
        // The lastAppliedRoutesPushMs field must be tracked so the
        // gate has a baseline.
        assertTrue(
            "RunViewModel must track lastAppliedRoutesPushMs " +
                "for the gate to be effective",
            src.contains("lastAppliedRoutesPushMs"),
        )
    }

    @Test
    fun `observeRoutesBridge writes through routeStore_save on apply`() {
        // Why: the in-memory state update is ephemeral; the
        // DataStore-backed routeStore is what survives cold launch.
        // Drop the routeStore.save call and the picker forgets
        // every push at the next watch reboot.
        val src = read("RunViewModel.kt")
        assertTrue(
            "observeRoutesBridge must persist pushed routes via " +
                "routeStore.save — without it, cold-launch + offline " +
                "loses the entire phone-push state",
            src.contains("routeStore.save("),
        )
    }

    @Test
    fun `RoutesBridge declares the DataLayer path - saved_routes`() {
        // Why: matches the phone-side writer's PATH constant
        // (apps/mobile_android/android/.../WearRoutesBridge.kt).
        // Drift on either side means the watch's listener never
        // fires for the phone's pushes — they go to /dev/null in
        // the Wearable Data Layer graph.
        val src = read("RoutesBridge.kt")
        assertTrue(
            "RoutesBridge must declare PATH = /saved_routes — " +
                "must match the phone-side WearRoutesBridge.kt PATH",
            src.contains("\"/saved_routes\""),
        )
    }

    @Test
    fun `RoutesBridge consumes both routes_json + updated_at_ms DataMap keys`() {
        // Why: the wire format has TWO keys. routes_json is the
        // payload; updated_at_ms is what shouldApplyRoutesPush
        // uses to detect stale deliveries. Drop either and the
        // gate becomes effectively a no-op.
        val src = read("RoutesBridge.kt")
        assertTrue(
            "RoutesBridge must read the routes_json DataMap key",
            src.contains("\"routes_json\""),
        )
        assertTrue(
            "RoutesBridge must read the updated_at_ms DataMap key " +
                "for stale-push protection to work",
            src.contains("\"updated_at_ms\""),
        )
    }

    @Test
    fun `events Flow emits RoutesPush (not bare List of SavedRoute)`() {
        // Why: the consumer needs both routes + the timestamp to
        // run the stale-push gate. A previous version emitted just
        // List<SavedRoute>; the May 2026 hardening pass added the
        // wrapper. Don't roll it back.
        val src = read("RoutesBridge.kt")
        assertTrue(
            "RoutesBridge.events must be Flow<RoutesPush> — a refactor " +
                "back to Flow<List<SavedRoute>> would silently disable " +
                "the stale-push gate",
            src.contains("Flow<RoutesPush>"),
        )
        // The data class itself must carry both fields.
        assertTrue(
            "RoutesPush data class must carry both routes + updatedAtMs",
            Regex("""data\s+class\s+RoutesPush\s*\([\s\S]*?routes[\s\S]*?updatedAtMs""").containsMatchIn(src),
        )
    }

    @Test
    fun `sortRoutesByRecency is file-level internal, not private`() {
        // Why: needs to be reachable from the test source set
        // (RoutesPushApplyTest exercises it directly). A future
        // refactor that moves it back inside RunViewModel and
        // marks it private would silently lose every test case
        // that exercises the recents math.
        val src = read("RoutesBridge.kt")
        assertTrue(
            "sortRoutesByRecency must live at file scope as `internal`",
            Regex("""internal\s+fun\s+sortRoutesByRecency""").containsMatchIn(src),
        )
    }

    @Test
    fun `shouldApplyRoutesPush is file-level internal too`() {
        val src = read("RoutesBridge.kt")
        assertTrue(
            "shouldApplyRoutesPush must live at file scope as `internal`",
            Regex("""internal\s+fun\s+shouldApplyRoutesPush""").containsMatchIn(src),
        )
    }

    @Test
    fun `RunViewModel sortByRecency delegates to file-level sortRoutesByRecency`() {
        // Why: the file-level function is the testable seam. If
        // the ViewModel quietly re-implements its own version
        // inline, the tests over the file-level fn would silently
        // stop covering the production path.
        val src = read("RunViewModel.kt")
        assertTrue(
            "RunViewModel.sortByRecency must delegate to the file-level " +
                "sortRoutesByRecency so the tests cover the production path",
            src.contains("sortRoutesByRecency("),
        )
    }

    @Test
    fun `LocalRouteStore is the persistence target for pushed routes`() {
        // Belt-and-braces: pin that the routes the bridge yields
        // flow through LocalRouteStore (DataStore-backed), not
        // some ephemeral in-memory map.
        val src = read("RunViewModel.kt")
        assertTrue(
            "observeRoutesBridge must persist via LocalRouteStore — " +
                "in-memory state alone would lose pushes across " +
                "cold launch",
            src.contains("LocalRouteStore("),
        )
    }

    @Test
    fun `WearRoutesBridge constants stay in sync — 100KB DataLayer budget`() {
        // The phone caps each push at 50 routes
        // (apps/mobile_android/lib/wear_routes_bridge.dart#kMaxRoutesPerPush)
        // because the Wearable Data Layer's per-DataItem cap is
        // ~100 KB and a typical route serialises to ~2 KB. The
        // watch's picker doesn't need to know the cap, but it
        // shouldn't reject a payload that approaches it. Pin that
        // the parser has no artificial cap on inbound routes —
        // whatever the phone sends, the watch ingests.
        val src = read("RoutesBridge.kt")
        assertEquals(
            "RoutesBridge must NOT cap the parsed list — the cap is a " +
                "phone-side budget, not a watch-side one",
            0,
            // Sanity: if a future PR adds `.take(N)` to the parser
            // it would silently truncate inbound pushes. Catch it.
            Regex("""\.take\(\s*\d+\s*\)""").findAll(src).count(),
        )
    }
}
