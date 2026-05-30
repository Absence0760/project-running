package com.runapp.watchwear.ui

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Source-level regression guards for the four main run-mode screens.
///
/// Compose UI tests would need androidx.compose.ui:ui-test-junit4 +
/// Robolectric, an infrastructure investment the team deliberately
/// avoided (per `apps/watch_wear/CLAUDE.md`'s "Pure formatters ...
/// are the only testable surface — the layouts themselves can't be
/// unit-tested without Robolectric.").
///
/// What we *can* lock in cheaply: the UI-wiring chain by source-grep,
/// mirroring `RouteMiniMapWiringTest`'s approach. These pin that
/// each screen still wires its load-bearing controls — the runner's
/// muscle memory associates specific UX with specific bindings, and
/// a refactor that silently dropped the hold-to-stop, the lap chip,
/// or the activity-type picker would only surface on a real run.
///
/// When one of these fails, read the **why** comment — a failure
/// means a recent change reversed an invariant we deliberately
/// codified, not that the regex needs blindly updating.
class ScreenWiringTest {

    private fun readRunWatchApp(): String =
        File("src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt").readText()

    private fun readSrc(rel: String): String =
        File("src/main/kotlin/com/runapp/watchwear/$rel").readText()

    // ───────────────────── PreRunScreen ─────────────────────

    @Test fun `PreRunScreen exists as a Composable function`() {
        // The four-screen architecture (PreRun / Running / Paused /
        // PostRun) is the watch's whole UX. Pin that PreRunScreen
        // hasn't been accidentally renamed or merged into another
        // screen.
        val src = readRunWatchApp()
        assertTrue(
            "PreRunScreen composable removed or renamed — watch UX architecture broken.",
            Regex("""@Composable[^@]*private\s+fun\s+PreRunScreen\s*\(""").containsMatchIn(src),
        )
    }

    @Test fun `PreRunScreen exposes the activity-type picker`() {
        // CompactChip cycles run → walk → hike → cycle. Pinned by
        // `metadata.activity_type` in docs/backend/metadata.md — losing the
        // picker would silently default every run to "run" regardless
        // of the user's choice. The pre-run screen receives the
        // current activityType + a setter callback; pin both.
        val src = readRunWatchApp()
        assertTrue(
            "PreRunScreen activity-type binding lost — metadata.activity_type would silently default.",
            src.contains("activityType = state.activityType") ||
                Regex("""activityType:\s*String""").containsMatchIn(src),
        )
        assertTrue(
            "PreRunScreen activity-type cycle order (run/walk/hike/cycle) lost.",
            src.contains("\"run\"") && src.contains("\"walk\"") &&
                src.contains("\"hike\"") && src.contains("\"cycle\""),
        )
    }

    @Test fun `PreRunScreen exposes the target-pace picker`() {
        // The pace-drift haptic alerts only fire when a target is
        // set. Losing the picker → no haptic alerts, ever.
        val src = readRunWatchApp()
        assertTrue(
            "PreRunScreen target-pace cycling lost — haptic pace alerts would never fire.",
            src.contains("cycleTargetPace"),
        )
    }

    @Test fun `PreRunScreen renders the route picker entry point`() {
        // Route-overlay + off-route detection both depend on the
        // runner being able to select a route from the pre-run
        // screen. Pin the navigation hook.
        val src = readRunWatchApp()
        assertTrue(
            "PreRunScreen route-picker entry lost — runner can no longer pick a route on the wrist.",
            src.contains("RoutePicker") || src.contains("openRoutePicker") ||
                src.contains("Stage.RoutePicker"),
        )
    }

