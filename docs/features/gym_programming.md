# Gym workout programming

A scoped **depth-tier gym-programming engine** — reusable routines, structured execution (supersets / set-types / rest), planned-vs-actual adherence, and progression schemes — layered as a parallel planning structure on top of the existing flat `gym_workouts` / `gym_sets` log. It mirrors the run side's `plan_workouts` → `WorkoutRunner` precedent (jsonb-`structure` + scalar targets, expand-once, the planned-vs-actual metadata trio with an 80%-of-target cutoff) and diverges only where the gym domain forces it (sets × reps × load end axis, supersets, rest timers, reps/load adherence instead of pace tolerance).

> **Status:** **P1 shipped on web + mobile** (2026-06-11, migration `20270101_001`): `gym_routines` / `gym_routine_exercises` / `gym_routine_sets` + `gym_workouts.metadata`, the `gym_routine` parity helper (`routineFromWorkout` + `prefillFromRoutine`, web + Dart twin), the `/gym/routines` library / `[id]` detail / `new` builder, "Save as routine" + "Repeat last" on `/gym/[id]`, DSAR export of all three tables (Deno twin **and** the production Go worker `exportPersonalDataSpecs`), Playwright + pgtap. **Mobile twin shipped:** `LocalRoutineStore` (offline-first, exercises+sets inline), the routine library + detail screens + the routine builder sheet, the Routines entry on the gym AppBar, "Save as routine" + "Repeat last" on the gym detail screen, ARB keys across all seven catalogues, and widget + store tests — byte-identical on the iOS twin. P1 is prefill-only on both surfaces (no execution loop). P2–P4 remain specced and gated (see [Phasing](#phasing--rollout) and [The validation gate](#the-validation-gate-stated-honestly)).

**Contents:** [Product contract](#product-contract) · [The validation gate](#the-validation-gate-stated-honestly) · [Data flow](#data-flow) · [Data model](#data-model) · [Progression engine](#progression-engine) · [Execution: planned-vs-actual + adherence](#execution-planned-vs-actual--adherence) · [Web UI](#web-ui) · [Mobile & watch](#mobile--watch) · [Persistence](#persistence) · [Failure modes](#failure-modes) · [Testing](#testing) · [File list](#file-list) · [Phasing & rollout](#phasing--rollout) · [Open questions](#open-questions) · [Rough sizing](#rough-sizing) · [Appendix A — ADR §140](#appendix-a--decisionsmd--140) · [Appendix B — roadmap edits](#appendix-b--roadmapmd-phase-4-checklist-edits) · [Appendix C — docs-to-update checklist](#appendix-c--docs-to-update-when-each-slice-lands)

## Product contract

A user who logs gym sessions can:

- **Save a routine** — a named, ordered list of planned exercises with target sets × reps × load (or RPE), optional supersets, set-types, and per-set rest.
- **Repeat last** — one-tap re-instantiate a prior session (no saved routine required), with the engine suggesting the next target (linear bump or hold).
- **Start a routine** — a set-by-set execution loop with a top execution band (`Bench Press · Set 2/4 · 5 reps @ 80 kg` + reps/load-hit pip + rest countdown), supersets run round-robin.
- **Review adherence** — after a session, planned-vs-actual per set with a `completed` / `partial` / `abandoned` pill.
- **Follow a progression scheme** — linear, double-progression, 5×5, %-of-1RM cycles (5/3/1), or RPE auto-regulation prescribe the next session's targets from logged history.

Everything **self-hides** until a routine exists: a runner who never programs sees today's gym log unchanged. The engine **only suggests** — it never auto-mutates targets from logged data without a confirm step.

Non-goals for v1: multi-week program grouping (a `gym_programs` layer over routines is deferred), public-routine browse/discovery UI, a structured exercise catalog (binding stays free-text via `normaliseExerciseName`), and any wrist follow-along (see [Mobile & watch § watch scope](#watch-scope--defer-the-wrist-follow-along)).

## The validation gate (stated honestly)

The roadmap lists full programming as the gym **"heavy" depth tier** and marks "exercise database, workout templates, programmes, RPE-driven progression" **Not in scope** for the shipped lightweight log ([roadmap.md](../product/roadmap.md), the `**Not in scope:**` bullet; the "Gym — heavy (full programming)" heading just below it). The sequencing **gate** is the roadmap's *measure gym engagement before committing to nutrition* validation-gate sentence in the Phase-4 sequencing block. (These line numbers drift — search by the quoted text, don't trust a line number.)

**This design does not jump that gate — it relocates it.** Rather than running a separate measurement-only phase, we sequence the engine so its cheapest slice (**P1**, reusable routines + "repeat last", near-zero new schema) *is itself the gate probe*. P1 ships a self-contained durable win; if its repeat-rate signal clears an owner-set threshold (suggest ≥20% of gym sessions over 4–6 weeks), P2–P4 are justified. If it doesn't, we freeze at P1 and leave P2–P4 specced-but-unbuilt.

- **The bet:** repeat-logging of the same exercises (already reconstructable today via `initExercises` + `normaliseExerciseName`) is evidence users want a routine.
- **The explicit tradeoff:** faster-to-signal, at the cost of building the routine schema before the gate formally clears. The durable alternative the owner is choosing against is "clear the gate first, then build any schema."
- **The owner must sign this off.** For SOC 2 / GovRAMP-scoped changes (Coach-authored progression reads logged sets), loop in the CISO / Security Analyst before that path ships.

## Data flow

```
gym_routines  +  gym_routine_exercises  +  gym_routine_sets   (relational plan)
    │
    │  expandRoutineSteps(routine)   — grouped/round-robin, the gym analogue of expandWorkoutSteps
    ▼
List<GymStep>                         ← computed once at session start
    │
    │  prescribeNext(history, lastActuals, config)   — pure, suggests next targets
    ▼
Prefilled editable session draft (StoredGymWorkout, pendingCreate)
    │
    │  GymWorkoutRunner consumes set check-offs → emits GymExecEvent stream
    ▼
Execution band (Set 2/4 · reps @ load + hit pip + rest countdown)
    │
    │  on finish → existing buildSets / replaceGymSets writes the flat log UNCHANGED
    ▼
gym_workouts.metadata.routine_id        ← links the saved session back to the routine
gym_workouts.metadata.gym_step_results  ← per-expanded-set planned-vs-actual
gym_workouts.metadata.gym_adherence     ← 'completed' | 'partial' | 'abandoned'
```

The **plan** shape (routine tables) and the **log** shape (`gym_workouts` / `gym_sets`, unchanged) bind by `normaliseExerciseName` + order, **never by FK** between activity rows. A routine is reusable and is *not* a dated activity, so it does not feed the `activities` view.

## Data model

Planned structure is **relational, not jsonb** — the deliberate divergence from the run precedent. A run interval workout is a shallow single-axis tree edited as one blob, so `plan_workouts.structure jsonb` fits. A gym routine is the opposite: a list of exercises, each with a list of typed sets, queried per-exercise ("what's my planned 5/3/1 top set for squat"), bound to logged sets by normalised name, progressed row-by-row. That wants real rows + indexes. We keep **one** jsonb escape hatch — `progression_params` — for the per-scheme tuning bag, exactly mirroring the "evolve without a migration" rationale.

**Naming & conventions.** `gym_routines` (plural snake_case; "routine" is the lifting-domain term and the gym route namespace is clean of `program`/`template`/`plan`). Owner column = **`author_id`** (routines are authored content, convention F17). Offline-first → **`last_modified_at`** client-stamped, newer-wins, **no** server `updated_at` trigger. CHECK idiom matches the existing gym tables: `length(...)` (not `char_length`), and the `X is null or length(X) <= N` form for nullable text.

> **One coherent storage decision, used everywhere below:** the plan → session link and the planned-vs-actual trail live in **`gym_workouts.metadata`** (jsonb), mirroring the run side's `runs.metadata` trio — **not** a typed `routine_id` FK column on `gym_workouts`. Rationale: the step-result shape can evolve without a migration, a deleted routine leaves a harmless dangling id (immutable history), and it keeps byte-for-byte symmetry with the run review trail. **`gym_workouts` has no `metadata` column today** — the migration adds it (see [§ Prerequisite](#prerequisite-add-gym_workoutsmetadata)).

### The three planning tables

#### `gym_routines` — a user-owned named workout plan

```sql
create table public.gym_routines (
  id                uuid primary key default gen_random_uuid(),
  author_id         uuid not null references auth.users (id) on delete cascade,
  title             text not null check (length(title) between 1 and 120),
  notes             text check (notes is null or length(notes) <= 1000),

  -- periodisation model for the routine as a whole (narrow union ↔ CHECK pair)
  periodisation     text not null default 'none'
                      check (periodisation in ('none','linear','block','conjugate')),

  -- denormalised count for the list screen; client-stamped on save, NOT a trigger cache
  exercise_count    int not null default 0 check (exercise_count >= 0),

  external_id       text,                                    -- per-author import idempotency
  last_modified_at  timestamptz not null default now(),      -- client-stamped, newer-wins; NO trigger
  created_at        timestamptz not null default now()
);

create unique index gym_routines_author_external_id_key
  on public.gym_routines (author_id, external_id) where external_id is not null;
create index gym_routines_author_modified_idx
  on public.gym_routines (author_id, last_modified_at desc);
```

- **No `is_public` column in v1.** Public-routine sharing is a real feature (publish a 5/3/1 template), but shipping public-read RLS *before* the browse UI exists means any authenticated user can already enumerate public routines' `notes` + planned sets through the REST API (a `public-rows` leak). We ship **author-only RLS** now and add `is_public` + its public-read branch in the *same* migration that ships the browse UI. (Recorded as a deferred follow-up, not dropped forever.)
- **No `(user_id, started_at desc)` spine index** — routines don't feed `activities`. `(author_id, last_modified_at desc)` serves the list screen + sync drain.

#### `gym_routine_exercises` — planned exercises within a routine, with grouping

```sql
create table public.gym_routine_exercises (
  id                  uuid primary key default gen_random_uuid(),
  routine_id          uuid not null references public.gym_routines (id) on delete cascade,

  -- stable identity: free-text name for display, normalised key for binding to logged gym_sets
  exercise_name       text not null check (length(exercise_name) between 1 and 120),
  exercise_key        text not null check (length(exercise_key) between 1 and 120),

  -- ordering + grouping for supersets/circuits
  position            int not null check (position >= 0),    -- order of the GROUP within the routine
  superset_group      int,                                   -- null = standalone; shared int = same superset
  superset_order      int check (superset_order >= 0),       -- round-robin order within the group

  -- exercise modality (narrow union ↔ CHECK pair)
  modality            text not null default 'weight_reps'
                        check (modality in ('weight_reps','time','distance','bodyweight_reps')),

  -- per-exercise progression scheme (narrow union ↔ CHECK pair)
  progression         text not null default 'none'
                        check (progression in
                          ('none','linear','double_progression','five_by_five','percent_cycle','rpe_autoreg')),
  progression_params  jsonb not null default '{}'::jsonb,    -- scheme tuning bag (the ONE jsonb escape hatch)

  notes               text check (notes is null or length(notes) <= 500),

  constraint gym_routine_exercises_superset_chk
    check ((superset_group is null) = (superset_order is null))
);

create index gym_routine_exercises_routine_idx
  on public.gym_routine_exercises (routine_id, position, superset_order);
create index gym_routine_exercises_key_idx
  on public.gym_routine_exercises (exercise_key);            -- "what's planned for squat" lookups
```

- **Grouping model.** `position` orders the *groups*; a non-null `superset_group` ties exercises into one superset/circuit; `superset_order` gives the round-robin sequence inside the group. A standalone exercise has `superset_group = null, superset_order = null` and is its own group at `position`. This is the relational analogue of the run runner's grouped expansion — `expandRoutineSteps` round-robins across a `superset_group` rather than walking a linear list.
- **`exercise_key`** is `normaliseExerciseName(exercise_name)` stamped **at write time** (reuse the `gym_prs` parity-pair helper). It is the stable identity that binds a planned exercise to logged `gym_sets` (which carry only free-text `exercise_name`). Storing it as a column lets us index it and keeps binding deterministic. **Freeze policy:** the key is frozen at write time; if the normaliser ever changes, a backfill migration re-stamps it. Documented in `derived_state.md` as a non-cache invariant.

#### `gym_routine_sets` — planned target values per set

```sql
create table public.gym_routine_sets (
  id                  uuid primary key default gen_random_uuid(),
  routine_exercise_id uuid not null
                        references public.gym_routine_exercises (id) on delete cascade,

  set_index           int not null check (set_index >= 0),   -- per-exercise, 0-based (NOT the flat workout index)

  -- set type (narrow union ↔ CHECK pair)
  set_type            text not null default 'working'
                        check (set_type in ('warmup','working','dropset','amrap','failure','backoff')),

  -- target reps: a single value (min only) OR an inclusive range (double-progression needs the range)
  target_reps_min     int check (target_reps_min >= 0),
  target_reps_max     int check (target_reps_max >= 0),

  -- target load: absolute kg OR a %1RM (exactly one, or neither for bodyweight/RPE-only)
  target_weight_kg    numeric(7,2) check (target_weight_kg is null or target_weight_kg >= 0),
  target_percent_1rm  numeric(5,2) check (target_percent_1rm is null
                          or (target_percent_1rm > 0 and target_percent_1rm <= 200)),

  target_rpe          numeric(3,1) check (target_rpe is null or (target_rpe >= 0 and target_rpe <= 10)),

  -- rest after this set, seconds (the explicit inter-set timer step; mirrors run 'walk'/'recovery')
  rest_s              int check (rest_s is null or (rest_s >= 0 and rest_s <= 3600)),

  -- tempo: eccentric-pause-concentric-pause string e.g. "30X0"
  tempo               text check (tempo is null or tempo ~ '^[0-9X]{3,4}$'),

  -- time / distance targets for non-rep modalities
  target_duration_s   int check (target_duration_s is null or target_duration_s >= 0),
  target_distance_m   numeric(10,2) check (target_distance_m is null or target_distance_m >= 0),

  constraint gym_routine_sets_load_chk
    check (not (target_weight_kg is not null and target_percent_1rm is not null)),
  constraint gym_routine_sets_rep_range_chk
    check (target_reps_max is null or target_reps_min is null or target_reps_max >= target_reps_min)
);

create index gym_routine_sets_exercise_idx
  on public.gym_routine_sets (routine_exercise_id, set_index);
```

- **Reps as a range** (`target_reps_min` / `_max`): a single target leaves `_max` null; double-progression needs the range (e.g. 8–12). `amrap` / `failure` leave both null (open-ended). This is the canonical rep shape — the web builder and the progression engine both read it; there is no single `target_reps` column.
- **Load as kg OR %1RM, never both** (`gym_routine_sets_load_chk`). kg is canonical (reuse `format/weight.ts`); %1RM resolves to kg at instantiation via `estimatedOneRepMax` over the bound exercise's logged history (reuse `gym_prs`). Neither set → bodyweight or pure-RPE prescription.
- **Tolerance is computed, not stored.** Adherence (below) reuses the run side's 80%-of-target cutoff per set; there is no per-set `tolerance` column, matching the run side where tolerance is a runner default.

### Adherence — the single definition used everywhere

> One coherent rule across the engine, review panel, and progression input — **per-axis, never volume-product.** For each **non-warmup** planned set, it is a **hit** when `actual_reps >= 0.8 * target_reps_min` **AND** (when load is prescribed) `actual_weight_kg >= 0.8 * target_weight_kg`. Load is skipped for bodyweight / time / distance modalities.

- Any **skipped** step OR any step under the per-axis cutoff → `partial`.
- Abandon flag → `abandoned`.
- Otherwise → `completed`.
- `warmup` sets are **excluded** from the adherence denominator (skipping a warmup must not mark the session `partial`). `amrap` / `failure` sets count as **completed if any reps were logged**.

Per-axis (not the reps×weight product) is the chosen resolution: it matches how lifters think (you got the reps or you didn't) and the run precedent's per-step semantics, and it is the load-bearing `evaluateHit` input the progression engine consumes — so the same rule governs the review pill and the next-target computation.

### Narrow-union ↔ CHECK pairs to register

Each real column below needs a TS union in `apps/web/src/lib/types.ts` (via `Omit & {…}`), a CHECK in the migration, and a `PAIRS` entry in `apps/web/scripts/check_constraint_unions.mjs` (CI `parity-types` fails the PR otherwise). The Dart side treats all four as raw `String` (no Dart enum); invalid writes are rejected at the DB — same as `RunSource` / `ActivityType`.

| Column | Domain |
|---|---|
| `gym_routines.periodisation` | `none \| linear \| block \| conjugate` |
| `gym_routine_exercises.modality` | `weight_reps \| time \| distance \| bodyweight_reps` |
| `gym_routine_exercises.progression` | `none \| linear \| double_progression \| five_by_five \| percent_cycle \| rpe_autoreg` |
| `gym_routine_sets.set_type` | `warmup \| working \| dropset \| amrap \| failure \| backoff` |

`gym_adherence` (`completed \| partial \| abandoned`) is a **metadata value, not a column**, so it gets a TS union + client-side validation + a `metadata.md` entry, but **no CHECK** — exactly how the run side's `workout_adherence` is handled.

### RLS (owner-scoped, mirror `gym_workouts`)

```sql
alter table public.gym_routines          enable row level security;
alter table public.gym_routine_exercises enable row level security;
alter table public.gym_routine_sets      enable row level security;
```

- **`gym_routines`**: `select` / `insert` / `update` / `delete` all gated on `author_id = auth.uid()` (author-only in v1 — no public branch until the browse-UI migration; see above).
- **`gym_routine_exercises`** + **`gym_routine_sets`**: no own owner column — gate via `EXISTS` against the parent routine (`routine_id` / `routine_exercise_id` → `gym_routines.author_id = auth.uid()`), exactly how `gym_sets` is "visible via parent."

### On-delete behaviour

- `gym_routines.author_id → auth.users(id) ON DELETE CASCADE` (account-deletion erases routines — Art. 17).
- `gym_routine_exercises.routine_id → gym_routines(id) ON DELETE CASCADE`.
- `gym_routine_sets.routine_exercise_id → gym_routine_exercises(id) ON DELETE CASCADE`.
- **Deleting a routine does NOT touch logged `gym_workouts` / `gym_sets`** — the link is a metadata string, not an FK, so prior executed sessions stay intact (the `metadata.routine_id` becomes a harmless dangling id, exactly like a deleted `plan_workout_id` on a run). History is immutable by design.

### Indexes (summary)

| Index | Purpose |
|---|---|
| `gym_routines (author_id, last_modified_at desc)` | list screen + sync drain |
| `gym_routines (author_id, external_id) unique where external_id not null` | import idempotency (mirrors `gym_workouts.external_id`) |
| `gym_routine_exercises (routine_id, position, superset_order)` | ordered expansion incl. superset round-robin |
| `gym_routine_exercises (exercise_key)` | "what's planned for squat" cross-routine lookups |
| `gym_routine_sets (routine_exercise_id, set_index)` | ordered per-exercise set read |

No `(user_id, started_at desc)` spine index — routines don't feed `activities`.

### Prerequisite: add `gym_workouts.metadata`

`gym_workouts` was created (`20261204_001`) without a jsonb bag — unlike `runs`. Before any planned-vs-actual storage works, the migration must add it:

```sql
alter table public.gym_workouts
  add column metadata jsonb not null default '{}'::jsonb;
```

- **Migration-lock safety:** `add column … default '{}'` is **metadata-only** on PG11+ (no table rewrite, no blocking scan) — safe on the populated prod table. The three new routine tables are empty at creation, so none take a blocking lock. No FK is added to `gym_workouts` (the link is a metadata string), so there is no `SHARE ROW EXCLUSIVE` validation scan to worry about. Run `/audit:migration-locks` to confirm before landing.
- **`activities` view check (required task):** adding a column to `gym_workouts` is only safe if the `activities` UNION view's lift branch enumerates explicit columns. **Read the view definition and confirm the lift branch does not `select *`** — if it did, the new `metadata` column would change the branch's shape and break column-count alignment with the run branch. (It selects `(id, user_id, kind, started_at, summary, is_public)` — explicit columns per branch, so `metadata` is excluded — but verify, don't assume.)

### Both codegen regenerations (mandatory)

1. **`npm run gen:types`** → regenerates `apps/web/src/lib/database.types.ts` (committed). Then add the four narrow unions to `types.ts` and the four `PAIRS` entries to `check_constraint_unions.mjs`.
2. **`dart run scripts/gen_dart_models.dart`** → regenerates `packages/core_models/lib/src/generated/db_rows.dart` (committed). **Prerequisite, not an aside:** verify the generator emits a field for a `jsonb not null default '{}'` column (`progression_params`, and the new `gym_workouts.metadata`) *before* committing to the schema. `numeric(7,2)` / `numeric(3,1)` are already proven by `gym_sets`; jsonb on a brand-new column is the open one. If the generator drops it, **grow the parser** in `gen_dart_models.dart` — never hand-edit `db_rows.dart`. The generator ignores CHECK / index / RLS / `~` regex / table-level constraints by design.

## Progression engine

The "intelligence" — **pure math over history + config, no side effects.** It does not read the DB, does not write a routine, does not auto-mutate anything. The (impure) instantiation layer calls it, gets a `PrescribedSession`, and prefills an editable draft the user can still change before logging. This keeps the engine a Tier-1 "inform" computation; the Tier-2 "command" (writing a routine row) is a deliberate user-confirmed step elsewhere.

### Module decomposition — three small parity pairs

The engine is **three** pure TS↔Dart parity pairs, not one monolith (the cleaner factoring; each is independently testable). All three go on the tracked-pair list in root `CLAUDE.md` and are checked by `shared-library-syncer` after edits:

| Pair (web ↔ mobile) | Responsibility |
|---|---|
| `gym/gym_routine.ts` ↔ `gym_routine.dart` | `routineFromWorkout`, `prefillFromRoutine`, `expandRoutineSteps` (grouped/round-robin plan → flat step list) |
| `gym/gym_adherence.ts` ↔ `gym_adherence.dart` | the per-axis 80%-cutoff reducer + skip/abandon logic → `'completed' \| 'partial' \| 'abandoned'` |
| `gym/gym_progression.ts` ↔ `gym_progression.dart` | `prescribeNext` — the next-target prescriber per scheme |

Mobile lives flat under `apps/mobile_android/lib/` (where the existing gym helpers `gym_prs.dart` / `exercise_history.dart` / `lift_load.dart` already sit — there is no `lib/gym/` subdir on mobile today; web nests under `gym/`, mobile is flat) and is mirrored **byte-identical** into `apps/mobile_ios/`. Each pair has identical algorithm, edge cases, outputs, and **test count** on both sides. They reuse `estimatedOneRepMax` + `normaliseExerciseName` (from `gym_prs`) and consume the `ExerciseSession[]` series from `exercise_history.ts` (`previousExerciseSession`) — so the prescriber and the "vs last time" hint can never drift. (The mobile `exercise_history.dart` mirror has already landed and is a tracked parity pair, so "next target" can reuse `previousExerciseSession` without new mirror work.)

### Core types (`gym_progression`)

```ts
export type ProgressionScheme =
  'none' | 'linear' | 'double_progression' | 'five_by_five' | 'percent_cycle' | 'rpe_autoreg';

export interface LoadingConfig {
  unit: WeightUnit;             // 'kg' | 'lbs' — from format/weight.ts
  incrementDisplay: number;     // smallest progression step in display unit (2.5 kg / 5 lb)
  smallestPlateDisplay: number; // smallest plate pair available for rounding (default = increment)
}

export interface ProgressionConfig {
  scheme: ProgressionScheme;
  loading: LoadingConfig;
  targetSets: number;
  targetReps: number;           // linear / 5x5: fixed rep target. double: top of range.
  repRangeMin?: number;         // double progression only (bottom of the climb)
  incrementKg?: number;         // overrides loading-derived increment (canonical kg)
  deloadAfterMisses?: number;   // N consecutive failed sessions → deload (default 3)
  deloadFactor?: number;        // multiply working weight on deload (default 0.9)
  // percent_cycle (5/3/1):
  trainingMaxKg?: number;       // explicit TM; else 0.9 × best e1RM
  weekIndex?: number;           // 0-based wave position
  percentWave?: number[][];     // per-week [pct-of-TM …]; default Wendler table
  tmIncrementKg?: number;       // TM bump after a completed wave (+2.5 upper / +5 lower, caller-set)
  // rpe_autoreg:
  targetRpe?: number;           // e.g. 8
  rpeRepTarget?: number;        // reps the prescribed sets are written for
}

export interface PrescribedSet {
  reps: number;
  weightKg: number;             // canonical kg, plate-rounded (0 ⇒ bodyweight)
  isAmrap?: boolean;            // 5/3/1 top set
  targetRpe?: number;
}

export interface PrescribedSession {
  exerciseName: string;
  scheme: ProgressionScheme;
  sets: PrescribedSet[];
  rationale: ProgressionRationale;   // drives a one-line chip; never a silent change
  trainingMaxKg: number | null;      // TM used (percent_cycle), echoed for the caller to persist
}

export type ProgressionRationale =
  | { kind: 'first_session' }
  | { kind: 'progress'; addedKg: number }
  | { kind: 'hold'; reason: 'partial' }
  | { kind: 'rep_climb'; fromReps: number; toReps: number }
  | { kind: 'deload'; factor: number; afterMisses: number }
  | { kind: 'wave_step'; weekIndex: number }
  | { kind: 'rpe_adjust'; deltaKg: number };

export function prescribeNext(
  history: ExerciseSession[],              // from exercise_history.ts (chronological, oldest-first)
  lastActuals: LastSessionActuals | null,  // null ⇒ first-ever session
  config: ProgressionConfig,
): PrescribedSession;
```

### Shared primitives

- **`evaluateHit(actuals, prescribedReps, prescribedSets) → 'hit' | 'partial'`** — applies the per-axis 80% cutoff (above) per working set on reps; a set under 80% of prescribed reps is a miss.
- **`consecutiveMisses(history, …) → int`** — count of most-recent-contiguous missed sessions of *this* exercise (matched by `normaliseExerciseName`); drives deload.
- **`roundToPlate(weightKg, loading) → number`** — the single load-quantiser every scheme funnels through, so a 5/3/1 percentage and a linear +2.5 land on the same plate grid. Rounds in the *display* unit then converts back to canonical kg via `format/weight.ts`. `roundToPlate(0) === 0` (bodyweight stays bodyweight). A computed load that rounds below the smallest increment clamps to the increment **in a barbell context** — for micro-load accessories (`smallestPlateDisplay` small) the clamp is skipped so a 1 kg dumbbell exercise isn't pushed to 2.5 kg.

### Schemes

| Scheme | Rule (one line) | Worked example |
|---|---|---|
| **linear** | Hit → +increment; partial → hold; `deloadAfterMisses` consecutive misses → `×deloadFactor`, round, reset counter. Tracks the bar, not e1RM. | Squat 3×5: hit @100 → 102.5; last set short → hold 102.5; 3rd consecutive miss → 102.5×0.9=92.25 → **92.5 kg**. |
| **double_progression** | Range `repRangeMin..targetReps` at fixed load: below top → +1 rep same load; at top, all sets → +increment, reps reset to min. Partial holds. | DB press 8–12: 3×8@20 hit → **3×9@20**; …3×12@20 hit → **3×8@22.5**. |
| **five_by_five** | A `linear` specialisation: 5 sets × 5 reps, defaults (+2.5 upper / +5 lower), `deloadAfterMisses=3`, `−10%`. One code path; the tag only changes defaults + rationale label. | Bench 5×5@60 hit → 62.5; stall 3× → 62.5×0.9=56.25 → **57.5 kg**, then resume. |
| **percent_cycle** (5/3/1) | % of training max (TM = explicit, else 0.9×best e1RM from history). `weekIndex` selects the wave row; top set `isAmrap`. After a full wave, caller bumps TM by `tmIncrementKg` and persists; engine echoes the TM used. | DL best e1RM 200 → TM 180; week 0 (65/75/85%) → **117.5 / 135 / 152.5**, top AMRAP. |
| **rpe_autoreg** | Load = `currentE1rm × pct(targetRpe, rpeRepTarget)` (RPE×reps coefficient table), plate-rounded. If last avg RPE was ≥1 off target, nudge ±1 increment (bounded to ±1/session). | RPE8@5, e1RM 100, coeff 0.81 → 81 → **80 kg**; last @RPE9.5 → −2.5 → **77.5 kg**. |

Default Wendler wave for `percent_cycle`:

| week | set 1 | set 2 | set 3 (AMRAP) |
|---|---|---|---|
| 0 | 65% | 75% | 85% |
| 1 | 70% | 80% | 90% |
| 2 | 75% | 85% | 95% |
| 3 (deload) | 40% | 50% | 60% |

### Edge cases (identical both sides)

- **First-ever session** (`history` empty AND `lastActuals == null`): `rationale: first_session`. Seed from config starting weight; `percent_cycle`/`rpe_autoreg` need a TM/e1RM, else fall back to config weight; if none, prescribe reps-only at weight 0 and let the user fill the bar. Never throw.
- **Partial:** never advances load → `hold`.
- **Deload trigger:** `consecutiveMisses >= deloadAfterMisses`, counted only for this exercise (name-normalised), most-recent-contiguous; resets implicitly once the deloaded load is hit.
- **Bodyweight (weight 0):** `roundToPlate(0) === 0`; linear/double "progress" advances **reps**; `percent_cycle`/`rpe_autoreg` of a 0-e1RM exercise → reps-only. No NaN, no negative load.
- **Non-finite / negative inputs:** `numericOrNull`-guarded (same shape as `gym_prs` / `exercise_history`); a null/NaN actual is treated as a missed set, never propagated.
- **Determinism:** ordering follows `exercise_history.ts` (oldest-first, workout-id tiebreak). No `Date.now()`, no RNG — output is a pure function of inputs, so TS and Dart produce byte-identical numbers (asserted by a shared fixture).

## Execution: planned-vs-actual + adherence

The `GymWorkoutRunner` is the direct mirror of `WorkoutRunner`: a state machine that sits **on top of** the gym logging session (not inside it), consumes `expandRoutineSteps`, drives a set-by-set band, and persists prescribed-vs-actual.

- **Lives in `packages/run_recorder/`** (where `WorkoutRunner` lives, per `workout_runner.dart`) so iOS/watch can reuse it. The package name is a known smell — the gym runner has zero GPS/`RunRecorder` dependency — accepted for reuse symmetry rather than spinning a sibling package; noted so a future session doesn't trip on it.
- **State machine** emits a `GymExecEvent` stream (`SetTransition`, `RestStarted` / `RestProgress` / `RestComplete`, `SetLogged`, `Complete`, `Abandoned`); idempotent `skipSet` / `rewindSet` (one deep) / `abandon`. Step transitions route through a `ValueNotifier` to avoid hot-path full-tree rebuilds, mirroring the run band.
- **Supersets** run round-robin (Set 1 of A → Set 1 of B → rest → Set 2 of A …), not a linear list.
- **Rest** is an explicit duration-based step kind, mirroring the run side's `walk` recovery; a local `Timer` drives the countdown, no server round-trip.
- **Crash-safety dual save:** a `reviewMetadata()` analogue runs on **both** the in-progress save tick and final stop, so a mid-session crash preserves the trail.

### The metadata trio (on `gym_workouts.metadata`)

Mirrors the run trio. Registered in [metadata.md](../backend/metadata.md):

| `gym_workouts.metadata` key | Shape | Mirrors |
|---|---|---|
| `routine_id` | uuid string — the `gym_routines.id` this session instantiated | `plan_workout_id` |
| `gym_step_results` | array, one per expanded planned set (below) | `workout_step_results` |
| `gym_adherence` | `'completed' \| 'partial' \| 'abandoned'` | `workout_adherence` |

Per-step result JSON (`GymStepResult.toJson()` in the runner package, mirroring `WorkoutStepResult`):

```jsonc
{
  "step_index": 4,
  "routine_exercise_id": "…",
  "exercise_key": "squat",
  "set_type": "working",
  "superset_group": 1, "superset_round": 2,
  "target_reps_min": 5, "target_reps_max": 5,
  "target_weight_kg": 100.0,
  "target_rpe": 8,
  "actual_reps": 5, "actual_weight_kg": 100.0, "actual_rpe": 8.5,
  "actual_gym_set_id": "…",
  "status": "completed"
}
```

- **Binding plan → log.** On finish, the existing `buildSets` flattens to the flat positional `set_index` list and `replaceGymSets` writes `gym_sets` **unchanged** — the planning layer is fully parallel. Each step result carries `actual_gym_set_id`; binding also works by `exercise_key` + order when ids are unavailable (offline).
- **Adherence** uses the single per-axis 80% rule from [Data model § Adherence](#adherence--the-single-definition-used-everywhere) — computed locally by `gym_adherence.dart` from logged-vs-planned sets, no server call.
- **Two-signal completion** reused: a session counts as "from routine" when `routine_id` is present in metadata (the execution signal) — the same two-signal shape as the run side's `manually_completed` / `completed_run_id`, no new column.

## Web UI

SvelteKit, the canonical feature surface. Everything **self-hides** until a routine exists.

### Routine library — inside `/gym`

- A **Routines** section on the existing `/gym` page, **above** the workout list. The whole section self-hides when the user has zero routines — no empty "create your first" placeholder (that would violate self-hide).
- **Entry to create:** when routines exist → a `New routine` button in the section header. When none exist → routines are surfaced *only* via the `GymEditor` "Save as routine" affordance (§ low-friction entry) and via Coach.
- **Rows** (`RoutineCard.svelte`): title, exercise count, superset glyph, last-used date, progression-model chip. Actions: **Start** (→ session), **Edit**, **Duplicate**, **Delete** (via global `ConfirmDialog`).
- **Routes:** extend `/gym/+page.svelte`; add `/gym/routines/[id]` (detail/preview, mirrors `/plans/[id]`) and `/gym/routines/new` (thin wrapper around the builder, mirroring `/plans/new` ↔ `PlanEditor`).
- **Components:** `RoutineLibrary.svelte`, `RoutineCard.svelte`.

### Routine builder — sibling of `GymEditor`

- **New `RoutineEditor.svelte`**, not an overload of `GymEditor` — the log's contract is *log actuals now*; the builder's is *prescribe targets, add supersets/rest/progression*. **Reuse** `GymEditor`'s in-memory `EditExercise{name, sets[]}` block model and the `<input list=datalist>` exercise picker (fed by `gym_exercise_names`) by extracting the block-list sub-UI into a shared **`ExerciseBlockList.svelte`** both editors mount (no copy-paste).
- Modal-hosted (`.modal-backdrop` / `.modal` / `oncreated` / `oncancel`); the `/gym/routines/new` route is the thin page wrapper.
- **Per exercise block:** target sets, per-set target reps (range), weight *or* `%1RM`, RPE (entry honours `weight_unit` via `format/weight.ts`), inter-set `rest_s`, a **superset toggle** that brackets adjacent blocks into a group, and drag-to-reorder.
- **Progression attach:** a per-exercise selector driving `gym_progression`'s prescriber.

### Follow / execute mode — `/gym/session/[routineId]`

A focused single-page surface (40–48rem cap), **not** a modal — execution is a sustained task like the run runner. On entry the prescriber prefills per-set targets. The **web execution band** (`GymExecutionBand.svelte`, the web-side analogue of `workout_execution_band.dart`):

1. `Bench Press · Set 2/4 · 5 reps @ 80 kg` + a **reps/load-hit pip** (green ≥ target, amber under, grey pending) — *no pace pip; the gym divergence.*
2. progress (sets done / total, superset round indicator).
3. collapsible controls: **rest countdown** (`RestTimer.svelte`, auto-starts on check-off), skip-set, mark-done.

Each prescribed set is a checkable row pre-filled with the target; the user edits reps/weight/RPE to actual and checks it off. **Crash-safety:** debounced in-progress write + a final write on finish. On finish → real `gym_workouts` + `gym_sets` log via `buildSets` / `replaceGymSets`, plus the metadata trio. Components: `GymSessionRunner.svelte`, `GymExecutionBand.svelte`, `RestTimer.svelte`.

### Planned-vs-actual review — on `/gym/[id]`

Mirrors the run workout-review section. When the saved workout carries `routine_id`, `/gym/[id]` shows an **Adherence** panel (`GymWorkoutReview.svelte`, mounted conditionally; self-hides for ad-hoc workouts). It shows the adherence pill + a per-set hit/miss list using **glyph + label**, not colour alone (`✓ 5×80 / target 5×80`, `△ 4×80 / target 5×80`, `✗ skipped`). The hit rule is the single per-axis 80% cutoff — *not* a reps×weight volume product.

### Low-friction entry — the adoption wedge

This is the most important adoption lever and what the validation gate measures:

- **`Repeat workout`** on `/gym/[id]` and each `/gym` row → opens `/gym/session/…` seeded from that prior workout's sets *as an ad-hoc routine* (no saved routine required); the prescriber suggests the next target. Delivers progression value before the user ever builds a routine.
- **`Save as routine`** on `/gym/[id]` → promotes the grouped in-memory blocks into a real `gym_routines` row. This is the **only create entry shown before any routine exists**, keeping the library self-hidden until earned.

### i18n (six locales)

Every new string lands in `en.ts` + `de/fr/es/ja/pt-BR` (`satisfies Messages` + `messages_parity.test.ts` enforce parity) before the call site uses `m('key')`, and mirrors to all mobile ARBs for the twin. Key groups: `gym.routine.*`, `gym.session.*`, `gym.review.*`. The band line is **interpolated** (`m('gym.session.bandSet', {set, total, reps, weight})`) — never string-concat; `weight` is pre-formatted via `format/weight.ts` so the unit follows the pref.

## Mobile & watch

Flutter (byte-identical twin) mirrors the web surfaces — strictly **downstream of web** (don't start the Flutter mirror until the web screens + the three parity pairs are merged and tested). Purely additive and self-hiding. **P1 shipped** (`local_routine_store.dart`, `screens/routine_library_screen.dart`, `screens/routine_detail_screen.dart`, `widgets/routine_builder_sheet.dart`, the Routines entry on `gym_screen.dart` + Save-as-routine/Repeat-last on `gym_detail_screen.dart`); execute mode (the runner + band rows in the table below) stays P2-deferred.

### Flutter screens & widgets

| New / extended | Mirrors web | Notes |
|---|---|---|
| `screens/gym_screen.dart` (extend) | `/gym` list | Add a Routines section that **self-hides** with zero routines. Primary action stays "Log workout"; "Start routine" appears only once a routine exists. |
| `screens/routine_library_screen.dart` (new) | `/gym/routines` | Authored routines; pull-to-refresh drains the routine sync; tap → detail. |
| `screens/routine_detail_screen.dart` (new) | `/gym/routines/[id]` | Planned targets, supersets shown grouped/indented. Primary **Start**; secondary edit/duplicate/delete (delete behind `ConfirmDialog`). |
| `widgets/routine_builder_sheet.dart` (new) | `RoutineEditor` | Reuse the `gym_compose_sheet.dart` block model; add target fields (sets, rep range, weight or %1RM, RPE), drag-reorder, superset toggle; `gym_exercise_names` autocomplete; `normaliseExerciseName` key binds plan → log. |
| `screens/routine_execute_screen.dart` (new) | `/gym/session/[routineId]` | The "dwell-in capture page" — owns the foreground for the session; set checklist + rest sheet. |
| `widgets/gym_execution_band.dart` (new) | `GymExecutionBand` | Mirrors `workout_execution_band.dart` structure: line 1 label + reps/load-hit pip; line 2 rest countdown; line 3 collapsible skip/rewind/abandon. Routed through a `ValueNotifier`. No pace pip. |
| `widgets/gym_summary_card.dart` / `gym_detail_screen.dart` (extend) | `GymWorkoutReview` | Prescribed-vs-actual adherence + a "next target" suggestion; self-hides for ad-hoc workouts. |

Weight display/entry stays kg-canonical via the Dart weight formatter (byte-for-byte mirror of `format/weight.ts`); %1RM resolves to kg at instantiation via `estimatedOneRepMax`.

### Offline-first store

- **New `LocalRoutineStore`** (sibling of `LocalGymStore` / `LocalGearStore`), extending `OfflineSyncStore<StoredRoutine>`: one JSON file per routine under `<appDocs>/routines/`, with `gym_routine_exercises` + their planned sets carried **inline** (a routine is never partially useful). `StoredRoutine implements SyncEntry`: client-minted v4 UUID = server id, client-stamped `last_modified_at`, `syncState` (`synced` / `pendingCreate` / `pendingUpdate` / `pendingDelete`), tombstones. Methods: `createLocal` / `updateLocal` / `deleteLocal` / `byId` / `entryFromJson` / `summaryOf` / `asSynced` / `asPendingCreate`.
- **An instantiated session is a `StoredGymWorkout`, not a new type.** Starting a routine reads it from `LocalRoutineStore`, expands via `expandRoutineSteps`, and prefills a `pendingCreate` `StoredGymWorkout` in the existing `LocalGymStore` — planned targets + the metadata trio ride in workout `metadata`. The logged-history pipeline (`activities` view, PR triggers, `volume_kg` cache) is unchanged.

### Execute mode offline

Fully offline by construction — no GPS/recorder stream. Instantiation reads local files; every check-off / edit / skip / rest tick mutates local state + the local JSON via the dual-save tick; on stop the session is a `pendingCreate` workout the normal `syncWithServer` drain pushes when connectivity returns. Adherence + "next target" computed locally by the parity pairs.

### Twin invariant & test obligations

- **Byte-identical twin:** every `lib/` + `test/` file added to `mobile_android` is copied byte-for-byte to `mobile_ios` (decisions §39); platform branches dispatch via `Platform.isIOS` inside the shared file, never two divergent files. Run `/audit:twin-parity` before declaring done.
- **Parity pairs:** after the web side lands, the three Dart pairs must match algorithm, edge cases, outputs, and **test count**; invoke `shared-library-syncer` after editing either side.
- **Tests:** `packages/run_recorder/test/gym_workout_runner_test.dart` (superset round-robin expansion, rest-step countdown, check-off auto-advance, skip/rewind-one/abandon, per-axis adherence, dual-save crash trail — mirror the `workout_runner_test.dart` shape); `gym_progression_test.dart` / `gym_adherence_test.dart` / `gym_routine_test.dart` (equal counts to their TS twins); `local_routine_store_test.dart` (sync states, drain order, `replaceFromServer` preserve-pending + newer-wins, inline round-trip — store I/O needs `tester.runAsync`); widget tests (builder superset grouping + %1RM→kg, execute band rest countdown + hit pip with dialog-scoped finders, detail "Start"). Mind the mobile-test gotchas: `pumpAndSettle` hangs on running animations; banner timers leave pending work. Mobile/watch have **no e2e** by design.

### Watch scope — defer the wrist follow-along

**Defer; ship mobile + web only this round.** The watch clients are a *wrist-only complement, not a pocket-app mirror*. A gym session is a stationary, two-hands-near-the-phone activity where the phone is glanceable on the floor by the rack — the opposite of running (phone pocketed, wrist is the only surface), which is *why* the run watch follow-along earns its place. Reps/load number entry on a 1.4" screen is exactly the fiddly interaction the watch scope rule pushes to the phone. A new Compose-for-Wear + SwiftUI screen, a new sync path (watches don't carry `LocalRoutineStore`), and a phone↔watch handoff are disproportionate cost. **Trigger to reopen:** a minimal wrist **rest-timer + set-advance haptic** *only if* mobile data shows users executing routines away from their phone. Record this one-liner in **both** `apps/watch_wear/CLAUDE.md` and `apps/watch_ios/CLAUDE.md` scope sections so a future session doesn't re-litigate it.

## Persistence

| What | Where | Notes |
|---|---|---|
| Routines (plan) | `gym_routines` + `gym_routine_exercises` + `gym_routine_sets` | relational; offline-mirrored in `LocalRoutineStore` (inline children) |
| Plan → session link | `gym_workouts.metadata.routine_id` | uuid string, not an FK |
| Planned-vs-actual trail | `gym_workouts.metadata.gym_step_results` | array of `GymStepResult` |
| Adherence verdict | `gym_workouts.metadata.gym_adherence` | `completed \| partial \| abandoned` |
| Logged sets (actual) | `gym_workouts` + `gym_sets` | **unchanged** — the existing flat log |
| `exercise_count` | `gym_routines.exercise_count` | **client-stamped on save, NOT a trigger cache.** Documented in `derived_state.md` as client-stamped + non-authoritative so a future session doesn't assume it's a derived cache. If we ever need server-authoritative counts, the full `derived_state.md` contract applies (full-recompute trigger, manual rebuild fn, pgtap that mutates source and asserts cache == recompute, recompute-from-scratch — never increment). |

No per-day/per-event growth → **no retention purge / pg_cron** for the planning tables.

### DSAR export + erasure (SOC 2 / GovRAMP — not optional)

- **Erasure (Art. 17):** handled by `ON DELETE CASCADE` from `auth.users` through all three routine tables; the metadata trail dies with the `gym_workouts` row. Verify with `/audit:account-deletion-completeness`.
- **Export (Art. 20 / CCPA):** the `export-data` Edge Function **must be extended** to include `gym_routines` + `gym_routine_exercises` + `gym_routine_sets` (and the new `gym_workouts.metadata` payload), with its completeness pgtap updated, or the export ships incomplete on day one. This is an explicit task in P1, not a follow-up. Verify with `/audit:data-export-completeness`.

## Failure modes

- **Routine deleted after a session ran it:** the session's `metadata.routine_id` becomes a harmless dangling id — history is intact (no FK, no cascade to logs).
- **Process killed mid-session:** the in-progress `StoredGymWorkout` is recovered from `LocalGymStore`; the dual-save tick means the metadata trail (`gym_step_results`, `gym_adherence`) is already on it. The in-progress set reads `skipped`; adherence reads `partial`.
- **Offline the whole session:** fully supported — instantiation reads local files, the runner is a local state machine, the rest timer is a local `Timer`; the `pendingCreate` workout syncs when connectivity returns.
- **Free-text name drift** ("Bench" vs "Barbell Bench Press"): the plan→log binding via `normaliseExerciseName` breaks and corrupts progression input. Inherited fragility until a stable exercise identity lands (see Open questions).
- **Fat-finger logged set (800 kg):** the prescriber would read it as a giant e1RM jump. The engine **only suggests**; the instantiation layer prefills an *editable* draft and never auto-logs. A "confirm next target" step is mandatory; auto-apply is never allowed.
- **Empty routine:** `expandRoutineSteps` yields zero steps → instant `Complete`, band doesn't mount, no null-deref.

## Testing

| Surface | Where | What |
|---|---|---|
| Parity pairs (×3) | `gym_progression`, `gym_adherence`, `gym_routine` — TS (`npx tsx --test`) + Dart (`flutter test`), **equal counts** | scheme outcomes (hit/partial/deload/rep-climb/wave/rpe nudge), per-axis 80% cutoff, expansion + superset round-robin, plate rounding incl. bodyweight + micro-load, first-session seeding, non-finite guards, determinism fixture |
| Runner | `packages/run_recorder/test/gym_workout_runner_test.dart` | expansion counts, auto-advance on check-off, rest countdown, skip/rewind/abandon idempotency, dual-save crash trail |
| Store | `local_routine_store_test.dart` | sync states, drain order, `replaceFromServer` preserve-pending + newer-wins, inline children round-trip (`tester.runAsync`) |
| Web widget / flow | Playwright `apps/web/tests-e2e/gym/` | `routine_builder.spec.ts`, `routine_session.spec.ts` (incl. one under-target + one skip → assert log created), `routine_review.spec.ts` (assert `partial` + per-set hit/miss AND ad-hoc workout shows **no** panel), `repeat_workout.spec.ts`, self-hide regression in `gym.spec.ts` |
| Backend | pgtap (`apps/backend/supabase/tests/`) | RLS author-only on all three tables + cascade-from-`auth.users`; `export-data` completeness includes the three tables; adherence-from-metadata math if any moves server-side |

Mobile widget tests cover the builder, execute band, and detail-Start instantiation. Mobile/watch have no e2e equivalent by design (web Playwright + backend pgtap cover the e2e path).

## File list

**Migration** — `apps/backend/supabase/migrations/20270101_001_gym_programming.sql` (next free slot; latest is `20261230_001` — re-confirm the next slot at land time, the migrations directory moves): `alter table gym_workouts add column metadata jsonb`, the three routine tables + indexes + RLS + four CHECKs.

**Generated (committed):** `apps/web/src/lib/database.types.ts`, `packages/core_models/lib/src/generated/db_rows.dart`.

**Web:** `src/lib/types.ts` (+4 unions), `scripts/check_constraint_unions.mjs` (+4 PAIRS), `src/lib/gym/gym_routine.ts`, `src/lib/gym/gym_adherence.ts`, `src/lib/gym/gym_progression.ts`, `src/lib/core/schema.ts` (metadata routing), `RoutineLibrary.svelte`, `RoutineCard.svelte`, `RoutineEditor.svelte`, `ExerciseBlockList.svelte` (extracted), `GymSessionRunner.svelte`, `GymExecutionBand.svelte`, `RestTimer.svelte`, `GymWorkoutReview.svelte`, routes `/gym/routines/[id]`, `/gym/routines/new`, `/gym/session/[routineId]`, `/gym/[id]` (+ panel), i18n in all six locales.

**Mobile (`mobile_android` → byte-identical `mobile_ios`):** `lib/gym_routine.dart`, `lib/gym_adherence.dart`, `lib/gym_progression.dart`, `lib/local_routine_store.dart` (stores live flat in `lib/`, e.g. `local_gym_store.dart` — there is no `lib/stores/`), `screens/routine_library_screen.dart`, `screens/routine_detail_screen.dart`, `screens/routine_execute_screen.dart`, `widgets/routine_builder_sheet.dart`, `widgets/gym_execution_band.dart`, extend `gym_screen.dart` / `gym_detail_screen.dart` / `gym_summary_card.dart`, ARBs.

**Shared:** `packages/run_recorder/lib/src/gym_workout_runner.dart` (+ re-export). The mobile `exercise_history.dart` mirror is already landed (a tracked parity pair), so no new mirror work is needed there.

**Edge Function:** extend `export-data` + its completeness pgtap.

## Phasing & rollout

Four web-first, independently-shippable slices. Each ships value alone, mirrors to the twin only after web lands, and unlocks the next. Sizing is dev-days for one engineer including web + mobile twin + tests + docs.

### P1 — Reusable routines + "repeat last" (the gate probe) — ~4–5 days

**Scope.** A routine = a saved ordered list of planned exercises with target sets/reps/load (or RPE) — **no** progression, supersets, or execution loop. Two entries: "Save as routine" from a `gym_workouts` row, and "Repeat last" (prefill-only instantiate of the most recent matching session into `GymEditor`). The logged workout is untethered from the routine after instantiation (no adherence yet). New `/gym/routines` list + `/gym/routines/[id]` detail, both self-hiding.

**Why first.** Smallest schema, highest leverage, and **this slice is the validation gate** — "repeat last" needs no new table (reuses `gym_exercise_set_history` + `previousExerciseSession`) and validates the core bet before P2–P4 are committed.

**Schema (`20270101_001`).** `gym_workouts.metadata` column (prerequisite); `gym_routines`; `gym_routine_exercises` (carrying the `target_reps_min/max` range, `exercise_key`, `position`); `gym_routine_sets`. Author-only RLS; `(routine_id, set_index)` index. No narrow-union CHECK pair is *exercised* by P1 UI, but the columns + CHECKs land now (the full schema ships in one migration).

**Parity / store / tests.** `gym_routine` pair (`routineFromWorkout`, `prefillFromRoutine`). `LocalRoutineStore`. Playwright save-as-routine + repeat-last + self-hide; pgtap RLS + cascade; **`export-data` extended + its pgtap** (DSAR completeness, day one).

**Unlocks P2:** explicit `position` + `exercise_key` + `superset_group` columns are the grouping primitive P2 builds on.

### P2 — Richer structure (supersets, set types, rest, time/distance) — ~4 days

**Scope.** Expressive depth in the *template* only (still no execution, no progression): supersets (round-robin groups via `superset_group` / `superset_order`), set types (`set_type`), per-set `rest_s`, and non-rep modalities (`modality` = `time` / `distance` for holds/carries). Richer authoring in `RoutineEditor` (group/ungroup, set-type chips, rest field).

**Parity / tests.** Extend `gym_routine`: `expandRoutineSteps` → grouped/round-robin flat list with `rest` injected as an explicit step kind (the gym divergence from run's linear expansion). Register the `modality` + `set_type` narrow-union ↔ CHECK pairs (TS union + `check_constraint_unions.mjs`). Playwright superset group/ungroup + set-type chips; parity unit tests for round-robin expansion.

**Unlocks P3:** `expandRoutineSteps` is the exact input the runner consumes.

### P3 — Execution + adherence (mirror the run engine) — ~5–6 days

**Scope.** The `GymWorkoutRunner` on top of the gym session, consuming the P2 expansion, driving the execution band, persisting the `gym_workouts.metadata` trio (`routine_id`, `gym_step_results`, `gym_adherence`). **No new columns** — the trio rides the `metadata` column added in P1. Adherence is the per-axis 80% cutoff (reps/load, not pace). Dual-save crash safety.

**Parity / tests.** `gym_adherence` pair (the cutoff reducer). Runner tests in `packages/run_recorder/test/gym_workout_runner_test.dart`. `/audit:metadata-keys` must pass for the new trio. Twin byte-identical; Playwright for the band.

**Unlocks P4:** persisted `gym_step_results` over time is the signal a progression scheme reads.

### P4 — Progression schemes (the engine) — ~5–6 days

**Scope.** Per-exercise schemes prescribing the next session's targets from logged history. Ship the highest-value first: **linear**, **double_progression**, **five_by_five**, **percent_cycle**, **rpe_autoreg** (the `progression` column + `progression_params`). The `periodisation` (routine-level) and the four narrow-union CHECK pairs are already in `20270101_001`; P4 wires the engine. Coach-authored progression (if built) is **validated/clamped by the same pure `prescribeNext` guardrails** before write — the engine is authoritative, the LLM advisory.

**Parity / tests.** `gym_progression` pair, deterministic, identical edge cases + test count; `shared-library-syncer` after edits. `/audit:schema-drift` (CHECK↔union) must pass. Playwright for scheme selection + next-target preview.

> **Gate:** proceed to P2 only if P1's repeat-rate clears the owner threshold. P3/P4 follow on sustained engagement. If the signal is weak, freeze at P1.

## Open questions

1. **Free-text exercise identity.** Binding relies on `normaliseExerciseName` (the only grouping primitive); typos/renames break it and corrupt progression input. *Do we need a per-user exercise catalog/identity before P4, or is normalisation enough?* (The one genuinely missing primitive.)
2. **Gate jumped/relocated (see [§ gate](#the-validation-gate-stated-honestly)).** If repeat-rate is weak, P2–P4 are sunk cost — mitigated by making P1 the probe.
3. **Twin + parity tax compounds.** Three parity pairs + the runner each need byte-identical Dart + matched test counts; the likeliest sizing miss.
4. **`set_type` at the DB.** It's a column here (queryable). Confirm no screen needs to *aggregate* by set type in a way the current shape can't serve.
5. **Coach-authored progression data flow.** The LLM reads logged sets (health-adjacent). Confirm it stays within the existing coach data-handling envelope; loop in CISO if it widens what leaves the system (SOC 2 / GovRAMP).
6. **Tier-2 "command" trust.** P4 prescribes — clamp rules + a "confirm next target" step are mandatory; auto-apply is never allowed.
7. **`activities` view interaction.** Executed sessions remain `gym_workouts` rows feeding the UNION lift branch — confirmed the view enumerates `(id, user_id, kind, started_at, summary, is_public)` (not `select *`) so the new `metadata` column does not leak into the lift branch. Re-verify if the view is ever rewritten.
8. **Paywall.** Recommend **fully free** (manual authoring/execution/progression) — consistent with the empty `PRO_ONLY_FEATURES` and "Pro buys behaviour, not access." The only marginal-cost surface is Coach *writing* a routine (an LLM call) → gate **that write** via the existing per-tier daily coach cap, not a screen gate. Do **not** add a `PRO_ONLY_FEATURES` key. Surface the tradeoff (the manual engine is free, so Pro's gym pull is "let Coach build it faster"); a screen gate is the available-but-costly conversion lever that would break the "free reaches every screen" trust property.

## Rough sizing

| Slice | Dev-days (1 eng, web→mobile serial) |
|---|---|
| P1 — routines + repeat-last + DSAR export + store + tests | ~4–5 |
| P2 — supersets / set-types / rest / modalities + expansion | ~4 |
| P3 — `GymWorkoutRunner` + band + adherence + metadata trio | ~5–6 |
| P4 — progression schemes + Coach validation hook | ~5–6 |

**Total ~18–21 dev-days** if all four ship, serial. Parallelising web/mobile breaks the twin invariant, so the numbers assume serial. Realistically only P1 ships first; P2–P4 are gated on the engagement signal.

---

## Appendix A — `decisions.md` § 140

> Append as the next section **by file position** — `## 139.` is already taken ("Routes is a run-modality surface; mobile nav is a Fitness hub"), so the gym ADR is `## 140.`. Note `decisions.md` also contains a **duplicate `## 137.`** (the round-by-distance Lambda and the env-file convention), so the file's heading sequence runs 135 · 136 · 137 · 137 · 138 · 139 — the next distinct number after the highest existing heading (§139) is **§140**. Do **not** silently renumber the existing duplicate or any later section (conventions forbid rewriting ADR history) — re-confirm the next free number at land time, since more ADRs may have landed.

> **§140 — The gym programming engine ships as a four-slice, web-first depth tier that relocates the "measure gym engagement first" gate into its cheapest slice rather than jumping it.** Instead of a separate measurement-only phase, we sequence the engine so P1 (reusable routines + "repeat last", near-zero new schema) *is* the validation gate: if repeat-rate clears an owner-set threshold (~20% of gym sessions over 4–6 weeks) we proceed to P2 (supersets / set-types / rest / time-distance structure), P3 (a `GymWorkoutRunner` mirroring `WorkoutRunner` — on-top-of-session state machine, prescribed-vs-actual `gym_step_results` + `gym_adherence` trail in a newly-added `gym_workouts.metadata` jsonb column, adherence on reps/load at the run engine's 80%-of-target cutoff applied **per axis**, not pace), and P4 (linear / double-progression / 5×5 / %-of-e1RM / RPE-autoreg progression schemes; Coach-authored progression validated and clamped by the same pure prescriber). The plan is **relational** (`gym_routines` → `gym_routine_exercises` → `gym_routine_sets`) — the deliberate divergence from `plan_workouts.structure jsonb`, justified by per-exercise querying and row-by-row progression — with one jsonb escape hatch (`progression_params`). The plan→session link lives in `gym_workouts.metadata.routine_id` (a string, **not** an FK), so deleting a routine leaves prior sessions intact (immutable history) and the step-result shape evolves without a migration. Each slice is independently shippable and ends the flat-`set_index` reconstruction heuristic by introducing explicit `position` + `exercise_key` + `superset_group`. The manual engine is **fully free** (consistent with the empty `PRO_ONLY_FEATURES` and "free reaches every screen"); only Coach-*authored* progression is metered, via the existing per-tier daily coach cap, never a screen gate. If repeat-rate is weak we freeze at P1 (still a durable win — it ships "repeat last" and ends the reconstruction heuristic) and leave P2–P4 specced-but-unbuilt; the explicit tradeoff is faster-to-signal at the cost of building the routine schema before the gate formally clears.

## Appendix B — `roadmap.md` Phase-4 checklist edits

Flip the "Not in scope" bullet (verified exact text: `- [ ] **Not in scope:** exercise database, workout templates, programmes, RPE-driven progression (all in the gym depth tier below).` — find it by this text, not a line number; the design diff must keep the checkbox) into a planned, gated sub-phase. The *measure gym engagement* gate sentence in the Phase-4 sequencing block and the "Gym — heavy (full programming)" depth-tier heading stay as-is.

```diff
- - [ ] **Not in scope:** exercise database, workout templates, programmes, RPE-driven progression (all in the gym depth tier below).
+ - **Gym programming engine (depth tier, gated on engagement — ADR §140).**
+   Web-first, four independently-shippable slices; P1 is the validation probe
+   (relocates the "measure gym engagement" validation gate into its cheapest
+   slice rather than running a separate measurement phase). The lightweight
+   free-form log is unchanged.
+   - [ ] P1 — Reusable routines + "repeat last" (gym_routines /
+         gym_routine_exercises / gym_routine_sets; adds gym_workouts.metadata;
+         ends the flat set_index reconstruction heuristic). **Gate probe:
+         measure repeat-rate before P2.**
+   - [ ] P2 — Richer structure: supersets, set types, rest, time/distance
+         (superset_group + modality + set_type; the four narrow-union CHECK
+         pairs land here).
+   - [ ] P3 — Execution + adherence: GymWorkoutRunner mirroring WorkoutRunner;
+         routine_id / gym_step_results / gym_adherence in gym_workouts.metadata;
+         adherence on reps/load at the 80%-of-target cutoff, applied per axis.
+   - [ ] P4 — Progression schemes: linear / double / 5×5 / %-of-e1RM / RPE;
+         Coach-authored progression validated by the pure prescriber.
+         **Proceed only if P1 clears the engagement gate.**
+   - Paywall: manual engine fully free; only Coach-authored progression
+     metered via the existing per-tier daily coach cap (no screen gate).
```

## Appendix C — docs to update when each slice lands

| Doc | P1 | P2 | P3 | P4 |
|---|---|---|---|---|
| `roadmap.md` (tick the sub-phase checkbox) | ✓ | ✓ | ✓ | ✓ |
| `parity.md` (flip the cell per platform, web→mobile) | ✓ | ✓ | ✓ | ✓ |
| `api_database.md` (tables, RLS, on-delete, "routines don't feed `activities`") | ✓ (3 tables + `gym_workouts.metadata`) | ✓ (columns) | — (no new columns) | — |
| `metadata.md` (register keys) | — | — | ✓ (`routine_id`, `gym_step_results`, `gym_adherence`) | — |
| `derived_state.md` (`exercise_count` client-stamped note; `exercise_key` freeze invariant) | ✓ | — | — | — |
| `schema_codegen.md` (regen note; both generators run) | ✓ | ✓ | — | ✓ (CHECK-union pairs) |
| root `CLAUDE.md` parity-pair list | ✓ (`gym_routine`) | ✓ (expansion in `gym_routine`) | ✓ (`gym_adherence`) | ✓ (`gym_progression`) + the four CHECK-union pairs |
| `multi_modal.md` (routines IA; Tier-2 command surface + `source` tag; self-hide) | ✓ | ✓ (superset authoring) | ✓ | ✓ |
| `workout_execution.md` (add the gym runner alongside the run runner, divergences called out) | — | — | ✓ | — |
| `paywall.md` (only if Coach-authored progression is metered) | — | — | — | ✓ |
| `apps/web/.../local_testing.md` + `manual_testing.md` (gym section) | ✓ | ✓ | ✓ | ✓ |
| `apps/watch_wear/CLAUDE.md` + `apps/watch_ios/CLAUDE.md` (deferral note) | ✓ (one line, both) | — | — | — |
| `decisions.md` (§140) | ✓ (lands with P1) | — | — | — |
