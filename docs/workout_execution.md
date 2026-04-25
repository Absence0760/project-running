# Structured workout execution

Live execution loop for running a `plan_workouts` row inside the existing `RunRecorder`. Phase 2 of the training-plan feature — the schema + editor + generator are shipped; this is the "start the workout" experience.

> **Status:** v1 shipped on Android. `packages/run_recorder/lib/src/workout_runner.dart` is the state machine + step expander; `apps/mobile_android/lib/widgets/workout_execution_band.dart` is the overlay; entry is via the today's-workout card on the Run tab ("Start workout"). On `recorder.stop()` the run picks up `plan_workout_id`, `workout_step_results`, and `workout_adherence` so the existing web review section on `/runs/[id]` lights up automatically. Below is the original spec; what shipped largely follows it. v1 deferrals: `rewindStep` is not surfaced in the UI (state machine has no rewind today; abandon + restart works); the entry point is the today's-workout card (no Start button on `workout_detail_screen` yet — long-press / detail screen is for reading only); ghost pacer remains a follow-up.

## Product contract

The user opens a planned workout (from `todays_workout_card` or `workout_detail_screen`) and taps **Start workout**. They get the familiar run screen plus:

- A **top band** on the map showing the current step: `Rep 3/6 · 400 m @ 4:00/km` with a thin progress bar for the step and a green / amber / red pace-adherence pip.
- **Automatic step advance** when the step's target distance is hit. The band slides to the next step and the recorder keeps running — same GPS, same clock, same distance total.
- **Audio cues** at step transitions ("Rep 4 of 6, four hundred metres at four per kilometre"), at half-distance, in the last 50 m of each step, and when behind/ahead by more than the tolerance.
- **Manual controls** in the band: skip to next step, rewind to previous step, abandon (convert to free run).
- **Post-run summary** that shows planned vs actual per step, not just the overall pace.

Non-goals for v1: time-based steps (v2 — all current plan workouts are distance-based), live interval-aware heart-rate zones (nice-to-have), adapting upcoming steps based on current effort.

## Data flow

```
plan_workouts.structure (jsonb, already stored)
    │
    │  _expandStructureToSteps(structure, paces)
    ▼
List<WorkoutStep>           ← computed once at workout start
    │
    │  WorkoutRunner consumes RunSnapshot stream
    ▼
Current step index + per-step start distance/elapsed
    │
    │  emit WorkoutExecEvent stream (transition, pace-drift, complete)
    ▼
Audio cues + execution-band UI rebuild
    │
    │  on recorder.stop():
    ▼
run.metadata.plan_workout_id      ← links the saved run back to the plan
run.metadata.workout_step_results ← per-step planned-vs-actual
run.metadata.workout_adherence    ← 'completed' | 'partial' | 'abandoned'
```

## Step expansion

`WorkoutStructure` (already in `training.dart`) has four optional sections. The expansion rule is fixed and simple:

1. `warmup` → one step
2. `repeats.count` × `{ rep, recovery }` pairs, but the **last rep has no trailing recovery** (cooldown takes its place)
3. `steady` → one step (mutually exclusive with `repeats` in current plans, but the expansion handles both existing)
4. `cooldown` → one step

Example: 6×400 with warmup + cooldown → **14 steps** (1 warmup + 6 reps + 5 recoveries + 1 cooldown).

A workout with no `structure` (e.g. "Easy 8 km") expands to a **single step** covering `target_distance_m` at the workout's `target_pace_sec_per_km`. The execution band still shows, just with a single row — the user gets a visible progress bar and pace-adherence pip without adding a code branch.

Step resolution for symbolic paces (`'easy'`, `'jog'`): look up on the plan's `paces` bag (VDOT-derived, already stored on `training_plans`). `'easy'` → `paces.easy`, `'jog'` → `paces.recovery`. Numeric paces in `repeats.pace_sec_per_km` / `steady.pace_sec_per_km` pass through unchanged.

### `WorkoutStep` shape

