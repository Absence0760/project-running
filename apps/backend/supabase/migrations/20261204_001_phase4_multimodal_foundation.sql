-- Phase 4 multi-modal foundation — gym + nutrition beside running.
--
-- This is the data layer only (decisions.md § 63, roadmap.md § Phase 4
-- "Activity-kind data model"). No UI ships with it; the nav reorg + the
-- gym / nutrition screens land later, behind the `multi_modal_nav`
-- feature flag. What this migration creates:
--
--   runs.kind        — broader modality marker on the existing runs
--                      table ('run' | 'lift' | 'meal'). Runs only ever
--                      hold 'run'; the column exists so the `activities`
--                      view can project a uniform `kind` and so a future
--                      merge of modalities into one table is a column
--                      change, not a re-model. CHECK pairs with the
--                      `ActivityKind` TS union (check_constraint_unions.mjs).
--   gym_workouts     — one row per logged strength session (parent).
--   gym_sets         — one row per set within a workout (child).
--   food_log         — one row per logged food item.
--   activities       — a UNION view over runs + gym_workouts + food_log
--                      projecting (id, user_id, kind, started_at,
--                      summary jsonb) so the unified History timeline is
--                      one query, not three round trips.
--
-- Conventions follow the existing schema: owner-scoped RLS keyed on
-- `user_id = auth.uid()` with a public-read branch mirroring
-- `runs.is_public` (so the social feed can reuse the follower/feed
-- plumbing for lift + meal cards). Offline-first sync uses a
-- client-stamped `last_modified_at` for newer-wins reconciliation — the
-- same shape LocalRunStore / LocalGearStore use — so there is
-- deliberately NO server-side updated_at trigger that would clobber the
-- client's conflict-resolution timestamp.

-- ─────────────────── runs.kind ───────────────────

alter table public.runs
  add column kind text not null default 'run'
  check (kind in ('run', 'lift', 'meal'));

-- ─────────────────── gym_workouts ───────────────────

create table public.gym_workouts (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid references auth.users(id) on delete cascade not null,
  title             text check (title is null or length(title) <= 120),
  started_at        timestamptz not null default now(),
  duration_s        integer check (duration_s is null or duration_s >= 0),
  notes             text check (notes is null or length(notes) <= 1000),
  is_public         boolean not null default false,
  external_id       text,
  last_modified_at  timestamptz not null default now(),
  created_at        timestamptz not null default now()
);

create index gym_workouts_user on public.gym_workouts (user_id, started_at desc);
-- Per-user import idempotency, mirroring runs.external_id.
create unique index gym_workouts_external_id
  on public.gym_workouts (user_id, external_id)
  where external_id is not null;

alter table public.gym_workouts enable row level security;

create policy "gym_workouts owner or public read"
  on public.gym_workouts for select
  using (user_id = auth.uid() or is_public);

create policy "gym_workouts owner insert"
  on public.gym_workouts for insert
  with check (user_id = auth.uid());

create policy "gym_workouts owner update"
  on public.gym_workouts for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "gym_workouts owner delete"
  on public.gym_workouts for delete
  using (user_id = auth.uid());

-- ─────────────────── gym_sets ───────────────────

create table public.gym_sets (
  id             uuid primary key default gen_random_uuid(),
  workout_id     uuid references public.gym_workouts(id) on delete cascade not null,
  set_index      integer not null,
  exercise_name  text not null check (length(exercise_name) between 1 and 120),
  reps           integer check (reps is null or reps >= 0),
  weight_kg      numeric(7, 2) check (weight_kg is null or weight_kg >= 0),
  rpe            numeric(3, 1) check (rpe is null or (rpe >= 0 and rpe <= 10))
);

create index gym_sets_workout on public.gym_sets (workout_id, set_index);

alter table public.gym_sets enable row level security;

