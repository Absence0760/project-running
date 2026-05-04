-- RLS suite for `public.fitness_snapshots`.
--
-- Three policies (no UPDATE — snapshots are append-only):
--   - fitness_snapshots_self_select  (auth.uid() = user_id)
--   - fitness_snapshots_self_insert  (auth.uid() = user_id AND source = 'client')
--   - fitness_snapshots_self_delete  (auth.uid() = user_id)
--
-- Snapshots carry resting HR, max HR, VDOT/CTL/ATL/TSB — the runner's
-- live physiological state. Cross-user reads are a clear privacy
-- regression, and the `source = 'client'` INSERT gate ensures users
-- can't forge snapshots that look like they came from a watch or job.

begin;

select plan(6);

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
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select 1 from fitness_snapshots $$,
  'anon cannot read fitness_snapshots'
);

select * from finish();

rollback;
