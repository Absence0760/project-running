-- One definition of the exercise grouping key, shared by every rail that
-- derives it (decisions § 790).
--
-- `normaliseExerciseName` groups a lifter's history: every PR, every "vs last
-- time" hint, every routine's plan-to-log binding is keyed on it, and the
-- clients PERSIST it as `gym_routine_exercises.exercise_key` and
-- `exercises.name_key`. Four live SQL functions derived the same key by hand as
--
--   regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g')
--
-- which disagrees with both clients in two independent ways, and disagrees
-- with ITSELF across deployments in a third:
--
--   * `btrim(text)` with no second argument strips U+0020 and nothing else.
--     A name carrying any other leading or trailing whitespace — a pasted
--     trailing newline, a leading tab — kept it through the trim, and the
--     `\s+` pass then turned it into a leading/trailing SPACE. So
--     `<TAB>Bench Press` keyed as ` bench press` on the server and
--     `bench press` on both clients: one exercise, two buckets, and the local
--     PR tracker says PR where `gym_workout_summaries.is_pr` says no.
--
--   * `\s` is `[[:space:]]`, whose membership past ASCII is decided by the
--     database's locale provider, NOT by Unicode. Measured on PG 17.6: under
--     the ICU provider `\s` matches U+00A0, U+2007, U+202F and U+001C-U+001F;
--     under the libc `en_US.utf8` provider it matches none of them. The same
--     name therefore normalises differently on two databases running the same
--     migration set — a persisted key must not be a function of the server's
--     collation. Neither provider matches U+FEFF, which both clients fold.
--
-- The clients are the anchor, not the SQL: they are what stamps the persisted
-- key, and their class (Unicode White_Space plus U+FEFF) is spelled out by
-- code point rather than left to a runtime default. This function is that same
-- class written a third time in the one place SQL can share, and it is written
-- with explicit `\uXXXX` code points so it means the same thing under every
-- locale provider. `scripts/check_shared_constants.mjs` compares the three.
--
-- Lock impact (migration_locks.md): CREATE FUNCTION and CREATE OR REPLACE
-- FUNCTION lock the pg_proc entry only — no table is touched. The two backfills
-- are batched by primary key and scoped by a predicate that matches only rows
-- whose stored key already disagrees; on a database whose keys were all written
-- by a conforming client they update nothing. The two CHECK constraints go on
-- as NOT VALID (instant, metadata only) and are validated in a second pass
-- under SHARE UPDATE EXCLUSIVE, which lets reads and writes through.

-- ── The canonical derivation ────────────────────────────────────────────────
-- Mirrors `EXERCISE_WS` in apps/web/src/lib/gym/gym_prs.ts and
-- `kExerciseWhitespace` in apps/mobile_android/lib/gym_prs.dart, code point for
-- code point. `\u0009-\u000d` is TAB/LF/VT/FF/CR, which the clients write as
-- `\t\n\v\f\r`; the rest are U+0020, the Unicode White_Space characters above
-- ASCII, and U+FEFF (a pasted BOM / zero-width no-break space, which is not
-- White_Space but is invisible and must not split a bucket).
--
-- IMMUTABLE is what lets a CHECK constraint and an index reference it. It is
-- honest for the whitespace half — the class names code points, so no locale
-- can move it — and `lower()` carries exactly the collation dependence it
-- already carried in the four hand-written copies.
create or replace function public.normalise_exercise_name(p_name text)
returns text
language sql
immutable
parallel safe
returns null on null input
set search_path = ''
as $$
  select btrim(
    regexp_replace(
      lower(p_name),
      '[\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+',
      ' ',
      'g'
    ),
    ' '
  );
$$;

comment on function public.normalise_exercise_name(text) is
  'The exercise grouping key: lower-cased, every run of whitespace collapsed to one space, trimmed. The whitespace class is Unicode White_Space plus U+FEFF, written by code point so it does not depend on the database locale provider. Must stay identical to normaliseExerciseName in apps/web/src/lib/gym/gym_prs.ts and apps/mobile_android/lib/gym_prs.dart; scripts/check_shared_constants.mjs compares the three.';

-- The grant list is decided by who WRITES the two tables below, not by who
-- calls the four RPCs. A CHECK constraint naming a function ACL-checks that
-- function against the role performing the insert (decisions § 746 records the
-- same trap one layer over, inside a SECURITY INVOKER body), so a grant that
-- covered only `authenticated` made every service_role write to
-- gym_routine_exercises / exercises fail with 42501 -- the Playwright gym
-- fixtures included. Measured, not reasoned about: the insert was run as
-- service_role and refused before the grant was widened, and
-- normalise_exercise_name_test.sql pins both roles so the omission cannot
-- come back silently. `anon` is deliberately absent: RLS lets it write
-- neither table, and a CHECK is only ever evaluated on a write.
revoke execute on function public.normalise_exercise_name(text) from public;
grant  execute on function public.normalise_exercise_name(text) to authenticated;
grant  execute on function public.normalise_exercise_name(text) to service_role;

-- ── The four live derivations, re-emitted against the function ──────────────
-- Bodies are otherwise verbatim. The blank-name filter moves with the key: a
-- name that is nothing but whitespace normalises to '' and is not an exercise,
-- which `btrim(coalesce(name,'')) <> ''` got wrong for exactly the characters
-- btrim does not strip (a lone TAB counted as an exercise named " " server-side
-- and was dropped by both clients).

