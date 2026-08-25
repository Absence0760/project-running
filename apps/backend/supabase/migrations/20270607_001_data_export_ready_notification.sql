-- Tell the subject when their queued Art 20 export has finished building.
--
-- `followups.md` carried this as NOT planned for a long time, on a reason
-- that has since expired: "the export endpoint is synchronous and returns
-- a 10-minute signed URL inline, so an async 'your export is ready' email
-- would arrive stale. Revisit only if export moves to an async/job model."
-- The export IS an async job model since decisions.md § 717, and since
-- § 724 the queued rail is the only rail on either client.
--
-- The staleness objection is answered by the same design that closed it,
-- not waived: the signed URL is minted when the subject asks for it — at
-- read time by `GET /v1/export/jobs/latest`, at the tap on mobile — never
-- when the worker finishes. `data_export_jobs` stores the object PATH,
-- which is inert on its own (the `exports` bucket carries no
-- `storage.objects` policies at all, 20270602_001). So the message this
-- migration makes possible carries a link to the PAGE and nothing with a
-- clock already running on it. Nothing here stores or mints a URL, and
-- nothing may: the moment a notification carried one, the original
-- objection would be back. decisions.md § 729.

-- ─────────────── 1. notifications.kind += data_export_ready ───────────────

-- Re-emit the full union (the "create or replace strips prior fixes" rule
-- applies to CHECK rebuilds too — 20270218_001 is the live list).
--
-- `notifications` is a guarded high-volume table, so the widen takes the
-- online two-step (migration_locks.md § CHECK constraints) rather than the
-- single-step drop-and-recreate every previous kind migration used. A
-- validating ADD holds ACCESS EXCLUSIVE while it scans every notification
-- ever written, and the scan is pure waste here: this only ever ADDS a
-- kind, so every existing row already satisfies the wider set. VALIDATE
-- re-runs it under SHARE UPDATE EXCLUSIVE with reads and writes
-- proceeding. Both halves ship together because the scan is of
-- `notifications`, not of `runs`; the lock class is what mattered.
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement', 'challenge_complete', 'content_hidden',
      'data_export_ready'
    )
  )
  not valid;
alter table notifications validate constraint notifications_kind_check;

-- ─────────────── 2. the send-state stamp ───────────────

-- The per-export "already told them" marker, the same shape as
-- `notifications.email_sent_at` / `web_push_sent_at` / `native_push_sent_at`:
-- one stamp per delivery, checked and written in the same statement that
-- delivers. Nullable ADD COLUMN with no default, so it is a catalogue-only
-- flip and rewrites nothing.
--
-- It lives here rather than being derived from the presence of a
-- `notifications` row because a subject may delete a notification from
-- their own inbox (the DELETE policy on `notifications` is theirs), and a
-- deleted row must not read as "never notified" and re-announce a
-- fortnight-old export the next time a retry touches the job.
alter table data_export_jobs add column notified_at timestamptz;

comment on column data_export_jobs.notified_at is
  'When the subject was told this export is ready. Written by '
  'notify_data_export_ready() in the same statement as the notifications '
  'insert, so an at-least-once queue redelivery cannot announce the same '
  'archive twice. Null on a row that has not become ready.';

-- ─────────────── 3. notify_data_export_ready ───────────────

-- Insert the inbox row and stamp the export in ONE statement, under a row
-- lock, so a redelivered `data_export` job (max_attempts = 2, and the
-- queue is at-least-once regardless) announces the archive exactly once.
-- Returns whether it inserted, so the caller can say so in a log line
-- rather than guess.
--
-- The three refusals are each deliberate:
--
--   * `status <> 'ready'` — a failed, expired or still-building export has
--     nothing to collect. `expire_stale_export_jobs` flips a `ready` row to
--     `expired` and nulls its path once the artifact is swept, so a worker
--     that comes back a week late is refused here rather than announcing a
--     download that 404s.
--   * `object_path is null` — the row's whole claim is that an artifact
--     exists; without the path there is nothing to sign at read time.
--   * `notified_at is not null` — already announced.
--
-- SECURITY DEFINER because `notifications` INSERT is closed to every
-- client role (20260528000001: only definer trigger functions write it)
-- and `data_export_jobs` is granted to `service_role` alone. Not granted
-- to anon/authenticated: a caller who could invoke this could fabricate an
-- inbox row on their own account, and — worse — the AFTER INSERT fan-out
-- would turn each one into an email and a push.
--
-- The insert carries no FK. The export has no row in any table the
-- notification can point at, and `pathForKind` / `notificationLinkFor`
-- both send this kind to `/settings/account`, which is where the download
-- lives and where the URL is minted.
create or replace function notify_data_export_ready(p_export_job_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row data_export_jobs;
begin
  select * into v_row
  from data_export_jobs
  where id = p_export_job_id
  for update;

  if not found
     or v_row.status <> 'ready'
     or v_row.object_path is null
     or v_row.notified_at is not null then
    return false;
  end if;

  insert into notifications (user_id, kind)
  values (v_row.user_id, 'data_export_ready');

  update data_export_jobs
  set notified_at = now()
  where id = p_export_job_id;

  return true;
end;
$$;

revoke execute on function notify_data_export_ready(uuid) from public, anon, authenticated;
grant execute on function notify_data_export_ready(uuid) to service_role;

comment on function notify_data_export_ready(uuid) is
  'Announce a finished Art 20 export to its subject: one notifications '
  'row of kind data_export_ready, stamped notified_at in the same '
  'statement so an at-least-once redelivery cannot announce it twice. '
  'Refuses a row that is not ready, carries no object_path, or has '
  'already been announced. service_role only — the AFTER INSERT fan-out '
  'turns the row into an email and a push, so a client-reachable version '
  'would be a mail cannon. decisions.md § 729.';
