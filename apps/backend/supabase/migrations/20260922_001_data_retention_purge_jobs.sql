-- GDPR Art 5(1)(e) storage-limitation retention jobs.
--
-- Background: audit/gdpr (2026-05-25) flagged three tables holding
-- personal data with no documented retention window or purge:
--
--   * coach_messages — chat history including health context.
--   * notifications  — identity + interaction metadata.
--   * device_tokens  — identity + device binding (FCM/APNs).
--
-- This migration ships defensible default windows so the data
-- subject's storage-limitation right is honoured today. Counsel
-- can tighten the windows later — the SQL is the one place to
-- change them; the cron entries pick up the new function bodies
-- on the next fire.
--
-- Why these values:
--
--   coach_messages   — 18 months. Long enough for a runner's
--                      season-on-season comparison ("what did
--                      you say about my marathon last spring?")
--                      to remain useful; short enough that the
--                      retention is defensible if a regulator
--                      asks "why are you holding chat history
--                      from 2024?"
--   notifications    — 90 days. The unread badge surfaces 0-30
--                      day items; the inbox tab paginates back
--                      ~30-90; nothing past that has ever been
--                      shown to a user. 90 days gives forensic
--                      headroom on a kudos-spam incident.
--   device_tokens    — 60 days of inactivity (`last_seen_at`).
--                      FCM rotates tokens proactively and APNs
--                      may invalidate silently; a 60-day stale
--                      token is almost certainly dead. The
--                      cleanup also catches the "user signed
--                      out on web but never opened the app
--                      again" case where the row would otherwise
--                      live forever.
--
-- Audit-log trail: each purge function emits the row count it
-- deleted into Postgres' standard log via `raise notice`. The
-- Supabase log explorer keeps that 7 days, which is enough to
-- spot a sudden mass deletion.

create extension if not exists pg_cron;

-- ─── coach_messages ────────────────────────────────────────────
-- Bare function body so pg_cron can call it without parameters;
-- the cutoff window lives inside so a future tweak is a single-
-- file change. Per audit/gdpr (2026-05-25).
create or replace function private.purge_stale_coach_messages()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
begin
  with deleted as (
    delete from coach_messages
    where created_at < now() - interval '18 months'
    returning 1
  )
  select count(*) into v_deleted from deleted;
  if v_deleted > 0 then
    raise notice 'purge_stale_coach_messages: removed % row(s)', v_deleted;
  end if;
end;
$$;

revoke all on function private.purge_stale_coach_messages() from public, anon, authenticated;

select cron.schedule(
  'purge-stale-coach-messages',
  '17 3 * * *',  -- 03:17 UTC daily — off-peak; offset minute so it
                  -- doesn't pile up on top of other 03:00 jobs.
  $$select private.purge_stale_coach_messages()$$
);

-- ─── notifications ────────────────────────────────────────────
create or replace function private.purge_stale_notifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
begin
  with deleted as (
    delete from notifications
    where created_at < now() - interval '90 days'
    returning 1
  )
  select count(*) into v_deleted from deleted;
  if v_deleted > 0 then
    raise notice 'purge_stale_notifications: removed % row(s)', v_deleted;
  end if;
end;
$$;

revoke all on function private.purge_stale_notifications() from public, anon, authenticated;

select cron.schedule(
  'purge-stale-notifications',
  '23 3 * * *',  -- 03:23 UTC daily.
  $$select private.purge_stale_notifications()$$
);

-- ─── device_tokens ────────────────────────────────────────────
create or replace function private.purge_stale_device_tokens()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
begin
  with deleted as (
    delete from device_tokens
    where last_seen_at < now() - interval '60 days'
    returning 1
  )
  select count(*) into v_deleted from deleted;
  if v_deleted > 0 then
    raise notice 'purge_stale_device_tokens: removed % row(s)', v_deleted;
  end if;
end;
$$;

revoke all on function private.purge_stale_device_tokens() from public, anon, authenticated;

select cron.schedule(
  'purge-stale-device-tokens',
  '29 3 * * *',  -- 03:29 UTC daily.
  $$select private.purge_stale_device_tokens()$$
);

comment on function private.purge_stale_coach_messages() is
  'GDPR Art 5(1)(e) storage-limitation: purges coach_messages older '
  'than 18 months. Scheduled by pg_cron entry '
  '`purge-stale-coach-messages` (03:17 UTC daily). Window can be '
  'tightened by editing the interval here. See audit/gdpr '
  '(2026-05-25).';

comment on function private.purge_stale_notifications() is
  'GDPR Art 5(1)(e) storage-limitation: purges notifications older '
  'than 90 days. Scheduled by pg_cron entry '
  '`purge-stale-notifications` (03:23 UTC daily). See '
  'audit/gdpr (2026-05-25).';

comment on function private.purge_stale_device_tokens() is
  'GDPR Art 5(1)(e) storage-limitation: purges device_tokens whose '
  'last_seen_at is more than 60 days old. Catches stale FCM / APNs '
  'tokens and abandoned sessions. Scheduled by pg_cron entry '
  '`purge-stale-device-tokens` (03:29 UTC daily). See '
  'audit/gdpr (2026-05-25).';
