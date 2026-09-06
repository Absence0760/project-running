-- RLS suite for `public.fitness_snapshots`.
--
-- Four policies, all scoped to the owner:
--   - fitness_snapshots_self_select  (auth.uid() = user_id)
--   - fitness_snapshots_self_insert  (auth.uid() = user_id AND source = 'client')
--   - fitness_snapshots_self_update  (auth.uid() = user_id AND source = 'client')
--   - fitness_snapshots_self_delete  (auth.uid() = user_id)
--
-- The UPDATE arm is 20270710000001's. The table was append-only before it, and
-- append-only is what filled the 60-point trend window with duplicates: the
-- /dashboard mount inserts, so a runner opening it four times a day buried the
-- multi-month curve under a fortnight. One row per runner per UTC day
-- (`fitness_snapshots_user_day_uniq`) needs an upsert, and an upsert whose
-- conflict arm is DO NOTHING would freeze the day's numbers at the first mount
-- rather than refreshing them — so the UPDATE arm is what makes the key usable
-- rather than merely a cap.
--
-- Snapshots carry resting HR, max HR, VDOT/CTL/ATL/TSB — the runner's
-- live physiological state. Cross-user reads are a clear privacy
-- regression, and the `source = 'client'` INSERT gate ensures users
-- can't forge snapshots that look like they came from a watch or job.

begin;

select plan(15);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000f17a001', 'authenticated', 'authenticated',
   'a@fit.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000f17a002', 'authenticated', 'authenticated',
   'b@fit.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000f17a001"}';

insert into fitness_snapshots (user_id, computed_at, source, vdot, acute_load, chronic_load, training_stress_bal)
values ('00000000-0000-0000-0000-00000f17a001', now(), 'client',
        50.5, 40.0, 35.0, 5.0);

-- 1. Owner can read their own snapshot.
select results_eq(
  $$ select vdot from fitness_snapshots
     where user_id = '00000000-0000-0000-0000-00000f17a001' $$,
  $$ values (50.5::numeric) $$,
  'owner can read their fitness_snapshots'
);

-- 2. Non-owner SELECT: ZERO rows.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000f17a002"}';
select is_empty(
  $$ select 1 from fitness_snapshots
     where user_id = '00000000-0000-0000-0000-00000f17a001' $$,
  'non-owner cannot read another user''s fitness snapshots'
);

-- 3. Forged INSERT under another user_id rejected.
select throws_ok(
  $$ insert into fitness_snapshots (user_id, computed_at, source, vdot)
     values ('00000000-0000-0000-0000-00000f17a001', now(), 'client', 99.0) $$,
  '42501',
  null,
  'cannot INSERT a snapshot under another user_id'
);

-- 4. INSERT with non-'client' source rejected (the source-gate).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000f17a002"}';
select throws_ok(
  $$ insert into fitness_snapshots (user_id, computed_at, source, vdot)
     values ('00000000-0000-0000-0000-00000f17a002', now(), 'job', 60.0) $$,
  '42501',
  null,
  'authenticated user cannot INSERT with source != ''client'''
);

-- 5. Owner DELETE works.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000f17a001"}';
delete from fitness_snapshots
  where user_id = '00000000-0000-0000-0000-00000f17a001';
select is_empty(
  $$ select 1 from fitness_snapshots
     where user_id = '00000000-0000-0000-0000-00000f17a001' $$,
  'owner can delete their own snapshot'
);

-- 6. Anon cannot read.
-- Test 5 deleted the only snapshot in this transaction, so without
-- filing a fresh one this assertion reads an empty table and passes
-- whether or not the policy exists (decisions § 741). File the subject
-- first, as the owner, so the empty result below is a refusal rather
-- than an absence.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000f17a001"}';
insert into fitness_snapshots (user_id, computed_at, source, vdot, acute_load, chronic_load, training_stress_bal)
values ('00000000-0000-0000-0000-00000f17a001', now(), 'client',
        51.5, 41.0, 36.0, 5.5);

set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select 1 from fitness_snapshots $$,
  'anon cannot read fitness_snapshots'
);


-- ── the one-per-day key (20270710000001, 20270710000002) ───────────────────

reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000f17a001"}';

-- 7. The key is derived from `computed_at`, not from the clock. An import or a
-- backfill writing a back-dated snapshot must land on the day it describes, or
-- a client could put every historical row on today and collapse them all onto
-- one bucket.
insert into fitness_snapshots (user_id, computed_at, source, vdot)
values ('00000000-0000-0000-0000-00000f17a001', timestamptz '2026-02-03 22:30:00+00', 'client', 44.0);

select is(
  (select snapshot_day from fitness_snapshots where vdot = 44.0),
  date '2026-02-03',
  'snapshot_day is derived from computed_at, in UTC'
);

-- 8. And a client cannot choose its own bucket. A DEFAULT would only fire when
-- the column is omitted; the BEFORE INSERT trigger overwrites what was sent.
insert into fitness_snapshots (user_id, computed_at, source, vdot, snapshot_day)
values ('00000000-0000-0000-0000-00000f17a001', timestamptz '2026-02-04 22:30:00+00', 'client', 45.0, date '1999-01-01');

select is(
  (select snapshot_day from fitness_snapshots where vdot = 45.0),
  date '2026-02-04',
  'a client-supplied snapshot_day is overwritten by the derived one'
);

