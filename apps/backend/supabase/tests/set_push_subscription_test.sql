-- Owner-callable atomic web-push registration write: set_push_subscription
-- (migration 20270419_001_set_push_subscription_rpc.sql, issue #235).
--
-- Pins:
--   * setting a subscription on an existing device row touches ONLY the
--     push_subscription key — every other per-device pref survives (the
--     whole-bag clobber this RPC replaced).
--   * re-setting replaces the stored subscription in place.
--   * clearing (NULL / jsonb 'null') removes only the key, prefs intact.
--   * a not-yet-provisioned device row is created with the caller's
--     platform/label (the insert arm; platform is NOT NULL).
--   * the write is scoped to auth.uid() — a caller can never reach another
--     user's row, even with the same device_id.
--   * anon has no execute grant.

begin;

select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 'authenticated', 'authenticated', 'owner@sps.local', '', now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccc02', 'authenticated', 'authenticated', 'other@sps.local', '', now(), now());

-- The owner's device row carries unrelated prefs the RPC must preserve;
-- the other user has a row under the SAME device_id to pin uid-scoping.
insert into user_device_settings (user_id, device_id, platform, prefs) values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 'device-sps', 'web',
   jsonb_build_object('theme', 'dark', 'voice_feedback', true)),
  ('cccccccc-cccc-cccc-cccc-cccccccccc02', 'device-sps', 'web',
   jsonb_build_object('theme', 'light'));

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccc01","role":"authenticated"}';

-- 1-2. Set: the key lands, unrelated prefs survive.
select set_push_subscription(
  'device-sps',
  jsonb_build_object('endpoint', 'https://push.example/one',
                     'keys', jsonb_build_object('p256dh', 'pk', 'auth', 'ak'),
                     'registered_at', now()));
select is(
  (select prefs->'push_subscription'->>'endpoint'
   from user_device_settings
   where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01' and device_id = 'device-sps'),
  'https://push.example/one', 'set stores the subscription');
select is(
  (select prefs->>'theme' || '/' || (prefs->>'voice_feedback')
   from user_device_settings
   where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01' and device_id = 'device-sps'),
  'dark/true', 'set preserves every unrelated per-device pref');

-- 3. Re-set replaces in place.
select set_push_subscription(
  'device-sps',
  jsonb_build_object('endpoint', 'https://push.example/two',
                     'keys', jsonb_build_object('p256dh', 'pk2', 'auth', 'ak2'),
                     'registered_at', now()));
select is(
  (select prefs->'push_subscription'->>'endpoint'
   from user_device_settings
   where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01' and device_id = 'device-sps'),
  'https://push.example/two', 're-set replaces the stored subscription');

-- 4. The other user's row under the same device_id was never touched
--    (read as superuser — owner-only RLS hides it from the caller).
reset role;
select is(
  (select prefs ? 'push_subscription'
   from user_device_settings
   where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc02' and device_id = 'device-sps'),
  false, 'the write is auth.uid()-scoped — another user''s same-device_id row is untouched');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccc01","role":"authenticated"}';

-- 5-6. Clear removes only the key.
select set_push_subscription('device-sps', null);
select is(
  (select prefs ? 'push_subscription'
   from user_device_settings
   where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01' and device_id = 'device-sps'),
  false, 'clear removes the push_subscription key');
select is(
  (select prefs->>'theme' || '/' || (prefs->>'voice_feedback')
   from user_device_settings
   where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01' and device_id = 'device-sps'),
  'dark/true', 'clear preserves every unrelated per-device pref');

-- 7. jsonb 'null' is treated as clear, not stored as a value.
select set_push_subscription('device-sps', 'null'::jsonb);
select is(
  (select prefs ? 'push_subscription'
   from user_device_settings
   where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01' and device_id = 'device-sps'),
  false, 'jsonb ''null'' clears instead of storing a null value');

-- 8. Setting on a device row that was never provisioned creates it.
select set_push_subscription(
  'device-fresh',
  jsonb_build_object('endpoint', 'https://push.example/fresh',
                     'keys', jsonb_build_object('p256dh', 'pk', 'auth', 'ak'),
                     'registered_at', now()),
  'web-mac', 'Macintosh');
select is(
  (select platform || '/' || (prefs->'push_subscription'->>'endpoint')
   from user_device_settings
   where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01' and device_id = 'device-fresh'),
  'web-mac/https://push.example/fresh',
  'an unprovisioned device row is created with the caller''s platform');

-- 9. anon has no execute grant.
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$ select set_push_subscription('device-x', null) $$,
  '42501',
  null,
  'anon cannot execute set_push_subscription');

select * from finish();

rollback;
