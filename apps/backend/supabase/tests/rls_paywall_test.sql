-- pgtap suite for the paywall tier gates:
--
--   - is_pro() — SECURITY DEFINER. Returns true when auth.uid()'s
--     subscription_tier is 'pro' or 'lifetime'. Read-side gate; used
--     by RLS policies on paid-tier tables and Edge Functions that
--     guard premium endpoints.
--   - check_rate_limit_tiered(p_user_id, p_bucket, free_max, pro_max,
--     window_s) — SECURITY DEFINER. Reads tier and uses it to pick
--     the max. Increments the rate_limits row in the same call so
--     EFs only need a single round-trip.
--   - lock_subscription_columns trigger — guards the WRITE side: a
--     normal user UPDATE on their own user_profiles row must NOT be
--     able to flip subscription_tier from free → pro (the only
--     legitimate writer is the revenuecat-webhook EF running as
--     service_role).
--
-- Blast radius if any of these regresses:
--   - is_pro: paid features become free for everyone (revenue) or
--     premium gates lock paid users out (support storm).
--   - check_rate_limit_tiered: throughput limits stop working OR
--     pro users get throttled to the free ceiling.
--   - lock trigger: a user can self-promote to pro by editing their
--     own row. Direct revenue leak.

begin;

select plan(19);

-- ── Fixture: a free user, a pro user, a lifetime user ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000f001', 'authenticated', 'authenticated',
   'free@pay.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000f002', 'authenticated', 'authenticated',
   'pro@pay.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000f003', 'authenticated', 'authenticated',
   'lifetime@pay.local', '', now(), now());

-- Insert profiles as postgres so we bypass the lock-columns trigger
-- while building the fixture. The trigger only fires on UPDATE; INSERT
-- is the legitimate sign-up path.
insert into user_profiles (id, subscription_tier) values
  ('00000000-0000-0000-0000-00000000f001', 'free'),
  ('00000000-0000-0000-0000-00000000f002', 'pro'),
  ('00000000-0000-0000-0000-00000000f003', 'lifetime');

-- ── is_pro ──
set local role authenticated;

-- 1. Free user: is_pro() = false.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f001","role":"authenticated"}';
select is(is_pro(), false, 'is_pro() returns false for a free user');

-- 2. Pro user: is_pro() = true.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f002","role":"authenticated"}';
select is(is_pro(), true, 'is_pro() returns true for a pro user');

-- 3. Lifetime user: is_pro() = true.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f003","role":"authenticated"}';
select is(is_pro(), true, 'is_pro() returns true for a lifetime user');

-- 4. Anon (no auth.uid): is_pro() = false (no row matches NULL).
set local role anon;
set local "request.jwt.claims" = '';
select is(is_pro(), false, 'is_pro() returns false for an unauthenticated caller');

-- ── check_rate_limit_tiered ──
set local role authenticated;

-- 5. Free user, free_max=2, pro_max=100. First two calls allowed,
--    third denied. (Matches the per-EF user-id bucket pattern.)
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f001","role":"authenticated"}';

select results_eq(
  $$ select allowed, tier from check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f001', 'paywall_test', 2, 100, 3600) $$,
  $$ values (true, 'free') $$,
  'free user: 1st call allowed; tier reported as free'
);
select results_eq(
  $$ select allowed from check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f001', 'paywall_test', 2, 100, 3600) $$,
  $$ values (true) $$,
  'free user: 2nd call allowed (at the limit)'
);
select results_eq(
  $$ select allowed from check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f001', 'paywall_test', 2, 100, 3600) $$,
  $$ values (false) $$,
  'free user: 3rd call denied (over the limit)'
);

-- 6. Pro user with the SAME free_max=2, pro_max=100 arguments stays
--    allowed past the free ceiling.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f002","role":"authenticated"}';
select results_eq(
  $$ select allowed, tier from check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f002', 'paywall_test_pro', 2, 100, 3600) $$,
  $$ values (true, 'pro') $$,
  'pro user: 1st call allowed; tier reported as pro'
);
-- Burn 5 more calls — past the free ceiling, well within pro.
do $$
declare i int;
begin
  for i in 1..5 loop
    perform check_rate_limit_tiered(
      '00000000-0000-0000-0000-00000000f002', 'paywall_test_pro', 2, 100, 3600);
  end loop;
end;
$$;
select results_eq(
  $$ select allowed from check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f002', 'paywall_test_pro', 2, 100, 3600) $$,
  $$ values (true) $$,
  'pro user: 7th call still allowed (well past free ceiling)'
);

