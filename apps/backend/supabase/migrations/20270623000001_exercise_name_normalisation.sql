-- One definition of exercise-name normalisation, on the rail that persists it.
-- decisions.md § 790.
--
-- `gym_routine_exercises.exercise_key` and `exercises.name_key` are STORED
-- grouping keys. Until now three rails derived them and no two agreed:
--
--   web    gym_prs.ts#normaliseExerciseName  — an explicit whitespace class,
--          JS `toLowerCase()` (FULL case folding).
--   mobile gym_prs.dart#normaliseExerciseName — the same explicit class,
--          Dart `toLowerCase()` (SIMPLE case folding).
--   sql    `regexp_replace(lower(btrim(name)), '\s+', ' ', 'g')`, inlined into
--          four live functions.
--
-- The SQL form is wrong twice over, and both are reachable from a paste:
--
--   * `btrim(text)` with no second argument strips ONLY U+0020. A leading tab
--     therefore survives it and is then turned into a leading SPACE by the
--     `\s+` collapse, so "<TAB>Bench Press" keys as " bench press" on the
--     server and "bench press" on both clients. Every non-space whitespace
--     character at either end of a name hits this — tab, newline, CR, NBSP,
--     an em space pasted out of a spreadsheet.
--   * `\s` is `[[:space:]]`, whose membership above U+007F is decided by the
--     database's ctype rather than by us. Measured under en_US.UTF-8 it
--     matches U+00A0/U+1680/U+2000-200A/U+2028/U+2029/U+202F/U+205F/U+3000 but
--     NOT U+0085 or U+FEFF, both of which the clients fold. A key whose value
--     depends on the server's locale is not a key.
--
-- So the class is spelled out here by code point, exactly as both clients
-- spell it out, and `btrim` is given the space explicitly. Nothing in this
-- function consults the ctype, which is what makes it `immutable` in fact and
-- not merely by declaration.
--
-- `normalise_exercise_name` is the weaker of the two and it is the one the
-- CHECK below references, because its trailing `lower()` resolves through the
-- database's ctype above ASCII. Postgres declares `lower(text)` IMMUTABLE by
-- convention rather than in fact, so a libc or ICU upgrade that moves the fold
-- for a code point present in a stored `exercise_name` leaves an
-- already-validated row violating `gym_routine_exercises_key_normalised_chk`,
-- and the next UPDATE of that row raises 23514. The residual is bounded to the
-- code points named below and is filed rather than claimed away -- hoisting it
-- into the constraint means pre-mapping every one of them, which trades a
-- measured 197-code-point exposure for a large table on three rails.
--
-- The one case fold we refuse to leave to the runtime is applied before
-- `lower()`: U+0130 (Turkish dotted capital I) and the four titlecase digraphs
-- are the code points where JS full-case-folding, Dart's simple folding and
-- libc's `towlower` were measured to disagree. Everything else is each rail's
-- own `lower()`; the residual is confined to Cherokee, Coptic, Glagolitic,
-- Georgian Mtavruli and Cyrillic/Latin Extended-B additions, and is recorded
-- rather than claimed away.

create or replace function public.collapse_exercise_whitespace(p_name text)
returns text
language sql
immutable
parallel safe
as $$
  -- The class, by code point: U+0009 U+000A U+000B U+000C U+000D U+0020
  -- U+0085 U+00A0 U+1680 U+2000..U+200A U+2028 U+2029 U+202F U+205F U+3000
  -- U+FEFF. Written as chr() so the source stays ASCII and every member is
  -- legible as a number rather than as an invisible character.
  select btrim(
    regexp_replace(
      coalesce(p_name, ''),
      '[' || chr(9) || chr(10) || chr(11) || chr(12) || chr(13) || chr(32)
          || chr(133) || chr(160) || chr(5760)
          || chr(8192) || '-' || chr(8202)
          || chr(8232) || chr(8233) || chr(8239) || chr(8287)
          || chr(12288) || chr(65279) || ']+',
      ' ',
      'g'),
    ' ');
$$;

comment on function public.collapse_exercise_whitespace(text) is
  'Folds every whitespace code point the clients fold to a single space and trims. decisions.md § 790.';

create or replace function public.normalise_exercise_name(p_name text)
returns text
language sql
immutable
parallel safe
as $$
  select lower(
    translate(
      public.collapse_exercise_whitespace(p_name),
      chr(304) || chr(453) || chr(456) || chr(459) || chr(498),
      chr(105) || chr(454) || chr(457) || chr(460) || chr(499)));
$$;

-- Both helpers keep postgres's default PUBLIC execute, as the other pure text
-- helpers do: a CHECK constraint's expression is ACL-checked against the role
-- WRITING the row, so revoking here would have to be undone by a grant to every
-- role that can insert a routine exercise. They read no data.
comment on function public.normalise_exercise_name(text) is
  'The exercise grouping key: whitespace folded, the five runtime-divergent case mappings applied by hand, then lower(). Twin of normaliseExerciseName in gym_prs.ts / gym_prs.dart. decisions.md § 790.';

