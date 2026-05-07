-- Pin the caller-identity guard on refresh_personal_records_for_user
-- from migration 20260801_002_pr_refresh_null_guard.sql.
--
-- Pre-fix: the function used `auth.uid() != p_user_id` as its guard.
-- Under Postgres three-valued logic, `null != <uuid>` evaluates to
-- NULL (falsy), so the guard silently passed for any caller without
-- a JWT (including a future SECURITY DEFINER chain that reached the
-- function via a service-role context or a trigger with no JWT).
-- Same footgun shape that 20260709_001 closed on coach_usage.
--
-- The fix mirrors the coach-usage and lock_subscription_columns
-- pattern: read the JWT role from BOTH claim formats, bypass for
-- service_role and empty-role (direct-SQL / trigger), otherwise
-- require `auth.uid() is not null and auth.uid() is not distinct
-- from p_user_id`. Also tightens the EXECUTE grant: revoke from
-- public + anon before the targeted re-grant to authenticated.
--
-- Coverage:
--   1. Service-role context (empty JWT) succeeds calling for any
--      user_id — seed.sql / RevenueCat / admin-script paths.
--   2. Authenticated caller succeeds calling with their own user_id
--      (positive control).
--   3. Authenticated caller raises 42501 calling with another
--      user's user_id (the High-severity fix).
--
-- The anon-role grant-level deny is verified at migration time
-- (`revoke ... from public, anon`) and tested cross-cuttingly by
-- `rls_function_hygiene_test.sql`; not duplicated here because
-- pgtap loses its session connection when a permission-denied
-- error fires at the EXECUTE-grant layer inside `throws_ok`.

begin;

select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000fa1', 'authenticated', 'authenticated',
   'self@pr.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000000fa2', 'authenticated', 'authenticated',
   'other@pr.local', '', now(), now());

set local role service_role;

-- 1. Service-role context (no JWT claim) succeeds for any uuid.
do $$
begin
  perform refresh_personal_records_for_user(
    '00000000-0000-0000-0000-000000000fa2');
end $$;
select pass('service-role context refreshes another user PB cache (trigger / seed path)');

-- 2. Authenticated caller can refresh their own.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000fa1","role":"authenticated"}';

do $$
begin
  perform refresh_personal_records_for_user(
    '00000000-0000-0000-0000-000000000fa1');
end $$;
select pass('authenticated caller can refresh their own PB cache');

-- 3. Authenticated caller is denied attempting to refresh another
--    user's PB cache (the High-severity fix).
select throws_ok(
  $$ select refresh_personal_records_for_user(
       '00000000-0000-0000-0000-000000000fa2') $$,
  '42501',
  null,
  'authenticated caller cannot refresh another user PB cache'
);

select * from finish();

rollback;
