-- Web-push notification channel: the notification → web_push-job enqueue
-- trigger (subscription-gated) + the clear_push_subscription prune RPC
-- (migration 20261219_001_web_push_channel.sql).
--
-- Pins:
--   * a notification for a user WITH a browser push subscription enqueues a
--     web_push job carrying that row's id.
--   * a notification for a user WITHOUT any subscription enqueues NO web_push
--     job (the trigger's subscription gate).
--   * clear_push_subscription removes only the push_subscription key, leaving
--     every other per-device pref intact.
--   * notifications.web_push_sent_at defaults NULL (unprocessed) on insert.

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 'authenticated', 'authenticated', 'haspush@wp.local', '', now(), now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02', 'authenticated', 'authenticated', 'nopush@wp.local', '', now(), now());

-- Only the first user has a browser push subscription (plus an unrelated pref
-- we expect the prune to preserve).
insert into user_device_settings (user_id, device_id, platform, prefs) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 'device-1', 'web',
   jsonb_build_object(
     'theme', 'dark',
     'push_subscription', jsonb_build_object(
       'endpoint', 'https://push.example/abc',
       'keys', jsonb_build_object('p256dh', 'pk', 'auth', 'ak'),
       'registered_at', now()))),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02', 'device-2', 'web',
   jsonb_build_object('theme', 'light'));

-- Insert a notification for each user.
insert into notifications (id, user_id, kind) values
  ('dddddddd-dddd-dddd-dddd-dddddddddd01', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 'follow'),
  ('dddddddd-dddd-dddd-dddd-dddddddddd02', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb02', 'follow');

-- 1. The subscribed user's notification enqueued a web_push job for it.
select isnt_empty(
  $$ select 1 from public.jobs
     where kind = 'web_push'
       and payload->>'notification_id' = 'dddddddd-dddd-dddd-dddd-dddddddddd01' $$,
  'a notification for a subscribed user enqueues a web_push job');

-- 2. The unsubscribed user's notification enqueued NO web_push job.
select is_empty(
  $$ select 1 from public.jobs
     where kind = 'web_push'
       and payload->>'notification_id' = 'dddddddd-dddd-dddd-dddd-dddddddddd02' $$,
  'a notification for an unsubscribed user enqueues no web_push job');

-- 3. web_push_sent_at defaults NULL (unprocessed).
select is(
  (select web_push_sent_at from notifications
   where id = 'dddddddd-dddd-dddd-dddd-dddddddddd01'),
  null, 'web_push_sent_at defaults NULL on a fresh notification');

-- 4. clear_push_subscription removes the push_subscription key …
select clear_push_subscription('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', 'device-1');
select is(
  (select (prefs ? 'push_subscription')
   from user_device_settings
   where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01' and device_id = 'device-1'),
  false, 'clear_push_subscription removes the push_subscription key');

-- 5. … but leaves the other per-device prefs intact.
select is(
  (select prefs->>'theme'
   from user_device_settings
   where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01' and device_id = 'device-1'),
  'dark', 'clear_push_subscription preserves unrelated prefs');

select * from finish();

rollback;
