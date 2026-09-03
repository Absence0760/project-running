-- Stamp the existing rows, make the key an invariant, and stop the five RPCs
-- re-deriving it.
--
-- Second half of 20270706000001. That migration added the column and the
-- trigger, so every row written since then already carries its key and the set
-- this backfill has to walk stopped growing.
--
-- ── Measured, on PG 17.6 against a 500,000-row copy of gym_sets ────────────
--   * keyset-paginated backfill, 5,000-row chunks:      6.94 s
--   * both CHECKs, `not valid`:                         6.1 ms
--   * `validate constraint` (canonical):                2.08 s, SHARE UPDATE
--                                                       EXCLUSIVE (reads and
--                                                       writes proceed)
--   * `validate constraint` (not-null):                 41.8 ms
--   * `alter column ... set not null`:                  0.83 ms -- it skips its
--                                                       own scan by trusting
--                                                       the validated CHECK,
--                                                       the PG12+ route
--                                                       migration_locks.md
--                                                       names
--   * dropping the now-redundant not-null CHECK:        2.2 ms
--
-- The only ACCESS EXCLUSIVE holds are the millisecond-scale catalogue flips.
--
-- ── The backfill is keyset-paginated, and that is not a detail ─────────────
-- The batched-backfill idiom the two earlier key migrations used --
-- `select id ... where <predicate> order by id limit N` re-run until it
-- matches nothing -- is O(n^2/batch): every chunk restarts at the low end of
-- the primary key and has to step over every row the previous chunks already
-- fixed. Measured on the same 500,000 rows it took **129.5 s** against the
-- 6.94 s of the keyset form below, which carries the last id forward so each
-- chunk starts where the previous one stopped. It did not bite in
-- 20270623000001 or 20270630000003 because both walk bounded tables (one row
-- per exercise per routine / per catalogue entry); on `gym_sets` it would.
--
-- The predicate stays on the UPDATE rather than on the chunk selection for the
-- same reason: a chunk is a contiguous id range, and a row already carrying its
-- key is skipped without leaving a hole the next chunk has to re-find.
--
-- ── No index on the new column, measured ──────────────────────────────────
-- The obvious `create index on gym_sets (exercise_key)` is not here. Every one
-- of the five RPCs is user-scoped -- it reaches `gym_sets` through
-- `gym_workouts.user_id = auth.uid()` -- so the planner drives from the user's
-- workouts and into `gym_sets_workout (workout_id, set_index)`. Measured on a
-- 2,000-user / 100,000-workout / 500,000-set fixture, the plan for the
-- `gym_exercise_set_history` shape is byte for byte the same with and without
-- the index (`Index Scan using ..._workout`, `Filter: (exercise_key = ...)`),
-- and `pg_stat_user_indexes.idx_scan` for the key index stayed at 0. It would
-- cost a build, disk, and write amplification on the highest-volume gym table
-- to buy a plan nothing chooses. `gym_routine_exercises_key_idx` exists because
-- that table is small and is looked up BY key across routines; nothing looks a
-- `gym_set` up by key across users.

-- ── Backfill ───────────────────────────────────────────────────────────────
do $$
declare
  batch_size constant integer := 5000;
  lo uuid := '00000000-0000-0000-0000-000000000000';
  seen integer;
begin
  loop
    with chunk as (
      select id from public.gym_sets where id > lo order by id limit batch_size
    ), stamped as (
      update public.gym_sets t
      set exercise_key = public.normalise_exercise_name(t.exercise_name)
      from chunk c
      where t.id = c.id
        and t.exercise_key is distinct from public.normalise_exercise_name(t.exercise_name)
      returning 1
    )
    select (select id from chunk order by id desc limit 1),
           (select count(*) from chunk)
      into lo, seen;
    exit when seen = 0;
  end loop;
end;
$$;

