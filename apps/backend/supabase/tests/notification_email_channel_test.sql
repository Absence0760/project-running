-- Email notification channel: event-day reminder scheduler + the
-- notification → email-job enqueue trigger + dedupe
-- (migration 20261130_001_notification_email_channel.sql).
--
-- Pins:
--   * enqueue_event_reminders() reminds a 'going' attendee whose
--     occurrence is inside the next 24 h.
--   * a 'maybe' attendee, an out-of-window occurrence, and a cancelled
--     occurrence are all skipped.
--   * re-running the scheduler is idempotent (the partial unique index).
--   * inserting an event_reminder fires the AFTER INSERT trigger that
--     enqueues a notification_email job carrying that row's id.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee01', 'authenticated', 'authenticated', 'owner@rem.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee02', 'authenticated', 'authenticated', 'going@rem.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee03', 'authenticated', 'authenticated', 'maybe@rem.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee04', 'authenticated', 'authenticated', 'far@rem.local', '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee05', 'authenticated', 'authenticated', 'cancel@rem.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-cccc-cccc-cccc-ccccccccee01',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee01', 'Reminder Club', 'reminder-club', false);

insert into events (id, club_id, title, starts_at, created_by, recurrence_freq)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01',
        'cccccccc-cccc-cccc-cccc-ccccccccee01', 'Reminder Run',
        now() + interval '2 hours', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee01', 'weekly');

-- Occurrences:
--   I1 (now+2h)  going  + maybe   → reminder only for the going one
--   I2 (now+3d)  going            → out of the 24h window, no reminder
--   I3 (now+5h)  going, cancelled → no reminder (event_exceptions)
insert into event_attendees (event_id, user_id, status, instance_start) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee02', 'going', now() + interval '2 hours'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee03', 'maybe', now() + interval '2 hours'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee04', 'going', now() + interval '3 days'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee05', 'going', now() + interval '5 hours');

-- Cancel the I3 occurrence so its going attendee is not reminded.
insert into event_exceptions (event_id, instance_start, cancelled_by, reason)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01', now() + interval '5 hours',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee01', 'rained off');

select public.enqueue_event_reminders();

-- 1. The going + in-window attendee is reminded.
select is(
  (select count(*)::int from notifications
   where kind = 'event_reminder'
     and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee02'),
  1, 'going attendee inside the 24h window is reminded');

-- 2. The 'maybe' attendee is not.
select is(
  (select count(*)::int from notifications
   where kind = 'event_reminder' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee03'),
  0, 'maybe attendee is not reminded');

-- 3. The out-of-window (3 days) attendee is not.
select is(
  (select count(*)::int from notifications
   where kind = 'event_reminder' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee04'),
  0, 'occurrence outside the 24h window is not reminded');

-- 4. The cancelled-occurrence attendee is not.
select is(
  (select count(*)::int from notifications
   where kind = 'event_reminder' and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee05'),
  0, 'cancelled occurrence is not reminded');

-- 5. Idempotent: a second run inserts nothing new (partial unique index).
select public.enqueue_event_reminders();
select is(
  (select count(*)::int from notifications
   where kind = 'event_reminder'
     and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'
     and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee02'),
  1, 're-running the scheduler is a no-op (dedup index)');

-- 6. The new event_reminder enqueued a notification_email job carrying its id.
select isnt_empty(
  $$ select 1 from public.jobs j
     where j.kind = 'notification_email'
       and j.payload->>'notification_id' = (
         select id::text from notifications
         where kind = 'event_reminder'
           and user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaee02'
           and event_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'
         limit 1) $$,
  'inserting an event_reminder enqueues a notification_email job for it');

select * from finish();

rollback;