-- ── The four live readers, now deriving the key in one place ────────────────

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
      normalise_exercise_name(s.exercise_name) as key,
      collapse_exercise_whitespace(s.exercise_name) as display,
      s.reps,
      s.weight_kg,
      s.workout_id,
      gw.started_at
    from gym_sets s
    join gym_workouts gw on gw.id = s.workout_id
    where gw.user_id = auth.uid()
      and normalise_exercise_name(s.exercise_name) <> ''
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
      round(max(case when reps is not null and reps > 0 then weight_kg * reps end), 1)
        as best_volume_kg,
      round(max(case when reps is not null and reps > 0
                     then case when reps = 1 then weight_kg
                               else weight_kg * (1 + least(reps, 12)::numeric / 30) end
                end), 1) as best_est_1rm_kg
    from weighted
    group by key
  ),
  heaviest_reps as (
    select distinct on (key) key, reps as heaviest_weight_reps
    from weighted
    order by key, weight_kg desc, reps desc nulls last
  )
  select
    m.display as exercise_name,
    b.heaviest_weight_kg,
    hr.heaviest_weight_reps,
    b.best_volume_kg,
    b.best_est_1rm_kg,
    m.last_performed_at,
    m.session_count
  from meta m
  join bests b on b.key = m.key
  join heaviest_reps hr on hr.key = m.key
  order by m.last_performed_at desc, m.display;
$$;

revoke execute on function gym_exercise_records() from public;
grant  execute on function gym_exercise_records() to authenticated;

drop function if exists gym_exercise_set_history(text);

create function gym_exercise_set_history(p_name text)
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
    and normalise_exercise_name(s.exercise_name) = normalise_exercise_name(p_name)
    and normalise_exercise_name(p_name) <> '';
$$;

revoke execute on function gym_exercise_set_history(text) from public;
grant  execute on function gym_exercise_set_history(text) to authenticated;

drop function if exists gym_exercise_set_history_batch(text[]);

create function gym_exercise_set_history_batch(p_names text[])
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
    normalise_exercise_name(s.exercise_name) as normalised_name,
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
    and normalise_exercise_name(s.exercise_name) in (
      select normalise_exercise_name(n)
      from unnest(coalesce(p_names, '{}'::text[])) as n
      where normalise_exercise_name(n) <> ''
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
      normalise_exercise_name(s.exercise_name) as key,
      s.reps,
      s.weight_kg
    from gym_sets s
    join mine m on m.id = s.workout_id
    where normalise_exercise_name(s.exercise_name) <> ''
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

-- The autocomplete datalist stays deliberately CASE-preserving — "Bench Press"
-- and "bench press" are two suggestions on purpose, so the editor offers back
-- the spelling the lifter actually types. Only its whitespace half was wrong,
-- and by the same `btrim` defect: a tab-suffixed name was a separate suggestion
-- carrying an invisible tab. Group on the collapsed display name, not on the
-- normalised key.
create or replace function gym_exercise_names()
returns table (
  exercise_name text,
  uses integer
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    collapse_exercise_whitespace(s.exercise_name) as exercise_name,
    count(*)::int as uses
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where gw.user_id = auth.uid()
    and collapse_exercise_whitespace(s.exercise_name) <> ''
  group by collapse_exercise_whitespace(s.exercise_name)
  order by count(*) desc, collapse_exercise_whitespace(s.exercise_name);
$$;

revoke execute on function gym_exercise_names() from public;
grant  execute on function gym_exercise_names() to authenticated;

-- ── The persisted key: the server stamps it, the clients no longer decide ───

-- `exercise_key` arrived from whichever client wrote the row, which is what let
-- the three rails disagree about a STORED value in the first place. A client
-- still sends one (the offline routine store has no database to ask), and it is
-- now overwritten rather than trusted.
create or replace function stamp_exercise_key()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.exercise_key := normalise_exercise_name(new.exercise_name);
  return new;
end;
$$;

revoke execute on function stamp_exercise_key() from public, authenticated;

create trigger gym_routine_exercises_stamp_key
  before insert or update of exercise_name, exercise_key
  on public.gym_routine_exercises
  for each row execute function stamp_exercise_key();

create or replace function stamp_exercise_name_key()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.name_key := normalise_exercise_name(new.name);
  return new;
end;
$$;

revoke execute on function stamp_exercise_name_key() from public, authenticated;

create trigger exercises_stamp_name_key
  before insert or update of name, name_key
  on public.exercises
  for each row execute function stamp_exercise_name_key();

-- Scoped to the rows that are actually wrong, per migration_locks.md § Large
-- backfills. `gym_routine_exercises` is a bounded per-routine child table and
-- is not in the guarded high-volume set, so this is the inline case the
-- playbook allows; chunking it inside a migration's single transaction would
-- hold the same locks to commit either way and buy nothing.
update public.gym_routine_exercises
set exercise_key = normalise_exercise_name(exercise_name)
where exercise_key is distinct from normalise_exercise_name(exercise_name);

-- NOT VALID first (no scan, brief lock), then VALIDATE under SHARE UPDATE
-- EXCLUSIVE so writers proceed through the scan.
alter table public.gym_routine_exercises
  add constraint gym_routine_exercises_key_normalised_chk
  check (exercise_key = normalise_exercise_name(exercise_name)) not valid;

alter table public.gym_routine_exercises
  validate constraint gym_routine_exercises_key_normalised_chk;

-- `exercises` gets the trigger but no constraint and no backfill. Its two
-- partial UNIQUE indexes on `name_key` mean a re-key can collide with a
-- sibling row, and merging two catalogue entries is a data decision rather
-- than something a migration may take on a user's behalf. The seeded globals
-- are ASCII and already agree.
