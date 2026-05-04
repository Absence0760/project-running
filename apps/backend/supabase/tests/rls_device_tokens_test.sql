-- RLS suite for `public.device_tokens`.
--
-- Owner-only across SELECT / INSERT / UPDATE / DELETE. The table holds
-- APNs / FCM push tokens. Cross-user access lets an attacker route push
-- notifications to arbitrary devices.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000d000c301', 'authenticated', 'authenticated',
   'a@dev.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000d000c302', 'authenticated', 'authenticated',
   'b@dev.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000d000c301"}';

insert into device_tokens (user_id, platform, token)
values ('00000000-0000-0000-0000-0000d000c301', 'ios', 'apns-token-AAA');

-- 1. Owner reads their own token row.
select results_eq(
  $$ select token from device_tokens
     where user_id = '00000000-0000-0000-0000-0000d000c301' $$,
  $$ values ('apns-token-AAA'::text) $$,
  'owner can read their device_tokens row'
);

-- 2. Non-owner SELECT: ZERO rows.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000d000c302"}';
select is_empty(
  $$ select 1 from device_tokens
     where user_id = '00000000-0000-0000-0000-0000d000c301' $$,
  'non-owner cannot read another user''s device_tokens'
);

-- 3. Forged INSERT under another user_id rejected.
select throws_ok(
  $$ insert into device_tokens (user_id, platform, token)
     values ('00000000-0000-0000-0000-0000d000c301', 'ios', 'forged-token') $$,
  '42501',
  null,
  'cannot INSERT a device_token under another user_id'
);

-- 4. Non-owner UPDATE: no-op.
update device_tokens set token = 'compromised'
  where user_id = '00000000-0000-0000-0000-0000d000c301';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000d000c301"}';
select results_eq(
  $$ select token from device_tokens
     where user_id = '00000000-0000-0000-0000-0000d000c301' $$,
  $$ values ('apns-token-AAA'::text) $$,
  'non-owner UPDATE on a device_token is a no-op'
);

-- 5. Non-owner DELETE: no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000d000c302"}';
delete from device_tokens where user_id = '00000000-0000-0000-0000-0000d000c301';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000d000c301"}';
select results_eq(
  $$ select count(*)::int from device_tokens
     where user_id = '00000000-0000-0000-0000-0000d000c301' $$,
  $$ values (1) $$,
  'non-owner DELETE on a device_token is a no-op'
);

-- 6. Anon cannot read.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select 1 from device_tokens
     where user_id = '00000000-0000-0000-0000-0000d000c301' $$,
  'anon cannot read device_tokens'
);

select * from finish();

rollback;
