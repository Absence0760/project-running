-- Overdue-runner escalation (migration 20270401_001, docs/features/safety.md).
--
-- Pins: the enqueue_safety_overdue_emails() scan predicate (silent live run
-- past the owner's threshold, fail-closed on a missing pref / no confirmed
-- contact / already stamped / saved run), the once-only stamp, and the
-- live-stub transition fix on the finish + run_completed notifiers (no
-- "finished" alert at broadcast START; alert on the stub→saved UPDATE).

begin;

select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d01', 'authenticated', 'authenticated', 'runner@ovd.local',  '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d02', 'authenticated', 'authenticated', 'contact@ovd.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d03', 'authenticated', 'authenticated', 'nopref@ovd.local',  '', now(), now());

insert into user_profiles (id, display_name, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d01', 'Olive Overdue', now(), now(), 'km', 'free');

-- Runner opted in: 30-minute threshold + one confirmed contact.
insert into user_settings (user_id, prefs)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d01', '{"safety_overdue_minutes": 30}');

insert into safety_contacts (owner_id, contact_email)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d01', 'contact@ovd.local');
update safety_contacts
  set confirmed_at = now(),
      contact_user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d02'
  where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d01';

-- Wipe the confirm job noise so job counts below are exact.
delete from public.jobs;

-- ─────────── live-stub INSERT does not fire the finish notifier ───────────

-- The broadcast stub: is_public, zero duration, in_progress.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d01',
        now() - interval '45 minutes', 0, 0, 'app', 'run', true, '{"activity_type": "run", "in_progress": true}');

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'finish'),
  0, 'a live-broadcast stub INSERT enqueues no finish email');

-- ─────────── overdue scan: silent past threshold → one job, one stamp ───────────

select public.enqueue_safety_overdue_emails();

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'overdue'
     and payload->>'contact_email' = 'contact@ovd.local'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01'
     and payload->>'owner_name' = 'Olive Overdue'),
  1, 'a silent in-progress run past the threshold enqueues one overdue job per confirmed contact');

select isnt(
  (select metadata->>'safety_escalated_at' from runs
   where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01'),
  null, 'the matched run is stamped safety_escalated_at');

-- No last ping ever landed → the payload carries no last_seen_at.
select is(
  (select payload ? 'last_seen_at' from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'overdue' limit 1),
  false, 'a broadcast with zero pings reports no last_seen_at (started_at is the floor)');

-- Second sweep: already stamped → no second job.
select public.enqueue_safety_overdue_emails();

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'overdue'),
  1, 'a stamped run never re-fires');

-- ─────────── recent ping inside the threshold → no match ───────────

insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d01',
        now() - interval '3 hours', 0, 0, 'app', 'run', true, '{"activity_type": "run", "in_progress": true}');

insert into live_run_pings (run_id, user_id, at, lat, lng)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d01',
        now() - interval '5 minutes', 51.5, -0.12);

select public.enqueue_safety_overdue_emails();

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'overdue'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d02'),
  0, 'a run whose latest ping is inside the threshold is not overdue');

-- ...and once the ping ages past the threshold it matches, carrying it.
update live_run_pings
  set at = now() - interval '40 minutes'
  where run_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d02';

select public.enqueue_safety_overdue_emails();

select is(
  (select payload ? 'last_seen_at' from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'overdue'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d02'),
  true, 'a silent run with pings carries last_seen_at in the payload');

-- ─────────── fail-closed: no pref → never matches ───────────

insert into user_profiles (id, display_name, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d03', 'Nora Nopref', now(), now(), 'km', 'free');

insert into safety_contacts (owner_id, contact_email)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d03', 'contact@ovd.local');
update safety_contacts set confirmed_at = now()
  where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d03';

insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d03', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d03',
        now() - interval '4 hours', 0, 0, 'app', 'run', true, '{"activity_type": "run", "in_progress": true}');

select public.enqueue_safety_overdue_emails();

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'overdue'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d03'),
  0, 'no safety_overdue_minutes pref means no escalation (fail-closed)');

-- ─────────── unconfirmed-only contacts → no match ───────────

update safety_contacts set confirmed_at = null
  where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d03';
insert into user_settings (user_id, prefs)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d03', '{"safety_overdue_minutes": 30}');

select public.enqueue_safety_overdue_emails();

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'overdue'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d03'),
  0, 'an unconfirmed contact never receives an overdue alert');

-- ─────────── stub→saved UPDATE fires the finish email exactly then ───────────

-- A follower, so the run_completed notifier's transition path is
-- observable too (and pins the 20261212_001 activity_kind/activity_id
-- pair the bare-body rewrite must preserve).
insert into user_follows (follower_id, followee_id)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d01');

select is(
  (select count(*)::int from notifications
   where kind = 'run_completed'
     and run_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01'),
  0, 'the live-broadcast stub INSERT fires no run_completed notification');

delete from public.jobs;

update runs
  set duration_s = 2400, distance_m = 8000,
      metadata = '{"activity_type": "run"}'::jsonb
  where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01';

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'finish'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01'
     and (payload->>'duration_s')::int = 2400),
  1, 'the stub→saved transition enqueues the finish email with the saved stats');

select is(
  (select count(*)::int from notifications
   where kind = 'run_completed'
     and run_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa6d02'
     and activity_kind = 'run'
     and activity_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01'),
  1, 'the transition fires run_completed once, carrying the polymorphic activity pair (20261212_001)');

-- An ordinary edit after save must not re-alert.
update runs set distance_m = 8100
  where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01';

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'finish'),
  1, 'a post-save edit does not enqueue another finish email');

-- The saved run is out of the scan (in_progress cleared) — no re-match even
-- though the stamp was overwritten by the save.
select public.enqueue_safety_overdue_emails();

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'overdue'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb6d01'),
  0, 'a saved run never matches the overdue scan');

select * from finish();
rollback;
