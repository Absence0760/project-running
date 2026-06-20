-- Native-push notification channel: the notification → native_push-job enqueue
-- trigger (device-token-gated) + the clear_device_token prune RPC
-- (migration 20270212_001_native_push_channel.sql).
--
-- Pins:
--   * a notification for a user WITH an enabled device token enqueues a
--     native_push job carrying that row's id.
--   * a notification for a user WITHOUT any token enqueues NO native_push job.
--   * a notification for a user whose only token is disabled
--     (is_notifications_enabled = false) enqueues NO native_push job.
--   * clear_device_token deletes exactly the dead token row, nothing else.
--   * notifications.native_push_sent_at defaults NULL (unprocessed) on insert.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 'authenticated', 'authenticated', 'hastoken@np.local', '', now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccc02', 'authenticated', 'authenticated', 'notoken@np.local', '', now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccc03', 'authenticated', 'authenticated', 'disabled@np.local', '', now(), now());

-- User 1 has an enabled token; user 3 has one explicitly disabled; user 2 none.
insert into device_tokens (user_id, platform, token, is_notifications_enabled) values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 'android', 'fcm-token-enabled', true),
  ('cccccccc-cccc-cccc-cccc-cccccccccc03', 'ios', 'apns-token-disabled', false);

-- Insert a notification for each user.
insert into notifications (id, user_id, kind) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'cccccccc-cccc-cccc-cccc-cccccccccc01', 'follow'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02', 'cccccccc-cccc-cccc-cccc-cccccccccc02', 'follow'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee03', 'cccccccc-cccc-cccc-cccc-cccccccccc03', 'follow');

-- 1. The user with an enabled token gets a native_push job for their notification.
select isnt_empty(
  $$ select 1 from public.jobs
     where kind = 'native_push'
       and payload->>'notification_id' = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01' $$,
  'a notification for a user with an enabled device token enqueues a native_push job');

-- 2. The user with no token gets NO native_push job.
select is_empty(
  $$ select 1 from public.jobs
     where kind = 'native_push'
       and payload->>'notification_id' = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee02' $$,
  'a notification for a user with no device token enqueues no native_push job');

-- 3. The user whose only token is disabled gets NO native_push job.
select is_empty(
  $$ select 1 from public.jobs
     where kind = 'native_push'
       and payload->>'notification_id' = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee03' $$,
  'a notification for a user with only a disabled token enqueues no native_push job');

-- 4. native_push_sent_at defaults NULL (unprocessed).
select is(
  (select native_push_sent_at from notifications
   where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'),
  null, 'native_push_sent_at defaults NULL on a fresh notification');

-- 5. clear_device_token removes exactly the dead token row …
select clear_device_token('fcm-token-enabled');
select is_empty(
  $$ select 1 from device_tokens where token = 'fcm-token-enabled' $$,
  'clear_device_token deletes the named token row');

-- 6. … and leaves another user's token untouched.
select isnt_empty(
  $$ select 1 from device_tokens where token = 'apns-token-disabled' $$,
  'clear_device_token leaves other tokens intact');

select * from finish();

rollback;
