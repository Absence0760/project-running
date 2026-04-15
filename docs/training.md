# Training plans

Runna / Garmin-Coach parity. Web-first in v1. The data model is shared so the Android app and the structured-workout execution loop can land without a schema change.

## Surfaces (web, v1)

| Route | Purpose |
|---|---|
| `/plans` | Lists the user's plans, highlights the active one, supports abandon/delete. |
| `/plans/new` | Wizard: goal race + goal time + recent 5K + days/week. Live pace + week-outline preview before save. |
| `/plans/[id]` | Plan detail. Progress ring, today's workout card, full week grid with per-workout tiles. |
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

- **Live execution loop** in the run screen (interval state machine, live rep count, cooldown-on-completion) — Phase 2 of this feature. Needs mobile-app work to land end-to-end, even though `structure` is already stored in a ready-to-execute shape.
- **Plan generator v2** with adaptive weekly rescheduling driven by adherence.
- **Plan library / sharing** — publish a plan, clone into your own account. Deferred until the clubs/social layer is the natural home for it.
- **Structured-interval execution on the Android run screen** — no code yet; `plan_workouts.structure` is the handoff.
- **Paste-a-template import** — markdown table → weeks/workouts.
- **Export as markdown / JSON** — round-trips through the paste path above.
- **Dart port of the engine** — Android read-only for v1; when execution lands, the engine is ported the same way `recurrence.ts` → `recurrence.dart` was for clubs.
- **Premium gating** — the plans surface is free in v1. A later Stripe migration gates whichever features turn out to need it.
