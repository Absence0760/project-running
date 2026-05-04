-- RLS suite for `public.integrations`.
--
-- Owner-only (auth.uid() = user_id) FOR ALL. The table holds the
-- provider links + sync state (the actual OAuth tokens live in
-- vault.secrets and are referenced by id). A leak here exposes
-- which platforms a user has connected, their external_user_id,
-- and the secret-vault foreign-keys — enough on its own to mount a
-- targeted phishing or impersonation attack.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000ee01', 'authenticated', 'authenticated',
   'a@integ.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000ee02', 'authenticated', 'authenticated',
   'b@integ.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee01"}';

insert into integrations (user_id, provider, token_expiry, external_id, scope)
values ('00000000-0000-0000-0000-00000000ee01',
        'strava', now() + interval '1 hour',
        'strava-12345', 'activity:read_all');

-- 1. Owner can read their integration.
select results_eq(
  $$ select external_id from integrations
     where user_id = '00000000-0000-0000-0000-00000000ee01' $$,
  $$ values ('strava-12345'::text) $$,
  'owner can read their integration row'
);

-- 2. Non-owner SELECT: ZERO rows.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee02"}';
select is_empty(
  $$ select external_id from integrations
     where user_id = '00000000-0000-0000-0000-00000000ee01' $$,
  'non-owner cannot read another user''s integration row'
);

-- 3. Non-owner UPDATE: no-op.
update integrations set external_id = 'compromised'
  where user_id = '00000000-0000-0000-0000-00000000ee01';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee01"}';
select results_eq(
  $$ select external_id from integrations
     where user_id = '00000000-0000-0000-0000-00000000ee01' $$,
  $$ values ('strava-12345'::text) $$,
  'non-owner UPDATE on another user''s integration is a no-op'
);

-- 4. Non-owner DELETE: no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee02"}';
delete from integrations where user_id = '00000000-0000-0000-0000-00000000ee01';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee01"}';
select results_eq(
  $$ select count(*)::int from integrations
     where user_id = '00000000-0000-0000-0000-00000000ee01' $$,
  $$ values (1) $$,
  'non-owner DELETE on another user''s integration is a no-op'
);

-- 5. Forged INSERT under another user_id rejected.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee02"}';
select throws_ok(
  $$ insert into integrations (user_id, provider, token_expiry)
     values ('00000000-0000-0000-0000-00000000ee01',
             'garmin', now() + interval '1 hour') $$,
  '42501',
  null,
  'cannot INSERT an integration under another user_id'
);

-- 6. Anon cannot SELECT.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select 1 from integrations
     where user_id = '00000000-0000-0000-0000-00000000ee01' $$,
  'anon cannot read integrations'
);

select * from finish();

rollback;