create or replace function gym_exercise_records()
returns table (
  exercise_name text,
  heaviest_weight_kg numeric,
  heaviest_weight_reps integer,
  best_volume_kg numeric,
  best_est_1rm_kg numeric,
  last_performed_at timestamptz,
  session_count integer
)
language sql
stable
security invoker
set search_path = public
as $$
  with norm as (
    select
      public.normalise_exercise_name(s.exercise_name) as key,
      s.exercise_name as display,
      s.reps,
      s.weight_kg,
      s.workout_id,
      gw.started_at
    from gym_sets s
    join gym_workouts gw on gw.id = s.workout_id
    where gw.user_id = auth.uid()
      and coalesce(public.normalise_exercise_name(s.exercise_name), '') <> ''
  ),
  meta as (
    select
      key,
      max(started_at) as last_performed_at,
      count(distinct workout_id)::int as session_count,
      (array_agg(display order by started_at desc, display))[1] as display
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
  order by m.last_performed_at desc, m.display;
$$;

revoke execute on function gym_exercise_records() from public;
grant  execute on function gym_exercise_records() to authenticated;

create or replace function gym_exercise_set_history(p_name text)
returns table (
  workout_id uuid,
  started_at timestamptz,
  exercise_name text,
  reps integer,
  weight_kg numeric,
  rpe numeric,
  duration_s integer,
  set_type text
)
language sql
stable
security invoker
set search_path = public
as $$
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
    and public.normalise_exercise_name(s.exercise_name)
      = public.normalise_exercise_name(p_name);
$$;

revoke execute on function gym_exercise_set_history(text) from public;
grant  execute on function gym_exercise_set_history(text) to authenticated;

create or replace function gym_exercise_set_history_batch(p_names text[])
returns table (
  normalised_name text,
  workout_id uuid,
  started_at timestamptz,
  exercise_name text,
  reps integer,
  weight_kg numeric,
  rpe numeric,
  duration_s integer,
  set_type text
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    public.normalise_exercise_name(s.exercise_name) as normalised_name,
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
    and public.normalise_exercise_name(s.exercise_name) in (
      select public.normalise_exercise_name(n)
      from unnest(coalesce(p_names, '{}'::text[])) as n
      where coalesce(public.normalise_exercise_name(n), '') <> ''
    );
$$;

revoke execute on function gym_exercise_set_history_batch(text[]) from public;
grant  execute on function gym_exercise_set_history_batch(text[]) to authenticated;

create or replace function gym_workout_summaries(p_limit integer default 100)
returns table (
  workout_id uuid,
  exercise_count integer,
  is_pr boolean
)
language sql
stable
security invoker
set search_path = public
as $$
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
      public.normalise_exercise_name(s.exercise_name) as key,
      s.reps,
      s.weight_kg
    from gym_sets s
    join mine m on m.id = s.workout_id
    where coalesce(public.normalise_exercise_name(s.exercise_name), '') <> ''
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
$$;

revoke execute on function gym_workout_summaries(integer) from public;
grant  execute on function gym_workout_summaries(integer) to authenticated;

-- ── Backfill the two persisted keys ─────────────────────────────────────────
-- Every writer of both columns stamps `normaliseExerciseName(<the name it
-- stores>)`, and the client rule is unchanged by this migration, so a key
-- written by a conforming client already equals the canonical derivation and
-- the predicate matches nothing. The pass exists because "already equals" is a
-- claim about every client build that ever wrote a row, which is not a claim a
-- migration can verify — and a wrong grouping key silently splits a lifter's
-- history rather than failing.
--
-- Batched by primary key so each statement holds row locks briefly instead of
-- one statement locking every matching row for its whole duration. Both tables
-- are bounded (one row per exercise per routine / per custom catalogue entry),
-- so this is the cheap end of the playbook, but the batching costs nothing.
do $$
declare
  batch_size constant integer := 1000;
  touched integer;
begin
  loop
    with candidates as (
      select id
      from public.gym_routine_exercises
      where exercise_key is distinct from public.normalise_exercise_name(exercise_name)
        and coalesce(public.normalise_exercise_name(exercise_name), '') <> ''
      order by id
      limit batch_size
    )
    update public.gym_routine_exercises t
    set exercise_key = public.normalise_exercise_name(t.exercise_name)
    from candidates c
    where t.id = c.id;
    get diagnostics touched = row_count;
    exit when touched = 0;
  end loop;

  loop
    with candidates as (
      select id
      from public.exercises
      where name_key is distinct from public.normalise_exercise_name(name)
        and coalesce(public.normalise_exercise_name(name), '') <> ''
      order by id
      limit batch_size
    )
    update public.exercises t
    set name_key = public.normalise_exercise_name(t.name)
    from candidates c
    where t.id = c.id;
    get diagnostics touched = row_count;
    exit when touched = 0;
  end loop;
end;
$$;

-- ── Make the invariant the database's, not the clients' ─────────────────────
-- The key was a convention four surfaces had to remember. A stored key that
-- disagrees with its own name is now rejected at the boundary instead of
-- quietly splitting a lifter's history into two buckets.
--
-- NOT VALID first (instant metadata flip; new and updated rows are enforced
-- immediately), then VALIDATE, which scans under SHARE UPDATE EXCLUSIVE.
alter table public.gym_routine_exercises
  add constraint gym_routine_exercises_exercise_key_canonical
  check (exercise_key = public.normalise_exercise_name(exercise_name))
  not valid;

alter table public.exercises
  add constraint exercises_name_key_canonical
  check (name_key = public.normalise_exercise_name(name))
  not valid;

alter table public.gym_routine_exercises
  validate constraint gym_routine_exercises_exercise_key_canonical;

alter table public.exercises
  validate constraint exercises_name_key_canonical;
