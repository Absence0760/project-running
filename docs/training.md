# Training plans

Runna / Garmin-Coach parity. Web-first in v1. The data model is shared so the Android app and the structured-workout execution loop can land without a schema change.

## Plan editor (web)

The plan detail page now supports inline workout edits. Hovering a day-tile reveals an edit button (`apps/web/src/lib/components/WorkoutEditor.svelte`) that opens a side-drawer: kind, distance, target pace (single value or a start → end progression for phase-based pace bumps), tolerance, zone label, and notes. Backed by `updatePlanWorkout` in `data.ts`.

Migration `20260420_001_plan_editor.sql` adds:
- `plan_workouts.pace_zone` — free-text label (E, T, I, MP, etc.) for UI colouring
- `plan_workouts.target_pace_end_sec_per_km` — for pace progressions (null = flat pace)
- `training_plans.source` — `'generated' | 'imported' | 'manual'`
- `training_plans.rules` — jsonb array of plan-wide guidance strings rendered in the hero

Week-level and plan-level editing (`updatePlanWeek`, `updatePlanMeta`) are exposed in `data.ts` but aren't wired to the UI yet — a plan-meta drawer is the natural follow-up.

## Coach chat (web)

A Claude-powered second-opinion chat embedded below the week grid on the plan detail page (`apps/web/src/lib/components/CoachChat.svelte` + `src/routes/api/coach/+server.ts`).

**What it does**: critiques adherence, answers "should I run tomorrow?", explains what a workout is designed for, flags red-flag patterns in recent runs.

**What it explicitly doesn't do** — captured in the system prompt and `decisions.md #12`: generate new plans, prescribe medical or nutrition changes, invent stats it doesn't have in context.

**Architecture**:
- Server endpoint `POST /api/coach` — runs per-request (`prerender = false`), reads the caller's Supabase JWT to scope context pulls via RLS.
- Context = user profile + active (or specified) plan + `plan_weeks` + `plan_workouts` + last 20 runs, serialised as JSON.
- **Prompt caching at two breakpoints**: (1) coach system prompt, (2) first user message carrying the context dump. Subsequent chat turns hit the cache for ~95% of input tokens. `cache_control: { type: 'ephemeral' }` on both blocks. The UI surfaces `cache_read` / `cache_creation` / `input` / `output` token counts below the composer for verification.
- Model: `claude-sonnet-4-5`. Output tokens: 768 (free tier) / 2048 (Pro tier). Context window: 30 runs (free) / 200 runs (Pro).

**Deploy requirement**: the endpoint needs a server adapter. Under the default `adapter-static` the route returns 404 and the UI shows a helpful message pointing at `adapter-vercel` (already a dep). Set `ANTHROPIC_API_KEY` in the server env — missing key returns 503.

## Surfaces (Android, v1)

| Screen | Purpose |
|---|---|
| `plans_screen.dart` | Reached from the Run tab idle state (`Training plans` button when no active plan, `<plan name>` chip when one is active). Lists all plans with status chips and per-card Abandon / Delete actions. |
| `plan_new_screen.dart` | Wizard mirror of the web `/plans/new` page: goal race, start date, days/week, optional goal time and recent 5K, week override. Live preview of paces + the first six weeks' outline updates as inputs change. |
| `plan_detail_screen.dart` | Plan home. Progress ring in the hero, today-card when applicable, week cards with per-workout rows. Current week gets a primary-colour border. |
| `workout_detail_screen.dart` | Structured-interval breakdown (warmup / repeats / steady / cooldown), target metrics, per-kind "how to run it" advice, unlink control when the workout is matched to a completed run. |
| `widgets/todays_workout_card.dart` | Priority card on the Run tab idle state — sits above `UpcomingEventCard`. Tapping opens the workout detail. |

Plan + event creation flows intentionally stay on mobile (unlike clubs, where web is the admin surface) because plans are personal: the user in front of the phone is the one who cares about start date + fitness inputs.

## Surfaces (web, v1)

| Route | Purpose |
|---|---|
| `/plans` | Lists the user's plans, highlights the active one, supports abandon/delete. |
| `/plans/new` | Wizard: goal race + goal time + recent 5K + days/week. Live pace + week-outline preview before save. |
| `/plans/[id]` | Plan detail. Progress ring, today's workout card, month-by-month calendar (`PlanCalendar.svelte`) projecting workouts onto real dates with completion shading, plus the full week grid below for sequential reading. |
| `/plans/[id]/workouts/[wid]` | Workout detail: target distance / pace / tolerance, structured intervals laid out step-by-step, tailored "how to run it" advice per kind. |
| `/dashboard` | Hosts the "Today's workout" card (or a promo card if no active plan). |

## Engine: `apps/web/src/lib/training.ts`

