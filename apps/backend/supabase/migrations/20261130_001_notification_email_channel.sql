-- Email delivery channel for the notifications inbox + event-day reminders
-- (roadmap Phase 4b).
--
-- The notifications inbox (decisions §38) and its fan-out triggers (kudos
-- / comment / follow, then event_rsvp / event_cancel / plan_update /
-- message, then club_post / run_completed in 20261101_001) already write
-- the rows that drive the in-app bell. Phase 4b layers *delivery* on top:
-- get a notification off the app and onto the user. The plan lumped this
-- under "blocked on user-supplied Firebase/APNs credentials" — true for
-- the native FCM/APNs legs, but NOT for email: email needs no third-party
-- push credential and is end-to-end testable against the local Mailpit
-- (apps/backend Mailpit at :54324, SMTP :54325). This migration wires the
-- email leg; native push stays deferred until Firebase/APNs are provisioned.
--
-- Two things are added:
--
--   1. event-day reminders (the scheduled Phase 4b item). A new
--      'event_reminder' notification kind, plus enqueue_event_reminders()
--      run hourly by pg_cron: it inserts one reminder per 'going' RSVP
--      whose occurrence falls inside the next 24 h and isn't cancelled.
--      RSVPs already pin the concrete occurrence in
--      event_attendees.instance_start, so there's no recurrence expansion
--      to do server-side — the set of occurrences anyone cares about IS
--      the set of distinct instance_start values people RSVP'd to.
--
--   2. the generic email channel. notifications.email_sent_at tracks send
--      state; an AFTER INSERT trigger enqueues a 'notification_email' job
--      (per recipient) onto the existing jobs queue. The Go worker's
--      handler_notification_email.go drains it, checks the recipient's
--      user_settings.prefs.email_notifications preference ('all' |
--      'important' | 'off', default 'important' — see docs/backend/
--      settings.md), resolves the address, and sends. Bounded by recipient
--      count, exactly like the inbox fan-out it shadows.
--
-- The notifications row stays the single source of truth: the in-app bell
-- and the email both read the same row. Adding a future FCM/APNs sender is
-- another consumer of the same rows; nothing here changes for that.

-- ─────────────────── notifications: send state + occurrence key ───────────────────

-- Email send bookkeeping. NULL = not yet processed by the email handler;
-- non-NULL = sent OR deliberately skipped (recipient opted the category
-- out, or has no address). Either way the handler won't reconsider it, so
-- one column covers both terminal states.
alter table notifications
  add column email_sent_at timestamptz;

-- The occurrence an event_reminder points at. NULL for every other kind.
-- Mirrors the per-occurrence column naming on club_posts
-- (event_instance_start) and run_photos. It's the third leg of the
-- reminder's natural identity (recipient, event, occurrence) — without it
-- a recurring event could only ever remind once.
alter table notifications
  add column event_instance_start timestamptz;

-- ─────────────────── new 'event_reminder' kind ───────────────────

-- Bare-body CHECK rewrite: re-list every existing kind (the full set as of
-- 20261101_001) plus the new one. Dropping a kind here would silently
-- break an existing fan-out trigger's insert.
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder'
    )
  );

-- One reminder per (recipient, event, occurrence). Makes enqueue_event_
-- reminders() idempotent under hourly re-runs: the first tick after the
-- occurrence enters the 24 h window inserts, every later tick conflicts.
-- event_instance_start is NOT NULL for every event_reminder row (the
-- scheduler always sets it), so the partial unique index is well-defined.
create unique index notifications_event_reminder_uniq
  on notifications (user_id, event_id, event_instance_start)
  where kind = 'event_reminder';

-- ─────────────────── jobs.kind allowlist += notification_email ───────────────────

-- Three-file rule (apps/job_worker/CLAUDE.md): a new kind needs the CHECK
-- widened here + the Go dispatch case (worker.go) + the pgtap test
-- (jobs_kind_allowlist_test.sql), all in this same commit. Until all three
-- land the CHECK rejects the insert at 23514 so the enqueue trigger below
-- can't silently drop email jobs.
alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (kind in ('map_match', 'token_refresh', 'strava_event', 'photo_process', 'notification_email'));

-- ─────────────────── enqueue trigger: notification → email job ───────────────────

-- One email job per notification row. Fires for every kind; the per-user
-- category preference is enforced in the worker (so a user on
-- email_notifications='all' still gets social emails, while the default
-- 'important' filters them out). The work the handler does for a filtered
-- notification is a cheap "stamp email_sent_at and finish" — no send.
--
-- SECURITY DEFINER so it can write public.jobs (RLS-denied to everyone but
-- service_role). Same shape as enqueue_photo_process_job
-- (20260825_001). Fired by the row insert, never called directly, so no
-- grant to public/anon/authenticated is needed.
create or replace function enqueue_notification_email_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.jobs (kind, payload)
  values (
    'notification_email',
    jsonb_build_object('notification_id', NEW.id::text)
  );
  return NEW;
end;
$$;

revoke execute on function enqueue_notification_email_job() from public;

create trigger notifications_enqueue_email
  after insert on notifications
  for each row execute function enqueue_notification_email_job();

-- ─────────────────── event-day reminder scheduler ───────────────────

-- Insert an 'event_reminder' for every attendee who's 'going' to an
-- occurrence starting within the next 24 h, skipping cancelled
-- occurrences (event_exceptions, 20261019_001). The unique index above
-- dedupes re-runs; the AFTER INSERT trigger turns each fresh row into an
-- email job. SECURITY DEFINER so it can write notifications regardless of
-- the caller (cron runs it; an operator may invoke it manually).
create or replace function enqueue_event_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into notifications (user_id, kind, event_id, event_instance_start)
  select a.user_id, 'event_reminder', a.event_id, a.instance_start
  from event_attendees a
  where a.status = 'going'
    and a.instance_start >= now()
    and a.instance_start < now() + interval '24 hours'
    and not exists (
      select 1 from event_exceptions x
      where x.event_id = a.event_id
        and x.instance_start = a.instance_start
    )
  on conflict do nothing;
end;
$$;

revoke execute on function enqueue_event_reminders() from public;
grant execute on function enqueue_event_reminders() to service_role;

-- Hourly. A 24 h look-ahead with an hourly tick means an attendee whose
-- occurrence is a day out gets reminded on the first tick that sees it
-- inside the window, then never again (dedup index). pg_cron's extension
-- + schedule helper are already set up by 20260602_001; cron.schedule is
-- idempotent on name.
select cron.schedule(
  'enqueue-event-reminders',
  '0 * * * *',
  $$select public.enqueue_event_reminders()$$
);