    @Test fun `PreRunScreen offers crash recovery when checkpoint exists`() {
        // The "Recover unsaved run?" prompt is what saves a run from
        // being lost when the process was killed mid-recording.
        // Losing this UI = silent data loss. Pin both the prompt
        // copy and the onRecover / onDiscardRecovery callbacks
        // (which actually save / drop the checkpoint).
        val src = readRunWatchApp()
        assertTrue(
            "PreRunScreen recovery-prompt copy lost — killed-process runs would silently vanish.",
            src.contains("Recover unsaved run?"),
        )
        assertTrue(
            "PreRunScreen recover/discard callback wiring lost — recovery prompt becomes a no-op.",
            src.contains("recoverCheckpoint") && src.contains("discardCheckpoint"),
        )
    }

    @Test fun `PreRunScreen surfaces battery-saver remediation chip`() {
        // Without the "Fix battery saver" chip, runners not on the
        // ignore-battery-optimizations whitelist get throttled
        // after ~10 minutes. Pin the chip's presence — the
        // BatteryOptimization check + UI nudge documented in
        // CLAUDE.md is what extends recording to marathon length.
        val src = readRunWatchApp()
        assertTrue(
            "PreRunScreen battery-optimization remediation chip lost — long-run reliability regression.",
            src.contains("Fix battery") ||
                src.contains("BatteryOptimization") ||
                src.contains("isIgnoringBatteryOptimizations"),
        )
    }

    // ───────────────────── RunningScreen ─────────────────────

    @Test fun `RunningScreen exists as a Composable function`() {
        val src = readRunWatchApp()
        assertTrue(
            "RunningScreen composable removed or renamed.",
            Regex("""@Composable[^@]*private\s+fun\s+RunningScreen\s*\(""").containsMatchIn(src),
        )
    }

    @Test fun `RunningScreen exposes the lap button`() {
        // Lap marking flows into `metadata.laps` on save. Losing
        // the button means the post-run laps table is empty AND
        // the runner can't mark splits mid-run.
        val src = readRunWatchApp()
        assertTrue(
            "RunningScreen lap button lost — metadata.laps would never populate.",
            src.contains("markLap"),
        )
    }

    @Test fun `RunningScreen exposes pause toggle`() {
        // Pause / Resume is the auto-pause counterpart on the
        // recorder-layer state machine. Losing the toggle leaves
        // the recorder permanently in Running stage.
        val src = readRunWatchApp()
        assertTrue(
            "RunningScreen pause toggle lost — runner can't pause mid-run.",
            Regex("""pause\(\)|togglePause|Stage\.Paused""").containsMatchIn(src),
        )
    }

    @Test fun `RunningScreen uses HoldToStopButton (not a plain tap)`() {
        // Hold-to-stop requires an 800 ms press before fire. Pinned
        // because a plain `onClick { vm.stop() }` would let a
        // single accidental tap end a long run mid-effort. CLAUDE.md
        // explicitly documents this contract.
        val src = readRunWatchApp()
        assertTrue(
            "RunningScreen hold-to-stop replaced with a tap — single accidental tap can now end a run.",
            src.contains("HoldToStopButton"),
        )
    }

    @Test fun `RunningScreen renders distance + pace`() {
        // The core "what's my run doing right now" panel. Pin
        // the bindings exist — losing either would render the
        // screen useless for its primary purpose.
        val src = readRunWatchApp()
        assertTrue(
            "RunningScreen distance binding lost.",
            src.contains("distanceM") || src.contains("metersToKm"),
        )
        assertTrue(
            "RunningScreen pace binding lost.",
            src.contains("paceSecPerKm") || src.contains("formatPaceSecPerKm"),
        )
    }

    // ───────────────────── PausedScreen ─────────────────────

    @Test fun `PausedScreen exposes resume control`() {
        // The recording stays in Paused stage until the runner
        // taps Resume. Losing the resume binding → permanently
        // paused recording.
        val src = readRunWatchApp()
        assertTrue(
            "PausedScreen resume binding lost — paused runs can't be resumed.",
            src.contains("vm::resume") || src.contains("vm.resume"),
        )
    }

    // ───────────────────── PostRunScreen ─────────────────────

