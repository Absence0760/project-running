-- Pin the audit/storage thumb_512_path lockdown added by
-- 20260915_002. Two surface invariants:
--   1. CHECK constraint rejects a thumb_512_path that doesn't start
--      with the row's owner_id (prevents cross-user path injection
--      that would then be approved by the read policy).
--   2. The block-thumb-update trigger rejects user-side UPDATEs of
--      thumb_512_path (the column is service-role only by design;
--      the worker writes it once the thumbnail job runs).
--
-- Positive controls confirm legitimate paths still work:
--   3. INSERT with a properly-prefixed thumb_512_path is accepted.
--   4. service_role can UPDATE thumb_512_path (the trigger only
--      blocks the authenticated path).

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000fa01', 'authenticated', 'authenticated',
   'thumb-victim@forge.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000fa02', 'authenticated', 'authenticated',
   'thumb-attacker@forge.local', '', now(), now());

-- A run owned by the attacker that the SELECT policy will approve
-- (the attacker is the owner). We need a real run row so the FK
-- to runs.id is satisfied and the trigger fires on a realistic
-- update path.
set local role service_role;

insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values
  ('11111111-1111-1111-1111-111111111101',
   '00000000-0000-0000-0000-00000000fa02',
   now(), 5000, 1800, 'app', jsonb_build_object('activity_type', 'run'));

-- ── Switch to attacker ──
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-00000000fa02","role":"authenticated"}';

-- 1. CHECK: insert a row where thumb_512_path references the victim's
--    prefix. The constraint must reject (codes for check_violation:
--    Postgres uses 23514).
select throws_ok(
  $$ insert into run_photos
       (id, run_id, owner_id, storage_path, thumb_512_path)
     values
       (gen_random_uuid(),
        '11111111-1111-1111-1111-111111111101',
        '00000000-0000-0000-0000-00000000fa02',
        '00000000-0000-0000-0000-00000000fa02/photo.jpg',
        '00000000-0000-0000-0000-00000000fa01/stolen.jpg') $$,
  '23514',
  null,
  'CHECK rejects a thumb_512_path that does not start with the owner_id'
);

-- 2. Insert a legitimate row (proper prefix + no thumb yet) so the
--    next tests have a row to UPDATE.
do $$
begin
  insert into run_photos
    (id, run_id, owner_id, storage_path, thumb_512_path)
  values
    ('22222222-2222-2222-2222-222222222201',
     '11111111-1111-1111-1111-111111111101',
     '00000000-0000-0000-0000-00000000fa02',
     '00000000-0000-0000-0000-00000000fa02/original.jpg',
     null);
end $$;
select pass('legitimate INSERT with NULL thumb_512_path accepted');

-- 3. Owner-side UPDATE of thumb_512_path is rejected (the
--    block-thumb-update trigger fires).
select throws_ok(
  $$ update run_photos
        set thumb_512_path = '00000000-0000-0000-0000-00000000fa02/thumb.jpg'
      where id = '22222222-2222-2222-2222-222222222201' $$,
  '42501',
  null,
  'owner cannot UPDATE thumb_512_path — service-role only column'
);

-- 4. Service role can UPDATE the same column (worker / thumbnail
--    job path).
set local role service_role;
reset "request.jwt.claims";

do $$
begin
  update run_photos
     set thumb_512_path = '00000000-0000-0000-0000-00000000fa02/thumb.jpg'
   where id = '22222222-2222-2222-2222-222222222201';
end $$;
select pass('service_role can UPDATE thumb_512_path (worker path)');

select * from finish();
rollback;
