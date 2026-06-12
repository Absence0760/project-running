-- Gym programming engine, slice P1 (docs/features/gym_programming.md).
-- Reusable routines (gym_routines → gym_routine_exercises → gym_routine_sets),
-- "save as routine" + "repeat last". No execution loop, no progression engine
-- yet (P2-P4). The full schema (incl. the superset / progression columns the
-- later slices need) lands in this one migration; P1 leaves those columns at
-- their defaults / null.

-- ── Prerequisite: gym_workouts.metadata ─────────────────────────────────────
-- gym_workouts was created (20261204_001) without a jsonb bag, unlike runs.
-- The plan→session link + the planned-vs-actual trail (P3) live here, mirroring
-- runs.metadata. `add column ... default '{}'` is metadata-only on PG11+
-- (no table rewrite, no blocking scan). The activities view's lift branch
-- enumerates explicit columns (id, user_id, kind, started_at, summary), so the
-- new column does not change the UNION shape.
alter table public.gym_workouts
  add column metadata jsonb not null default '{}'::jsonb;

-- ── gym_routines — a user-owned named workout plan ──────────────────────────
create table public.gym_routines (
  id                uuid primary key default gen_random_uuid(),
  author_id         uuid not null references auth.users (id) on delete cascade,
  title             text not null check (length(title) between 1 and 120),
  notes             text check (notes is null or length(notes) <= 1000),

  periodisation     text not null default 'none'
                      check (periodisation in ('none','linear','block','conjugate')),

  -- denormalised count for the list screen; client-stamped on save, NOT a
  -- trigger cache (derived_state.md records it as client-stamped / non-authoritative).
  exercise_count    int not null default 0 check (exercise_count >= 0),

  external_id       text,
  last_modified_at  timestamptz not null default now(),
  created_at        timestamptz not null default now()
);

create unique index gym_routines_author_external_id_key
  on public.gym_routines (author_id, external_id) where external_id is not null;
create index gym_routines_author_modified_idx
  on public.gym_routines (author_id, last_modified_at desc);

-- ── gym_routine_exercises — planned exercises within a routine ──────────────
create table public.gym_routine_exercises (
  id                  uuid primary key default gen_random_uuid(),
  routine_id          uuid not null references public.gym_routines (id) on delete cascade,

  -- free-text name for display, normalised key for binding to logged gym_sets.
  exercise_name       text not null check (length(exercise_name) between 1 and 120),
  exercise_key        text not null check (length(exercise_key) between 1 and 120),

  -- ordering + grouping for supersets/circuits (P1 leaves the superset cols null).
  position            int not null check (position >= 0),
  superset_group      int,
  superset_order      int check (superset_order >= 0),

  modality            text not null default 'weight_reps'
                        check (modality in ('weight_reps','time','distance','bodyweight_reps')),

  progression         text not null default 'none'
                        check (progression in ('none','linear','double_progression','five_by_five','percent_cycle','rpe_autoreg')),
  progression_params  jsonb not null default '{}'::jsonb,

  notes               text check (notes is null or length(notes) <= 500),

  constraint gym_routine_exercises_superset_chk
    check ((superset_group is null) = (superset_order is null))
);

create index gym_routine_exercises_routine_idx
  on public.gym_routine_exercises (routine_id, position, superset_order);
create index gym_routine_exercises_key_idx
  on public.gym_routine_exercises (exercise_key);