    @Test fun `PostRunScreen exists as a Composable function`() {
        val src = readRunWatchApp()
        assertTrue(
            "PostRunScreen composable removed or renamed.",
            Regex("""@Composable[^@]*private\s+fun\s+PostRunScreen\s*\(""").containsMatchIn(src),
        )
    }

    @Test fun `PostRunScreen surfaces the lap-splits table when laps exist`() {
        // FinishedSummary.laps powers the splits table. Pin the
        // binding so a future refactor doesn't drop the table and
        // silently lose visibility into per-lap performance.
        val src = readRunWatchApp()
        assertTrue(
            "PostRunScreen laps table binding lost — splits no longer visible after a run.",
            src.contains("laps") && src.contains("FinishedSummary"),
        )
    }

    // ───────────────────── Foreground-service tile-update wiring ─────────────────────

    @Test fun `RunRecordingService nudges the active-run tile on state transitions`() {
        // The wrist's tile carousel re-binds the active-run tile
        // every 30 s, but state CHANGES need an immediate nudge so
        // the runner doesn't see a stale tile after Stop. CLAUDE.md
        // pins ≥4 requestUpdate call sites in RunRecordingService.
        val src = readSrc("recording/RunRecordingService.kt")
        val nudgeCount = Regex("""ActiveRunTileService\.requestUpdate""").findAll(src).count()
        assertTrue(
            "RunRecordingService active-run tile nudges dropped below 4 — tile now stale on state transitions. Found $nudgeCount.",
            nudgeCount >= 4,
        )
    }

    // ───────────────────── PostRun → Sync chip ─────────────────────

    @Test fun `Sync chip exists for manual drain (back-off bypass path)`() {
        // The "Sync N runs" chip on PreRun calls vm.sync() which
        // forces a drain. Losing the chip strands offline-recorded
        // runs whenever the auto-drain triggers don't fire — a real
        // bug we'd only catch on a stuck device.
        val src = readRunWatchApp()
        assertTrue(
            "Manual sync chip lost — offline runs can no longer be force-drained from the UI.",
            src.contains("vm.sync()") || src.contains("Sync ") ||
                src.contains("debugTrySync"),
        )
    }

    @Test
    fun `running-screen Buttons carry contentDescription for TalkBack`() {
        // Reason: audit/accessibility High (May 2026). The Pause /
        // Resume / Lap / Sync / Next / Discard buttons used Text("||"),
        // Text("Lap"), Text("×") for their visual children. TalkBack
        // announces these as their literal text, which on a wrist
        // display is meaningless ("||", "×"). Wrap each Button in
        // Modifier.semantics { contentDescription = "..." } so the
        // announcement names the action.
        //
        // The mobile run_screen got the equivalent fix via
        // Semantics(label:) in commit 6b2ef21 — this pins the Wear
        // twin so it stays in lockstep.
        val src = readRunWatchApp()
        for (label in listOf(
            "Pause run",
            "Resume run",
            "Mark lap",
            "Discard unsaved run",
            "Sync run",
            "Start next run",
        )) {
            // Accept either form: `contentDescription = "Label"` (static
            // assignment) or `"Label"` as a branch of a when-expression
            // assigned to contentDescription (e.g. the Sync/Done/Syncing
            // toggle). The label literal alone is unique enough; the
            // surrounding code is the contentDescription assignment.
            assertTrue(
                "RunWatchApp.kt must reference \"$label\" as a Button " +
                    "contentDescription so TalkBack announces it.",
                src.contains("\"$label\""),
            )
        }
        // Belt-and-braces: at least six Modifier.semantics blocks should
        // exist — one per Pause/Resume/Lap/Discard/Sync(toggle)/Next.
        val semanticsBlocks = Regex("\\.semantics\\s*\\{[\\s\\S]*?contentDescription")
            .findAll(src).count()
        assertTrue(
            "expected >= 6 Modifier.semantics blocks with contentDescription " +
                "on RunWatchApp buttons; found $semanticsBlocks",
            semanticsBlocks >= 6,
        )
    }
}
