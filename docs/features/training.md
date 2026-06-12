# Training plans

Runna / Garmin-Coach parity. Web-first in v1. The data model is shared so the Android app and the structured-workout execution loop can land without a schema change.

## Plan editor (web)

The plan detail page now supports inline workout edits. Hovering a day-tile reveals an edit button (`apps/web/src/lib/components/WorkoutEditor.svelte`) that opens a side-drawer: kind, distance, target pace (single value or a start → end progression for phase-based pace bumps), tolerance, zone label, and notes. Backed by `updatePlanWorkout` in `data.ts`.

For structured kinds (`tempo`, `interval`, `marathon_pace`, `race`) the editor also exposes a Structure block: warmup distance, a Repeats / Steady mode toggle, and cooldown distance. Repeats mode edits the count + per-rep distance + per-rep pace + recovery distance + recovery pace (`easy` / `jog`); Steady mode edits distance + pace. The block writes the `plan_workouts.structure` jsonb in the canonical `WorkoutStructure` shape from `training.ts` so the read-side on `/plans/[id]/workouts/[wid]` renders the new values without translation. Flipping kind to an unstructured kind (easy / long / recovery / rest) clears `structure` to `null`.

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
- Context = user profile + active (or specified) plan + `plan_weeks` + `plan_workouts` + last 20 runs, serialised as JSON. Phase 4 adds the Tier-1 cross-modality slice: a bounded `recent_lifts` array (capped per-session gym summaries) + a `nutrition_7d` daily-average rollup (gated on the Art 9 health-consent, like DOB/HR). Both self-hide when nothing is logged — see [multi_modal.md § Cross-modality](multi_modal.md#cross-modality-touches-tier-1--ship-with-phase-4-this-is-the-headline).
- **Prompt caching at two breakpoints**: (1) coach system prompt, (2) first user message carrying the context dump. Subsequent chat turns hit the cache for ~95% of input tokens. `cache_control: { type: 'ephemeral' }` on both blocks. The UI surfaces `cache_read` / `cache_creation` / `input` / `output` token counts below the composer for verification.
- Model: `claude-sonnet-4-5`. Output tokens: 768 (free tier) / 2048 (Pro tier). Context window: 30 runs (free) / 200 runs (Pro).

**Deploy requirement**: the endpoint runs as a Node 24 Lambda Function URL behind the prod CloudFront distribution (see [`apps/web/deployment.md`](../../apps/web/deployment.md) and [decisions.md § 53](../architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages)). The static SvelteKit build (under `adapter-static`) does not serve `/api/coach`; CloudFront routes that path to the Lambda. `ANTHROPIC_API_KEY` is sops-encrypted under `infra/envs/<env>/secrets.enc.yaml` (env-specific AWS KMS key) and wired into the Lambda's env by Terraform; missing key returns 503.

## Surfaces (Android, v1)

| Screen | Purpose |
|---|---|
| `plans_screen.dart` | Reached from the Run tab idle state (`Training plans` button when no active plan, `<plan name>` chip when one is active). Lists all plans with status chips and per-card Abandon / Delete actions. |
| `plan_new_screen.dart` | Wizard mirror of the web `/plans/new` page: goal race, start date, days/week, optional goal time and recent 5K, week override. Live preview of paces + the first six weeks' outline updates as inputs change. Also hosts a **"Start from a club template" picker** at the top (fetches every adoptable template across the viewer's clubs → bottom-sheet picker → `clonePlanTemplate`), mirroring web's `/plans/new` template picker. |
| `plan_detail_screen.dart` | Plan home. Progress ring in the hero, today-card when applicable, week cards with per-workout rows. Current week gets a primary-colour border. **Owner-only surfaces (mirror web `/plans/[id]`):** an adherence banner (`plan_adherence.dart#weeklyDrift` >±20% over/under + `missedWorkoutAdvice` make-up/skip for a missed long run; actual mileage from a recent-runs fetch), a "Re-plan remaining weeks" flow (`plan_replan.dart#replanRemaining` → preview modal → apply via the per-workout update path), and a per-week Duplicate action (`TrainingService.duplicatePlanWeek` → `duplicate_plan_week` RPC). |
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

## Engine: `apps/web/src/lib/training/training.ts`

Pure TypeScript, no deps, 100% tested under `src/lib/training.test.ts` (20 tests, run with `npx tsx --test src/lib/training.test.ts`).