-- ── Make it an invariant ───────────────────────────────────────────────────
-- Three constraints. The canonical one alone does not reject a NULL key:
-- `null = public.normalise_exercise_name(exercise_name)` is NULL, and a CHECK
-- that evaluates to NULL passes. A NULL key would then be silently dropped from
-- every aggregate below rather than splitting a bucket -- worse, because
-- nothing surfaces it. The not-null CHECK exists only to let `set not null`
-- skip its scan and is dropped once the column attribute carries the claim; the
-- attribute is also what makes the generated row types non-nullable, so no
-- client has to handle a null that cannot occur.
--
-- The length cap is the one `free_text_caps_test.sql` demands of every
-- user-writable free-text column, and 120 is `gym_sets_exercise_name_check`'s
-- own ceiling because the fold cannot lengthen a name: `translate` is 1:1 both
-- times, the whitespace collapse and the trim only shorten, and `lower()` under
-- `und-x-icu` was measured 1:1 in length over all 1,112,064 assignable code
-- points in five contexts each -- flanked by ASCII, doubled, before and after a
-- Greek all-caps word (Final_Sigma), and followed by a combining acute --
-- 5,560,320 strings, none of which folded longer than its input. Unlike
-- `gym_routine_exercises_exercise_key_check` there is no `>= 1` half: a name
-- that is only whitespace passes `gym_sets_exercise_name_check` and folds to
-- the empty key, which is exactly the value the readers below filter out.
alter table public.gym_sets
  add constraint gym_sets_exercise_key_canonical
    check (exercise_key = public.normalise_exercise_name(exercise_name)) not valid,
  add constraint gym_sets_exercise_key_present
    check (exercise_key is not null) not valid,
  add constraint gym_sets_exercise_key_len_chk
    check (length(exercise_key) <= 120) not valid;

alter table public.gym_sets validate constraint gym_sets_exercise_key_canonical;
alter table public.gym_sets validate constraint gym_sets_exercise_key_present;
alter table public.gym_sets validate constraint gym_sets_exercise_key_len_chk;

alter table public.gym_sets alter column exercise_key set not null;

alter table public.gym_sets drop constraint gym_sets_exercise_key_present;

-- ── The five readers ───────────────────────────────────────────────────────
-- Bodies are otherwise verbatim: `public.normalise_exercise_name(s.exercise_name)`
-- becomes `s.exercise_key`, and the blank filter `coalesce(..., '') <> ''`
-- becomes `s.exercise_key <> ''` (the column is NOT NULL, so the coalesce has
-- nothing left to do). The two history RPCs still fold their ARGUMENT -- once
-- per call, or once per requested name, which is the cost this migration exists
-- to separate from the per-row one. No grant statements: `create or replace`
-- preserves each function's ACL.
--
-- Measured read-path effect on a 15,000-set history: 66-74 ms re-deriving
-- against 4.9-5.4 ms reading the column, and 2,241 ms against 196 ms at
-- 500,000 sets. That is with today's `lower()`; the frozen fold table this
-- unblocks is 128x more expensive per call, and after this migration it is paid
-- on writes only.