```dart
class WorkoutStep {
  final WorkoutStepKind kind;          // warmup | rep | recovery | steady | cooldown
  final int? repIndex;                 // 1-based, only for rep + recovery
  final int? repTotal;                 // only for rep + recovery
  final double targetDistanceMetres;
  final int targetPaceSecPerKm;
  final int toleranceSecPerKm;         // inherits workout-level tolerance, default 10
  final String label;                  // "Warmup", "Rep 3/6", "Recovery 3/5", "Cooldown"
}
```

No duration-based field in v1 — see open questions.

## `WorkoutRunner` state machine

Lives in **`packages/run_recorder/lib/src/workout_runner.dart`** so iOS / watch can reuse it later. Sits *on top of* `RunRecorder`, not inside — the recorder stays focused on GPS/time/distance, the runner is a stateful consumer of `RunSnapshot`s.

```dart
class WorkoutRunner {
  WorkoutRunner(this.steps, {required this.plan PacesBag paces});

  final List<WorkoutStep> steps;
  int get currentStepIndex;
  WorkoutStep? get currentStep;           // null after the last step
  bool get isComplete;

  // Current-step derived metrics (cheap getters, recomputed from the last snapshot).
  double get stepDistanceMetres;
  Duration get stepElapsed;
  int? get stepAveragePaceSecPerKm;
  PaceAdherence get paceAdherence;        // onPace | ahead | behind | wayAhead | wayBehind
  double get stepRemainingMetres;

  // Drive.
  void onSnapshot(RunSnapshot s);

  // Controls — all idempotent if called after completion.
  void skipStep();                        // mark current complete, advance
  void rewindStep();                      // current restarts at now; prior step re-entered
  void abandon();                         // stop emitting transitions; recorder keeps running

  // Results (call when recorder.stop() is about to fire).
  List<WorkoutStepResult> snapshotResults();

  Stream<WorkoutExecEvent> get events;
  void dispose();
}
```

Auto-advance trigger: on each `onSnapshot`, compare `stepDistanceMetres` (= `snapshot.distanceMetres - _stepStartDistance`) to `currentStep.targetDistanceMetres`. If ≥, call `_advance(snapshot)`. Same logic whether the distance accumulated quickly or slowly; the recorder's pause gate already keeps stepDistance from creeping during a manual pause.

No internal "workout paused" flag — there is exactly one pause in the system, the recorder's. That's the whole point of sitting on top.

## Integration with `RunRecorder`

The recorder is unchanged. Hooking points in `run_screen.dart`:

1. **Construct**: if the route extras carry a `PlanWorkoutRow`, `_preload` builds a `WorkoutRunner(steps, paces: ...)` from the workout's structure + the plan's `paces` jsonb. Stored on `_State` alongside `_recorder`.
2. **Consume**: the existing `_onSnapshot` handler calls `_workoutRunner?.onSnapshot(snapshot)` before its own logic. The runner either no-ops or emits a `WorkoutExecEvent`.
3. **React**: subscribe to `_workoutRunner!.events` in `_preload` and:
   - `StepTransitionEvent` → fire audio cue, force one `setState` for the top band (cadence slow enough that a full rebuild is fine), schedule the "halfway" + "last 50 m" timers relative to the new step.
   - `PaceDriftEvent` → fire audio cue (throttled ~45 s so we don't nag).
   - `WorkoutCompleteEvent` → band collapses to "Workout complete · run on or stop", no audio change.
4. **Save**: `_finishRun` reads `_workoutRunner?.snapshotResults()` and writes to `run.metadata` before `saveRun`.
5. **Dispose**: in `_State.dispose`, call `_workoutRunner?.dispose()`.

The `_onSnapshot` handler in `run_screen.dart` remains free of `setState` — step transitions are routed through a new `_workoutNotifier` (same `ValueNotifier` pattern as `_statsNotifier`) to avoid the full-tree rebuild cost per CLAUDE.md hot-path rule.

## UI

One new widget: `apps/mobile_android/lib/widgets/workout_execution_band.dart`. Mounted at the top of the map stack in `run_screen.dart`, above the existing off-route banner.

```
┌────────────────────────────────────────────────┐
│ Rep 3/6 · 400 m @ 4:00/km         ● ahead −6s │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░  320 m to go    │
│                                                │
│  [↶ back]    [skip step ↷]    [abandon]        │
└────────────────────────────────────────────────┘
```

- **Line 1**: step label · target distance · target pace. Pace pip colour tracks `paceAdherence` (green onPace, amber ahead/behind, red wayAhead/wayBehind) with a signed seconds delta.
- **Line 2**: progress bar + remaining-metres readout. Bar fills as `stepDistance / targetDistance` capped at 1.0.
- **Line 3**: expander. Collapsed by default; tap the card to expand. Keeps screen real estate for the map.

After the final step, the band switches to a **"Workout complete"** state — a green pip, no controls, and a "Cooldown done — tap stop to save" hint.

The existing collapsible stats panel underneath (distance / time / pace) is unchanged. The map still shows the pace-heatmap polyline. Nothing competes for the same space.

## Audio cues

Reuses `audio_cues.dart`. New cue kinds, all throttled and fire-and-forget (wrap each in try/catch + `debugPrint` per layered-resilience rules):

| Trigger | Utterance |
|---|---|
| Step transition | "Next: rep three of six. Four hundred metres at four minutes per kilometre." |
| Halfway (distance ≥ 50 % of target, fired once per step) | "Halfway through this rep." |
| Last 50 m (once per step) | "Fifty metres to go." |
| Pace drift (every ≥ 45 s while `wayBehind` / `wayAhead`) | "Pick it up — ten seconds behind pace." / "Ease up — twelve seconds ahead." |
| Workout complete | "Workout complete. Nice work." |

Transition cues stall the halfway / last-50 m tracking on the previous step — any mid-step cue that would have fired after the advance is dropped.

## Control semantics

- **Skip step**: marks the current step as "incomplete" in results (actual distance < target), advances. Recorder keeps running. Useful when the user bails out of a rep but wants the plan intact for the next one.
- **Rewind step**: the current step's distance counter resets to zero and the previous step re-enters. Used when the user accidentally tapped skip, or took too short a recovery and wants to redo it. Only rewinds one step — no deep history.
- **Abandon workout**: stops emitting events, band collapses to "Workout abandoned", recorder continues as a free run. On save, `workout_adherence = 'abandoned'`. No way back from abandon in-session (the intent is "I just want to run").

All three are idempotent and safe during any `isComplete` state.

## Persistence

Three new `runs.metadata` keys — register in [metadata.md](metadata.md) in the same turn as shipping the code:

- `plan_workout_id` — uuid of the linked `plan_workouts` row. Makes auto-match unnecessary for this run; the matcher only fires if absent.
- `workout_step_results` — `Array<{ step_index, kind, rep_index?, rep_total?, target_distance_m, actual_distance_m, target_pace_sec_per_km, actual_pace_sec_per_km, duration_s, status: 'completed' | 'skipped' }>`. One row per step, including skipped ones.
- `workout_adherence` — `'completed' | 'partial' | 'abandoned'`. `completed` = all steps hit target ±tolerance. `partial` = any step skipped or more than 20 % short. `abandoned` = user tapped abandon.

Run detail screen on mobile + web adds a "Workout" section when `plan_workout_id` is set — shows the planned-vs-actual table.

## Failure modes

- **GPS lost mid-step**: step distance stalls (recorder's distance doesn't grow without a fix). Clock keeps running. Auto-advance doesn't trigger; user has to skip manually or wait for GPS. Same degradation path the rest of the recorder already has — no new fallback code.
- **Phone call / app backgrounded**: foreground service keeps recording. Runner is an in-process consumer; it picks back up when the app resumes because snapshots keep flowing. No persisted runner state needed for v1.
- **Process killed mid-run**: same as today — the run is lost. v2 checkpoint file (analogous to `watch_wear`'s `CheckpointStore`) would hold `currentStepIndex` + `_stepStartDistance`. Out of scope.
- **Empty workout structure**: expansion produces zero steps. The runner treats this as an instant `isComplete` and the band doesn't mount. No null-deref.
- **Plan paces missing**: symbolic paces resolve to defaults (`easy = 360 s/km`, `jog = 420`) with a `debugPrint`. Better than crashing.

## Testing

New test file **`packages/run_recorder/test/workout_runner_test.dart`**:

- Expansion: 6×400 workout → 14 steps with correct labels; no-structure workout → 1 step; `steady`-only workout → 3 steps.
- Auto-advance: inject synthetic snapshots with increasing distance; assert the runner advances exactly when `stepDistance >= target`.
- Skip: manual skip advances and marks the step `status: 'skipped'` in results.
- Rewind: rewinds one step and re-entering that step resets step distance to zero.
- Abandon: no more events after abandon, even when snapshot distance crosses the would-be target.
- Pace adherence: given target 240 s/km and a step lasting 400 m over 110 s (275 s/km, 35 s slow), the runner reports `wayBehind`.
- Results: `snapshotResults()` covers all expanded steps, with the right kinds / rep numbering / skipped flags.

Widget-level coverage for the band is out of scope (there are no widget tests on `mobile_android` — the repo-wide gap mentioned in `CLAUDE.md`). The unit-tested runner is the behaviour that matters; the band is a thin reader over its state.

## File list

Net new:
- `packages/run_recorder/lib/src/workout_runner.dart` — state machine + events
- `packages/run_recorder/test/workout_runner_test.dart` — the tests above
- `apps/mobile_android/lib/widgets/workout_execution_band.dart` — the overlay

Modified:
- `packages/run_recorder/lib/run_recorder.dart` — re-export the runner + events
- `apps/mobile_android/lib/screens/run_screen.dart` — preload / snapshot / save wiring, route-argument plumbing for the incoming `PlanWorkoutRow`
- `apps/mobile_android/lib/screens/workout_detail_screen.dart` — primary **Start workout** button navigates to the run screen with the workout attached
- `apps/mobile_android/lib/widgets/todays_workout_card.dart` — tap goes to Start workout directly (skip the detail screen when the card is the entry point)
- `apps/mobile_android/lib/audio_cues.dart` — new cue kinds
- `apps/mobile_android/lib/screens/run_detail_screen.dart` — "Workout" section when `plan_workout_id` is set
- `apps/web/src/routes/runs/[id]/+page.svelte` — same section on the web run detail

## Open questions (before building)

1. **Duration-based steps.** Current plans are all distance-based. When plan v2 adds `target_duration_sec` steps (useful for time-trial reps and short warmups), the auto-advance check grows a second branch. Decision needed before a time-based workout ships, not before.
2. **Audio cue wording** — "four hundred metres" vs "point four kilometres" vs "four hundred" (metric unit implied). Stick with the verbose-and-clear form for v1; revisit if users flag it.
3. **Tolerance default** — 10 s/km is tight for a beginner, loose for a racer. The existing `plan_workouts.target_pace_tolerance_sec_per_km` is editable; default stays 10 but surface it in the workout editor.
4. **Skip vs abandon ergonomics** — two buttons that sound similar. If user testing shows confusion, collapse to one "stop workout" that the user confirms to "stop entirely" or "convert to free run".
5. **Ghost pacer on the map?** An NRC-inspired animated pacer marker that shows where a runner-on-plan-pace would be right now would be a natural extension of the existing heatmap. Design it as a follow-up, not v1 — it risks competing with the blue dot for attention.

## Rough sizing

- `WorkoutRunner` + tests: ~1 day
- Band widget: ~0.5 day
- `run_screen.dart` integration (preload, snapshot, save, route args): ~1 day
- Audio cues: ~0.5 day
- `run_detail_screen.dart` + `apps/web` workout section: ~0.5 day
- Polish / manual device QA: ~0.5 day

**Total: ~4 dev-days of concentrated work.** Fits inside one focused week with buffer for the inevitable audio / device-QA surprises.
