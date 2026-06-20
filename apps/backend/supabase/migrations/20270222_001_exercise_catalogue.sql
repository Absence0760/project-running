-- Exercise catalogue — a structured exercise table the gym log can bind to,
-- replacing nothing. The gym depth-tier "mid" (Strong-app territory) first
-- bullet (roadmap.md § Depth tiers / Gym — mid). Deliberately ADDITIVE:
--
--   * gym_sets keeps free-text `exercise_name` (+ history autocomplete) exactly
--     as today. A new NULLABLE `exercise_id` FK references this catalogue. A
--     logged set may reference a catalogue entry OR stay pure free-text — never
--     required. This preserves every existing logged set and the offline-first
--     LocalGymStore path (which has no catalogue and writes exercise_id null).
--   * `exercises` carries a starter set of common compounds + isolations +
--     cardio seeded with author_id NULL (global, read-only for everyone). An
--     authenticated user may add their OWN custom entries (author_id = them).
--
-- PR computation (gym_prs) stays keyed on normaliseExerciseName(exercise_name)
-- — the catalogue link is provenance, not the grouping key, so existing PRs are
-- untouched whether a set is bound or free-text.

-- ── exercises — the catalogue (seeded globals + owner-created customs) ───────
create table public.exercises (
  id              uuid primary key default gen_random_uuid(),

  -- NULL = a seeded global row, readable by every authenticated user and not
  -- personal data. A non-null author_id is an owner-created custom entry,
  -- readable + writable only by that owner, and IS the subject's Art-20 data.
  author_id       uuid references auth.users (id) on delete cascade,

  name            text not null check (length(name) between 1 and 120),

  -- normalised key (lower/trim/collapse-whitespace) so a catalogue entry binds
  -- to logged gym_sets by the SAME identity gym_prs / gym_routine_exercises use.
  -- Stamped at write time; mirrors gym_routine_exercises.exercise_key.
  name_key        text not null check (length(name_key) between 1 and 120),

  -- muscle group / category (narrow union ↔ CHECK pair)
  category        text not null default 'other'
                    check (category in
                      ('chest','back','shoulders','legs','arms','core','cardio','full_body','other')),

  -- exercise modality (narrow union ↔ CHECK pair); mirrors
  -- gym_routine_exercises.modality so a catalogue pick can seed a routine.
  modality        text not null default 'weight_reps'
                    check (modality in ('weight_reps','time','distance','bodyweight_reps')),

  external_id     text check (external_id is null or length(external_id) <= 120),
  last_modified_at timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

-- A seeded global is unique by name_key (author_id null); a user's customs are
-- unique by name_key within their own set. Two partial uniques keep the two
-- namespaces independent (a user may shadow a global name with a custom one).
create unique index exercises_global_name_key
  on public.exercises (name_key) where author_id is null;
create unique index exercises_author_name_key
  on public.exercises (author_id, name_key) where author_id is not null;

-- The autocomplete read path: a user sees globals + their own customs, looked
-- up by name_key. category-filtered browse uses the same index prefix.
create index exercises_author_idx on public.exercises (author_id);
create index exercises_name_key_idx on public.exercises (name_key);

comment on table public.exercises is
  'Structured exercise catalogue. author_id NULL = seeded global (read-only, not personal data); author_id set = an owner-created custom entry. gym_sets.exercise_id is a NULLABLE link into this table — free-text logging still works with exercise_id null.';

-- ── gym_sets.exercise_id — the NULLABLE link ────────────────────────────────
-- on delete set null: deleting a custom catalogue entry must NOT erase the
-- logged set (history is immutable) — it just drops the provenance link and
-- the set reverts to pure free-text via its retained exercise_name.
alter table public.gym_sets
  add column exercise_id uuid references public.exercises (id) on delete set null;

comment on column public.gym_sets.exercise_id is
  'Optional link to a public.exercises catalogue entry. NULL for free-text sets (the default). exercise_name is always populated regardless; the link is provenance, not the PR grouping key.';

create index gym_sets_exercise_id_idx
  on public.gym_sets (exercise_id) where exercise_id is not null;

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- Read: any authenticated user reads seeded globals (author_id is null) OR
-- their own customs. Write: only against your own customs — no one can mutate a
-- seeded global, and you can't create a row owned by someone else.
alter table public.exercises enable row level security;

create policy "exercises read globals and own customs"
  on public.exercises for select
  using (author_id is null or author_id = auth.uid());

create policy "exercises owner insert custom"
  on public.exercises for insert
  with check (author_id = auth.uid());

create policy "exercises owner update custom"
  on public.exercises for update
  using (author_id = auth.uid()) with check (author_id = auth.uid());

create policy "exercises owner delete custom"
  on public.exercises for delete
  using (author_id = auth.uid());

-- ── Seed: ~40 common compounds + isolations + cardio (global, author_id null) ─
-- name_key is the normalised name (lower, single-spaced). Idempotent on the
-- global partial unique index so a re-applied migration / db reset is a no-op.
insert into public.exercises (author_id, name, name_key, category, modality) values
  -- compounds (legs)
  (null, 'Back Squat',          'back squat',          'legs',      'weight_reps'),
  (null, 'Front Squat',         'front squat',         'legs',      'weight_reps'),
  (null, 'Deadlift',            'deadlift',            'legs',      'weight_reps'),
  (null, 'Romanian Deadlift',   'romanian deadlift',   'legs',      'weight_reps'),
  (null, 'Leg Press',           'leg press',           'legs',      'weight_reps'),
  (null, 'Lunge',               'lunge',               'legs',      'weight_reps'),
  (null, 'Bulgarian Split Squat','bulgarian split squat','legs',    'weight_reps'),
  (null, 'Hip Thrust',          'hip thrust',          'legs',      'weight_reps'),
  (null, 'Calf Raise',          'calf raise',          'legs',      'weight_reps'),
  (null, 'Leg Curl',            'leg curl',            'legs',      'weight_reps'),
  (null, 'Leg Extension',       'leg extension',       'legs',      'weight_reps'),
  -- compounds (chest / shoulders)
  (null, 'Bench Press',         'bench press',         'chest',     'weight_reps'),
  (null, 'Incline Bench Press', 'incline bench press', 'chest',     'weight_reps'),
  (null, 'Dumbbell Bench Press','dumbbell bench press','chest',     'weight_reps'),
  (null, 'Overhead Press',      'overhead press',      'shoulders', 'weight_reps'),
  (null, 'Dumbbell Shoulder Press','dumbbell shoulder press','shoulders','weight_reps'),
  (null, 'Push-up',             'push-up',             'chest',     'bodyweight_reps'),
  (null, 'Dip',                 'dip',                 'chest',     'bodyweight_reps'),
  -- compounds (back)
  (null, 'Pull-up',             'pull-up',             'back',      'bodyweight_reps'),
  (null, 'Chin-up',             'chin-up',             'back',      'bodyweight_reps'),
  (null, 'Lat Pulldown',        'lat pulldown',        'back',      'weight_reps'),
  (null, 'Barbell Row',         'barbell row',         'back',      'weight_reps'),
  (null, 'Dumbbell Row',        'dumbbell row',        'back',      'weight_reps'),
  (null, 'Seated Cable Row',    'seated cable row',    'back',      'weight_reps'),
  (null, 'Face Pull',           'face pull',           'back',      'weight_reps'),
  -- isolations (arms / shoulders)
  (null, 'Bicep Curl',          'bicep curl',          'arms',      'weight_reps'),
  (null, 'Hammer Curl',         'hammer curl',         'arms',      'weight_reps'),
  (null, 'Tricep Pushdown',     'tricep pushdown',     'arms',      'weight_reps'),
  (null, 'Skull Crusher',       'skull crusher',       'arms',      'weight_reps'),
  (null, 'Lateral Raise',       'lateral raise',       'shoulders', 'weight_reps'),
  (null, 'Rear Delt Fly',       'rear delt fly',       'shoulders', 'weight_reps'),
  (null, 'Chest Fly',           'chest fly',           'chest',     'weight_reps'),
  -- core
  (null, 'Plank',               'plank',               'core',      'time'),
  (null, 'Hanging Leg Raise',   'hanging leg raise',   'core',      'bodyweight_reps'),
  (null, 'Cable Crunch',        'cable crunch',        'core',      'weight_reps'),
  (null, 'Russian Twist',       'russian twist',       'core',      'bodyweight_reps'),
  -- cardio
  (null, 'Treadmill Run',       'treadmill run',       'cardio',    'distance'),
  (null, 'Stationary Bike',     'stationary bike',     'cardio',    'distance'),
  (null, 'Rowing Machine',      'rowing machine',      'cardio',    'distance'),
  (null, 'Elliptical',          'elliptical',          'cardio',    'time'),
  (null, 'Stair Climber',       'stair climber',       'cardio',    'time'),
  (null, 'Jump Rope',           'jump rope',           'cardio',    'time'),
  (null, 'Burpee',              'burpee',              'full_body', 'bodyweight_reps')
on conflict do nothing;
