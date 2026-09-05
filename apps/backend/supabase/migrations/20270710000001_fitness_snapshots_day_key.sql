-- One fitness snapshot per runner per day: the derived day key, the trigger
-- that owns it, the UPDATE path an upsert needs, and the reduction of the
-- duplicates already on the table. The unique index itself is the NEXT
-- migration, deliberately (see the bottom of this file).
--
-- `insertFitnessSnapshot` writes a row on every `/dashboard` mount. The
-- sufficiency gate above it (`vdot == null && chronicLoad == null &&
-- qualifyingRunCount < 3`) is commented as stopping write-spam and does not:
-- it stops a runner with no data from writing, and says nothing about a runner
-- with data opening the dashboard four times. `fetchFitnessSnapshots(60)`
-- returns the newest 60 points, so at four mounts a day the whole trend chart
-- is fifteen days of the same fortnight and the multi-month curve it exists to
-- draw has scrolled off the left edge.
--
-- ── Why a stored column and not an expression index ────────────────────────
-- `(computed_at at time zone 'utc')::date` is exactly the key wanted, and it
-- cannot be the index. `timezone(text, timestamptz)` is STABLE, not IMMUTABLE,
-- so Postgres refuses it in an index expression and in a STORED generated
-- column alike; and PostgREST's `on_conflict` takes a COLUMN LIST, never an
-- expression or an index name, so a client upsert could not name it even if
-- Postgres allowed it. A plain column both roles can name is the only shape
-- that works from the browser.
--
-- The day is UTC rather than the runner's own. The key has to be derivable
-- from the row and nothing else — the row carries no timezone, and reaching
-- into `user_settings` from a BEFORE trigger would make the key depend on a
-- preference the runner can change under it. A runner at UTC+13 therefore
-- rolls over at 11:00 local. The point of the key is one chart point per day,
-- which either reading gives.
--
-- ── Derived on INSERT, frozen on UPDATE ────────────────────────────────────
-- The trigger sets the column rather than a DEFAULT doing it, because a
-- DEFAULT is only consulted when the client omits the column: a client that
-- sent `snapshot_day` would choose its own bucket, and a client that sent a
-- back-dated `computed_at` (an import, a backfill) would land on today's.
-- Deriving it in a BEFORE INSERT trigger makes both unreachable, which is
-- stronger than the column-grant freeze `20270704000003` uses for the derived
-- caches — there is no value a client can send that survives.
--
-- On UPDATE it is pinned to the old value instead of recomputed. The upsert
-- this exists for refreshes `computed_at` to now(), and a mount that straddles
-- UTC midnight would then move the row onto a day another row may already
-- hold — a 23505 raised from inside `ON CONFLICT DO UPDATE`, which is the one
-- failure the upsert was added to remove. Pinned, that mount instead leaves
-- one row keyed to yesterday carrying a timestamp a few seconds into today,
-- and the next mount inserts today's row. The chart plots `computed_at`, so
-- the visible result is two points a moment apart, once, for a runner who
-- opened the dashboard across midnight.

alter table fitness_snapshots add column snapshot_day date;

comment on column fitness_snapshots.snapshot_day is
  'UTC calendar day of computed_at, derived by fitness_snapshots_set_day_trg '
  'on INSERT and immutable thereafter. The dedupe key behind '
  'fitness_snapshots_user_day_uniq: one snapshot per runner per day, so a '
  'runner who opens /dashboard four times a day does not fill the 60-point '
  'trend window with a fortnight of duplicates.';

-- ── the UPDATE arm the upsert needs ────────────────────────────────────────
-- The table shipped with SELECT / INSERT / DELETE policies and no UPDATE one,
-- described in `rls_fitness_snapshots_test.sql` as "append-only". Append-only
-- is what produced the duplicates: with only `ON CONFLICT DO NOTHING` reachable
-- the first mount of the day would win and the day's numbers would never
-- refresh, so the runner would read Monday-morning fitness all Monday. The
-- table-level UPDATE grant has been there since `20270408_001`'s matrix and
-- reaches nothing without a policy; this is the policy, scoped exactly as its
-- three siblings are.
--
-- `source = 'client'` is carried onto both arms for the reason the INSERT
-- policy carries it: a client must not be able to mint or convert a row into
-- one that looks server-computed. `using` names it too, so a `server` row is
-- not merely un-writable INTO but un-writable AT ALL from a session.
create policy fitness_snapshots_self_update on fitness_snapshots
  for update to authenticated
  using (user_id = (select auth.uid()) and source = 'client')
  with check (user_id = (select auth.uid()) and source = 'client');

