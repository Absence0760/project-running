-- The other two exercise-key columns are stamped by the server too.
--
-- `gym_sets.exercise_key` is derived by a BEFORE INSERT OR UPDATE trigger
-- (20270706000001), whose comment records that it "stamps unconditionally, so a
-- client-supplied exercise_key is replaced rather than rejected".
-- `gym_routine_exercises.exercise_key` and `exercises.name_key` are the same
-- key on the same vocabulary, and they were left the other way round: the
-- client computes the value and a VALIDATED CHECK REFUSES it when it disagrees
-- with `public.normalise_exercise_name(<name>)`.
--
-- That refusal is a client-VERSION coupling, not a client-correctness one. The
-- fold is a frozen Unicode table on three rails since 20270709000010
-- (decisions § 1175), so a client whose build predates a widening of that table
-- computes a different key for a code point the server now folds and gets a
-- 23514 on a legitimate save. Measured at the time: 410 such code points before
-- § 1175, 465 after, 55 of them newly so (decisions § 1252). Reaching one means
-- naming a lift in Cherokee, Georgian Mtavruli, Deseret, Adlam, Garay,
-- Medefaidrin, Vithkuqi or Sidetic on a stale build -- narrow, but the number
-- is only ever zero when the server derives the key itself, and every future
-- change to the table re-opens it.
--
-- Stamping turns each of those refusals into a silent correction. The two
-- CHECKs stay exactly as they are: with the trigger in front of them nothing
-- can violate them, so they cost a per-row expression evaluation on write and
-- buy the guarantee that a disabled or dropped trigger fails loudly instead of
-- quietly splitting a lifter's history. That is the same belt-and-braces shape
-- `gym_sets` carries.
--
-- ── No backfill, and that is a proof rather than an assumption ──────────────
-- `gym_routine_exercises_exercise_key_canonical` and
-- `exercises_name_key_canonical` are both VALIDATED (20270709000010 re-proved
-- them after moving the fold). A validated CHECK is a statement about every row
-- in the table, so `exercise_key = normalise_exercise_name(exercise_name)`
-- already holds for all of them and a backfill would touch nothing. The pgtap
-- suite asserts `convalidated` rather than trusting this note.
--
-- ── Lock impact (migration_locks.md) ───────────────────────────────────────
-- `CREATE TRIGGER` takes SHARE ROW EXCLUSIVE: catalogue-only, blocks concurrent
-- writers on that one table for an O(1) change and lets every reader through.
-- `ALTER COLUMN ... SET DEFAULT` takes a brief ACCESS EXCLUSIVE and is
-- catalogue-only as well -- a default is stored in `pg_attrdef` and existing
-- rows are not read, let alone rewritten (this is not `ADD COLUMN`, where the
-- constant-default fast path is the thing being relied on). Neither table is on
-- the high-volume list.

-- ── gym_routine_exercises.exercise_key ─────────────────────────────────────

-- Unqualified `before insert or update`, not `update of exercise_name`, for the
-- reason 20270706000001 gives: the narrower form leaves an UPDATE that names
-- only `exercise_key` unstamped, and the CHECK would then refuse it with a
-- 23514 the client cannot act on.
--
-- SECURITY INVOKER: the body reads NEW and folds a string, so it needs no
-- privilege of its own. The writing role needs EXECUTE on
-- `normalise_exercise_name`, which `authenticated` and `service_role` hold and
-- `anon` does not -- and RLS lets `anon` write no row of either table.
create or replace function public.gym_routine_exercises_stamp_exercise_key()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.exercise_key := public.normalise_exercise_name(new.exercise_name);
  return new;
end;
$$;

comment on function public.gym_routine_exercises_stamp_exercise_key() is
  'BEFORE INSERT OR UPDATE trigger on gym_routine_exercises: derives exercise_key from exercise_name so the persisted key can never disagree with the name it groups. Stamps unconditionally, so a client-supplied exercise_key is replaced rather than rejected.';

drop trigger if exists gym_routine_exercises_stamp_exercise_key_trigger
  on public.gym_routine_exercises;
create trigger gym_routine_exercises_stamp_exercise_key_trigger
  before insert or update on public.gym_routine_exercises
  for each row execute function public.gym_routine_exercises_stamp_exercise_key();

-- The column is NOT NULL with no default, which makes it REQUIRED in the
-- `Insert` type the row-type generators emit -- so a client is still obliged to
-- compute a key the server now derives. A constant default is what releases
-- that obligation, and it is never a value any row keeps: the trigger overwrites
-- it on the same statement. `''` would fail the column's own
-- `length(exercise_key) between 1 and 120` CHECK if the trigger were ever gone,
-- which is the loud failure this shape wants. Same call as
-- `gym_sets.exercise_key`.
alter table public.gym_routine_exercises
  alter column exercise_key set default '';

comment on column public.gym_routine_exercises.exercise_key is
  'The exercise grouping key for this planned exercise: public.normalise_exercise_name(exercise_name), stamped by the gym_routine_exercises_stamp_exercise_key trigger on every insert and update. Server-derived, never supplied by a client -- a client value is overwritten rather than refused.';

-- ── exercises.name_key ─────────────────────────────────────────────────────

create or replace function public.exercises_stamp_name_key()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.name_key := public.normalise_exercise_name(new.name);
  return new;
end;
$$;

comment on function public.exercises_stamp_name_key() is
  'BEFORE INSERT OR UPDATE trigger on exercises: derives name_key from name so the persisted key can never disagree with the name it groups. Stamps unconditionally, so a client-supplied name_key is replaced rather than rejected.';

drop trigger if exists exercises_stamp_name_key_trigger on public.exercises;
create trigger exercises_stamp_name_key_trigger
  before insert or update on public.exercises
  for each row execute function public.exercises_stamp_name_key();

alter table public.exercises
  alter column name_key set default '';

comment on column public.exercises.name_key is
  'The exercise grouping key for this catalogue entry: public.normalise_exercise_name(name), stamped by the exercises_stamp_name_key trigger on every insert and update. Server-derived, never supplied by a client -- a client value is overwritten rather than refused. The two partial unique indexes over it are therefore uniqueness on the FOLDED name.';
