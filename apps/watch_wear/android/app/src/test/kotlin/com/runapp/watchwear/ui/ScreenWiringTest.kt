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

    /// Default (English) string resources. User-facing copy moved out of
    /// RunWatchApp.kt into `values/strings.xml` during i18n, so the wiring
    /// guards below pin the resource reference in code AND the English copy
    /// in the default catalogue.
    private fun readDefaultStrings(): String =
        File("src/main/res/values/strings.xml").readText()

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
            src.contains("R.string.recover_unsaved_run") &&
                readDefaultStrings().contains("Recover unsaved run?"),
        )
        assertTrue(
            "PreRunScreen recover/discard callback wiring lost — recovery prompt becomes a no-op.",
            src.contains("recoverCheckpoint") && src.contains("discardCheckpoint"),
        )
    }

    @Test fun `a denied permission dialog reports what it cost`() {
        // The callback was two lines: set showCountdown when
        // ACCESS_FINE_LOCATION came back granted, and nothing at all
        // otherwise. So a runner who tapped GO and declined — or who had
        // declined once before, after which the system stops prompting —
        // landed back on an unchanged pre-run screen with no countdown, no
        // message and no way to ask why. The gate was right and stays; what
        // was missing was the report.
        val src = readRunWatchApp()
        assertTrue(
            "the launcher result must be graded through permissionOutcome, " +
                "not read as a single boolean",
            src.contains("permissionOutcome(granted)"),
        )
        assertTrue(
            "a graded result must be able to raise the notice — otherwise " +
                "the else branch is still empty",
            Regex("""shouldInterruptForCosts\([^)]*\)\s*\)?\s*\{[^}]*permissionNotice\s*=""")
                .containsMatchIn(src),
        )
        assertTrue(
            "PermissionNotice must exist as the surface that renders it",
            Regex("""@Composable[^@]*private\s+fun\s+PermissionNotice\s*\(""")
                .containsMatchIn(src),
        )
        // Each cost carries its own sentence, and the card offers a route
        // back rather than only bad news.
        val strings = readDefaultStrings()
        for (key in listOf(
            "perm_cost_location",
            "perm_cost_heart_rate",
            "perm_cost_steps",
            "perm_cost_notification",
            "perm_watch_steps",
            "perm_try_again",
        )) {
            assertTrue(
                "values/strings.xml must declare $key",
                strings.contains("name=\"$key\""),
            )
            assertTrue(
                "RunWatchApp must reference R.string.$key",
                src.contains("R.string.$key"),
            )
        }
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

    @Test fun `PostRunScreen gates the calorie line on the show_calories opt-out`() {
        // `show_calories` is a universal harm-reduction opt-out (default
        // on) for weight-conscious runners. Web /runs/[id] and mobile
        // run_detail both hide their calorie cell when it's false; the
        // wrist shipped ignoring it, so an opted-out runner still got a
        // kcal figure after every run. Pin the gate + the state binding
        // that feeds it, so a refactor can't silently un-gate it again.
        val src = readRunWatchApp()
        assertTrue(
            "PostRunScreen no longer takes showCalories — the opt-out can't reach the calorie line.",
            Regex("""fun\s+PostRunScreen\s*\([^)]*showCalories\s*:\s*Boolean""", RegexOption.DOT_MATCHES_ALL)
                .containsMatchIn(src),
        )
        assertTrue(
            "PostRunScreen calorie line is no longer gated on showCalories.",
            Regex("""if\s*\(\s*showCalories\s*\)[\s\S]{0,400}?RunCalories\.estimate""").containsMatchIn(src),
        )
        assertTrue(
            "showCalories no longer bound from RunViewModel state at the PostRun call site.",
            src.contains("showCalories = state.showCalories"),
        )
    }

    @Test fun `PostRunScreen marks the calorie figure estimated when no body weight is set`() {
        // Without `body_weight_kg` the estimate rides a 70 kg median the
        // runner never entered. Web distinguishes runDetail.caloriesLabel
        // from caloriesEstLabel for exactly this; the wrist must not
        // present the guess as measured.
        val src = readRunWatchApp()
        assertTrue(
            "PostRunScreen no longer picks kcal_est when bodyWeightKg is null.",
            Regex("""if\s*\(\s*bodyWeightKg\s*!=\s*null\s*\)\s*R\.string\.kcal\s+else\s+R\.string\.kcal_est""")
                .containsMatchIn(src),
        )
        assertTrue(
            "kcal_est missing from the default string catalogue.",
            readDefaultStrings().contains("""name="kcal_est""""),
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
        val strings = readDefaultStrings()
        // contentDescription copy moved into resources. Pin both the
        // resource reference in code (so the Button still announces a label)
        // and the English copy in the default catalogue (so the announced
        // label is still the right words). key → expected English copy.
        val labels = mapOf(
            "R.string.cd_pause_run" to "Pause run",
            "R.string.cd_resume_run" to "Resume run",
            "R.string.cd_mark_lap" to "Mark lap",
            "R.string.cd_discard_unsaved_run" to "Discard unsaved run",
            "R.string.cd_sync_run" to "Sync run",
            "R.string.cd_start_next_run" to "Start next run",
        )
        for ((key, copy) in labels) {
            assertTrue(
                "RunWatchApp.kt must reference $key as a Button " +
                    "contentDescription so TalkBack announces it.",
                src.contains(key),
            )
            assertTrue(
                "values/strings.xml must carry the English copy \"$copy\" for $key.",
                strings.contains(copy),
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

    @Test fun `the signed-out notice says signed out, not offline`() {
        // The pre-run header renders two DIFFERENT facts a few lines apart:
        // `!online && authed` -> the watch cannot reach the network, and
        // `!authed` -> nobody has signed in on this wrist. Both branches
        // rendered `R.string.offline`.
        //
        // Nothing fails when they share a string. The runner is simply told
        // the wrong thing about a watch that is usually perfectly online, and
        // sent to check Bluetooth instead of tapping the Sign in chip
        // immediately below it — the affordance that actually fixes what they
        // are looking at. Grep-level rather than Compose-level for the reason
        // the class comment gives; the branch body is read on its own so a
        // match from the sibling `!online` branch cannot satisfy it.
        val src = readRunWatchApp()
        val at = src.indexOf("if (!authed) {")
        assertTrue("the `if (!authed) {` pre-run branch is gone", at >= 0)
        var depth = 0
        var end = at
        for (i in src.indexOf('{', at) until src.length) {
            if (src[i] == '{') depth += 1
            if (src[i] == '}') {
                depth -= 1
                if (depth == 0) { end = i; break }
            }
        }
        val branch = src.substring(at, end)
        assertTrue(
            "the signed-out branch must render R.string.not_signed_in",
            branch.contains("R.string.not_signed_in"),
        )
        assertTrue(
            "the signed-out branch must NOT render R.string.offline — a " +
                "runner who has not signed in is usually online, and the " +
                "offline notice belongs to the `!online && authed` branch",
            !branch.contains("R.string.offline"),
        )
        assertTrue(
            "the network branch must still render R.string.offline",
            src.contains("!online && authed"),
        )
        assertTrue(
            "values/strings.xml must carry the English copy for not_signed_in",
            readDefaultStrings().contains("<string name=\"not_signed_in\">Not signed in</string>"),
        )
    }
}
