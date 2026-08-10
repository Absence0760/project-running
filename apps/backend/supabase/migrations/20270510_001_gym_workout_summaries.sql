-- The per-workout PR flag and exercise count, aggregated server-side.
--
-- /gym called fetchGymSetHistoryWithError() with no window — deliberately, per
-- its doc comment: the per-workout PR badge is an all-time question ("did this
-- workout beat everything logged before it?") and a windowed read cannot
-- answer it. The defect was the other end. PostgREST caps an unbounded SELECT
-- at 1000 rows, so a lifter past ~1000 logged sets (roughly 40 sessions of 25)
-- silently got a truncated history in no defined order, and every value the
-- page derived from it went quietly wrong: PR badges on workouts that set
-- nothing, no badge on workouts that did, and per-row stats reading zero for
-- whatever fell off the end.
--
-- The durable fix is the one gym_exercise_records (20261224_001) and
-- gym_exercise_names (20261226_001) already established for the other two
-- surfaces that used to recompute over raw set history: aggregate in SQL and
-- return one row per workout. With this in place /gym reads no raw sets at
-- all — its volume / set-count stats come from the trigger-maintained
-- gym_workouts.volume_kg / set_count columns (20261214_001), its autocomplete
-- from gym_exercise_names(), and the two values below from here.
--
-- Recompute-on-read (no stored cache, so it cannot drift from gym_sets) and
-- SECURITY INVOKER, so the owner-only gym_workouts / gym_sets RLS scopes it to
-- the caller — plus an explicit auth.uid() filter for clarity, matching
-- gym_exercise_records.

-- One row per workout the /gym list shows. `p_limit` bounds the rows returned;
-- the PR judgement always runs over the caller's ENTIRE history, because that
-- is the question the badge asks. That is also a fix: the client walked only
-- the 100 workouts it had fetched, so a PR set 101 workouts ago failed to
-- suppress a badge, and /gym disagreed with /gym/[id] (which judges against
-- all-time via fetchExerciseSetHistoryBatch).
--
-- exercise_count is the distinct exercise names in the workout, normalised
-- (trim -> lowercase -> collapse internal whitespace) as everywhere else in
-- the gym engine. A whitespace-only name passes the length(1..120) CHECK on
-- gym_sets.exercise_name; it is work performed, so it stays in the stored
-- set_count / volume_kg, but it is not an exercise and never sets a PR.
--
-- is_pr mirrors gym_prs.ts#RunningPrTracker (and its Dart twin): walk the
-- caller's workouts oldest -> newest and flag one when, for any single
-- exercise, its best single-set weight, best single-set volume, or best Epley
-- e1rm strictly beats every earlier workout's — an exercise with no earlier
-- set being a PR by definition. Volume and e1rm are rounded to 1 dp on both
-- sides of the comparison, as round1() does in gym_prs.ts, and the e1rm of a
-- true single is the weight lifted rather than Epley's 3.3% inflation. Ties in
-- started_at are broken by id so two workouts stamped at the same instant
-- judge deterministically.
--
-- The PR definition MUST stay in lockstep with gym_prs.ts. gym_workout_
-- summaries_test.sql and gym_workout_summaries.test.ts build the same fixture
-- and assert the same expected answer, one by calling this function and one by
-- running the real RunningPrTracker.
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
      regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g') as key,
      s.reps,
      s.weight_kg
    from gym_sets s
    join mine m on m.id = s.workout_id
    where btrim(coalesce(s.exercise_name, '')) <> ''
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

-- Has the caller ever logged a set carrying a positive weight? Gates the
-- Records link on /gym, since /gym/records only surfaces weighted exercises.
-- All-time and exists-early-exit, so it stays honest for a lifter whose last
-- weighted session was further back than the list page shows — which is
-- exactly the case a per-page flag would get wrong.
create or replace function gym_has_weighted_sets()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from gym_sets s
    join gym_workouts gw on gw.id = s.workout_id
    where gw.user_id = auth.uid()
      and s.weight_kg is not null
      and s.weight_kg > 0
  );
$$;

revoke execute on function gym_has_weighted_sets() from public;
grant  execute on function gym_has_weighted_sets() to authenticated;
