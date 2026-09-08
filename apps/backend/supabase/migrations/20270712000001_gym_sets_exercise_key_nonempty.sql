-- The `>= 1` half `gym_sets.exercise_key` never had.
--
-- The three columns that persist an exercise grouping key are meant to carry
-- the same invariant, and one of them did not. `gym_routine_exercises.
-- exercise_key` (20270101_001) and `exercises.name_key` (20270222_001) both
-- carry `length(...) between 1 and 120`; `gym_sets.exercise_key` came out of
-- 20270706000002 with the canonical equality and a `<= 120` cap and no floor,
-- and that migration recorded the omission as deliberate -- "a name that is
-- only whitespace passes `gym_sets_exercise_name_check` and folds to the empty
-- key, which is exactly the value the readers below filter out".
--
-- Filtering it out is what makes it wrong. A set whose key is empty is a row
-- the database holds and every read denies: `gym_exercise_names`,
-- `gym_exercise_records`, `gym_exercise_set_history`,
-- `gym_exercise_set_history_batch` and `gym_workout_summaries` all skip it on
-- `exercise_key <> ''`, `routineFromWorkout` drops it, `distinctExerciseCount`
-- counts it as nothing -- while the gym editor renders it and
-- `gym_workouts.set_count` counts it. Decisions § 1367 closed the web and
-- mobile paths that MINTED such a row, so nothing this repo ships creates one
-- any more; the database still accepts one from any other client, and the
-- asymmetry above is why. This is the floor, on the third column.
--
-- ── Why the key and not the name ────────────────────────────────────────────
-- `check (normalise_exercise_name(exercise_name) <> '')` is the same test
-- written against the column the client actually supplied, and it would give a
-- more legible 23514. It is not what the two sibling columns say, and the value
-- of this constraint is that all three now say one thing about one idea. The
-- legibility is bought back by the constraint's NAME -- `nonempty` rather than
-- a second `_len_chk` -- and by the comment below, which is what a reader
-- chasing a 23514 through `pg_constraint` finds.
--
-- ── Lock impact (migration_locks.md) ────────────────────────────────────────
-- `ADD CONSTRAINT ... NOT VALID` takes ACCESS EXCLUSIVE for a catalogue flip
-- and runs no scan, so it is instant on a table of any size. Every insert and
-- every update is enforced from the moment it commits; the existing rows are
-- outside the claim until 20270712000002 validates it. The split is across
-- files because a `VALIDATE` in this one would scan under the ACCESS EXCLUSIVE
-- this statement is still holding, which is the whole of what the playbook's
-- two-step buys. `gym_sets` is not in the guard's GUARDED_TABLES, so nothing
-- forces the shape here -- it is the highest-volume gym table and the shape is
-- right on its own terms.

alter table public.gym_sets
  add constraint gym_sets_exercise_key_nonempty_chk
    check (length(exercise_key) >= 1) not valid;

comment on constraint gym_sets_exercise_key_nonempty_chk on public.gym_sets is
  'The exercise grouping key names an exercise. exercise_key is server-derived (gym_sets_stamp_exercise_key), so a row reaches this constraint with an empty key only when exercise_name is entirely whitespace -- the class public.normalise_exercise_name folds, which is Unicode White_Space plus U+FEFF. Such a set is excluded from every read-side aggregate while still counting toward gym_workouts.set_count, so it is refused rather than stored. Mirrors the >= 1 half of gym_routine_exercises_exercise_key_check and exercises_name_key_check.';