-- ── the rows already on the table ──────────────────────────────────────────
-- The duplicates MUST be reduced before the unique index can build, and they
-- are worth reducing on their own: they are what is currently filling the
-- 60-point window. The survivor per (user, day) is the one with the greatest
-- `computed_at`, tie-broken on `id` so exactly one row survives every group
-- whatever the timestamps do. That is the row a `DO UPDATE` upsert would have
-- left behind, so the reduction and the going-forward behaviour agree.
--
-- Nothing is lost that the table was carrying: every column here is recomputed
-- from the run list on the next mount, and `derived_state.md`'s contract is
-- that a derived cache is discardable. No column on a deleted row is an input
-- to anything.
--
-- Batched per user, over `fitness_snapshots_user_time`'s leading column, so
-- each statement is an index-driven pass over one runner's rows rather than
-- one sort of the whole table. **What that does NOT buy is lock relief.** The
-- apply path wraps a migration file in one transaction ([§ 1148]), so every
-- row lock this loop takes is held until the file commits, exactly as an
-- unbounded DELETE would be. Batching bounds the work per STATEMENT; only a
-- split across files or a job bounds it per LOCK, and this table has no
-- cross-file split available because the index in the next file needs the
-- reduction already done.
do $backfill$
declare
  subject uuid;
begin
  for subject in select distinct user_id from fitness_snapshots loop
    update fitness_snapshots
       set snapshot_day = (computed_at at time zone 'utc')::date
     where user_id = subject
       and snapshot_day is null;

    delete from fitness_snapshots stale
     where stale.user_id = subject
       and exists (
         select 1 from fitness_snapshots fresher
          where fresher.user_id = stale.user_id
            and fresher.snapshot_day = stale.snapshot_day
            and (fresher.computed_at, fresher.id) > (stale.computed_at, stale.id));
  end loop;
end
$backfill$;

-- The trigger is created AFTER the loop, not before it, and the order is
-- load-bearing: its UPDATE arm pins `snapshot_day` to `old`, so a trigger in
-- place during the backfill would overwrite each `SET` with the NULL it was
-- replacing and the loop would write nothing at all. Measured -- the first
-- draft of this migration created the trigger first and left every legacy row
-- NULL, which the unique index then accepted because NULLs are distinct.

create or replace function fitness_snapshots_set_day()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.snapshot_day := (new.computed_at at time zone 'utc')::date;
  else
    new.snapshot_day := old.snapshot_day;
  end if;
  return new;
end;
$$;

create trigger fitness_snapshots_set_day_trg
  before insert or update on fitness_snapshots
  for each row execute function fitness_snapshots_set_day();


-- `snapshot_day` is left NULLABLE. A NULL is unreachable for any row written
-- after this migration — `computed_at` is NOT NULL and the BEFORE INSERT
-- trigger derives from it unconditionally — and the loop above removed the
-- legacy NULLs. `SET NOT NULL` would scan the whole table under ACCESS
-- EXCLUSIVE for a property nothing can violate; the online route to it
-- (a `NOT VALID` check, a `VALIDATE` in a second file, the `SET NOT NULL` in a
-- third) is three more migrations for the same nothing.

-- The unique index is `20270710000002`, in its own file so the ACCESS
-- EXCLUSIVE its build takes is a second short window rather than an extension
-- of this file's, and so a build that finds an unexpected duplicate leaves
-- this migration applied and retryable on its own. `CREATE INDEX
-- CONCURRENTLY` is not available: it cannot run inside a transaction block,
-- the apply path wraps every migration file in one, and a PL/pgSQL body is
-- always inside one too — so there is no form of it this repo can ship
-- (migration_locks.md § Lock reference).
