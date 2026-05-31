-- audit-findings 2026-05-30 High [security/rls] regression pin.
--
-- `app_quota` is the app-wide Strava-quota counter. It must be
-- untouchable by ordinary callers: a single direct write could trip
-- the soft floor (making the whole app back off from Strava) or zero
-- the counter (blowing the real Strava limit → app suspension). The
-- 20261106_001 migration revoked direct grants + enabled RLS. This
-- suite pins both halves so a future grant can't silently re-open it.
--
--   1. `authenticated` can neither SELECT nor INSERT/UPDATE the table.
--   2. `authenticated` cannot EXECUTE the SECURITY DEFINER RPC (it is
--      service_role-only — the Go worker + Edge Functions use the
--      service key).
--   3. RLS is actually enabled on the table (defence-in-depth behind
--      the revoke).

begin;

select plan(4);

-- ── 1. No direct read ────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000a0001"}';

select throws_ok(
  $$ select count(*) from public.app_quota $$,
  '42501',
  'permission denied for table app_quota',
  'authenticated cannot SELECT the app_quota counter directly'
);

-- ── 2. No direct write ───────────────────────────────────────────
select throws_ok(
  $$ insert into public.app_quota (provider, window_kind, window_start, count)
       values ('strava', 'day', now(), 1) $$,
  '42501',
  'permission denied for table app_quota',
  'authenticated cannot INSERT/inflate the app_quota counter directly'
);

reset role;

-- ── 3. No RPC execute grant ──────────────────────────────────────
-- The gate RPC must be service_role-only; neither anon nor
-- authenticated may consume (or reset) the quota through it. Assert
-- the *grant* rather than invoking the function: the local dev
-- Postgres image segfaults (signal 11) when a role without EXECUTE
-- actually calls it, so a privilege check is both safer and a more
-- direct pin on the ACL the migration sets.
select ok(
  not has_function_privilege('anon', 'public.try_consume_strava_quota(integer, integer)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.try_consume_strava_quota(integer, integer)', 'EXECUTE'),
  'neither anon nor authenticated can EXECUTE try_consume_strava_quota'
);

-- ── 4. RLS is enabled ────────────────────────────────────────────
select is(
  (select relrowsecurity from pg_class where relname = 'app_quota'),
  true,
  'RLS is enabled on app_quota (defence-in-depth behind the revoke)'
);

select * from finish();
rollback;