- **VDOT from race** — Daniels' published formula: `vo2 = -4.6 + 0.182258v + 0.000104v²`, `pct = 0.8 + 0.1894393·e^(-0.012778T) + 0.2989558·e^(-0.1932605T)`, `VDOT = vo2 / pct`.
- **Riegel equivalence** — `t2 = t1 × (d2/d1)^1.06` for projecting a recent 5K to the goal-race distance.
- **Recent-5K recency gate** — both wizards (`PlanEditor.svelte`, `plan_new_screen.dart`) only pass the entered 5K time into `generatePlan` once the runner ticks a "reflects my current fitness" confirmation. An entered-but-unconfirmed time is treated as absent so paces fall back to the conservative goal-based estimate — a returning runner typing an old PR otherwise gets paces that are too fast (comeback persona #24, fail-closed default).
- **Training paces** — 5 intensity zones (easy / marathon / tempo / interval / repetition) computed as multipliers of goal pace. See `pacesFromGoalPace` in the source.
- **Pace fallback disclosure** — when neither a recent 5K nor a goal time is given, `resolveTrainingPacesWithMeta` falls back to a conservative ~10:00/km goal pace **and** returns `isFallback: true`, surfaced on the plan as `pacesAreFallback`. Both wizards render "Estimated paces — add a recent run or a goal time for personalised targets." so the placeholder isn't presented as a real prescription (persona round-5 runner-comeback). The numbers stay usable — the plan generates either way.
- **Plan generator** — `generatePlan({ goalEvent, goalTimeSec?, recent5kSec?, startDate, daysPerWeek, weeks? })` → `{ weeks, paces, vdot, endDate, goalDistanceM, pacesAreFallback }`. Phase breakdown 30/40/20/10 base/build/peak/taper with the final week always 'race'. Step-back every 4th week (every 3rd for masters 50+ — see below). Long run grows with volume, capped at ~35% of the week. With **no fitness anchor** (no goal time, no recent 5k) the peak volume is scaled to 0.6× so a no-info plan doesn't open with a punishing week 1 (#23); `limitToDays` trims auto-generated filler days (easy **and** recovery) so the active-day count actually honours `daysPerWeek`.

## Pace derivation — why multipliers, not Daniels tables

Daniels' official training paces are derived from VDOT via the same implicit equation used for VDOT itself. There's no closed-form inverse; real implementations lookup the paces in a published table. For v1 we anchor training paces on goal pace directly (`easy = 1.22 × goal`, `tempo = 0.97 × goal`, etc.) — these multipliers land within ~5 s/km of the Daniels tables across the 3:00-5:00/km goal band, which is well inside the tolerance band a plan runner expects.

If pace accuracy is ever the user-visible complaint, swap `paceFor` for a Daniels-table lookup — the public surface of `training.ts` stays the same.

## Data model

Migration: `apps/backend/supabase/migrations/20260419_001_training_plans.sql`. Three tables:

- `training_plans` — one per user-plan; `vdot`, `goal_distance_m`, `goal_time_seconds`, `status`, `current_5k_seconds`. Partial unique index enforces **one active plan per user**; `createTrainingPlan` auto-completes the previous active plan on insert.
- `plan_weeks` — 8–16 rows per plan; `phase`, `target_volume_m`, `notes`, `week_index`.
- `plan_workouts` — ~4–6 rows per week; `kind`, target distance / duration / pace / tolerance, free-form `structure jsonb` for intervals. Completion is encoded by **two** fields: `completed_run_id` (set by the auto-matcher when a tracked run lands) and `manually_completed` (boolean, set by the calendar editor's "Mark as done" when the user ran without recording). Read sites should treat the workout as done if either is truthy — the shared helper is `isWorkoutCompleted(wo)` in `apps/web/src/lib/training/training.ts`.

### `plan_workouts.structure` shape

```ts
{
  warmup?:   { distance_m?: number; duration_s?: number; pace: 'easy' };
  repeats?:  {
    count: number;
    distance_m?: number;          // distance- OR time-based (one of these)
    duration_s?: number;
    pace_sec_per_km: number;
    recovery_distance_m?: number;
    recovery_duration_s?: number;
    recovery_pace: 'easy' | 'jog' | 'walk';
  };
  steady?:   { distance_m?: number; duration_s?: number; pace_sec_per_km: number };
  cooldown?: { distance_m?: number; duration_s?: number; pace: 'easy' };
}
```

Kept as `jsonb` because the execution loop (Phase 2 — mobile-primary) will grow the schema (lap markers, HR targets, rep numbering cues) and a migration per revision is overkill for a v1 shape that's still settling. Each step is **distance- or time-based**: `distance_m` wins when both are present, else `duration_s` is used (the runner's `expandWorkoutSteps` already reads either). `recovery_pace: 'walk'` marks a walk break.

### Walk-run (beginner / C25K) — persona #22, decisions §91

`generatePlan({ beginnerWalkRun: true })` produces a 9-week C25K-style plan: the goal stays a 5k, but every session is a `walk_run` workout of **timed** run/walk intervals (warmup walk → `count ×` (run `duration_s` / walk `recovery_duration_s`) → cooldown walk), graduating to a single continuous ~25-minute run in the final week. The progression table is `WALK_RUN_PROGRESSION` (mirrored in `training.ts` and `training.dart` — keep in lockstep). The wizard exposes it as a "New to running? Use a walk-run plan" toggle on web (`PlanEditor`) and mobile (`plan_new_screen`). On web, enabling the toggle also switches the goal to 5K when it was set to a longer distance (the default is a half) — a brand-new runner is not training for a half (persona round-5 runner-new); it's a one-shot on enable, so the runner can still re-pick 10K and a deliberate 5K choice is never clobbered. Beginners train 3 days/week (the toggle caps run days at 3). `walk_run` workouts carry an estimated `target_distance_m` so the auto-match-from-run path still links them; the live recorder announces "Run"/"Walk" on interval transitions (see workout_execution.md).

The beginner plan's week count comes from `walkRunDefaultWeeks()` (= the progression length, 9), not `defaultPlanWeeks('distance_5k')` (= 8) — `PlanEditor`/`plan_new_screen` size `weeks` from it when the toggle is on. The generator also floors `totalWeeks` at the progression length so an explicit shorter `weeks` can never truncate the final graduation week (persona round-5 runner-new — the old web path forced 8 and silently dropped graduation).

### Masters recovery calibration (50+) — persona #30, decisions §93

`generatePlan({ age })` applies a masters recovery calibration when `age >= 50` (`isMastersAge`, mirrored in both twins). It does **not** touch pace — only recovery density: the first quality session moves from Tuesday (48h after the Sunday long run) to **Wednesday** (72h), the second from Thursday to **Friday**, and volume steps back every **3rd** week instead of every 4th (`isStepBackWeek(i, masters)`; week 0 is never a step-back). Age is read from `user_profiles.date_of_birth` on mount by both wizards (`PlanEditor` on web, `TrainingService.fetchViewerAge` → `plan_new_screen` on mobile) — no new wizard field. Null/unset age → the standard schedule. Why spacing and not slower paces: no validated age × VDOT pace table exists, and the gap masters athletes actually hit is hard-day frequency, not intensity — see decisions §93.

## Marking a workout as done

Two paths land in the same UI state (the green check on the calendar, the progress-ring counter ticking up):

1. **Auto-match from a tracked run.** `autoMatchRunToPlanWorkout(runId, runIsoDate, runDistanceM)` links a run to the same-day plan workout whose target distance is within ±25% of the recorded distance. Wrong matches are manually clearable via the "Unlink" control on the workout-detail page. Called automatically on the web client after both `createManualRun` and `saveRun` (importer path) succeed; wrapped in its own try/catch so an auto-match failure cannot block the run insert (auxiliary effect per the layered-resilience contract).
2. **Manual mark from the calendar editor.** The "Mark as done" button in `WorkoutEditor.svelte` calls `markWorkoutCompleted(id, null, { manual: true })`, which sets `manually_completed = true` and stamps `completed_at`. The same button toggles back to "Mark not done" — clearing both flags — when the workout is already completed via the manual path. If a workout already has a linked run, the button is disabled with a tooltip pointing the user at the workout-detail page's Unlink flow so the run/workout link is severed deliberately.

## Coach-athlete roster (human coaches)

Distinct from the AI Coach chat above: a human coach links to an athlete via a shareable invite token and sees them on a roster. `coach_athletes` (migration `20261102_001`) is one row per link — `coach_id`, nullable `athlete_id`, `status` (`pending` | `active` | `ended`), `invite_token`. The coach mints a pending invite on `/coaching` and shares `/coaching/accept/<token>`; the athlete redeems via the `redeem_coach_invite` SECURITY DEFINER RPC (sets `athlete_id`, flips to `active`). RLS scopes every read/write to the two parties; either may end a link, and a coach may revoke an unredeemed invite. Web-only MVP (`/coaching` hub + accept landing); the data layer lives in `data.ts` (`createCoachInvite`, `fetchMyAthletes`, `fetchPendingCoachInvites`, `fetchMyCoaches`, `redeemCoachInvite`, `endCoachLink`, `revokeCoachInvite`). Persona #46; rationale in [decisions.md § 97](../architecture/decisions.md#97-coach-athlete-roster-is-a-web-first-inviteaccept-link-model-persona-hunt-coach-46). **Shipped since:** consent-gated coach run + plan-read visibility (migrations `20261103_001` / `20261116_001`, #47) — a coach reviews a linked athlete's runs + active-plan compliance on `/coaching/athletes/[id]` (decisions § 98) — and **plan assignment** (migration `20270106_001`, decisions § 143): a coach deep-clones one of their own plans into an athlete-**owned** active plan via `assign_plan_to_athlete` / `assignPlanToAthlete`, surfaced on that same review page (clone-not-subscribe; provenance in `training_plans.assigned_by_coach_id`; raises if the athlete already has an active plan). The athlete is notified on assign via a `plan_assigned` notification (migration `20270107_001`, in-app/bell only). Deferred: a coach authoring plans directly in the athlete's account (vs. clone-from-own), an accept/decline notification round-trip, email/push for the assign notification, and any mobile/watch coaching surface.

## Deferred

- **Live execution loop** in the run screen (interval state machine, live rep count, cooldown-on-completion) — Phase 2 of this feature. **Specced in [workout_execution.md](workout_execution.md)**, not yet built. `plan_workouts.structure` already stores everything the runner needs; the remaining work is the `WorkoutRunner` state machine (in `packages/run_recorder`), the execution-band widget, and run-screen wiring. Rough sizing ~4 dev-days. Read the spec before picking this up.
- **Plan generator v2** — adaptive weekly rescheduling driven by adherence. **P1 shipped (2026-06-12, decisions §144):** `adaptiveReplanRemaining` (web `training/plan_adaptive_replan.ts` ↔ mobile `plan_adaptive_replan.dart` parity pair) gates a re-plan on a sustained multi-week adherence trend (2-of-3 trailing completed weeks flagged under/over) and delegates the future-only deltas to `replanRemaining`, surfaced as an "Adaptive re-plan" button + trend/confidence badge on web `/plans/[id]` + mobile `plan_detail_screen` (reuses the existing preview-and-apply). Pure, suggestion-only, no schema. **P2 (fitness-gated direction via TSB/ATL/CTL) is the first phase reading health-derived load into a prescription → gated on CISO / Security-Analyst sign-off before it ships;** P3 (atomic multi-week RPC) + P4 (date-shifts/deload) deferred. Full design in `reviews/plan-generator-v2.md`.
- ~~**Plan library / sharing** — publish a plan, clone into your own account. Deferred until the clubs/social layer is the natural home for it.~~ **Shipped** as **club-owned plan templates** (decisions §35) in `20260524_001_plan_templates.sql`. `training_plans.is_template + parent_template_id + club_id`; `clone_plan_template(template_id, start_date)` RPC. UI on `/clubs/[slug]` Templates tab, `/plans/new` template picker, `/plans/[id]` Publish-as-template flow. Clone-not-subscribe — template edits don't propagate to existing instances.
- **Structured-interval execution on the Android run screen** — specced in [workout_execution.md](workout_execution.md), no code yet; `plan_workouts.structure` is the handoff.
- **Owner bulk edits on `/plans/[id]`** — shift the whole plan ±N days and mark a week as recovery (`plan_bulk_ops.ts`, client-orchestrated per-row updates), plus **duplicate a week** (repeat a block / add a down week) via the atomic `duplicate_plan_week` RPC (migration `20261205_001`) — the re-index of `plan_weeks.week_index` can't be done safely with per-row updates because of the `(plan_id, week_index)` unique constraint. **Mobile parity (2026-06-12):** the duplicate-week action shipped on `plan_detail_screen.dart` (`TrainingService.duplicatePlanWeek`); shift-plan / mark-recovery stay web-only.
- **Plan-adherence + re-plan engines** — `plan_adherence.ts` ↔ `plan_adherence.dart` (`weeklyDrift`, `missedWorkoutAdvice`) and `plan_replan.ts` ↔ `plan_replan.dart` (`replanRemaining`) are TS↔Dart parity pairs. Shipped on web `/plans/[id]` + Android `plan_detail_screen.dart` (2026-06-12): the over/under-running adherence banner, the missed-long-run make-up/skip callout, and the owner-only Re-plan preview-and-apply flow.
- **Paste-a-template import** — markdown table → weeks/workouts.
- **Export as markdown / JSON** — round-trips through the paste path above.
- **Dart port of the engine** — *Shipped in Phase 3 Android port* via `apps/mobile_android/lib/training.dart` with 17 mirror tests in `test/training_test.dart`. Must stay in sync with `apps/web/src/lib/training/training.ts`; any change to pace multipliers, phase breakdown, or mileage fractions requires updating both files and re-running both test suites.
- **Premium gating** — the plans surface is free in v1. A later Stripe migration gates whichever features turn out to need it.
