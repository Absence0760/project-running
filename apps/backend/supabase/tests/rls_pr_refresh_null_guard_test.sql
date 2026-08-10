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
--   4. The EXECUTE grants themselves: service_role + authenticated hold
--      it, public + anon do not. Coverage 1 asserts the service-role
--      BEHAVIOUR, but `revoke … from public` also stripped the EXECUTE
--      that service_role held only through PUBLIC, so the call was
--      rejected at the grant layer before the body's service-role branch
--      could run — aborting this whole file at its first assertion.
--      Restored in 20270515_001; pinned here as a privilege so a future
--      re-emission of the revoke/grant pair cannot drop it again.
--
-- The anon-role grant-level deny is verified at migration time
-- (`revoke ... from public, anon`) and tested cross-cuttingly by
-- `rls_function_hygiene_test.sql`; not duplicated here because
-- pgtap loses its session connection when a permission-denied
-- error fires at the EXECUTE-grant layer inside `throws_ok`.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000fa1', 'authenticated', 'authenticated',
   'self@pr.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000000fa2', 'authenticated', 'authenticated',
   'other@pr.local', '', now(), now());

-- 0. The grant matrix behind coverage 1. Asserted before the call so a
--    stripped service_role EXECUTE reports as a failed assertion rather
--    than a 42501 that aborts the file.
select ok(
  has_function_privilege('service_role', 'public.refresh_personal_records_for_user(uuid)', 'EXECUTE')
    and has_function_privilege('authenticated', 'public.refresh_personal_records_for_user(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.refresh_personal_records_for_user(uuid)', 'EXECUTE')
    and not has_function_privilege('public', 'public.refresh_personal_records_for_user(uuid)', 'EXECUTE'),
  'EXECUTE is held by service_role + authenticated only — not public, not anon'
);

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
