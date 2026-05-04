-- RLS suite for `public.user_settings` and `public.user_device_settings`.
--
-- Both are owner-only (auth.uid() = user_id) for the full CRUD set.
-- Settings carry every personal preference (privacy_zones, units,
-- HR thresholds, audio cues, watch overrides). A leak here would let
-- one user read another's home-area privacy zones — a direct
-- doxxing vector.

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000aa1', 'authenticated', 'authenticated',
   'a@settings.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000000aa2', 'authenticated', 'authenticated',
   'b@settings.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000aa1"}';

insert into user_settings (user_id, prefs)
values ('00000000-0000-0000-0000-000000000aa1',
        '{"privacy_zones":[{"lat":47.37,"lng":8.54,"radius_m":150}]}');

insert into user_device_settings (user_id, device_id, platform, prefs)
values ('00000000-0000-0000-0000-000000000aa1', 'device-1', 'android',
        '{"audio_cues_enabled":false}');

-- 1. Owner can SELECT (compare jsonb-typed for whitespace insensitivity).
select results_eq(
  $$ select prefs -> 'privacy_zones' from user_settings
     where user_id = '00000000-0000-0000-0000-000000000aa1' $$,
  $$ values ('[{"lat":47.37,"lng":8.54,"radius_m":150}]'::jsonb) $$,
  'owner can read their user_settings'
);

-- 2. Non-owner SELECT: ZERO rows.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000aa2"}';
select is_empty(
  $$ select 1 from user_settings
     where user_id = '00000000-0000-0000-0000-000000000aa1' $$,
  'non-owner cannot read another user_settings row'
);

-- 3. Non-owner UPDATE: no-op.
update user_settings set prefs = '{}'
  where user_id = '00000000-0000-0000-0000-000000000aa1';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000aa1"}';
select isnt(
  (select prefs::text from user_settings where user_id = '00000000-0000-0000-0000-000000000aa1'),
  '{}',
  'non-owner UPDATE on user_settings is a no-op'
);

-- 4. Forged INSERT (under another user_id) is rejected.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000aa2"}';
select throws_ok(
  $$ insert into user_settings (user_id, prefs)
     values ('00000000-0000-0000-0000-000000000aa1', '{"forged":true}') $$,
  '42501',
  null,
  'cannot INSERT a user_settings row under another user_id'
);

-- 5. Anon cannot read.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select 1 from user_settings
     where user_id = '00000000-0000-0000-0000-000000000aa1' $$,
  'anon cannot read user_settings'
);

-- ── user_device_settings ──
-- 6. Owner can read their device override row.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000aa1"}';
select results_eq(
  $$ select prefs ->> 'audio_cues_enabled' from user_device_settings
     where user_id = '00000000-0000-0000-0000-000000000aa1'
       and device_id = 'device-1' $$,
  $$ values ('false'::text) $$,
  'owner can read their user_device_settings'
);

-- 7. Non-owner cannot read another user's device overrides.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000aa2"}';
select is_empty(
  $$ select 1 from user_device_settings
     where user_id = '00000000-0000-0000-0000-000000000aa1' $$,
  'non-owner cannot read another user_device_settings row'
);

-- 8. Forged INSERT into user_device_settings rejected.
select throws_ok(
  $$ insert into user_device_settings (user_id, device_id, platform, prefs)
     values ('00000000-0000-0000-0000-000000000aa1', 'device-2', 'android', '{"x":1}') $$,
  '42501',
  null,
  'cannot INSERT a user_device_settings row under another user_id'
);

select * from finish();

rollback;
