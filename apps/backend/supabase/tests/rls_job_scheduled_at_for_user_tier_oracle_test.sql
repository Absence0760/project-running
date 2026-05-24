-- Pin the caller-identity guard added by 20260914_001 to
-- job_scheduled_at_for_user(uuid).
--
-- Pre-fix the function leaked the target user's subscription tier
-- to any authenticated caller: pass a victim UUID, compare the
-- return to `now()` vs `now() + 30 s`, learn whether they are
-- pro / lifetime or free.
--
-- Coverage:
--   1. Authenticated user inspecting THEMSELVES still works (positive
--      control — the trigger + RPC paths both pass auth.uid() for
--      p_user_id and must keep working).
--   2. Authenticated user inspecting ANOTHER user is rejected with
--      42501 (the regression fix).
--   3. Service-role caller can inspect any user_id (positive control
--      for the worker / cron paths that have no auth.uid()).

begin;

select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000a01', 'authenticated', 'authenticated',
   'tier-oracle-victim@forge.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000000a02', 'authenticated', 'authenticated',
   'tier-oracle-prober@forge.local', '', now(), now());

set local role service_role;

-- Force the victim to pro so the leaked signal would be observable
-- (free -> +30 s vs pro -> +0 s) if the function were unguarded.
update user_profiles
   set subscription_tier = 'pro'
 where id = '00000000-0000-0000-0000-000000000a01';

-- ── Switch to the prober ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000a02","role":"authenticated"}';

-- 1. Positive control: prober inspects themselves (legitimate use).
do $$
declare
  v_ts timestamptz;
begin
  v_ts := job_scheduled_at_for_user('00000000-0000-0000-0000-000000000a02');
  if v_ts is null then
    raise exception 'expected non-null return from self-inspection';
  end if;
end $$;
select pass('authenticated caller can inspect their own scheduled_at');

-- 2. Regression fix: probing another user is rejected.
select throws_ok(
  $$ select job_scheduled_at_for_user('00000000-0000-0000-0000-000000000a01') $$,
  '42501',
  null,
  'authenticated caller cannot inspect another user''s scheduled_at'
);

-- 3. Service role bypass: the worker / cron paths still work.
set local role service_role;
reset "request.jwt.claims";

do $$
declare
  v_ts timestamptz;
begin
  v_ts := job_scheduled_at_for_user('00000000-0000-0000-0000-000000000a01');
  if v_ts is null then
    raise exception 'expected non-null return from service-role inspection';
  end if;
end $$;
select pass('service_role can inspect any user_id');

select * from finish();
rollback;
