-- Persist the exercise grouping key on `gym_sets`, stamped by the server.
--
-- The key is derived once per `gym_sets` row on every read today: five live
-- RPCs call `public.normalise_exercise_name(s.exercise_name)` inside the scan
-- (decisions § 790 named four; `gym_exercise_names` joined them in
-- 20270630000004). That is what makes the remaining half of the key's
-- portability defect unaffordable — the three rails still disagree at 465 code
-- points because each runtime carries its own Unicode case table, and the fix
-- is a frozen 1,488-entry `translate()` table costing 60 us a call against
-- 0.34 us for `lower()`. Paid per row on every read, a 15,000-set history would
-- spend ~0.9 s of pure folding per `gym_workout_summaries()` call. Paid once
-- per WRITE, it disappears.
--
-- This migration is the first half of moving that cost: the column and the
-- trigger that keeps it true. It reads nothing and changes no answer. The
-- backfill, the constraints and the five RPCs are 20270706000002, so the
-- catalogue-only work here commits and releases its locks before the long half
-- starts (`supabase db push` applies each file in its own transaction).
--
-- ── Why a trigger and not a generated column ───────────────────────────────
-- `generated always as (public.normalise_exercise_name(exercise_name)) stored`
-- says exactly what is meant and needs no trigger, and it was rejected on two
-- measurements taken on PG 17.6 against a 500,000-row copy of this table:
--
--   * Adding it REWRITES the table. Measured: 2,756 ms holding ACCESS
--     EXCLUSIVE **and** ShareLock, with `pg_relation_filenode` moving
--     28885 -> 28895. The plain `add column exercise_key text` below took
--     5 ms and left the filenode alone. The rewrite is ~5.5 us/row and linear,
--     so a 5,000,000-row `gym_sets` is ~28 s during which no session can read
--     or write a set. That is downtime, and `gym_sets` is the highest-volume
--     gym table.
--
--   * A generated column freezes its expression into the catalogue and
--     Postgres never recomputes stored values when the function underneath is
--     replaced. The whole point of persisting the key is to make the NEXT
--     change to `normalise_exercise_name` affordable; with a generated column
--     that change is a `drop expression` plus a second full rewrite, where the
--     trigger makes it a `create or replace function` plus the batched
--     backfill this migration's sibling already establishes.
--
-- The trigger's write cost was measured too: 50,000 single-statement inserts
-- took 146 ms without it and 462 ms with it, +6.3 us a row. A logged gym
-- session is 10-40 sets, so it is a quarter of a millisecond on a save.
--
-- The `default ''` is not a value any row ever keeps -- the trigger overwrites
-- it on the same statement. It is there because a NOT NULL column with no
-- default is REQUIRED in the `Insert` type both row-type generators emit, and a
-- client must not have to compute a key the server derives. It is the shape
-- every trigger-maintained column in this schema already carries
-- (`gym_workouts.set_count`, `clubs.member_count`, `challenges.participant_count`
-- are all `default 0` + NOT NULL), and a CONSTANT default is still the
-- no-rewrite fast path.
--
-- Lock impact (migration_locks.md): `ADD COLUMN` with a constant default is the
-- metadata-only fast path (measured 5 ms, no rewrite). `CREATE TRIGGER` takes
-- SHARE ROW EXCLUSIVE — catalogue-only, blocks concurrent writers on this table
-- alone for an O(1) change and lets every reader through, the same call
-- 20270608_001 made. Nullable on purpose: the column cannot be NOT NULL until
-- the existing rows are stamped, which is the sibling migration's job.

alter table public.gym_sets add column exercise_key text default '';

comment on column public.gym_sets.exercise_key is
  'The exercise grouping key for this set: public.normalise_exercise_name(exercise_name), stamped by the gym_sets_stamp_exercise_key trigger on every insert and update. Server-derived, never supplied by a client -- a client value is overwritten rather than refused. Read by gym_exercise_names, gym_exercise_records, gym_exercise_set_history, gym_exercise_set_history_batch and gym_workout_summaries instead of re-deriving the key per row.';

-- Unqualified `before insert or update`, not `update of exercise_name`. The
-- narrower form is cheaper and leaves a hole: an UPDATE that names only
-- `exercise_key` would not fire it, and the canonical CHECK would then refuse
-- the write with a 23514 the client cannot act on. Stamping unconditionally
-- makes the column derived in fact as well as in name, so no client is ever
-- asked to compute it -- which is the difference from the
-- `gym_routine_exercises.exercise_key` precedent, where the client stamps the
-- key and mobile's older Unicode case table can therefore produce a 23514 on a
-- legitimate save (decisions § 830).
--
-- SECURITY INVOKER: the function only reads NEW and folds a string, so it needs
-- no privilege of its own. The writing role needs EXECUTE on
-- `normalise_exercise_name`, which `authenticated` and `service_role` hold and
-- `anon` does not -- and RLS lets `anon` write no row of this table.
create or replace function public.gym_sets_stamp_exercise_key()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.exercise_key := public.normalise_exercise_name(new.exercise_name);
  return new;
end;
$$;

comment on function public.gym_sets_stamp_exercise_key() is
  'BEFORE INSERT OR UPDATE trigger on gym_sets: derives exercise_key from exercise_name so the persisted key can never disagree with the name it groups. Stamps unconditionally, so a client-supplied exercise_key is replaced rather than rejected.';

create trigger gym_sets_stamp_exercise_key_trigger
  before insert or update on public.gym_sets
  for each row execute function public.gym_sets_stamp_exercise_key();