-- 9. The guarantee itself.
select throws_ok(
  $$ insert into fitness_snapshots (user_id, computed_at, source, vdot)
     values ('00000000-0000-0000-0000-00000f17a001', timestamptz '2026-02-03 01:00:00+00', 'client', 46.0) $$,
  '23505',
  null,
  'a second snapshot on a day the runner already has is refused'
);

-- 10. Which is why the write path is an upsert. The conflict arm REFRESHES the
-- day's row: a DO NOTHING arm would leave the runner reading their
-- first-mount-of-the-day fitness until midnight.
insert into fitness_snapshots (user_id, computed_at, source, vdot)
values ('00000000-0000-0000-0000-00000f17a001', timestamptz '2026-02-03 01:00:00+00', 'client', 46.0)
on conflict (user_id, snapshot_day)
do update set vdot = excluded.vdot, computed_at = excluded.computed_at;

select results_eq(
  $$ select count(*)::int, max(vdot) from fitness_snapshots
      where user_id = '00000000-0000-0000-0000-00000f17a001' and snapshot_day = date '2026-02-03' $$,
  $$ values (1, 46.00::numeric) $$,
  'the upsert refreshes the day''s single row rather than adding a second'
);

-- 11. The key is frozen once written. The upsert refreshes `computed_at` to
-- now(), and a mount straddling UTC midnight would otherwise move the row onto
-- a day another row may already hold — a 23505 raised from inside the conflict
-- arm, which is the failure the upsert exists to remove.
update fitness_snapshots set snapshot_day = date '1999-01-01'
 where user_id = '00000000-0000-0000-0000-00000f17a001' and snapshot_day = date '2026-02-04';

select is(
  (select snapshot_day from fitness_snapshots where vdot = 45.0),
  date '2026-02-04',
  'an UPDATE cannot move snapshot_day — the key is immutable once derived'
);

-- 12. The UPDATE arm is owner-scoped like its three siblings. The statement
-- carries NO `where` and its `set` references no column, deliberately: with
-- either, Postgres also applies the SELECT policies to the rows it reads, and
-- the owner-scoped SELECT policy would refuse a non-owner's update whatever the
-- UPDATE policy said — measured, an open `using (true)` UPDATE policy leaves
-- this assertion green in that shape. Bare, only the UPDATE policy is
-- consulted. It matches no row rather than erroring, so the subject is read
-- back to separate a refusal from an absence (decisions § 741).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000f17a002"}';
update fitness_snapshots set vdot = 1.0;

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000f17a001"}';
select is(
  (select vdot from fitness_snapshots where snapshot_day = date '2026-02-04'),
  45.00::numeric,
  'a non-owner UPDATE reaches no row — the owner''s snapshot is untouched'
);

-- 13. And the source gate holds on UPDATE as it does on INSERT: a
-- server-computed row is not convertible, nor editable, from a session. It is
-- named on the USING arm as well as the WITH CHECK one, so the row is not
-- merely un-writable INTO but unreachable.
reset role;
insert into fitness_snapshots (user_id, computed_at, source, vdot)
values ('00000000-0000-0000-0000-00000f17a001', timestamptz '2026-02-05 10:00:00+00', 'server', 47.0);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000f17a001"}';
update fitness_snapshots set vdot = 2.0
 where user_id = '00000000-0000-0000-0000-00000f17a001' and source = 'server';

select is(
  (select vdot from fitness_snapshots where snapshot_day = date '2026-02-05'),
  47.00::numeric,
  'an authenticated session cannot UPDATE a server-computed snapshot'
);



-- 14. And the freeze is a freeze, not a re-derivation. Assertion 11 cannot tell
-- the two apart: a trigger that recomputed `snapshot_day` from `computed_at` on
-- UPDATE would also refuse the forged date there, because the row's
-- `computed_at` had not moved. Move `computed_at` onto another day and the key
-- must NOT follow it — that is what stops a mount straddling UTC midnight from
-- pushing its row onto a day another row already holds and raising a 23505
-- from inside a conflict arm. (Measured: without this assertion the
-- recompute-on-update mutation survives the whole file.)
update fitness_snapshots set computed_at = timestamptz '2026-06-15 12:00:00+00'
 where user_id = '00000000-0000-0000-0000-00000f17a001'
   and snapshot_day = date '2026-02-04';

select results_eq(
  $$ select snapshot_day, computed_at from fitness_snapshots
      where user_id = '00000000-0000-0000-0000-00000f17a001'
        and vdot = 45.0 $$,
  $$ values (date '2026-02-04', timestamptz '2026-06-15 12:00:00+00') $$,
  'moving computed_at to another day leaves snapshot_day where it was — the key is pinned, not re-derived'
);

-- 15. The positive control for 12 and 14 together: the owner CAN update their
-- own snapshot. Without it, a policy that refused every update would satisfy
-- both, and the day's numbers would freeze at the first mount of the day —
-- which is the failure the UPDATE arm exists to prevent once one-row-per-day
-- is enforced.
update fitness_snapshots set vdot = 45.5
 where user_id = '00000000-0000-0000-0000-00000f17a001'
   and snapshot_day = date '2026-02-04';

select is(
  (select vdot from fitness_snapshots
    where user_id = '00000000-0000-0000-0000-00000f17a001'
      and snapshot_day = date '2026-02-04'),
  45.50::numeric,
  'the owner can refresh their own snapshot — the day''s row is correctable, not frozen at the first mount'
);

select * from finish();

rollback;
