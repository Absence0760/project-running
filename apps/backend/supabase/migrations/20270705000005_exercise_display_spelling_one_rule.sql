-- One question, one rule: the display spelling for an exercise key is the
-- caller's MOST RECENT one, on both RPCs that answer it.
--
-- `gym_exercise_names` (the gym editor autocomplete) picked the most-USED
-- spelling; `gym_exercise_records` (the records page) picked the most-RECENT
-- one. Both were deliberate, neither is a key, and nothing downstream broke —
-- but the two surfaces could name one exercise differently, which decisions
-- § 831 filed for a decision rather than settling.
--
-- ── What the filing's own reasoning got wrong ──────────────────────────────
-- The entry justified keeping both with "a lifter who renamed 'DB Bench' to
-- 'Dumbbell Bench Press' wants the new name on a records page and, for a
-- while, the old one in an autocomplete they have used a hundred times."
-- Measured: `normalise_exercise_name('DB Bench')` is `db bench` and
-- `normalise_exercise_name('Dumbbell Bench Press')` is `dumbbell bench press`
-- — two DIFFERENT keys. Both surfaces already list both, under both rules, and
-- the two rules cannot disagree about that case at all.
--
-- The fold is case and whitespace and nothing else (20270630000003), so the
-- competing spellings INSIDE one key differ only in capitalisation and in
-- whitespace. The real choice is between "the capitalisation you use most" and
-- "the capitalisation you used last" — and that makes most-used the wrong
-- answer for a reason stronger than consistency:
--
--   **most-used is self-reinforcing on an autocomplete.** A lifter who
--   re-capitalises "bench press" to "Bench Press" is offered the old spelling
--   by the datalist, accepts it (that is what a datalist is for), and logs
--   another set under it — so the counts never cross and the rename can never
--   take effect. Most-recent converges instead: the next session is offered
--   the new spelling, and the surface stops fighting the user.
--
-- ── The tiebreak, and why it is not just `display` ─────────────────────────
-- `gym_exercise_records` already ordered `started_at desc, display`, so its
-- RULE does not move here. Its tiebreak does. A bare `display` comparison is
-- resolved by the argument's own collation, which is the dependence § 830
-- measured and closed for the KEY: the same two spellings order differently on
-- an ICU-provider and a libc-provider database, and differently again under
-- `tr-TR`. The pick is therefore pinned to `collate "und-x-icu"`, the same
-- root locale `normalise_exercise_name` pins, and so are both RPCs' final
-- `order by` on the returned list — a cosmetic reordering between providers is
-- still a divergence between two deployments of one product.
--
-- `length(display)` sits ahead of the lexical term because the spellings that
-- reach a genuine tie (two sessions stamped the same instant) differ only in
-- whitespace or case: case variants are the same length and fall through,
-- while a spreadsheet paste carrying a leading tab or a doubled internal space
-- is longer and loses to its clean sibling. It expresses "prefer the tidy
-- spelling" without a fourth hand-written copy of the whitespace class, which
-- is the duplication § 790 exists to have removed. A group whose ONLY spelling
-- carries edge whitespace still shows it, exactly as § 831 recorded.
--
-- ── User-visible consequence, stated plainly ──────────────────────────────
-- The surface that changes is the AUTOCOMPLETE, not the records page — the
-- opposite of what the filing predicted. A lifter whose most-used
-- capitalisation differs from their most-recent one will see the suggestion
-- change to the newer spelling once. The records page's rule is untouched; only
-- its tiebreak became deterministic, which can change a display only where two
-- of a key's spellings were logged at the same instant. `uses` still counts
-- every spelling in the group, and the list is still ordered most-used first.
--
-- No table, column, constraint or grant moves — two `create or replace` bodies
-- on STABLE SQL functions, so neither row-type generator has anything to
-- regenerate and none of docs/backend/migration_locks.md's machinery applies.
-- `create or replace` preserves each function's existing ACL.

CREATE OR REPLACE FUNCTION public.gym_exercise_names()
 RETURNS TABLE(exercise_name text, uses integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with norm as (
    select
      public.normalise_exercise_name(s.exercise_name) as key,
      s.exercise_name as display,
      gw.started_at
    from gym_sets s
    join gym_workouts gw on gw.id = s.workout_id
    where gw.user_id = auth.uid()
      and coalesce(public.normalise_exercise_name(s.exercise_name), '') <> ''
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
