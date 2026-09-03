package com.runapp.watchwear.tiles

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// The active-run tile is an L4 auxiliary effect on an L1 path.
///
/// `RunRecordingService` nudges the tile from four places and three of
/// them run inside `onStartCommand` — start, pause, resume — where a
/// throw does not degrade a feature, it reaches the thread's uncaught
/// handler and ends the process with the run in it. The start-path call
/// is the worst of the four: it sits between publishing `Recording` and
/// subscribing GPS, HR, steps, the ticker and the checkpoint job, so a
/// throw there loses a run that the foreground service, the wake lock
/// and the open track file all say is under way.
///
/// The AndroidX call chain was read rather than assumed (decisions
/// § 1053): `TileService.getUpdater` only allocates, and the "no Tiles
/// host" case is the one AndroidX itself handles — `buildUpdateBindIntent`
/// logs and returns null. What is unisolated is the composite it returns,
/// which calls `Context.bindService` on one delegate and
/// `Context.sendBroadcast` on the other with no catch between them, and
/// `bindService` is documented to raise `SecurityException`.
///
/// Source-level, in the idiom of `SensorStreamResilienceTest`: neither
/// ProtoLayout nor a Tiles host is drivable from the host JVM.
class ActiveRunTileResilienceTest {

    private val tileSource: String by lazy {
        File("src/main/kotlin/com/runapp/watchwear/tiles/ActiveRunTileService.kt").readText()
    }

    private val serviceSource: String by lazy {
        File("src/main/kotlin/com/runapp/watchwear/recording/RunRecordingService.kt").readText()
    }

    @Test
    fun `the tile updater call is wrapped in its own catch`() {
        assertTrue(
            "ActiveRunTileService.requestUpdate must wrap getUpdater(...).requestUpdate " +
                "in a try/catch of its own — every caller is on the recording path",
            Regex(
                """try\s*\{[^{}]*getUpdater\([^()]*\)\s*\.requestUpdate\([^()]*\)[^{}]*\}\s*catch\s*\(""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(tileSource),
        )
    }

    @Test
    fun `the catch reports rather than swallowing`() {
        // A silent catch turns a tile that stopped updating into a
        // mystery. The conventions ask for a log line beside every
        // auxiliary-effect guard, not a bare `catch (_: Throwable) {}`.
        val body = Regex(
            """catch\s*\(\s*(\w+)\s*:\s*Throwable\s*\)\s*\{([^{}]*)\}""",
            RegexOption.DOT_MATCHES_ALL,
        ).find(tileSource)
        assertTrue("no `catch (e: Throwable)` found in the tile service", body != null)
        assertTrue(
            "the tile-update catch swallows silently: ${body?.groupValues?.get(2)}",
            body!!.groupValues[2].contains("Log."),
        )
    }

    @Test
    fun `nobody reaches the platform updater around the guard`() {
        // The guard is only worth anything if it is the single door. A
        // caller that resolves its own updater re-opens the hole without
        // touching this file.
        val direct = Regex("""getUpdater\s*\(""").findAll(serviceSource).count()
        assertEquals(
            "RunRecordingService must go through ActiveRunTileService.requestUpdate, " +
                "not resolve a TileUpdateRequester itself",
            0,
            direct,
        )
        assertTrue(
            "the guard is reading nothing — ActiveRunTileService no longer names getUpdater",
            tileSource.contains("getUpdater("),
        )
    }
}