-- ── gym_routine_sets — planned target values per set ────────────────────────
create table public.gym_routine_sets (
  id                  uuid primary key default gen_random_uuid(),
  routine_exercise_id uuid not null
                        references public.gym_routine_exercises (id) on delete cascade,

  set_index           int not null check (set_index >= 0),

  set_type            text not null default 'working'
                        check (set_type in ('warmup','working','dropset','amrap','failure','backoff')),

  target_reps_min     int check (target_reps_min is null or target_reps_min >= 0),
  target_reps_max     int check (target_reps_max is null or target_reps_max >= 0),

  target_weight_kg    numeric(7,2) check (target_weight_kg is null or target_weight_kg >= 0),
  target_percent_1rm  numeric(5,2) check (target_percent_1rm is null
                          or (target_percent_1rm > 0 and target_percent_1rm <= 200)),

  target_rpe          numeric(3,1) check (target_rpe is null or (target_rpe >= 0 and target_rpe <= 10)),

  rest_s              int check (rest_s is null or (rest_s >= 0 and rest_s <= 3600)),

  tempo               text check (tempo is null or tempo ~ '^[0-9X]{3,4}$'),

  target_duration_s   int check (target_duration_s is null or target_duration_s >= 0),
  target_distance_m   numeric(10,2) check (target_distance_m is null or target_distance_m >= 0),

  constraint gym_routine_sets_load_chk
    check (not (target_weight_kg is not null and target_percent_1rm is not null)),
  constraint gym_routine_sets_rep_range_chk
    check (target_reps_max is null or target_reps_min is null or target_reps_max >= target_reps_min)
);

create index gym_routine_sets_exercise_idx
  on public.gym_routine_sets (routine_exercise_id, set_index);

-- ── RLS — owner-scoped (author-only in v1, no public branch) ────────────────
alter table public.gym_routines          enable row level security;
alter table public.gym_routine_exercises enable row level security;
alter table public.gym_routine_sets      enable row level security;

create policy "gym_routines author select"
  on public.gym_routines for select using (author_id = auth.uid());
create policy "gym_routines author insert"
  on public.gym_routines for insert with check (author_id = auth.uid());
create policy "gym_routines author update"
  on public.gym_routines for update using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "gym_routines author delete"
  on public.gym_routines for delete using (author_id = auth.uid());

create policy "gym_routine_exercises via parent select"
  on public.gym_routine_exercises for select
  using (exists (select 1 from public.gym_routines r
    where r.id = gym_routine_exercises.routine_id and r.author_id = auth.uid()));
create policy "gym_routine_exercises via parent insert"
  on public.gym_routine_exercises for insert
  with check (exists (select 1 from public.gym_routines r
    where r.id = gym_routine_exercises.routine_id and r.author_id = auth.uid()));
create policy "gym_routine_exercises via parent update"
  on public.gym_routine_exercises for update
  using (exists (select 1 from public.gym_routines r
    where r.id = gym_routine_exercises.routine_id and r.author_id = auth.uid()))
  with check (exists (select 1 from public.gym_routines r
    where r.id = gym_routine_exercises.routine_id and r.author_id = auth.uid()));
create policy "gym_routine_exercises via parent delete"
  on public.gym_routine_exercises for delete
  using (exists (select 1 from public.gym_routines r
    where r.id = gym_routine_exercises.routine_id and r.author_id = auth.uid()));

create policy "gym_routine_sets via parent select"
  on public.gym_routine_sets for select
  using (exists (select 1 from public.gym_routine_exercises e
    join public.gym_routines r on r.id = e.routine_id
    where e.id = gym_routine_sets.routine_exercise_id and r.author_id = auth.uid()));
create policy "gym_routine_sets via parent insert"
  on public.gym_routine_sets for insert
  with check (exists (select 1 from public.gym_routine_exercises e
    join public.gym_routines r on r.id = e.routine_id
    where e.id = gym_routine_sets.routine_exercise_id and r.author_id = auth.uid()));
create policy "gym_routine_sets via parent update"
  on public.gym_routine_sets for update
  using (exists (select 1 from public.gym_routine_exercises e
    join public.gym_routines r on r.id = e.routine_id
    where e.id = gym_routine_sets.routine_exercise_id and r.author_id = auth.uid()))
  with check (exists (select 1 from public.gym_routine_exercises e
    join public.gym_routines r on r.id = e.routine_id
    where e.id = gym_routine_sets.routine_exercise_id and r.author_id = auth.uid()));
create policy "gym_routine_sets via parent delete"
  on public.gym_routine_sets for delete
  using (exists (select 1 from public.gym_routine_exercises e
    join public.gym_routines r on r.id = e.routine_id
    where e.id = gym_routine_sets.routine_exercise_id and r.author_id = auth.uid()));
