-- GDPR Art 5(1)(e) storage-limitation for direct_messages.
--
-- audit/gdpr (2026-05-31) Medium: direct_messages (private
-- correspondence between users) had no time-window retention — the
-- only erasure was the ON DELETE CASCADE when EITHER participant
-- deletes their account. A user who cannot exercise the erasure right
-- (e.g. a suspended account) had no backstop, so private messages
-- accumulated indefinitely. Coach_messages (18-month cron) and
-- notifications (90-day cron) already have backstops; this closes the
-- last gap (20260922_001 is the precedent).
--
-- Window: 2 years from `created_at`. A DM thread is a lightweight
-- "meet at the trailhead Saturday?" channel, not an archival mailbox;
-- two years comfortably outlasts any season-planning back-reference
-- while keeping the retention defensible to a regulator. The window
-- lives inside the function body so a future tightening is a single-
-- file change; the cron entry picks up the new body on the next fire.

create extension if not exists pg_cron;

create or replace function private.purge_stale_direct_messages()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
begin
  with deleted as (
    delete from direct_messages
    where created_at < now() - interval '2 years'
    returning 1
  )
  select count(*) into v_deleted from deleted;
  if v_deleted > 0 then
    raise notice 'purge_stale_direct_messages: removed % row(s)', v_deleted;
  end if;
end;
$$;

revoke all on function private.purge_stale_direct_messages() from public, anon, authenticated;

select cron.schedule(
  'purge-stale-direct-messages',
  '41 3 * * *',  -- 03:41 UTC daily — off-peak; offset minute so it
                 -- doesn't pile up on the other 03:xx retention jobs
                 -- (17/23/29 = 20260922_001, 35 = purge-stale-jobs).
  $$select private.purge_stale_direct_messages()$$
);

comment on function private.purge_stale_direct_messages() is
  'GDPR Art 5(1)(e) storage-limitation: purges direct_messages older '
  'than 2 years from created_at. The ON DELETE CASCADE on sender/'
  'recipient handles account-deletion erasure; this is the time-window '
  'backstop for correspondence that would otherwise live forever. '
  'Scheduled by pg_cron entry `purge-stale-direct-messages` '
  '(03:35 UTC daily). Window can be tightened by editing the interval '
  'here. See audit/gdpr (2026-05-31).';
