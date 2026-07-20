-- Pins migration 20270423_001 — the 'done' dedupe back-ported to the
-- drip_onboarding + drip_reengagement cohorts in enqueue_lifecycle_drip()
-- (issue #376). Before the fix these cohorts only excluded a candidate with a
-- ('queued','running') job, so a drip that had drained to 'done' let the daily
-- cron re-enqueue the same still-matching candidate the next tick — onboarding
-- up to 4x, re-engagement every day forever. This proves a completed ('done')
-- job now blocks the re-enqueue for both.

begin;
select plan(6);

-- Two synthetic opted-in users:
--   aaaa — profile 3 days old, no runs        → drip_onboarding enqueued
--   bbbb — one run 40 days ago, none since     → drip_reengagement enqueued
insert into auth.users (id, email, encrypted_password,
                        email_confirmed_at, instance_id, aud, role) values
  ('77777777-7777-7777-7777-77777777aaaa', 'drip-dd-a@example.com', '',
   now(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('77777777-7777-7777-7777-77777777bbbb', 'drip-dd-b@example.com', '',
   now(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- Onboarding join is on user_profiles.created_at — seed it 3 days back (no
-- auto-create trigger exists, so insert explicitly).
insert into user_profiles (id, created_at) values
  ('77777777-7777-7777-7777-77777777aaaa', now() - interval '3 days')
on conflict (id) do update set created_at = excluded.created_at;

insert into user_settings (user_id, prefs) values
  ('77777777-7777-7777-7777-77777777aaaa', '{"email_lifecycle_drip":"on"}'),
  ('77777777-7777-7777-7777-77777777bbbb', '{"email_lifecycle_drip":"on"}')
on conflict (user_id) do update set prefs = excluded.prefs;

-- bbbb's only run is 40 days ago: gives running history (>30d) with no activity
-- in the last 30 days → re-engagement matches.
insert into runs (user_id, started_at, distance_m, duration_s, source, metadata) values
  ('77777777-7777-7777-7777-77777777bbbb', now() - interval '40 days', 5000, 1800,
   'app', '{"activity_type":"run"}');

select lives_ok(
  $q$ select enqueue_lifecycle_drip() $q$,
  'enqueue_lifecycle_drip() runs'
);

select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'template' = 'drip_onboarding'
     and payload->>'user_id' = '77777777-7777-7777-7777-77777777aaaa'),
  1::bigint,
  'onboarding candidate -> drip_onboarding enqueued'
);

select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'template' = 'drip_reengagement'
     and payload->>'user_id' = '77777777-7777-7777-7777-77777777bbbb'),
  1::bigint,
  're-engagement candidate -> drip_reengagement enqueued'
);

-- Drain both to 'done' and re-run the enqueue. Before the fix the daily cron
-- re-enqueued both (only queued/running was deduped); the 'done' predicate now
-- blocks the second row.
update jobs set status = 'done', finished_at = now()
where kind = 'lifecycle_drip'
  and payload->>'user_id' in (
    '77777777-7777-7777-7777-77777777aaaa',
    '77777777-7777-7777-7777-77777777bbbb'
  );

select enqueue_lifecycle_drip();

select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'template' = 'drip_onboarding'
     and payload->>'user_id' = '77777777-7777-7777-7777-77777777aaaa'),
  1::bigint,
  'a done drip_onboarding blocks re-enqueue (no daily duplicate)'
);

select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'template' = 'drip_reengagement'
     and payload->>'user_id' = '77777777-7777-7777-7777-77777777bbbb'),
  1::bigint,
  'a done drip_reengagement blocks re-enqueue (no daily-forever loop)'
);

-- Sanity: the streak cohort deliberately keeps re-firing daily, so this fix
-- must not have widened its dedupe. Confirm the function still enqueues nothing
-- unexpected for these two users beyond the two templates asserted above.
select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'user_id' in (
       '77777777-7777-7777-7777-77777777aaaa',
       '77777777-7777-7777-7777-77777777bbbb'
     )),
  2::bigint,
  'exactly two drips total for the two candidates after the re-run'
);

select * from finish();
rollback;
