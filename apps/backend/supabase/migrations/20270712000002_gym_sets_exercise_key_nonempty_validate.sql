-- Second half of 20270712000001: bring the rows that were already there inside
-- the claim.
--
-- ── Lock impact (migration_locks.md) ────────────────────────────────────────
-- `VALIDATE CONSTRAINT` scans under SHARE UPDATE EXCLUSIVE, so readers and
-- writers proceed for its duration -- but only because it is in its own
-- migration, and therefore its own transaction: the ACCESS EXCLUSIVE the
-- sibling file's `ADD ... NOT VALID` took would otherwise still be held. The
-- sibling measured the same table's canonical CHECK at 2.08 s over 500,000
-- rows; this predicate is a `length()` on a stored value rather than a call
-- into `normalise_exercise_name`, so it is strictly cheaper.
--
-- ── The pre-flight, and why a `raise` beats letting VALIDATE fail ───────────
-- Nothing this repo ships can have written a violating row: the 88 `gym_sets`
-- rows the seed, the migrations and the pgtap suite spell out all fold to a
-- non-empty key, and § 1367 closed the two web save paths that could mint one.
-- What cannot be measured from the repo is PRODUCTION, whose history predates
-- both -- `gym_sets` has accepted a whitespace-only `exercise_name` since
-- 20261204_001, and no client refused one until § 1367.
--
-- Against such a row `validate constraint` answers `check constraint ... is
-- violated by some row`: no count, no column, no instruction. The scan below
-- costs one extra ACCESS SHARE pass over a table this statement is about to
-- walk anyway, and turns that into the two facts an operator needs -- how many,
-- and that the repair is a decision about USER DATA rather than a backfill.
-- There is deliberately no automatic repair: the offending row is a logged set
-- whose name has no content, so there is no name to derive and no correct
-- value to invent, and deleting a set the gym editor still renders is the
-- owner's call and not a migration's. Enforcement does not wait on it either
-- way -- the sibling's `NOT VALID` constraint already refuses every new and
-- updated row, so a database that fails here is protected against the next such
-- row while the existing ones are decided.
do $$
declare
  offenders bigint;
begin
  select count(*) into offenders
    from public.gym_sets where length(exercise_key) < 1;
  if offenders > 0 then
    raise exception
      '% gym_sets row(s) carry an empty exercise_key and cannot be validated', offenders
      using hint =
        'These are sets whose exercise_name is entirely whitespace, and they are already '
        'excluded from every read-side aggregate. List them with: select id, workout_id, '
        'set_index, exercise_name from public.gym_sets where length(exercise_key) < 1. Decide '
        'with the owner whether to rename or delete them, then re-run this migration. '
        'gym_sets_exercise_key_nonempty_chk is already enforcing on new and updated rows '
        'either way.';
  end if;
end;
$$;

alter table public.gym_sets validate constraint gym_sets_exercise_key_nonempty_chk;
