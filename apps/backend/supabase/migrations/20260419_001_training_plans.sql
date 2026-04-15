-- Training plans — Runna / Garmin Coach parity, web-first.
--
-- Three tables:
--   training_plans   — one row per active (or past) plan per user
--   plan_weeks       — 12–16 rows per plan, one per week, with a phase label
--   plan_workouts    — ~4–6 rows per week, scheduled to dates
--
-- Decisions (see docs/decisions.md #11):
--   * Pace generation uses Riegel equivalence + simple intensity multipliers
--     anchored on goal pace. Daniels-VDOT is computed and stored for display
--     but not used to back-project paces in v1 — the Daniels formula is an
--     implicit equation with no closed-form inverse for training paces, and
--     Riegel + multipliers gets a runner within ~5 s/km of correct, which is
--     well within the tolerance band a plan runner expects.
--   * `structure` is jsonb so we can evolve the structured-workout schema
--     without a migration. `docs/training.md` documents the shape.
--   * `completed_run_id` is set by a client-side auto-match (same user, same
--     scheduled date, distance within 25% of target). Wrong matches are
--     manually fixable — no fancy scoring in v1.

create type workout_kind as enum (
  'easy',
  'long',
  'recovery',
  'tempo',
  'interval',
  'marathon_pace',
  'race',
  'rest'
);

create type plan_phase as enum (
  'base',
  'build',
  'peak',
  'taper',
  'race'
);

create type goal_event as enum (
  'distance_5k',
  'distance_10k',
  'distance_half',
  'distance_full',
  'custom'
);

-- ─────────────────────── Plans ───────────────────────
create table training_plans (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid references auth.users on delete cascade not null,
  name                text not null,
  goal_event          goal_event not null,
  goal_distance_m     numeric(10, 2) not null,
  goal_time_seconds   integer,             -- null = no target, just volume-based plan
  start_date          date not null,
  end_date            date not null,
  days_per_week       smallint not null default 4,
  vdot                numeric(5, 2),       -- Daniels VDOT; null if we couldn't compute one
  current_5k_seconds  integer,             -- provided by the runner for pace anchoring
  status              text not null default 'active',  -- 'active' | 'completed' | 'abandoned'
  notes               text,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),
  check (end_date >= start_date),
  check (days_per_week between 3 and 7)
);

create index training_plans_user on training_plans (user_id, created_at desc);
create index training_plans_active
  on training_plans (user_id)
  where status = 'active';

-- ─────────────────────── Weeks ───────────────────────
create table plan_weeks (
  id                    uuid primary key default gen_random_uuid(),
  plan_id               uuid references training_plans on delete cascade not null,
  week_index            smallint not null,                  -- 0-based, 0 == first week
  phase                 plan_phase not null default 'base',
  target_volume_m       numeric(10, 2),
  notes                 text,
  unique (plan_id, week_index)
);

create index plan_weeks_plan on plan_weeks (plan_id, week_index);

-- ─────────────────────── Workouts ───────────────────────
create table plan_workouts (
  id                         uuid primary key default gen_random_uuid(),
  week_id                    uuid references plan_weeks on delete cascade not null,
  scheduled_date             date not null,
  kind                       workout_kind not null,
  target_distance_m          numeric(10, 2),
  target_duration_seconds    integer,
  target_pace_sec_per_km     integer,
  target_pace_tolerance_sec  integer,                   -- +/- around the target
  structure                  jsonb,                      -- see docs/training.md for shape
  notes                      text,
  completed_run_id           uuid references runs on delete set null,
  completed_at               timestamptz
);

create index plan_workouts_week on plan_workouts (week_id, scheduled_date);
create index plan_workouts_user_date
  on plan_workouts (scheduled_date, kind);

-- ─────────────────────── RLS ───────────────────────
-- All three tables are owner-only. No public browsing in v1 (plan sharing /
-- public plan library is deferred — see roadmap).
alter table training_plans enable row level security;
create policy "users own their plans"
  on training_plans for all using (auth.uid() = user_id);

alter table plan_weeks enable row level security;
create policy "users own their plan weeks"
  on plan_weeks for all using (
    exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id and p.user_id = auth.uid()
    )
  );

alter table plan_workouts enable row level security;
create policy "users own their plan workouts"
  on plan_workouts for all using (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id and p.user_id = auth.uid()
    )
  );

-- Only one `active` plan per user at a time. A partial unique index is
-- cleaner than a trigger for this — the application code auto-completes an
-- old plan when the user starts a new one (see data.ts#createTrainingPlan).
create unique index training_plans_one_active
  on training_plans (user_id)
  where status = 'active';
