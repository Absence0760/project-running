-- Pin `user_coach_usage` as a SERVER-MAINTAINED meter: no client write of
-- any kind, on any verb.
--
-- 20260722_001 closed DELETE ("the daily cap cannot be reset by deleting the
-- counter row") but left the self-INSERT / self-UPDATE policies from
-- 20260430_001 in place, and 20270408_001's grant matrix handed
-- table-level INSERT/UPDATE to anon + authenticated. A signed-in caller could
-- therefore PATCH `message_count` back to 0, or INSERT a future-dated bucket
-- with a negative count that the rolling-24h sum in `increment_coach_usage`
-- adds in — re-rolling the AI-coach allowance and uncapping the Anthropic
-- spend the counter exists to bound. 20270505_001 closes both.
--
-- Coverage:
--   - the owner can still READ their own meter
--   - DELETE / UPDATE / INSERT from an authenticated context are all rejected
--     outright (privilege revoked; the deny policies are the RLS backstop)
--   - the counter is unchanged after all three attempts
--   - the legitimate writer — the auth.uid()-guarded SECURITY DEFINER
--     `increment_coach_usage` — still works, so the lockdown did not break
--     the metered path it protects

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000cc01', 'authenticated', 'authenticated',
        'free@usage.local', '', now(), now());

-- Bootstrap: insert a usage row directly via service-role context
-- so the test has a concrete row to attempt to write against.
set local role service_role;
insert into user_coach_usage (user_id, usage_date, message_count)
values ('00000000-0000-0000-0000-00000000cc01', current_date, 3);

-- ── Owner (authenticated) write attempts ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc01"}';

-- 1. Owner reads their own row (SELECT policy works).
select results_eq(
  $$ select message_count from user_coach_usage
     where user_id = '00000000-0000-0000-0000-00000000cc01'
       and usage_date = current_date $$,
  $$ values (3) $$,
  'owner reads their own coach-usage row'
);

-- 2. DELETE — the 20260722_001 contract, now enforced at the grant layer.
select throws_ok(
  $$ delete from user_coach_usage
      where user_id = '00000000-0000-0000-0000-00000000cc01'
        and usage_date = current_date $$,
  '42501',
  null,
  'owner cannot DELETE their own coach-usage row'
);

-- 3. UPDATE — the reset-to-zero re-roll.
select throws_ok(
  $$ update user_coach_usage set message_count = 0
      where user_id = '00000000-0000-0000-0000-00000000cc01'
        and usage_date = current_date $$,
  '42501',
  null,
  'owner cannot UPDATE their own coach-usage counter (no allowance re-roll)'
);

-- 4. INSERT — the future-dated negative bucket the rolling-24h sum would add in.
select throws_ok(
  $$ insert into user_coach_usage (user_id, usage_date, message_count)
       values ('00000000-0000-0000-0000-00000000cc01',
               current_date + 1, -1000000) $$,
  '42501',
  null,
  'owner cannot INSERT a coach-usage bucket (no negative-count poisoning)'
);

-- 5. Counter unchanged after all three attempts.
select results_eq(
  $$ select message_count from user_coach_usage
     where user_id = '00000000-0000-0000-0000-00000000cc01'
       and usage_date = current_date $$,
  $$ values (3) $$,
  'coach-usage counter survives every client write attempt'
);

-- 6. The legitimate writer still works: the SECURITY DEFINER RPC runs as the
--    table owner, so the client-side revoke cannot break metering itself.
select is(
  increment_coach_usage('00000000-0000-0000-0000-00000000cc01'),
  4,
  'increment_coach_usage still meters the owner after the client lockdown'
);

select * from finish();

rollback;
