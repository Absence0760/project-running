# Nutrition programming & the nutritionist console

A scoped **depth-tier nutrition-programming engine** — reusable meal plans with prescribed macro targets, prescribed-vs-actual day adherence, body-weight-trend progression — plus a **professional client console** that lets a credentialed nutritionist assign those plans to clients and review adherence. It is the nutrition analogue of two things already in the repo: the [gym-programming engine](gym_programming.md) (routines → prescribed targets → adherence → progression) and the shipped **running-coach** stack (`coach_athletes` roster → consent-gated cross-user read → client-detail review). The design reuses both rather than reinventing either.

> **Status:** specced, not built. This is the canonical design for the four-slice rollout. P1 (self-serve meal plans, the gate probe) is the only slice approved to start; P2–P4 — and especially the cross-user health-data read in P3 — are gated (see [Phasing](#phasing--rollout), [The validation gate](#the-validation-gate-stated-honestly), and [Compliance](#compliance--dsar-consent-soc-2--govramp)).

**Contents:** [Who this is for](#who-this-is-for) · [Product contract](#product-contract) · [The two halves](#the-two-halves-engine--console) · [The validation gate](#the-validation-gate-stated-honestly) · [Data flow](#data-flow) · [Data model](#data-model) · [Adherence](#adherence--the-single-definition-used-everywhere) · [Progression engine](#progression-engine) · [The professional console](#the-professional-console-reuse-the-coach-stack) · [Web UI](#web-ui) · [Mobile](#mobile--watch) · [Persistence](#persistence) · [Compliance](#compliance--dsar-consent-soc-2--govramp) · [Failure modes](#failure-modes) · [Testing](#testing) · [File list](#file-list) · [Phasing & rollout](#phasing--rollout) · [Open questions](#open-questions) · [Rough sizing](#rough-sizing)

## Who this is for

Two users, one engine:

- **The self-programmer** — a runner who already logs food (`food_log`, shipped) and wants a *prescribed* daily macro target tied to a goal phase (cut / maintain / build), not just the computed Mifflin-St Jeor number, plus a daily "did I hit it" verdict and a weekly nudge from their body-weight trend. This is **P1** and it is the validation gate.
- **The nutritionist** — a credentialed professional who manages 5–30 clients, authors meal plans once, assigns them to clients, and reviews each client's adherence + weight trend weekly. This is the **headline persona** the title asks for, but it ships *after* the self-serve engine that feeds it (P3), because the console is just a multi-client read over the same plans + the same pure adherence math.

The split matters: the engine is trustworthy single-user data; the console adds a **cross-user health-data read** (a nutritionist sees a client's food diary + body weight — GDPR Art 9 special category). We never ship the console before the engine is proven, and never ship the cross-user read without explicit scoped consent + CISO sign-off.

## Product contract

A user who logs meals can:

- **Save a meal plan** — a named plan with prescribed daily macro targets (kcal / protein / carbs / fat), a goal phase, an optional training-day override (higher carbs on workout days), and optional **prescribed meals** (a template breakfast the client one-tap logs).
- **Follow a plan** — once a plan is active for today, `/nutrition` seeds the day's rings with the **prescribed** targets (overriding the computed Mifflin-St Jeor target) and shows an adherence pill as the day fills in.
- **Review adherence** — per-day, direction-aware: each macro is *met* / *under* / *over* against its prescribed band, rolled up to an `on_target` / `off_target` / `partial` day verdict.
- **Get a weekly nudge** — the progression engine reads the logged body-weight series + adherence history and *suggests* next week's target adjustment (e.g. "weight flat over 10 days on a cut → drop 100 kcal"). It **only suggests** — never auto-mutates a target.

A nutritionist additionally can (P3):

- **Invite a client** and, on acceptance, **read that client's food log + body-weight trend + plan adherence** — scoped to the nutrition relationship, revocable, fully audited.
- **Assign a plan** to a client over a date range; the client is notified and can see who prescribed it.

Everything **self-hides** until a plan exists: a runner who never programs nutrition sees today's `/nutrition` unchanged. The engine **only suggests** — it never auto-mutates prescribed targets from logged data without a confirm step (the Tier-2 data-trust gate, [multi_modal.md § integration model](multi_modal.md#integration-model--inform-tier-1-vs-command-tier-2)).

Non-goals for v1: a public meal-plan marketplace, recipe/ingredient decomposition (a plan prescribes macros + optionally named foods, not gram-level recipes), barcode-driven prescribed meals, automatic meal-timing/circadian logic, and any wrist surface (nutrition has no watch story — see [Mobile](#mobile--watch)).

## The two halves (engine + console)

```
  HALF A — the engine (P1/P2, self-serve, single-user, trustworthy)
  ┌──────────────────────────────────────────────────────────────┐
  │ nutrition_plans  +  nutrition_plan_meals   (the prescription)  │
  │        │  prescribedTargetsForDate(plan, date, isTrainingDay)  │
  │        ▼                                                        │
  │ /nutrition day view seeded with prescribed targets             │
  │        │  food_log rows accumulate through the day (UNCHANGED)  │
  │        ▼                                                        │
  │ nutritionAdherence(prescribed, sumMacros(foodLog))  → verdict   │
  │        │  prescribeNextWeek(weightSeries, adherence)  (suggest) │
  │        ▼                                                        │
  │ next-week target suggestion (editable, never auto-applied)      │
  └──────────────────────────────────────────────────────────────┘
                              ▲   reads the SAME plans + SAME pure math
  HALF B — the console (P3, multi-client, cross-user, consent-gated)
  ┌──────────────────────────────────────────────────────────────┐
  │ coach_athletes (scoped 'nutrition')  +  nutrition_plan_assignments
  │        │  is_active_professional_of(prof, client, 'nutrition')  │
  │        ▼                                                        │
  │ nutritionist reads client food_log + body_metrics (RLS-gated)   │
  │        │  assignPlanToClient RPC → notification to client       │
  │        ▼                                                        │
  │ client-detail panel: 7-day adherence + weight trend + assign    │
  └──────────────────────────────────────────────────────────────┘
```

The console is deliberately *thin*: it is a roster + a cross-user read + an assignment RPC over the exact same `nutrition_plans` rows and the exact same pure `nutritionAdherence` / `prescribeNextWeek` helpers the self-programmer uses. There is no separate "nutritionist engine."

## The validation gate (stated honestly)

The roadmap lists nutrition's depth tier (programming, professional tools) as deferred behind the same engagement gate gym sits behind ([multi_modal.md § sequencing](multi_modal.md#sequencing-validation-gates--risk-controls)): *ship the lightweight tier, measure engagement, only then commit to depth.* Nutrition's lightweight tier (Open-Food-Facts search logging + dynamic-TDEE rings) is shipped.

**This design does not jump that gate — it relocates it, exactly as gym programming did.** P1 (self-serve meal plans + day adherence, near-zero cross-user surface) *is itself the gate probe*. If a meaningful share of food-logging users adopt a prescribed plan and the day-adherence surface gets repeat use over 4–6 weeks (owner-set threshold; suggest ≥15% of active food-loggers create a plan), the professional console (P3) is justified. If not, we freeze at P2 and leave the console specced-but-unbuilt.

- **The bet:** users already hand-tune the dynamic-TDEE target in Settings; a prescribed-plan + adherence verdict is the structured version of a behaviour they already exhibit.
- **The explicit tradeoff:** faster-to-signal, at the cost of building the plan schema before the gate formally clears. The durable alternative is "clear the gate first, build any schema second" — we are choosing against it to get a self-contained P1 win.
- **The owner must sign this off.** The P3 cross-user health-data read (a nutritionist reading a client's food diary) is a SOC 2 / GovRAMP-scoped change — loop in the CISO / Security Analyst **before P3 ships**, not after. P1/P2 touch only the caller's own data and do not need that review.

## Data flow

```
nutrition_plans  +  nutrition_plan_meals   (relational plan)
    │
    │  prescribedTargetsForDate(plan, date, isTrainingDay)   — pure
    ▼
PrescribedDay { calories, proteinG, carbsG, fatG, meals[] }   ← computed per date
    │
    │  /nutrition seeds the rings with these targets instead of computeNutritionTargets()
    ▼
food_log rows for that date  (UNCHANGED — the existing flat diary)
    │
    │  nutritionAdherence(prescribed, sumMacros(rows))   — pure, direction-aware
    ▼
DayAdherence { perMacro: {met|under|over}, verdict: on_target|off_target|partial }
    │
    │  prescribeNextWeek(weightSeries, adherenceHistory, config)   — pure, suggests
    ▼
Suggested next-week targets  (editable draft, never auto-applied)
```

The **plan** shape (`nutrition_plans`) and the **diary** shape (`food_log`, unchanged) bind by **date + assignment**, never by FK between a plan and a food row. A plan is reusable and is *not* a dated activity, so it does not feed the `activities` view (mirrors `gym_routines`).

> **The single biggest divergence from gym programming, stated up front:** gym stores a per-set planned-vs-actual trail in `gym_workouts.metadata` because a workout is a discrete, crash-prone execution session. **Nutrition stores no per-day adherence trail.** A nutrition "day" is not a stored entity — it is fully reconstructable from immutable `food_log` rows plus the prescribed targets from the active assignment. So adherence is **computed on read, never cached** (the `derived_state.md` "cache = authoritative query" philosophy, with the deliberate choice not to cache). We store only the *plan* and the *assignment*; everything else is a pure function. This means there is **no nutrition runner state machine** — the "execution surface" is the existing `/nutrition` day view, seeded with prescribed targets.

## Data model

Planned structure is **relational, not jsonb** — the same divergence-from-the-run-precedent gym made, for the same reason (queried per-field, bound by date, progressed week-by-week). Naming follows the gym precedent: `nutrition_plans` (plural snake_case), owner column **`author_id`** (authored content, convention F17), offline-first **`last_modified_at`** client-stamped newer-wins (no server `updated_at` trigger), CHECK idiom `length(...)` + the `X is null or length(X) <= N` form.

### `nutrition_plans` — a user-owned named meal plan

```sql
create table public.nutrition_plans (
  id                uuid primary key default gen_random_uuid(),
  author_id         uuid not null references auth.users (id) on delete cascade,
  title             text not null check (length(title) between 1 and 120),
  notes             text check (notes is null or length(notes) <= 1000),

  -- goal phase for the plan as a whole (narrow union ↔ CHECK pair)
  goal_phase        text not null default 'maintain'
                      check (goal_phase in ('cut','maintain','build','recomp')),

  -- prescribed REST-day daily targets (canonical). kcal is the spine; macros optional.
  target_calories   numeric(7,1) not null check (target_calories >= 1000 and target_calories <= 12000),
  target_protein_g  numeric(6,1) check (target_protein_g is null or target_protein_g >= 0),
  target_carbs_g    numeric(6,1) check (target_carbs_g  is null or target_carbs_g  >= 0),
  target_fat_g      numeric(6,1) check (target_fat_g    is null or target_fat_g    >= 0),

  -- optional TRAINING-day override (null ⇒ same as rest-day; the app knows workout days)
  training_calories numeric(7,1) check (training_calories is null
                       or (training_calories >= 1000 and training_calories <= 12000)),
  training_carbs_g  numeric(6,1) check (training_carbs_g is null or training_carbs_g >= 0),

  -- weekly progression scheme (narrow union ↔ CHECK pair)
  progression       text not null default 'none'
                      check (progression in ('none','weight_trend','linear_deficit','reverse_diet')),
  progression_params jsonb not null default '{}'::jsonb,   -- the ONE jsonb escape hatch

  meal_count        int not null default 0 check (meal_count >= 0),  -- denormalised, client-stamped
  external_id       text,
  last_modified_at  timestamptz not null default now(),     -- client-stamped, newer-wins; NO trigger
  created_at        timestamptz not null default now()
);

create unique index nutrition_plans_author_external_id_key
  on public.nutrition_plans (author_id, external_id) where external_id is not null;
create index nutrition_plans_author_modified_idx
  on public.nutrition_plans (author_id, last_modified_at desc);
```

- **`target_calories` is `not null`** — a plan without a calorie target is meaningless; macros are optional (a kcal-only plan is valid and common). This is the divergence from gym, where load could be absent (bodyweight); a meal plan always has a number. The `>= 1000` CHECK is a hard DB sanity floor *below* the app's soft floor (`MIN_CALORIE_TARGET = 1200` in `nutrition_targets.ts`); the engine clamps to 1200, the DB rejects only the absurd.
- **`goal_phase` vs the shipped `WeightGoal` vocabulary.** `nutrition_targets.ts` already has `GOAL_KCAL_DELTA: Record<WeightGoal, number>` keyed `'lose' | 'maintain' | 'gain'`. The plan's richer `goal_phase` (`cut | maintain | build | recomp`) must **map onto** that, not fork a parallel vocabulary: `cut→lose`, `build→gain`, `maintain`/`recomp→maintain`. The mapping lives in `meal_plan.ts` so `prescribeNextWeek` can reuse `GOAL_KCAL_DELTA` directly; pin it with a test so the two don't drift.
- **No `is_public` column in v1.** Same reasoning as `gym_routines`: shipping public-read RLS before a browse UI lets any authenticated user enumerate plans' `notes` + targets through REST (a `public-rows` leak). Author-only RLS now; `is_public` + its public-read branch land in the same migration that ships a marketplace, if ever.

### `nutrition_plan_meals` — optional prescribed meals within a plan

```sql
create table public.nutrition_plan_meals (
  id            uuid primary key default gen_random_uuid(),
  plan_id       uuid not null references public.nutrition_plans (id) on delete cascade,

  meal_slot     text not null check (meal_slot in ('breakfast','lunch','dinner','snack')),
  position      int not null check (position >= 0),

  item_name     text not null check (length(item_name) between 1 and 200),
  -- prescribed macros for this template meal (one-tap-logged into food_log)
  calories      numeric(7,1) check (calories is null or calories >= 0),
  protein_g     numeric(6,1) check (protein_g is null or protein_g >= 0),
  carbs_g       numeric(6,1) check (carbs_g   is null or carbs_g   >= 0),
  fat_g         numeric(6,1) check (fat_g     is null or fat_g     >= 0),
  off_code      text check (off_code is null or length(off_code) <= 64),  -- Open Food Facts barcode, if picked

  notes         text check (notes is null or length(notes) <= 500)
);

create index nutrition_plan_meals_plan_idx
  on public.nutrition_plan_meals (plan_id, meal_slot, position);
```

- **Prescribed meals are optional and additive.** A plan can be pure-macro (no meals) — that is the common case and the P1 default. Prescribed meals (P2) let the nutritionist pre-build "your breakfast" so the client logs it with one tap, writing a normal `food_log` row (`item_name` + the four macros copied, `meal_slot` set). The diary stays the single source of truth for *actuals*.
- **Column shape mirrors `food_log`** (`item_name`, `calories`, `protein_g`, `carbs_g`, `fat_g`, `meal_slot`) so one-tap-log is a direct copy, no transform. **`off_code` does NOT round-trip into `food_log`** — `food_log` has no barcode column (it stores name + macros only), so `off_code` lives on the prescribed meal purely so the *editor* can re-open the Open Food Facts entry; the logged diary row carries name + macros and nothing else. No `food_log` schema change is implied.

### `nutrition_plan_assignments` — who is on which plan, when

This is the table that has no gym analogue and is the heart of the console. It records that a plan is active for a user over a date range, and **who assigned it** (self or a nutritionist).

```sql
create table public.nutrition_plan_assignments (
  id            uuid primary key default gen_random_uuid(),
  plan_id       uuid not null references public.nutrition_plans (id) on delete cascade,
  client_id     uuid not null references auth.users (id) on delete cascade,  -- whose days this governs
  assigned_by   uuid references auth.users (id) on delete set null,          -- self OR a nutritionist; NULLABLE so on delete set null is legal and a deleted pro leaves history

  start_date    date not null,
  end_date      date,                                   -- null ⇒ open-ended (until superseded/ended)
  status        text not null default 'active'
                  check (status in ('active','ended')),

  last_modified_at timestamptz not null default now(),
  created_at    timestamptz not null default now(),

  constraint nutrition_plan_assignments_dates_chk
    check (end_date is null or end_date >= start_date)
);

create index nutrition_plan_assignments_client_idx
  on public.nutrition_plan_assignments (client_id, start_date desc);
create index nutrition_plan_assignments_plan_idx
  on public.nutrition_plan_assignments (plan_id);
-- at most one active assignment per client per day is a CLIENT-side invariant
-- (overlapping ranges resolve newest-start-wins in prescribedTargetsForDate);
-- not a DB exclusion constraint in v1 (btree_gist not assumed enabled).
```

- **`client_id` vs `author_id`.** A plan is *authored* by `nutrition_plans.author_id`; it is *assigned to* `nutrition_plan_assignments.client_id`. For the self-programmer these are the same user. For the nutritionist, `author_id` = the nutritionist, `client_id` = the client, `assigned_by` = the nutritionist. This separation is what lets one nutritionist-authored plan be assigned to many clients.
- **Overlap resolution is client-side** (newest `start_date` wins for a given day) rather than a DB exclusion constraint, to avoid assuming `btree_gist`. The "one active plan per day" rule is enforced in `prescribedTargetsForDate` and the assign UI, documented as a client-side invariant.

### Narrow-union ↔ CHECK pairs to register

Each needs a TS union in `apps/web/src/lib/types.ts` (via `Omit & {…}`), a CHECK in the migration, and a `PAIRS` entry in `apps/web/scripts/check_constraint_unions.mjs` (CI `parity-types` fails otherwise). Dart treats all as raw `String`.

| Column | Domain |
|---|---|
| `nutrition_plans.goal_phase` | `cut \| maintain \| build \| recomp` |
| `nutrition_plans.progression` | `none \| weight_trend \| linear_deficit \| reverse_diet` |
| `nutrition_plan_meals.meal_slot` | `breakfast \| lunch \| dinner \| snack` (matches `food_log.meal_slot`, minus null) |
| `nutrition_plan_assignments.status` | `active \| ended` |

The day verdict (`on_target \| off_target \| partial`) is a **computed value, not a column** — TS union + client validation, **no CHECK** (mirrors how `gym_adherence` / `workout_adherence` are handled — never stored, always recomputed).

### RLS

```sql
alter table public.nutrition_plans            enable row level security;
alter table public.nutrition_plan_meals       enable row level security;
alter table public.nutrition_plan_assignments enable row level security;
```

> **RLS-recursion gotcha — the load-bearing reason these gate through a helper, not an inline `EXISTS`.** A client may read a plan only because an assignment row links them to it, so the `nutrition_plans` read policy must consult `nutrition_plan_assignments`. Referencing one RLS-protected table from inside another's policy `USING` clause re-applies the *referenced* table's RLS inside the policy — the exact trap `private.is_active_coach_of` was created to avoid (its migration comment: the helper exists "so it doesn't lean on `coach_athletes` RLS from inside the runs policy"). So the client-read branch routes through a **`SECURITY DEFINER` helper**, never a bare subquery:
>
> ```sql
> create or replace function private.can_read_nutrition_plan(p_plan_id uuid, p_uid uuid)
> returns boolean language sql stable security definer set search_path = public as $$
>   select exists (select 1 from nutrition_plans p where p.id = p_plan_id and p.author_id = p_uid)
>       or exists (select 1 from nutrition_plan_assignments a
>                  where a.plan_id = p_plan_id and a.client_id = p_uid and a.status = 'active');
> $$;
> -- grant usage on schema private; revoke from public; grant execute to anon/authenticated/service_role
> -- (mirror 20261103_001's grant block exactly).
> ```

- **`nutrition_plans`** — author writes (`insert`/`update`/`delete` gated on `author_id = auth.uid()`); reads gated on `private.can_read_nutrition_plan(id, auth.uid())` (author **or** active client). The active-client branch is only load-bearing in P3 (in P1/P2 author = client); it ships with the helper from day one so the policy never changes. **No public branch** until a marketplace migration.
- **`nutrition_plan_meals`** — no own owner column; gate `select` on `private.can_read_nutrition_plan(plan_id, auth.uid())` (same helper, not a fresh inline `EXISTS`), and write-gate on the parent's author. Mirrors how `gym_sets` is "visible via parent," but through the definer helper to dodge the recursion.
- **`nutrition_plan_assignments`** — readable by **either party** (`client_id = auth.uid()` OR `assigned_by = auth.uid()`). **Self-assign (P1) is a direct INSERT policy** `with check (client_id = auth.uid() and assigned_by = auth.uid())`. **Cross-user assign (P3, nutritionist) goes through the `assign_nutrition_plan` `SECURITY DEFINER` RPC** — because that row has `client_id != auth.uid()`, which the self-assign policy forbids, so a nutritionist cannot forge an assignment to an unconsented client outside the scoped link. Ending is `update status='ended'` via the same authority check.

### On-delete behaviour

- `nutrition_plans.author_id → auth.users ON DELETE CASCADE` (account deletion erases authored plans — Art 17).
- `nutrition_plan_meals.plan_id → nutrition_plans ON DELETE CASCADE`; `nutrition_plan_assignments.plan_id → CASCADE`; `client_id → CASCADE`.
- `assigned_by → auth.users ON DELETE SET NULL` (a deleted nutritionist leaves the client's assignment intact but unattributed — history survives).
- **Deleting a plan does NOT touch `food_log`** — the link is date+assignment, not an FK to a food row, so a client's logged meals stay intact.

### Both codegen regenerations (mandatory)

1. **`npm run gen:types`** → regenerate `database.types.ts`; then add the four unions to `types.ts` and the four `PAIRS` to `check_constraint_unions.mjs`.
2. **`dart run scripts/gen_dart_models.dart`** → regenerate `db_rows.dart`. **Verify the generator emits a field for `progression_params jsonb not null default '{}'`** before committing (gym programming flagged this exact open question — `numeric(7,1)` is proven by `food_log`, jsonb on a new table is the unproven one). If it drops it, **grow the parser**, never hand-edit `db_rows.dart`. The generator ignores CHECK / index / RLS by design.

## Adherence — the single definition used everywhere

> One coherent rule across the day view, review panel, console, and progression input — **per-macro and direction-aware.** This is the deliberate divergence from gym's per-axis 80% reps/load cutoff: nutrition macros are not all "more is better." A macro is **met** when its logged daily total lands inside its prescribed band, where the band direction comes from the shipped `MACRO_IS_CEILING` map (`nutrition_budget.ts`):
>
> - **Ceiling macros** (`calories`, `fat`) — met when `actual <= target × 1.10` (10% over-tolerance; over the ceiling is the failure).
> - **Floor macros** (`protein`, `carbs`) — met when `actual >= target × 0.90` (reaching it is the win; under is the failure).

- **Day verdict** rolls the four macro results up:
  - `partial` when the day looks **under-logged** — total logged calories `< 0.50 ×` prescribed (a proxy for "didn't finish logging"; see the honest fragility in [Failure modes](#failure-modes)). A partial day is excluded from the progression denominator, exactly as gym excludes warmups.
  - `on_target` when all prescribed macros are met.
  - `off_target` otherwise, carrying the per-macro `under` / `over` breakdown so the UI can say *which* macro missed, not just "off."
- **Macros with no prescribed target are excluded** from the verdict (a kcal-only plan is judged on calories alone).
- **Computed locally, never stored, never a server call** — `nutrition_adherence.{ts,dart}` reduces `sumMacros(food_log rows)` (shipped helper) against the prescribed targets. The same function feeds the review pill, the console's 7-day rollup, and `prescribeNextWeek` — so the verdict a client sees, the verdict the nutritionist sees, and the input to next week's suggestion can never drift.

Direction-aware-per-macro (not a single calorie distance) is the chosen resolution because it matches how a nutritionist actually reads a day ("hit protein, blew past fat") and it reuses the shipped `MACRO_IS_CEILING` semantics rather than inventing a second model.

## Progression engine

The "intelligence" — **pure math over the body-weight series + adherence history + config, no side effects.** It does not read the DB, does not write a plan, does not auto-mutate a target. The (impure) instantiation layer calls it, gets a `PrescribedTargets`, and prefills an *editable* draft the user/nutritionist confirms. This keeps it a Tier-1 "inform" computation; writing the new target is a deliberate user-confirmed Tier-2 step.

### Module decomposition — three small parity pairs

Mirrors gym's three-pair factoring; each independently testable, each on the tracked-pair list in root `CLAUDE.md`, each checked by `shared-library-syncer`:

| Pair (web ↔ mobile) | Responsibility |
|---|---|
| `nutrition/meal_plan.ts` ↔ `nutrition/meal_plan.dart` | `prescribedTargetsForDate(plan, date, isTrainingDay)`, `activeAssignmentForDate(assignments, date)` (newest-start-wins), one-tap-log expansion of prescribed meals |
| `nutrition/nutrition_adherence.ts` ↔ `nutrition/nutrition_adherence.dart` | the direction-aware per-macro band reducer → `DayAdherence` (reuses `MACRO_IS_CEILING` from `nutrition_budget`) |
| `nutrition/nutrition_progression.ts` ↔ `nutrition/nutrition_progression.dart` | `prescribeNextWeek(weightSeries, adherenceHistory, config)` — the next-week target prescriber per scheme |

These reuse the shipped `nutrition_targets` (Mifflin-St Jeor base), `nutrition_budget` (`MACRO_IS_CEILING`, `macroBudget`), and the `body_metrics` weight series. `nutrition_budget`, `hydration`, and `nutrition_week` are web-only today — **their mobile mirrors must land as part of this work** if `prescribeNextWeek` / the day verdict reuse them, not be deferred again (the same "land the mirror now" obligation gym programming put on `exercise_history`).

### Schemes

| Scheme | Rule (one line) | Worked example |
|---|---|---|
| **weight_trend** | 7–10-day weight-trend slope vs goal: trend stalled (or wrong-direction) and adherence ≥ target → adjust calories by `stepKcal` in the goal direction; on-track → hold. | Cut, 2,000 kcal, 10-day weight flat, adherence 90% → suggest **1,900 kcal** (−100). |
| **linear_deficit** | Fixed weekly calorie step toward a floor, gated on adherence (no step if last week was `partial`/`off_target` — fix logging first). | 2,200 → 2,100 → 2,000 … floored at `MIN_CALORIE_TARGET` (1,200). |
| **reverse_diet** | Post-cut: small weekly calorie *increase* while weight holds, to restore maintenance without fat regain. | 1,600 → 1,700 → 1,800 while weight stable; stop the climb if weight rises >X. |
| **none** | No suggestion; the plan's targets are fixed. | — |

- **Adherence-gated by design:** every scheme refuses to step on a week the client did not actually hit / fully log. You never tighten a deficit off noisy data — that is the nutrition version of gym's "partial → hold," and it is the Tier-2 data-trust gate made concrete.
- **Suggest-only:** output is a `PrescribedTargets` + a one-line `rationale` chip (`{kind:'hold'}`, `{kind:'adjust', deltaKcal:-100, reason:'weight_stall'}`, `{kind:'blocked', reason:'low_adherence'}`). The instantiation layer prefills an editable draft; **auto-apply is never allowed** (a fat-finger 500 kg-equivalent — here a mis-logged 5,000-kcal day — must not silently move next week's target).

### Edge cases (identical both sides)

- **No body-weight data** (`body_metrics` empty): `weight_trend` / `reverse_diet` cannot compute a slope → `{kind:'blocked', reason:'no_weight_data'}`, never throw. `linear_deficit` still works (it is weight-blind by design).
- **Sparse logging:** weeks with `< N` logged days are excluded from the adherence denominator; if the whole window is sparse → `blocked`.
- **Non-finite / negative inputs:** `numericOrNull`-guarded (same shape as `nutrition_targets`); a null/NaN day is treated as unlogged, never propagated.
- **Determinism:** ordering follows the weight series oldest-first; no `Date.now()` inside the pure core (the "today" boundary is passed in, exactly as `summarizeNutrition(rows, now)` and `ageFromDob(dob, nowMs)` already do) — so TS and Dart produce byte-identical numbers, asserted by a shared fixture.

## The professional console (reuse the coach stack)

The nutritionist is the **nutrition-scoped twin of the shipped running coach.** The durable decision — and the one to get right — is **how the professional↔client relationship is modelled.**

### Recommendation: scope the existing `coach_athletes` link, don't fork a parallel table

The shipped `coach_athletes` table (migration `20261102_001`) already carries the entire invite → redeem → active/ended lifecycle, the `redeem_coach_invite` / `end_coach_link` RPCs, the `private.is_active_coach_of(coach, athlete)` RLS helper (`20261103_001`), and consent-as-acceptance audit (`accepted_at`). Spawning a parallel `nutritionist_clients` table would duplicate all of that — two invite flows, two consent stacks, two RLS helpers to keep in lockstep, and a user who is *both* a coach and a nutritionist gets two unrelated links to the same client.

**The long-term solution is to generalise the link with a scope, not to fork it:**

```sql
-- additive migration on the shipped table; existing rows backfill to {'coaching'}
alter table public.coach_athletes
  add column scopes text[] not null default array['coaching']::text[]
    check (scopes <@ array['coaching','nutrition']::text[] and array_length(scopes, 1) >= 1);
```

- One invite, one redemption, one `accepted_at` consent record — the client sees "Jane requested **nutrition** access" vs "**coaching** access" vs "**both**," and the granted scopes are the lawful-basis evidence for exactly which data the professional may read. The invite carries the requested scopes; the redeem RPC copies them onto the active row.
- A new helper `private.is_active_professional_of(prof, client, p_scope text)` checks `status='active' AND p_scope = any(scopes)`. The shipped `private.is_active_coach_of(p_coach_id, p_athlete_id)` is **rewritten as a thin wrapper** that calls it with `'coaching'` — **keeping its exact two-arg signature** so the shipped `runs` / `plan` policies that call it are untouched (per the bare-body-`create or replace` rule: re-emit its full body, don't drop the wrapper later).
- The nutritionist's cross-user reads gate on `private.is_active_professional_of(auth.uid(), client_id, 'nutrition')`.

**Generator + parity notes (verified against the repo, not assumed):**
- **`text[]` is fine for the Dart generator** — it already emits `List<String>` for `routes.tags` and `events.recurrence_byday`; the parser has explicit array handling (`_dartType` → `List<$scalar>`). No generator gotcha here. *(This corrects an earlier worry that arrays were unsupported.)*
- **The array-membership CHECK does NOT go in `check_constraint_unions.mjs`.** That guard only understands scalar `column in ('a','b')` ↔ a TS string union. `scopes` is an array with a `<@` containment check, not a scalar union, so it gets **client-side validation** (and a documented allowed-values list) instead of a `PAIRS` entry — registering it would break the guard's parser.

**The tradeoff, stated honestly:** this touches a shipped, RLS-protected, production table and its helper — a wider blast radius than a greenfield table. It needs an `/audit:rls` + `/audit:migration-locks` pass (the `add column … default array[...]::text[]` default is a constant expression, so metadata-only on PG11+ — no table rewrite). The cheaper-but-worse alternative is a standalone `nutritionist_clients` clone; it ships faster and isolates risk, at the cost of two permanent parallel consent stacks and the both-roles double-link problem. **Lead with the generalisation; fall back to the clone only if the owner judges the shipped-table blast radius unacceptable for this round.**

### Cross-user data access (consent-gated, mirrors coach run visibility)

Once a `'nutrition'`-scoped link is active, add RLS branches mirroring `20261103_001`'s coach-run-visibility pattern:

- **`food_log` SELECT** — a `'nutrition'`-active professional reads the client's food rows (column-narrowed: `started_at`, `item_name`, `meal_slot`, the four macros — **not** `is_public`, **not** `external_id`). This is the cross-user Art 9 read; it is the single most compliance-sensitive line in the whole design.
- **`body_metrics` SELECT** — same gate, reads `recorded_at`, `weight_kg` only.
- **`nutrition_plan_assignments`** — already readable by `assigned_by` (the nutritionist).
- Visibility **revokes immediately** when the link's `status != 'active'` or the `'nutrition'` scope is dropped — recomputed per query, no cached grant.

### Assignment + audit

- **`assign_nutrition_plan(p_plan_id, p_client_id, p_start date, p_end date)`** — `SECURITY DEFINER` RPC (mirrors `redeem_coach_invite`'s pattern): asserts the caller is a `'nutrition'`-active professional of `p_client_id` AND authors `p_plan_id`, ends any overlapping active assignment, inserts the new one, and enqueues a notification. The client cannot be assigned a plan by anyone outside an accepted scoped link. **Gotcha:** a definer RPC that writes `nutrition_plan_assignments` needs an explicit `grant insert, update on public.nutrition_plan_assignments to postgres` — new public tables are auto-granted only to anon/authenticated/service_role, so without it the definer body hits "permission denied" (the exact `grant … to postgres` line `coach_athletes` carries for `redeem_coach_invite`).
- **Notification kind** — add `'nutrition_plan_assigned'` to the **user-notifications** `kind` CHECK. The authoritative current value lives in `20261211_001_consolidate_kind_check_constraints.sql` (`kudos, comment, comment_reply, follow, event_rsvp, event_cancel, plan_update, message, …`) — **not** `20261218_001`, which is the unrelated *jobs-queue* kind. Re-emit the full consolidated list plus the new value (don't bare-body a partial). **The existing `notifications.plan_id` column FKs `training_plans(id)`, so it cannot hold a nutrition-plan id** — add a sibling nullable `nutrition_plan_id uuid references nutrition_plans(id) on delete cascade` (mirroring how `20261024_001` added `plan_id` for `'plan_update'`). The client gets "Jane assigned you the *Marathon Build* plan."
- **Audit:** the assignment row's `assigned_by` + `created_at` is the trail; ending stamps `status='ended'` + `last_modified_at`. No silent edits — a nutritionist changing a target authors a new plan version (immutable-history posture, same as run plans).

### "Coach" naming — three meanings, keep them distinct

The repo already overloads "Coach": (1) the **AI Coach** (Claude LLM, `/coach`, per-user, `coach_consent_at`), and (2) the **human running coach** (`coach_athletes`, `/coaching`). Adding a nutritionist makes (3). To avoid a triple-overload, frame the human side as **"professionals"** with **roles** (coach / nutritionist): one roster surface, scoped by what each link grants. Do **not** add a third top-level noun. The AI Coach is untouched and orthogonal.

## Web UI

SvelteKit, canonical surface. Everything **self-hides** until a plan exists.

### Self-serve engine (P1/P2) — inside `/nutrition`

- A **Plans** section on `/nutrition`, above the day view, that self-hides at zero plans (no empty "create your first" card — that violates self-hide). Entry to create appears via a `New plan` button once plans exist, and via a **`Save as plan`** affordance on the day view (promote today's hand-set targets into a plan) — the only create entry shown before any plan exists, the adoption wedge.
- **Day view seeding:** when an assignment is active for today, `/nutrition` rings use `prescribedTargetsForDate(...)` **instead of** `computeNutritionTargets(...)`, with a chip naming the plan ("Following *Marathon Build*"). A training-day override fires off the same workout-day signal the dynamic-TDEE breakdown already uses.
- **Adherence pill** on the day view + a per-macro met/under/over breakdown using **glyph + label, not colour alone** (`✓ protein 140/130g`, `△ fat 95/70g over`), reusing the ring components.
- **Routes:** extend `/nutrition/+page.svelte`; add `/nutrition/plans/[id]` (detail/preview) and `/nutrition/plans/new` (thin wrapper around the editor). New `MealPlanEditor.svelte` — target fields, goal phase, training-day override, optional prescribed-meal blocks (reuse the `FoodLogEditor` Open-Food-Facts search to fill a prescribed meal), progression-scheme selector. Components: `NutritionPlanLibrary.svelte`, `NutritionPlanCard.svelte`, `MealPlanEditor.svelte`, `NutritionAdherencePanel.svelte`.

### Professional console (P3) — extend `/coaching`

- The shipped `/coaching` hub gains a **role-scoped** view: a client row shows which scopes are active (coaching / nutrition / both). Invite flow gains a scope picker.
- `/coaching/clients/[id]` (the generalised athlete-detail route) gains a **Nutrition panel** when the link is `'nutrition'`-scoped: 7-day adherence rollup (the same `nutritionAdherence` math), the body-weight trend (`body_metrics`), the active assignment, and an **Assign plan** action (pick one of the nutritionist's authored plans + date range → `assign_nutrition_plan`). New client API in `core/data.ts`: `fetchClientFoodLog`, `fetchClientBodyMetrics`, `fetchClientNutritionAdherence`, `assignNutritionPlan`, `fetchMyClients` (scope-filtered).

### i18n (six locales)

Every new string in `en.ts` + `de/fr/es/ja/pt-BR` (`satisfies Messages` + `messages_parity.test.ts`) before the call site uses `m('key')`, mirrored to all mobile ARBs. Key groups: `nutrition.plan.*`, `nutrition.adherence.*`, `nutrition.progression.*`, `coaching.nutrition.*`. Macro values are pre-formatted and interpolated (`m('nutrition.adherence.macro', {label, actual, target})`), never string-concat.

## Mobile & watch

Flutter (byte-identical twin) mirrors the web surfaces, strictly **downstream of web** (don't start the Flutter mirror until the web screens + the three parity pairs are merged and tested). Purely additive, self-hiding.

| New / extended | Mirrors web | Notes |
|---|---|---|
| `screens/nutrition_screen.dart` (extend) | `/nutrition` | Add a Plans section that self-hides at zero plans; seed rings from prescribed targets when an assignment is active; show the adherence pill. |
| `screens/nutrition_plan_detail_screen.dart` (new) | `/nutrition/plans/[id]` | Prescribed targets + optional meals; primary **Follow** (self-assign); edit/duplicate/delete behind `ConfirmDialog`. |
| `widgets/meal_plan_editor_sheet.dart` (new) | `MealPlanEditor` | Reuse `nutrition_log_sheet.dart`'s Open-Food-Facts search for prescribed meals; target fields, goal phase, training override, progression selector. |
| `widgets/nutrition_adherence_panel.dart` (new) | `NutritionAdherencePanel` | Per-macro met/under/over + day verdict; self-hides when no plan active. |
| `stores/local_nutrition_plan_store.dart` (new) | — | Sibling of `LocalFoodStore` / `LocalGymStore`: one JSON file per plan under `<appDocs>/nutrition_plans/`, prescribed meals carried inline, `SyncEntry` (client UUID, `last_modified_at`, sync states, tombstones). Assignments stored inline on the plan or a small sibling list. |

- **The mobile day view is fully offline** — prescribed targets read from the local plan store, actuals from `LocalFoodStore`, adherence from the pure Dart pair. No server round-trip to follow a plan.
- **Mobile body-metrics + weight entry is shipped (G5)** — `prescribeNextWeek` reads that series, no new capture surface needed.
- **Professional console: web-only**, mirroring how the running-coach console deferred mobile. A nutritionist managing clients is at a desk; the mobile surface is the *client's* follow-a-plan view, which is in scope. Record this scope line so a future session doesn't build a mobile roster.
- **No watch surface.** Nutrition has no wrist story (you don't log a meal on a 1.4" screen). Defer indefinitely; record the one-liner in both watch CLAUDE.md scope sections like gym did.

## Persistence

| What | Where | Notes |
|---|---|---|
| Plans (prescription) | `nutrition_plans` + `nutrition_plan_meals` | relational; offline-mirrored in `LocalNutritionPlanStore` (inline meals) |
| Assignment (who/when) | `nutrition_plan_assignments` | the plan→client→date-range link; self or nutritionist |
| Day adherence | **computed, never stored** | pure function over `food_log` + prescribed targets — the deliberate divergence from gym's metadata trail |
| Logged meals (actual) | `food_log` | **unchanged** — the existing flat diary |
| `meal_count` | `nutrition_plans.meal_count` | client-stamped on save, NOT a trigger cache; documented in `derived_state.md` as non-authoritative |

No per-day/per-event growth → **no retention purge / pg_cron** for the planning tables. `food_log` retention is unchanged.

## Compliance — DSAR, consent, SOC 2 / GovRAMP

This section is **not optional** and is the gate on P3.

- **Erasure (Art 17):** `ON DELETE CASCADE` from `auth.users` through `nutrition_plans` → meals → assignments; the client's `food_log` / `body_metrics` already cascade. Verify with `/audit:account-deletion-completeness`.
- **Export (Art 20 / CCPA):** extend the `export-data` Edge Function **and** the Go `dataexport` path to include `nutrition_plans` + `nutrition_plan_meals` + `nutrition_plan_assignments`, with completeness pgtap updated — an explicit P1 task, not a follow-up (a modality with data missing from export must never reach real users). `food_log` + `body_metrics` are already in the export path. Verify with `/audit:data-export-completeness`.
- **The cross-user health-data read (P3) is the SOC 2 / GovRAMP-scoped line.** A nutritionist reading a client's food diary + body weight is processing GDPR Art 9 special-category data on behalf of, and disclosed to, a third party. The lawful basis is the client's **explicit, scoped, revocable consent** captured at link acceptance (`accepted_at` + the granted `'nutrition'` scope). Requirements before P3 ships:
  - Loop in the **CISO / Security Analyst** (org rule for SOC 2 / GovRAMP changes) — this is the headline review trigger.
  - The scope grant is the lawful-basis evidence; the consent screen must name *exactly* what the nutritionist will see (food log + weight trend + adherence) and that it is revocable.
  - The food-log/body-metrics read policies are column-narrowed (no `is_public`, no `external_id`, no GPS-adjacent fields) — mirror the coach-run-visibility narrowing.
  - **Disclosure updates** before launch: the privacy policy's sub-processor/data-sharing section (a nutritionist is a new recipient class), and confirm no new outbound hop beyond Open Food Facts (already disclosed). Run the relevant `/audit/*` (rls, privacy, third-party-data-flows).
- **GovRAMP reminder:** do not process any government/regulated client data through this in a non-FedRAMP context — same standing constraint as the rest of the app.

## Failure modes

- **Plan deleted while assigned:** the assignment cascades away; days revert to the computed Mifflin-St Jeor target. The client's logged `food_log` is untouched (date link, not FK).
- **"Didn't log" vs "genuinely under-ate" is indistinguishable** — the central nutrition-adherence fragility, the analogue of gym's free-text name drift. We treat `< 50%` of prescribed calories as `partial` (under-logged) and **exclude partial days from progression**, so a forgotten dinner can't manufacture a fake deficit that tightens next week's cut. Stated honestly: this proxy is imperfect; a true crash-diet day reads as `partial` and is ignored by progression. Acceptable — the failure mode is "no suggestion," never "harmful suggestion."
- **Mis-logged 5,000-kcal entry:** progression `prescribeNextWeek` would see a giant surplus. The engine **only suggests**; the target change is an editable, user-confirmed draft. Auto-apply is never allowed.
- **Overlapping assignments:** `activeAssignmentForDate` resolves newest-`start_date`-wins; the assign RPC ends the prior active assignment, so the steady state has one. A stale overlap degrades to "newest plan governs," never a crash.
- **Nutritionist link ended mid-plan:** the cross-user read revokes immediately (RLS recomputes); the *assignment* persists so the client keeps following the plan they were given, but the nutritionist can no longer see their data. Clean separation of "can I read you" from "what plan are you on."
- **Empty plan (kcal-only, no macros, no meals):** adherence judges calories alone; `prescribedTargetsForDate` yields a kcal target + null macros; the rings show one ring. No null-deref.

## Testing

| Surface | Where | What |
|---|---|---|
| Parity pairs (×3) | `nutrition/meal_plan`, `nutrition/nutrition_adherence`, `nutrition/nutrition_progression` — TS (`npx tsx --test`) + Dart (`flutter test`), **equal counts** | prescribed-targets-for-date incl. training override, newest-start-wins assignment resolution, direction-aware per-macro band (ceiling vs floor), day verdict incl. under-logged `partial`, each progression scheme's hold/adjust/blocked outcomes, no-weight-data + sparse-logging guards, non-finite guards, determinism fixture |
| Store | `local_nutrition_plan_store_test.dart` | sync states, drain order, `replaceFromServer` preserve-pending + newer-wins, inline-meals round-trip (`tester.runAsync`) |
| Web flow | Playwright `apps/web/tests-e2e/nutrition/` | `meal_plan_builder.spec.ts`, `plan_day_adherence.spec.ts` (assert seeded targets + a `partial` day + an `off_target` day with per-macro breakdown AND a no-plan day shows **no** panel), `save_as_plan.spec.ts`, self-hide regression in `nutrition.spec.ts` |
| Backend | pgtap (`apps/backend/supabase/tests/`) | RLS author-only on plans + active-client read branch + cascade-from-`auth.users`; `nutrition_plan_assignments` either-party read + RPC-only write; **P3:** `'nutrition'`-scoped cross-user `food_log`/`body_metrics` read (and that an ended/unscoped link sees nothing); `assign_nutrition_plan` authority checks; `export-data` completeness includes the three tables |

Mobile widget tests cover the plan editor, the seeded day view, and the adherence panel. Mobile/watch have no e2e equivalent by design (web Playwright + backend pgtap cover the e2e path).

## File list

**Migration** — `apps/backend/supabase/migrations/20261228_001_nutrition_programming.sql` (next free slot after gym's proposed `20261227_001`; latest landed is `20261226_001`): the three planning tables + indexes + RLS + the `private.can_read_nutrition_plan` definer helper + four CHECKs + the self-assign INSERT policy. **P3 migration (separate, gated, on its OWN date** — the same-day `_NNN_` ordinal does *not* disambiguate the version key, so P1 and P3 must not share a date): `alter table coach_athletes add column scopes`, `private.is_active_professional_of` + the `is_active_coach_of` wrapper rewrite, the `food_log`/`body_metrics` cross-user read branches, the `assign_nutrition_plan` RPC + its `grant … to postgres`, the `nutrition_plan_id` notification ref column, and `'nutrition_plan_assigned'` re-emitted into the consolidated kind CHECK.

**Generated (committed):** `apps/web/src/lib/database.types.ts`, `packages/core_models/lib/src/generated/db_rows.dart`.

**Web:** `src/lib/types.ts` (+4 unions), `scripts/check_constraint_unions.mjs` (+4 PAIRS), `src/lib/nutrition/meal_plan.ts`, `nutrition_adherence.ts`, `nutrition_progression.ts`, plus the mobile mirrors of the web-only `nutrition_budget`/`hydration`/`nutrition_week` if reused, `MealPlanEditor.svelte`, `NutritionPlanLibrary.svelte`, `NutritionPlanCard.svelte`, `NutritionAdherencePanel.svelte`, routes `/nutrition/plans/[id]`, `/nutrition/plans/new`, `/nutrition` (+ seeding + panel), **P3:** `/coaching/clients/[id]` (+ Nutrition panel), `core/data.ts` client API, i18n in all six locales.

**Mobile (`mobile_android` → byte-identical `mobile_ios`):** `lib/nutrition/meal_plan.dart`, `nutrition_adherence.dart`, `nutrition_progression.dart`, `lib/stores/local_nutrition_plan_store.dart`, `screens/nutrition_plan_detail_screen.dart`, `widgets/meal_plan_editor_sheet.dart`, `widgets/nutrition_adherence_panel.dart`, extend `nutrition_screen.dart`, ARBs.

**Edge Function / Go:** extend `export-data` + the Go `dataexport` path + their completeness pgtap.

## Phasing & rollout

Four web-first, independently-shippable slices. Each ships value alone, mirrors to the twin only after web lands, and unlocks the next. Sizing is dev-days for one engineer including web + mobile twin + tests + docs.

### P1 — Self-serve meal plans + day adherence (the gate probe) — ~4–5 days
The `nutrition_plans` table (kcal + optional macros + training override, no prescribed meals yet) + `nutrition_plan_assignments` (self-assign only) + the `meal_plan` and `nutrition_adherence` parity pairs + `/nutrition` Plans section, day-view seeding, adherence pill, `Save as plan` wedge. **DSAR export wired in this slice.** This is the engagement signal that justifies P2–P4. No cross-user surface, no CISO review needed.

### P2 — Prescribed meals + weekly progression — ~3–4 days
`nutrition_plan_meals` (one-tap-log prescribed meals via Open Food Facts) + the `nutrition_progression` parity pair + the next-week suggestion chip (editable, confirm-only). Still single-user.

### P3 — The nutritionist console (gated on the P1 signal + CISO sign-off) — ~5–6 days
Scope the `coach_athletes` link (`scopes` column + `is_active_professional_of`), the consent-gated cross-user `food_log`/`body_metrics` read, `assign_nutrition_plan` RPC + notification, and the `/coaching/clients/[id]` Nutrition panel (7-day adherence + weight trend + assign). **This is the headline persona and the compliance-sensitive slice — do not start until the gate clears and the CISO has reviewed the cross-user read.**

### P4 — Mobile twin of P1/P2 — ~3–4 days
The Flutter self-serve mirror (plan store, editor sheet, seeded day view, adherence panel), byte-identical iOS twin. The console stays web-only.

## Open questions

- **Generalise `coach_athletes` vs fork `nutritionist_clients`?** The recommendation is to generalise (one consent stack); the owner decides whether the shipped-table blast radius is acceptable. Resolve before P3.
- **Training-day detection for the override:** reuse the dynamic-TDEE workout-day signal, or let the plan prescribe explicit training days (Mon/Wed/Fri)? Lean on the existing signal first; add explicit days only if users ask.
- **Prescribed-meal fidelity:** macros-only (P2 default) vs gram-level ingredient decomposition (a recipe engine — explicitly out of scope). Revisit only if adherence data shows users want it.
- **Weight-trend smoothing:** EMA vs simple 7-day average for `prescribeNextWeek` — pick one in the parity pair and pin it with the determinism fixture.

## Rough sizing

~15–19 dev-days total across the four slices (P1 ~4–5, P2 ~3–4, P3 ~5–6, P4 ~3–4), one engineer, web-first with the twin mirrored after each web slice lands. P3 carries the only non-engineering dependency: CISO / Security Analyst review of the cross-user health-data read, which should start in parallel with P1 so it doesn't block the gated slice.