CREATE OR REPLACE FUNCTION public.gym_exercise_names()
 RETURNS TABLE(exercise_name text, uses integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with norm as (
    select
      s.exercise_key as key,
      s.exercise_name as display,
      gw.started_at
    from gym_sets s
    join gym_workouts gw on gw.id = s.workout_id
    where gw.user_id = auth.uid()
      and s.exercise_key <> ''
  ),
  spellings as (
    select
      key,
      display,
      count(*)::int as spelling_uses,
      max(started_at) as last_used
    from norm
    group by key, display
  ),
  picked as (
    select
      key,
      (array_agg(display order by last_used desc, length(display),
                                 display collate "und-x-icu"))[1] as display,
      sum(spelling_uses)::int as uses
    from spellings
    group by key
  )
  select p.display, p.uses
  from picked p
  order by p.uses desc, p.display collate "und-x-icu";
$function$;

CREATE OR REPLACE FUNCTION public.gym_exercise_records()
 RETURNS TABLE(exercise_name text, heaviest_weight_kg numeric, heaviest_weight_reps integer, best_volume_kg numeric, best_est_1rm_kg numeric, last_performed_at timestamp with time zone, session_count integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with norm as (
    select
      s.exercise_key as key,
      s.exercise_name as display,
      s.reps,
      s.weight_kg,
      s.workout_id,
      gw.started_at
    from gym_sets s
    join gym_workouts gw on gw.id = s.workout_id
    where gw.user_id = auth.uid()
      and s.exercise_key <> ''
  ),
  meta as (
    select
      key,
      max(started_at) as last_performed_at,
      count(distinct workout_id)::int as session_count,
      (array_agg(display order by started_at desc, length(display),
                                  display collate "und-x-icu"))[1] as display
    from norm
    group by key
  ),
  weighted as (
    select key, reps, weight_kg
    from norm
    where weight_kg is not null and weight_kg > 0
  ),
  bests as (
    select
      key,
      max(weight_kg) as heaviest_weight_kg,
      round(max(weight_kg * reps) filter (where reps > 0), 1) as best_volume_kg,
      round(max(case when reps = 1 then weight_kg
                     else weight_kg * (1 + least(reps, 12)::numeric / 30) end)
              filter (where reps > 0), 1) as best_est_1rm_kg
    from weighted
    group by key
  ),
  heaviest_reps as (
    select distinct on (w.key)
      w.key,
      w.reps
    from weighted w
    join bests b on b.key = w.key and w.weight_kg = b.heaviest_weight_kg
    order by w.key, w.reps desc nulls last
  )
  select
    m.display,
    b.heaviest_weight_kg,
    hr.reps::int,
    b.best_volume_kg,
    b.best_est_1rm_kg,
    m.last_performed_at,
    m.session_count
  from meta m
  join bests b on b.key = m.key
  left join heaviest_reps hr on hr.key = m.key
  order by m.last_performed_at desc, m.display collate "und-x-icu";
$function$;

CREATE OR REPLACE FUNCTION public.gym_exercise_set_history(p_name text)
 RETURNS TABLE(workout_id uuid, started_at timestamp with time zone, exercise_name text, reps integer, weight_kg numeric, rpe numeric, duration_s integer, set_type text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select
    s.workout_id,
    gw.started_at,
    s.exercise_name,
    s.reps,
    s.weight_kg,
    s.rpe,
    s.duration_s,
    s.set_type
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where gw.user_id = auth.uid()
    and s.exercise_key = public.normalise_exercise_name(p_name);
$function$;

CREATE OR REPLACE FUNCTION public.gym_exercise_set_history_batch(p_names text[])
 RETURNS TABLE(normalised_name text, workout_id uuid, started_at timestamp with time zone, exercise_name text, reps integer, weight_kg numeric, rpe numeric, duration_s integer, set_type text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select
    s.exercise_key as normalised_name,
    s.workout_id,
    gw.started_at,
    s.exercise_name,
    s.reps,
    s.weight_kg,
    s.rpe,
    s.duration_s,
    s.set_type
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where gw.user_id = auth.uid()
    and s.exercise_key in (
      select public.normalise_exercise_name(n)
      from unnest(coalesce(p_names, '{}'::text[])) as n
      where coalesce(public.normalise_exercise_name(n), '') <> ''
    );
$function$;

CREATE OR REPLACE FUNCTION public.gym_workout_summaries(p_limit integer DEFAULT 100)
 RETURNS TABLE(workout_id uuid, exercise_count integer, is_pr boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with mine as (
    select gw.id, gw.started_at
    from gym_workouts gw
    where gw.user_id = auth.uid()
  ),
  listed as (
    select m.id, m.started_at
    from mine m
    order by m.started_at desc, m.id desc
    limit greatest(coalesce(p_limit, 100), 0)
  ),
  norm as (
    select
      s.workout_id,
      m.started_at,
      s.exercise_key as key,
      s.reps,
      s.weight_kg
    from gym_sets s
    join mine m on m.id = s.workout_id
    where s.exercise_key <> ''
  ),
  counts as (
    select n.workout_id, count(distinct n.key)::int as exercise_count
    from norm n
    join listed l on l.id = n.workout_id
    group by n.workout_id
  ),
  per_workout as (
    select
      n.workout_id,
      n.started_at,
      n.key,
      max(n.weight_kg) filter (where n.weight_kg > 0) as best_weight,
      round(max(n.weight_kg * n.reps)
              filter (where n.weight_kg > 0 and n.reps > 0), 1) as best_volume,
      round(max(case when n.reps = 1 then n.weight_kg
                     else n.weight_kg * (1 + least(n.reps, 12)::numeric / 30) end)
              filter (where n.weight_kg > 0 and n.reps > 0), 1) as best_e1rm
    from norm n
    group by n.workout_id, n.started_at, n.key
  ),
  judged as (
    select
      p.workout_id,
      p.best_weight,
      p.best_volume,
      p.best_e1rm,
      max(p.best_weight) over prior as prior_weight,
      max(p.best_volume) over prior as prior_volume,
      max(p.best_e1rm)   over prior as prior_e1rm
    from per_workout p
    window prior as (
      partition by p.key
      order by p.started_at, p.workout_id
      rows between unbounded preceding and 1 preceding
    )
  ),
  pr_workouts as (
    select distinct j.workout_id
    from judged j
    where (j.best_weight is not null
             and (j.prior_weight is null or j.best_weight > j.prior_weight))
       or (j.best_volume is not null
             and (j.prior_volume is null or j.best_volume > j.prior_volume))
       or (j.best_e1rm is not null
             and (j.prior_e1rm is null or j.best_e1rm > j.prior_e1rm))
  )
  select
    l.id,
    coalesce(c.exercise_count, 0),
    (pr.workout_id is not null)
  from listed l
  left join counts c on c.workout_id = l.id
  left join pr_workouts pr on pr.workout_id = l.id
  order by l.started_at desc, l.id desc;
$function$;
