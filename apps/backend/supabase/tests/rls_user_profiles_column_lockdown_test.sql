-- Pin the column-level lockdown on `user_profiles` from migration
-- 20260707_001_user_profiles_column_lockdown.sql.
--
-- The pre-rewrite shape of that migration used
--   `revoke select (subscription_tier, …) on user_profiles from authenticated, anon;`
-- which is a no-op when the role still has table-level SELECT. The
-- regression-test pass that introduced `rls_events_meet_point_test.sql`
-- exposed the same bug pattern in `events`; this test pins the
-- corrected user_profiles shape so a future writer that re-introduces
-- the broken column-level revoke pattern fails CI before merge.
--
-- Coverage:
--   1. Authenticated SELECT on `subscription_tier` raises 42501.
--   2. Authenticated SELECT on `parkrun_number` raises 42501.
--   3. Authenticated SELECT on `subscription_at` raises 42501.
--   4. Authenticated SELECT on `display_name` still works (the join
--      column for actor strips, comments, attendees, etc).
--   5. The `get_my_profile()` SECURITY DEFINER RPC returns the full
--      self row including the locked-down columns — that's the only
--      path the auth bootstrap and backup export rely on.

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000dd01', 'authenticated', 'authenticated',
   'self@profile.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000dd02', 'authenticated', 'authenticated',
   'other@profile.local', '', now(), now());

set local role service_role;

insert into user_profiles (id, display_name, parkrun_number, preferred_unit, subscription_tier)
values
  ('00000000-0000-0000-0000-00000000dd01', 'Self', 'A777', 'km', 'pro'),
  ('00000000-0000-0000-0000-00000000dd02', 'Other', 'A888', 'mi', 'free');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000dd01","role":"authenticated"}';

-- 1-3. Locked-down columns raise 42501 for any authenticated caller.
select throws_ok(
  $$ select subscription_tier from user_profiles
     where id = '00000000-0000-0000-0000-00000000dd02' $$,
  '42501',
  null,
  'authenticated SELECT on subscription_tier raises permission denied'
);

select throws_ok(
  $$ select parkrun_number from user_profiles
     where id = '00000000-0000-0000-0000-00000000dd02' $$,
  '42501',
  null,
  'authenticated SELECT on parkrun_number raises permission denied'
);

select throws_ok(
  $$ select subscription_at from user_profiles
     where id = '00000000-0000-0000-0000-00000000dd02' $$,
  '42501',
  null,
  'authenticated SELECT on subscription_at raises permission denied'
);

-- 4. display_name (the join column) still works.
select results_eq(
  $$ select display_name from user_profiles
     where id = '00000000-0000-0000-0000-00000000dd02' $$,
  $$ values ('Other'::text) $$,
  'authenticated SELECT on display_name still works'
);

-- 5. get_my_profile() returns the full self row including the
--    locked-down columns. This is the only path auth bootstrap and
--    backup export rely on for self-tier / self-parkrun reads.
select results_eq(
  $$ select (get_my_profile()).subscription_tier,
            (get_my_profile()).parkrun_number $$,
  $$ values ('pro'::text, 'A777'::text) $$,
  'get_my_profile() returns full self row including locked-down columns'
);

select * from finish();

rollback;
