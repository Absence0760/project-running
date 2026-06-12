# Session planner — structured yoga / pilates / class-content sequences

A **session-content engine**: a reusable, ordered sequence of timed/counted movements (poses, holds, flows, mat/reformer exercises) that an instructor builds once, optionally attaches to a `class` event, and that an attendee can **follow along** with — timed auto-advance, per-side switching, breath/alignment cues, TTS. It is the yoga/pilates analogue of the gym routine engine ([gym_programming.md](gym_programming.md)) and reuses the live-execution state-machine precedent ([workout_execution.md](workout_execution.md)).

> **Status: SPECCED, NOT BUILT.** This is the canonical design for an independent Claude session to implement. It assumes the typed-events + class→gym work is already shipped (see [Dependencies already in place](#dependencies-already-in-place)). P1 is the only slice to start; P2–P4 are gated behind it. Read [gym_programming.md](gym_programming.md) and [workout_execution.md](workout_execution.md) first — this spec deliberately mirrors their shapes and only diverges where the yoga/pilates domain forces it.

> **Goal / north star.** Same as the rest of the product ([multi_modal.md](multi_modal.md)): a **personal multi-modal training app whose differentiator is cross-modal intelligence.** A session planner serves that goal two ways — (1) it lets the instructors who anchor club communities run real classes (retention, not a second business — see [club_events.md](club_events.md)), and (2) **executing a session logs a `gym_workout`**, so a yoga/pilates session feeds the same recovery/load curve and Coach context as runs and lifts. If a slice doesn't deepen the core app, it doesn't ship.

**Contents:** [What it is / isn't](#what-it-is--isnt) · [Dependencies already in place](#dependencies-already-in-place) · [Why a new engine, not gym routines](#why-a-new-engine-not-gym-routines) · [Validation gate](#the-validation-gate-stated-honestly) · [Data flow](#data-flow) · [Data model](#data-model) · [The expand-once helper (parity pair)](#the-expand-once-helper-parity-pair) · [Execution: the follow-along runner](#execution-the-follow-along-runner) · [Logging: session → gym_workout](#logging-session--gym_workout) · [Web UI](#web-ui) · [Mobile & watch](#mobile--watch) · [Relationship to the gym_template seam](#relationship-to-the-gym_template-seam) · [Persistence](#persistence) · [Failure modes](#failure-modes) · [Testing](#testing) · [File list](#file-list) · [Phasing & rollout](#phasing--rollout) · [Open questions](#open-questions) · [Rough sizing](#rough-sizing) · [Appendix A — proposed ADR](#appendix-a--proposed-adr) · [Appendix B — roadmap edits](#appendix-b--roadmap-edits) · [Appendix C — docs-to-update](#appendix-c--docs-to-update-when-each-slice-lands)

## What it is / isn't

**A session plan is** a named, ordered list of **movements** (free-text — "Downward Dog", "Warrior II", "Roll-Up", "The Hundred"), optionally grouped into **blocks** (Warm-up / Standing / Floor / Cool-down), where each movement carries a **kind** (`hold` | `reps` | `flow`), a **duration or rep count**, an optional **per-side** flag, and free-text **cue** (breath / alignment / tempo). It is a **reusable template**, not a dated activity — like a gym routine, it does not itself appear in History or the `activities` view.

A session plan **can be**:
- built + saved by any user (instructor or self-practitioner),
- attached to a **`class`-category event** (the yoga/pilates events typed in [club_events.md](club_events.md)) so the host teaches from it and paid attendees follow it,
- **followed along** in a timed runner (instructor teaching screen or attendee at-home player), which on completion **logs a `gym_workout`** to the follower's own log.

**Non-goals for v1:** a curated pose catalog with images/anatomy (free-text first, catalog is P3); video; live class streaming (that's the deferred virtual-events / IAP question in `club_events.md` P4 — out of scope here); multi-week courses (P4); AI sequencing (P4); a watch follow-along (defer, like gym — see [Mobile & watch](#mobile--watch)).

## Dependencies already in place

This spec builds on shipped infrastructure — **verify each still exists before starting** (grep / read; don't assume):

- **Typed events** — `events.category` (`run`/`cycle`/`class`/`social`), `events.discipline` (free-text label), `events.host_user_id`, `events.gym_template` (jsonb). The `class` category + `isAthleticCategory()` gating. Migrations `20261227_001` (+ `20261228_001`, `20261230_001` grants). See [club_events.md § Slice E](club_events.md#slice-e--typed-events).
- **The class→gym seam** — `event_gym_template.ts` ↔ `.dart` (a TS↔Dart parity pair): `parseGymTemplate` / `gymTemplateFromInputs` / `workoutDraftFromTemplate`. An attendee one-tap-logs a `gym_workout` from a class's `gym_template`. The session planner is the **rich successor** to this lightweight seam — see [Relationship to the gym_template seam](#relationship-to-the-gym_template-seam).
- **The gym routine engine spec** — [gym_programming.md](gym_programming.md): mirror its plan→items relational shape, expand-once helper, planned-vs-actual metadata trio, and self-hiding/gate discipline.
- **The live-execution runner** — [workout_execution.md](workout_execution.md) + `packages/run_recorder`'s `WorkoutRunner` (step expansion, auto-advance, halfway/last-step progress, skip/abandon, results JSON, `workout_runner_test.dart`). The session runner is a sibling state machine.
- **The gym log + offline stores** — `gym_workouts` / `gym_sets`, `LocalGymStore` (offline-first, client-minted UUIDs, sets inline), `GymEditor.svelte` / `gym_compose_sheet.dart`. Executing a session writes here.
- **Conventions** — web-canonical (§24), byte-identical mobile twin (§39), TS↔Dart parity pairs + the `shared-library-syncer` agent, narrow-union+CHECK lockstep (`check_constraint_unions.mjs`), i18n in all six web locales + seven mobile ARBs, layered resilience (L0–L4), no emojis, minimal comments.

## Why a new engine, not gym routines

The axes differ enough to warrant a sibling structure (while mirroring its *shape*):

| | Gym routine ([gym_programming.md](gym_programming.md)) | Session plan (this spec) |
|---|---|---|
| End axis | sets × reps × **load (kg)** | time **or** reps, often **per-side**, **no load** |
| Order | matters loosely (supersets) | **sequence-critical** (a flow is the point) |
| Structure | exercises + supersets | **blocks** (warm-up / standing / floor / savasana) |
| Tempo/cue | RPE | **breath + alignment cue** per movement |
| Equipment | implicit (weights) | mat / **reformer** / props (yoga blocks, bands) |
| Execution | check off sets | **timed auto-advance** + per-side switch + TTS |

Reusing gym routines would force load/RPE semantics onto poses and lose hold-time + per-side + flow ordering. So: **a separate `session_plans` family that mirrors gym routines' relational shape + expand-once + planned-vs-actual, diverging on the time/side/cue axes.** Don't fork the *patterns*; do fork the *schema*.

## The validation gate (stated honestly)

Like the gym engine, **P1 is the probe, not a separate measurement phase.** P1 ships the cheapest durable slice — build + save + reuse a session plan, no execution, near-zero coupling — and its signal (do instructors actually build sessions? do self-practitioners?) justifies P2–P4. If the signal is flat, freeze at P1.

- **The bet:** the `class`-event instructors (yoga/pilates) who drove [club_events.md](club_events.md) want to author the *content* of their classes, not just schedule them; and self-practitioners want to build/repeat a personal flow.
- **The tradeoff:** P1 builds the session schema before execution proves out — accepted because it's additive, web-first, and independently useful (you can build + print/share a sequence even with no runner).
- **Owner sign-off to start.** No compliance gate (no payments, no new sub-processor) — this is gate-free on the legal axis, unlike `club_events.md` P. It only competes for build attention.

## Data flow

```
session_plans  +  session_plan_blocks  +  session_plan_items   (relational template)
    │
    │  expandSessionSteps(plan)   — flatten blocks→items, split per_side into L/R steps,
    │                               compute cumulative time   (PURE; TS↔Dart parity pair)
    ▼
List<SessionStep>                  ← computed once at execution start
    │
    │  SessionRunner consumes step timers / "next" taps → emits SessionExecEvent stream
    ▼
Follow-along band (Pose 4/12 · "Warrior II" · hold 0:90 · breath cue · Switch sides)
    │
    │  on finish → workoutDraftFromSession(plan, actuals)  → opens the gym composer pre-filled
    ▼
gym_workouts (+ gym_sets)          ← the session is LOGGED as a gym_workout (cross-modal)
gym_workouts.metadata.session_plan_id     ← links the log back to the plan
gym_workouts.metadata.session_step_results ← per-step planned-vs-actual
gym_workouts.metadata.session_adherence    ← 'completed' | 'partial' | 'abandoned'

events.session_plan_id  ── optional FK ──▶ a class event teaches from / offers a plan
```

The **template** (session_plan tables) and the **log** (`gym_workouts`, unchanged) bind by `metadata.session_plan_id`, never by FK between activity rows (mirrors the gym-routine ↔ gym-workout binding). A session plan is reusable and not dated → it does **not** feed the `activities` view.

## Data model

New tables (P1 migration `2026XXXX_001_session_plans.sql`; **run both type generators** — `npm run gen:types` + `dart run scripts/gen_dart_models.dart` — and **grow the Dart generator's table list** if needed, the way the paid-events tables were added):

- **`session_plans`** — `id` PK, `author_id` (FK → `auth.users`, the creator), `club_id` (nullable FK → `clubs`; set when a club owns the plan, mirroring `routes.club_id`), `title`, `discipline` (text, free-text label — "Vinyasa Yoga" / "Reformer Pilates" / "Barre"), `equipment` (text, nullable — "mat" / "reformer" / "none"), `est_duration_min` (int, nullable — derived from items, cached), `is_public` (bool, default false), `created_at`, `updated_at`. RLS: author reads/writes own; `is_public` readable by anyone; club-owned readable by club members + writable by club admins (mirror the club-owned-routes policies in [clubs.md § Club-owned routes](clubs.md#club-owned-routes)).
- **`session_plan_blocks`** — `id` PK, `plan_id` (FK, cascade), `position` (int), `name` (text — "Warm-up" / "Standing" / "Cool-down"; nullable → a flat plan with no blocks). Optional grouping layer. RLS inherits the parent plan's visibility.
- **`session_plan_items`** — `id` PK, `plan_id` (FK, cascade), `block_id` (nullable FK → blocks), `position` (int, ordering within plan/block), `movement_name` (text, free-text — normalise like gym exercise names), `kind` (text CHECK in (`'hold'`, `'reps'`, `'flow'`) — a **narrow union + CHECK pair**, register in `check_constraint_unions.mjs`), `duration_s` (int, nullable — for `hold`/`flow`), `reps` (int, nullable — for `reps`), `per_side` (bool, default false — splits into L/R at expand time), `tempo` (text, nullable — "slow" / "4-count"), `cue` (text, nullable — breath/alignment). RLS inherits the parent.

Additive column on the existing `events` table:

- **`events.session_plan_id`** (nullable FK → `session_plans`). A `class` event optionally attaches a full session plan (richer than the existing `gym_template` jsonb hint — see [Relationship](#relationship-to-the-gym_template-seam)). Readable wherever the event is; writable by the event organiser.

New narrow union (TS `types.ts` + CHECK, lockstep — append to `check_constraint_unions.mjs` `PAIRS`):

- `SessionItemKind = 'hold' | 'reps' | 'flow'`

New `runs.metadata`/`gym_workouts.metadata` keys (document in [metadata.md](../backend/metadata.md)): `session_plan_id`, `session_step_results`, `session_adherence`.

## The expand-once helper (parity pair)

`expandSessionSteps(plan)` — **pure**, the session analogue of gym's `expandRoutineSteps` / the workout runner's `expandWorkoutSteps`. Web `apps/web/src/lib/social/session_steps.ts` ↔ mobile `apps/mobile_android/lib/session_steps.dart` (**new TS↔Dart parity pair** — register in `CLAUDE.md` + `shared-library-syncer.md`). It:
- flattens blocks → items in `position` order,
- splits a `per_side` item into two consecutive steps (`…Left`, `…Right`),
- carries `kind` / `duration_s` / `reps` / `cue` / `tempo` onto each `SessionStep`,
- computes cumulative + total time (a `reps` step with no duration contributes 0 to the time estimate; note it in the est-duration caveat),
- is deterministic + side-effect-free so both platforms render identical step lists and the runner is unit-testable without a clock.

Mirror the test shape of `workout_runner_test.dart` / `distance_bands_test.dart` (same cases both sides, same count).

## Execution: the follow-along runner

A `SessionRunner` state machine mirroring `WorkoutRunner` ([workout_execution.md](workout_execution.md)) — but **time-driven**, not distance-driven:

- **States:** `idle → running → (paused) → finished | abandoned`.
- **Per step:** show `Pose i/N · movement_name · kind`, a **countdown** for `hold`/`flow` (auto-advances at 0), or a **rep counter + "Done" tap** for `reps`; the `cue` text; a **"Switch sides"** beat between an L and R step; **Skip** / **Pause** / **Abandon** controls; a progress bar + remaining time.
- **TTS (device-led):** announce the movement + cue + a 3-2-1 / "switch sides" / "last pose" via the existing locale-aware `audio_cues.dart` pattern (engine language follows `activeLocaleTag`); wrap every announcement in its own try/catch (L4 — a TTS failure never stops the timer). Pair with a haptic pulse like the run pace cues.
- **Keep-alive (mobile):** the runner is a keep-alive page like the recorder (it owns a foreground timer + TTS); it must survive backgrounding for the class duration. Do **not** demote it to a modal.
- **Two audiences, one runner:** an **instructor** runs it on the teaching screen (cue-forward, larger type, no "log my workout" prompt by default); an **attendee** runs it to follow along at home and on finish is offered the log step.
- **Results:** on finish, emit `session_step_results` (per step: planned vs actual — completed / skipped, actual hold time if cut short) + a `session_adherence` pill (`completed` / `partial` / `abandoned`, e.g. <80% of steps completed = partial), mirroring the gym/workout planned-vs-actual trio.

## Logging: session → gym_workout

On an attendee finishing a follow-along (confirm-first, inform-tier — never auto-write), open the **existing gym composer** (`GymEditor.svelte` / `gym_compose_sheet.dart`) pre-filled from the session: title = plan title, each movement → an "exercise" row (a `hold` → one set with the duration noted; a `reps` → reps, no load), `metadata.session_plan_id` + `session_adherence` stamped. This reuses `LocalGymStore` (offline-first) and means **a yoga/pilates session lands in the same gym log + recovery/load curve as a lift** — the cross-modal payoff. Extend `workoutDraftFromTemplate` (the existing seam helper) into `workoutDraftFromSession`, or add a sibling; keep it a parity pair.

(Open question: do timed holds map cleanly onto `gym_sets` (which assume reps/load), or does this need a `duration_s` column on `gym_sets`? See [Open questions](#open-questions).)

## Web UI

Web-first (§24). Surfaces:

- **`/sessions`** (or nested under the run-surface-style tabs for the gym/class modality) — list of the user's session plans + a "New session" button; club-owned plans surface on the club page (mirror club-owned routes).
- **`SessionPlanEditor.svelte`** (modal-hosted, the create-flow pattern) — title / discipline / equipment, then an ordered list of blocks + items; each item picks `kind` (Hold / Reps / Flow), enters duration-or-reps, a per-side toggle, tempo, and a free-text cue; drag-reorder; movement-name autocomplete from the user's history (like the gym exercise autocomplete). Live total-duration estimate.
- **`/sessions/[id]`** — read view + an "Attach to a class event" action (sets `events.session_plan_id`) + a web **player** (a simpler follow-along: timed auto-advance + on-screen cues; TTS optional on web).
- **`EventEditor.svelte`** (class events) — gains a "Session plan" picker (attach an existing plan or "none"), additive to the existing `gym_template` quick-hint.
- **`/clubs/[slug]/events/[id]`** — a class event with a `session_plan_id` shows the sequence + a "Start session" (host) / "Follow along" (attendee) entry.

## Mobile & watch

- **Mobile (Android/iOS, byte-identical twin §39):** the editor mirrors web; **mobile leads the follow-along runner** (TTS + timer + keep-alive page + haptics are device-led, the run-recorder precedent). The runner lands under the Fitness hub's Gym surface (a session is a gym-modality activity once logged) or off the class event detail. ARB keys in all seven catalogues.
- **Watch (Wear OS / watchOS):** a wrist follow-along (current pose + countdown + buzz on "switch sides") is a natural fit but **defer to P3/P4** — same call as the gym engine deferring the wrist follow-along. Build the phone runner first.

## Relationship to the gym_template seam

The shipped `events.gym_template` (jsonb `{discipline, duration_min}`) is the **lightweight** class→gym hint — "this class logs as ~50 min of Vinyasa." The `session_plan` is the **rich** successor — the actual movement sequence. They coexist:

- A class with **neither** → attendance only (current behaviour).
- A class with **`gym_template` only** → one-tap log a flat `gym_workout` (shipped seam).
- A class with **`session_plan_id`** → the full follow-along runner + a richer logged `gym_workout`; the plan's `discipline` + `est_duration_min` **supersede** the `gym_template` hint for that class.

Do **not** remove `gym_template` — it stays the zero-effort path for a host who doesn't want to author a full sequence. `workoutDraftFromSession` should fall back to `workoutDraftFromTemplate` when there's no plan.

## Persistence

- **Backend:** the three tables + `events.session_plan_id`, with RLS mirroring club-owned routes (author / public / club-member-read / club-admin-write).
- **Mobile offline:** a `LocalSessionStore` mirroring `LocalGymStore` / `LocalRouteStore` (one JSON file per plan, client-minted UUIDs, per-row sync state, `syncWithServer` drain create→update→delete, crash-atomic `writeJsonAtomic`, `_v` schema-version stamp). Building + editing a plan must work offline; the follow-along runner must work fully offline (it's a timer + local plan).
- The runner's in-progress state survives backgrounding (keep-alive); a crash mid-session should not corrupt the plan (the plan is immutable during execution; only the result draft is in flight).

## Failure modes

Per the [layered-resilience contract](../architecture/conventions.md#layered-resilience):
- **TTS / haptic failure** (L4) → wrapped per-effect; the timer + visual runner keep going.
- **A `reps` step with no duration** → contributes 0 to the time estimate; the runner waits on a "Done" tap, never auto-advances a rep step on a timer.
- **Backgrounding mid-session** → keep-alive page + a wall-clock anchor (don't trust a paused JS/Dart timer; recompute remaining from `started_at + elapsed`), like the recorder.
- **Plan edited while attached to a past event** → the logged `gym_workout` already captured the actuals; the plan is a template, so later edits don't rewrite history (no FK from the log to plan rows, only `metadata.session_plan_id`).
- **Empty plan / single item** → editor disallows save with zero items; the runner handles N=1.

## Testing

Per the [test-hygiene rule](../architecture/conventions.md#test-hygiene--review-then-unit-then-e2e):
- **Unit (both platforms, parity pair):** `expandSessionSteps` — block flattening, per-side L/R split, cumulative-time, reps-step-zero-duration, empty/single. Same cases + count web (`npx tsx --test`) and Dart (`flutter test`).
- **Unit:** the `SessionRunner` state machine (auto-advance on hold, wait on reps, skip/abandon, adherence classification) — mirror `workout_runner_test.dart`.
- **e2e (web, Playwright):** build a 3-item plan with a per-side hold → save → reopen → attach to a class event → the event shows the sequence. Backend pgtap: RLS (author/public/club-member read, club-admin write), the `SessionItemKind` CHECK, `events.session_plan_id` organiser-write.
- **Mobile widget:** the editor adds/reorders items; the runner renders a step + countdown + switch-sides beat; finishing opens the pre-filled gym composer.
- **Twin parity:** every Dart `lib/`+`test/` edit mirrored to iOS (§39); the new parity pair registered.

## File list

P1 (build + save + reuse a plan; no execution):
- `apps/backend/supabase/migrations/2026XXXX_001_session_plans.sql` — three tables + `events.session_plan_id` + RLS + the `SessionItemKind` CHECK. Regenerate both type files; grow the Dart generator table list.
- `apps/web/src/lib/social/session_steps.ts` (+ `.test.ts`) — pure expand helper (parity pair).
- `apps/web/src/lib/components/SessionPlanEditor.svelte` + `apps/web/src/routes/sessions/` (list + `[id]`).
- `apps/web/src/lib/core/data.ts` — `fetchSessionPlans` / `fetchSessionPlan` / `createSessionPlan` / `updateSessionPlan` / `deleteSessionPlan` / `setEventSessionPlan`.
- `apps/web/src/lib/types.ts` + `check_constraint_unions.mjs` — `SessionItemKind`.
- i18n: all six web locales.
- `apps/mobile_android/lib/session_steps.dart` (+ test, twin) — the Dart parity twin (P1 can ship the helper + a read/list view; the editor can follow in P1.5 or with execution).

P2 (attach + follow-along runner + log): `SessionRunner` (web + a `packages`-level or `lib/` state machine mirroring `WorkoutRunner`), the runner UI (web player + mobile keep-alive page + TTS via `audio_cues`), `workoutDraftFromSession`, `LocalSessionStore`, the `metadata` keys.
P3: movement/pose catalog + plan sharing/discovery + club-published session templates (mirror plan templates).
P4: progression/variations (beginner/intermediate per pose), multi-week courses (ties to `club_events.md` P4), watch follow-along, AI-assisted sequencing.

## Phasing & rollout

| Slice | Scope | Gate |
|---|---|---|
| **P1** | Build + save + reuse a session plan (editor, list, the pure expand helper as a parity pair). Web-first; mobile gets the helper + read/list. **No execution, no logging.** | Owner sign-off (low-risk, additive, no compliance gate) |
| **P2** | Attach a plan to a class event + the follow-along runner (timed, TTS, keep-alive) + log-as-gym_workout (cross-modal). Mobile leads execution. | P1 shows instructors/self-practitioners build plans |
| **P3** | Movement/pose catalog (free-text → optional catalog) + plan sharing/discovery + club-published session templates. | P2 engagement |
| **P4** | Progression/variations, multi-week courses, watch follow-along, AI sequencing. | Separate product decision |

## Open questions

1. **Timed holds vs `gym_sets`.** `gym_sets` assume reps/load. Does logging a session need a `duration_s` column on `gym_sets` (so a 90 s plank is first-class), or do we stash hold-time in `gym_sets.notes` / a metadata map for v1? Recommend a `gym_sets.duration_s` nullable column (clean, reusable for any timed exercise) — but it touches the gym schema, so decide before P2.
2. **Per-side modelling.** Split at expand time into L/R steps (recommended — keeps the data simple, the runner explicit) vs a `sides` count on the item. Expand-time split is the spec's default.
3. **Activity type.** Does an executed session log as a `gym_workout` (recommended — reuses the cross-modal model + recovery/load) or warrant its own activity type / `activities`-view branch? Reusing gym keeps it simple and on-model; revisit only if "yoga" needs to be visually distinct in History.
4. **Catalog vs free-text.** Free-text movement names (P1, like gym exercises) vs a curated pose catalog with images/cues (P3). Free-text first.
5. **Instructor vs attendee runner divergence.** One runner with a mode flag (recommended) vs two screens. Mode flag.
6. **Standalone vs class-only.** Can a self-practitioner build + run a session with no club/event (recommended yes — it's a personal-practice tool too) or is it class-only? Yes, standalone.

## Rough sizing

- **P1:** ~1.5–2 wk (3 tables + RLS + the editor + the pure helper + parity twin + tests). Low risk, additive, no compliance gate.
- **P2:** ~2–3 wk (the runner state machine + TTS/keep-alive + the log seam + offline store) — the meatiest, device-led slice.
- **P3 / P4:** separate, sized when reached.

## Appendix A — proposed ADR

Append to [decisions.md](../architecture/decisions.md) at the next free number when P1 lands:

> **§N. Yoga/pilates session content uses a dedicated `session_plans` engine (mirroring gym routines), not the gym-routine schema; executing a session logs a `gym_workout`.** The yoga/pilates domain is time-or-reps × per-side × sequence-critical × breath-cue — not sets × reps × load — so it gets a sibling relational family (`session_plans` / `_blocks` / `_items`) that mirrors the gym-routine engine's *shape* (expand-once, planned-vs-actual, self-hiding, parity-paired pure helper) while diverging on the axes. A `class` event optionally attaches a `session_plan_id` (the rich successor to the lightweight `events.gym_template` jsonb seam, which stays as the zero-effort path). The follow-along runner is a time-driven sibling of `WorkoutRunner`; on finish it logs a `gym_workout` (confirm-first, inform-tier) so a yoga/pilates session feeds the same recovery/load curve + Coach context as runs and lifts — the cross-modal payoff that is the product's north star. P1 (build/save/reuse, no execution) is the gate probe; no compliance gate (no payments).

## Appendix B — roadmap edits

When P1 lands: add a "Session planner (yoga/pilates content)" row under the Clubs/multi-modal area of [roadmap.md](../product/roadmap.md) (P1 shipped / P2–P4 planned). Flip [parity.md](../product/parity.md) cells (web ✓ editor; mobile ✓ when the twin lands; execution mobile-led in P2).

## Appendix C — docs-to-update (when each slice lands)

- [club_events.md](club_events.md) — the class→gym seam section: note `session_plan_id` as the rich successor to `gym_template`.
- [gym_programming.md](gym_programming.md) — cross-reference the sibling engine.
- [multi_modal.md](multi_modal.md) — a logged session is a gym-modality activity feeding the cross-modal curve.
- [api_database.md](../backend/api_database.md) — the three tables + RLS + `events.session_plan_id`.
- [metadata.md](../backend/metadata.md) — `session_plan_id` / `session_step_results` / `session_adherence` keys.
- `CLAUDE.md` + `shared-library-syncer.md` — register the `session_steps` (and any `workoutDraftFromSession`) parity pair; both type generators regenerated; `check_constraint_unions.mjs` updated for `SessionItemKind`.
- The per-app `CLAUDE.md` nav notes when the editor/runner surfaces land.