-- Visibility follows the parent workout: anyone who can see the workout
-- (owner, or a public workout) can see its sets.
create policy "gym_sets visible via parent workout"
  on public.gym_sets for select
  using (
    exists (
      select 1 from public.gym_workouts w
      where w.id = gym_sets.workout_id
        and (w.user_id = auth.uid() or w.is_public)
    )
  );

create policy "gym_sets owner insert"
  on public.gym_sets for insert
  with check (
    exists (
      select 1 from public.gym_workouts w
      where w.id = gym_sets.workout_id and w.user_id = auth.uid()
    )
  );

create policy "gym_sets owner update"
  on public.gym_sets for update
  using (
    exists (
      select 1 from public.gym_workouts w
      where w.id = gym_sets.workout_id and w.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.gym_workouts w
      where w.id = gym_sets.workout_id and w.user_id = auth.uid()
    )
  );

create policy "gym_sets owner delete"
  on public.gym_sets for delete
  using (
    exists (
      select 1 from public.gym_workouts w
      where w.id = gym_sets.workout_id and w.user_id = auth.uid()
    )
  );

-- ─────────────────── food_log ───────────────────

create table public.food_log (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid references auth.users(id) on delete cascade not null,
  logged_at         timestamptz not null default now(),
  item_name         text not null check (length(item_name) between 1 and 200),
  meal_slot         text check (meal_slot is null or meal_slot in ('breakfast', 'lunch', 'dinner', 'snack')),
  calories          numeric(7, 1) check (calories is null or calories >= 0),
  protein_g         numeric(6, 1) check (protein_g is null or protein_g >= 0),
  carbs_g           numeric(6, 1) check (carbs_g is null or carbs_g >= 0),
  fat_g             numeric(6, 1) check (fat_g is null or fat_g >= 0),
  is_public         boolean not null default false,
  external_id       text,
  last_modified_at  timestamptz not null default now(),
  created_at        timestamptz not null default now()
);

create index food_log_user on public.food_log (user_id, logged_at desc);
create unique index food_log_external_id
  on public.food_log (user_id, external_id)
  where external_id is not null;

alter table public.food_log enable row level security;

create policy "food_log owner or public read"
  on public.food_log for select
  using (user_id = auth.uid() or is_public);

create policy "food_log owner insert"
  on public.food_log for insert
  with check (user_id = auth.uid());

create policy "food_log owner update"
  on public.food_log for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "food_log owner delete"
  on public.food_log for delete
  using (user_id = auth.uid());

-- ─────────────────── activities view ───────────────────

-- Unified timeline source. `security_invoker = true` so the base
-- tables' RLS applies to the querying user — a non-owner only sees
-- public rows, the SUM/COUNT subqueries on gym_sets stay scoped, and no
-- cross-user leak is possible. summary is a thin jsonb projection the
-- History list renders without a second fetch; the detail screens load
-- the full row from the underlying table.
create or replace view public.activities
with (security_invoker = true) as
select
  r.id,
  r.user_id,
  r.kind,
  r.started_at,
  jsonb_build_object(
    'distance_m', r.distance_m,
    'duration_s', r.duration_s,
    'activity_type', r.metadata ->> 'activity_type'
  ) as summary
from public.runs r
union all
select
  w.id,
  w.user_id,
  'lift'::text as kind,
  w.started_at,
  jsonb_build_object(
    'title', w.title,
    'set_count', (select count(*) from public.gym_sets s where s.workout_id = w.id),
    'volume_kg', (
      select coalesce(sum(coalesce(s.reps, 0) * coalesce(s.weight_kg, 0)), 0)
      from public.gym_sets s where s.workout_id = w.id
    )
  ) as summary
from public.gym_workouts w
union all
select
  f.id,
  f.user_id,
  'meal'::text as kind,
  f.logged_at as started_at,
  jsonb_build_object(
    'item_name', f.item_name,
    'calories', f.calories,
    'meal_slot', f.meal_slot
  ) as summary
from public.food_log f;

grant select on public.activities to authenticated;