Pure TypeScript, no deps, 100% tested under `src/lib/training.test.ts` (20 tests, run with `npx tsx --test src/lib/training.test.ts`).

- **VDOT from race** — Daniels' published formula: `vo2 = -4.6 + 0.182258v + 0.000104v²`, `pct = 0.8 + 0.1894393·e^(-0.012778T) + 0.2989558·e^(-0.1932605T)`, `VDOT = vo2 / pct`.
- **Riegel equivalence** — `t2 = t1 × (d2/d1)^1.06` for projecting a recent 5K to the goal-race distance.
- **Training paces** — 5 intensity zones (easy / marathon / tempo / interval / repetition) computed as multipliers of goal pace. See `pacesFromGoalPace` in the source.
- **Plan generator** — `generatePlan({ goalEvent, goalTimeSec?, recent5kSec?, startDate, daysPerWeek, weeks? })` → `{ weeks, paces, vdot, endDate, goalDistanceM }`. Phase breakdown 30/40/20/10 base/build/peak/taper with the final week always 'race'. Step-back every 4th week. Long run grows with volume, capped at ~35% of the week.

## Pace derivation — why multipliers, not Daniels tables

Daniels' official training paces are derived from VDOT via the same implicit equation used for VDOT itself. There's no closed-form inverse; real implementations lookup the paces in a published table. For v1 we anchor training paces on goal pace directly (`easy = 1.22 × goal`, `tempo = 0.97 × goal`, etc.) — these multipliers land within ~5 s/km of the Daniels tables across the 3:00-5:00/km goal band, which is well inside the tolerance band a plan runner expects.

If pace accuracy is ever the user-visible complaint, swap `paceFor` for a Daniels-table lookup — the public surface of `training.ts` stays the same.

## Data model

Migration: `apps/backend/supabase/migrations/20260419_001_training_plans.sql`. Three tables:

- `training_plans` — one per user-plan; `vdot`, `goal_distance_m`, `goal_time_seconds`, `status`, `current_5k_seconds`. Partial unique index enforces **one active plan per user**; `createTrainingPlan` auto-completes the previous active plan on insert.
- `plan_weeks` — 8–16 rows per plan; `phase`, `target_volume_m`, `notes`, `week_index`.
- `plan_workouts` — ~4–6 rows per week; `kind`, target distance / duration / pace / tolerance, free-form `structure jsonb` for intervals, `completed_run_id` set by the auto-matcher.

### `plan_workouts.structure` shape

```ts
{
  warmup?:   { distance_m: number; pace: 'easy' };
  repeats?:  {
    count: number;
    distance_m: number;
    pace_sec_per_km: number;
    recovery_distance_m: number;
    recovery_pace: 'easy' | 'jog';
  };
  steady?:   { distance_m: number; pace_sec_per_km: number };
  cooldown?: { distance_m: number; pace: 'easy' };
}
```

Kept as `jsonb` because the execution loop (Phase 2 — mobile-primary) will grow the schema (lap markers, HR targets, rep numbering cues) and a migration per revision is overkill for a v1 shape that's still settling.

## Auto-match on run save

`autoMatchRunToPlanWorkout(runId, runIsoDate, runDistanceM)` links a run to the same-day plan workout whose target distance is within ±25% of the recorded distance. Wrong matches are manually clearable via the "Unlink" control on the workout-detail page. Not called automatically by `ApiClient.saveRun` yet — the wiring is on the roadmap once we've validated the matching logic in the wild.

## Deferred

- **Live execution loop** in the run screen (interval state machine, live rep count, cooldown-on-completion) — Phase 2 of this feature. **Specced in [workout_execution.md](workout_execution.md)**, not yet built. `plan_workouts.structure` already stores everything the runner needs; the remaining work is the `WorkoutRunner` state machine (in `packages/run_recorder`), the execution-band widget, and run-screen wiring. Rough sizing ~4 dev-days. Read the spec before picking this up.
- **Plan generator v2** with adaptive weekly rescheduling driven by adherence.
- **Plan library / sharing** — publish a plan, clone into your own account. Deferred until the clubs/social layer is the natural home for it.
- **Structured-interval execution on the Android run screen** — specced in [workout_execution.md](workout_execution.md), no code yet; `plan_workouts.structure` is the handoff.
- **Paste-a-template import** — markdown table → weeks/workouts.
- **Export as markdown / JSON** — round-trips through the paste path above.
- **Dart port of the engine** — *Shipped in Phase 3 Android port* via `apps/mobile_android/lib/training.dart` with 17 mirror tests in `test/training_test.dart`. Must stay in sync with `apps/web/src/lib/training.ts`; any change to pace multipliers, phase breakdown, or mileage fractions requires updating both files and re-running both test suites.
- **Premium gating** — the plans surface is free in v1. A later Stripe migration gates whichever features turn out to need it.
