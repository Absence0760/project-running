-- Weekly-digest enqueue scheduler (migration 20270220_001_weekly_digest_cron.sql).
--
-- Pins:
--   * enqueue_weekly_digests() enqueues a 'weekly_digest' job for a recipient
--     opted IN (user_settings.prefs.email_weekly_digest='on').
--   * 'off', a non-string value, and an absent pref are all skipped (opt-IN:
--     ONLY the literal 'on' enrolls — mirrors the worker's digestOptedIn).
--   * dedupe: a second run while the recipient's first digest is still
--     queued/running is a no-op (one live digest per recipient).
--   * re-arm: once the prior digest drains to done, the next run enqueues a
--     fresh one (the intended weekly cadence).
--   * the function returns the count of jobs it enqueued.

begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd01', 'authenticated', 'authenticated', 'optin@dig.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd02', 'authenticated', 'authenticated', 'optout@dig.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd03', 'authenticated', 'authenticated', 'absent@dig.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd04', 'authenticated', 'authenticated', 'wrongtype@dig.local', '', now(), now());

-- Opted IN (the only one that should be enqueued).
insert into user_settings (user_id, prefs)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd01', '{"email_weekly_digest":"on"}'::jsonb);
-- Explicit opt-OUT.
insert into user_settings (user_id, prefs)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd02', '{"email_weekly_digest":"off"}'::jsonb);
-- No digest key at all (default off → skip).
insert into user_settings (user_id, prefs)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd03', '{"preferred_unit":"km"}'::jsonb);
-- A non-'on' value (booleans / numbers must not enroll — only literal 'on').
insert into user_settings (user_id, prefs)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd04', '{"email_weekly_digest":true}'::jsonb);

-- First run: one enqueue (the opted-in user only).
select is(
  public.enqueue_weekly_digests(),
  1, 'first run enqueues exactly one digest (the opted-in recipient)');

-- 1. The opted-in recipient has a queued weekly_digest job carrying their id.
select is(
  (select count(*)::int from public.jobs
   where kind = 'weekly_digest'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd01'),
  1, 'opted-in recipient is enqueued');

-- 2. The explicit opt-out is not.
select is(
  (select count(*)::int from public.jobs
   where kind = 'weekly_digest'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd02'),
  0, 'opted-out recipient is skipped');

-- 3. The absent-pref recipient is not (default off).
select is(
  (select count(*)::int from public.jobs
   where kind = 'weekly_digest'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd03'),
  0, 'recipient with no digest pref is skipped (opt-IN default off)');

-- 4. The non-'on' (boolean true) recipient is not — only the literal 'on'.
select is(
  (select count(*)::int from public.jobs
   where kind = 'weekly_digest'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd04'),
  0, 'a non-''on'' digest value does not enroll');

-- 5. Dedupe: a second run while the first digest is still queued enqueues nothing.
select is(
  public.enqueue_weekly_digests(),
  0, 're-running while a digest is still queued is a no-op (per-user dedupe)');

-- 6. Re-arm: once the prior digest drains to done, the next run enqueues a fresh one.
update public.jobs
  set status = 'done', finished_at = now()
  where kind = 'weekly_digest'
    and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaadd01';
select is(
  public.enqueue_weekly_digests(),
  1, 'after the prior digest drains, the next run re-arms the recipient');

select * from finish();

rollback;