-- 7. Lifetime user: same shape — treated as pro.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f003","role":"authenticated"}';
select results_eq(
  $$ select allowed, tier from check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f003', 'paywall_test_lt', 2, 100, 3600) $$,
  $$ values (true, 'lifetime') $$,
  'lifetime user: tier reported as lifetime, treated as pro for limits'
);
do $$
declare i int;
begin
  for i in 1..3 loop
    perform check_rate_limit_tiered(
      '00000000-0000-0000-0000-00000000f003', 'paywall_test_lt', 2, 100, 3600);
  end loop;
end;
$$;
select results_eq(
  $$ select allowed from check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f003', 'paywall_test_lt', 2, 100, 3600) $$,
  $$ values (true) $$,
  'lifetime user: 5th call still allowed (treated as pro)'
);

-- 8. Auth context A cannot rate-limit-check user B (cross-user guard).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f001","role":"authenticated"}';
select throws_ok(
  $$ select check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f002', 'cross', 4, 16, 3600) $$,
  null,
  'check_rate_limit_tiered: not authorized',
  'cannot rate-limit-check another user_id'
);

-- 9. Invalid args (zero / negative max) raise.
select throws_ok(
  $$ select check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f001', 'b', 0, 16, 3600) $$,
  null,
  'check_rate_limit_tiered: free_max, pro_max, window must be positive',
  'rejects free_max <= 0'
);
select throws_ok(
  $$ select check_rate_limit_tiered(
       '00000000-0000-0000-0000-00000000f001', 'b', 4, 16, 0) $$,
  null,
  'check_rate_limit_tiered: free_max, pro_max, window must be positive',
  'rejects window_seconds <= 0'
);

-- 10. Denied result includes a non-zero retry_after_seconds.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f001","role":"authenticated"}';
-- Already over the limit from the test 5 burn. Trigger another denial
-- and assert retry_after_seconds > 0.
select cmp_ok(
  (select retry_after_seconds from check_rate_limit_tiered(
     '00000000-0000-0000-0000-00000000f001', 'paywall_test', 2, 100, 3600))::int,
  '>', 0,
  'denial returns retry_after_seconds > 0'
);

-- ── lock_subscription_columns trigger ──
-- 11. A user CANNOT upgrade their own tier via UPDATE on user_profiles.
--     The webhook EF runs as service_role and bypasses the trigger;
--     a normal authenticated UPDATE must be rejected. The lock-columns
--     trigger reads `request.jwt.claim.role` directly (singular,
--     dotted) — that's a separate GUC from the `request.jwt.claims`
--     bag, so we set it explicitly here.
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f001","role":"authenticated"}';
select throws_ok(
  $$ update user_profiles set subscription_tier = 'pro'
       where id = '00000000-0000-0000-0000-00000000f001' $$,
  '42501',
  null,
  'user cannot self-upgrade their subscription_tier via UPDATE'
);

-- 12. Sanity: the tier didn't change despite the attempt.
reset role;
select results_eq(
  $$ select subscription_tier from user_profiles
       where id = '00000000-0000-0000-0000-00000000f001' $$,
  $$ values ('free'::text) $$,
  'free user remained free after self-upgrade attempt'
);

-- ── billing_issue_at write-lock (20260729_001; must survive the
--    20261107_001 session_user-hardening rewrite — see
--    20261112_001) ──
-- Plant a renewal-failure flag as a privileged direct-SQL caller (the
-- webhook EF's service_role path is what writes it in production). The
-- trigger only gates non-service-role UPDATEs, so clear the role GUCs
-- first or the planting UPDATE trips its own guard.
set local "request.jwt.claim.role" = '';
set local "request.jwt.claims" = '';
update user_profiles set billing_issue_at = now() - interval '1 hour'
  where id = '00000000-0000-0000-0000-00000000f001';

-- 13. A normal user CANNOT clear their own billing_issue_at to suppress
--     the dunning banner (the column lost its guard once; pin it).
set local role authenticated;
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f001","role":"authenticated"}';
select throws_ok(
  $$ update user_profiles set billing_issue_at = null
       where id = '00000000-0000-0000-0000-00000000f001' $$,
  '42501',
  null,
  'user cannot clear their own billing_issue_at via UPDATE'
);

-- 14. Sanity: the flag survived the suppression attempt.
reset role;
select isnt(
  (select billing_issue_at from user_profiles
     where id = '00000000-0000-0000-0000-00000000f001'),
  null,
  'billing_issue_at remained set after the clear attempt'
);

select * from finish();

rollback;
