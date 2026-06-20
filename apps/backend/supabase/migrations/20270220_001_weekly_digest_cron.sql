-- Weekly-digest send: the pg_cron schedule that enqueues one `weekly_digest`
-- job per opted-in recipient (roadmap "Email — engagement"). This is the LAST
-- piece of the weekly digest — the worker backend (handler, builder,
-- suppression rail, RFC 8058 one-click unsubscribe token, the `weekly_digest`
-- jobs.kind) all landed behind the gate in migration `20270108_001`. This
-- migration wires the missing scheduler.
--
-- ─────────────────────────────── THE GATE ───────────────────────────────
-- This schedule ships ENQUEUE-ONLY and is FAIL-CLOSED at the worker: a
-- `weekly_digest` job that drains while `SMTP_HOST` (+ `APP_BASE_URL`) is
-- UNSET finishes `done` WITHOUT sending — `handleWeeklyDigest` returns early
-- when `w.Email == nil` (the exact shape `notification_email` / `web_push`
-- use). So in any environment without SMTP provisioned — including prod until
-- an operator provisions it — NOTHING is delivered. The cron is harmless
-- background churn (a handful of no-op jobs per week) until the send leg is
-- turned on by configuring the worker. Even once SMTP is live, the handler
-- still hard-gates EVERY recipient on the opt-IN `email_weekly_digest='on'`
-- pref (default off) AND the `email_suppressions` block list before sending.
--
-- Enabling an ACTUAL send is therefore a deploy-time operator step, not a code
-- change:
--   1. Provision SMTP on the worker (`SMTP_HOST/PORT/USERNAME/PASSWORD/FROM`)
--      + `APP_BASE_URL` + the RFC 8058 `WEEKLY_DIGEST_UNSUB_SECRET`.
--   2. Land SPF/DKIM/DMARC on the sending domain.
--   3. CISO + counsel sign-off — bulk/promotional mail under CAN-SPAM +
--      GDPR/ePrivacy, unlike the transactional kinds. This is a PRE-DEPLOY
--      checklist item, NOT a reason to leave the cron unscheduled (the code
--      path is built; the prod gate is the unset SMTP credential).
-- See docs/features/email.md § "Production ops".
-- ─────────────────────────────────────────────────────────────────────────
--
-- Dedupe-safe, like the `event_reminder` / `token_refresh` crons it copies:
-- a recipient gets at most ONE queued/running digest at a time. If the worker
-- is behind, a later weekly tick coalesces into the existing backlog row
-- rather than enqueueing a second. The handler tolerates at-least-once
-- delivery (the opt-in + suppression gates are the only dedupe it needs), so
-- a coalesced backlog is strictly better than a duplicated one.
--
-- The selection mirrors the Go builder's `FetchDigestCandidates` exactly
-- (`user_settings.prefs->>'email_weekly_digest' = 'on'`) — the builder
-- (`EnqueueAllWeeklyDigests`) stays as the operator-invokable manual/backfill
-- path; this function is the scheduled one. Both enqueue the identical
-- `{kind:'weekly_digest', payload:{user_id}}` row.

-- ─────────────────── enqueue function ───────────────────

-- SECURITY DEFINER so it can write public.jobs (RLS-denied to everyone but
-- service_role), the same shape as enqueue_event_reminders(). Fired by cron;
-- an operator may also invoke it manually. Returns the number of jobs
-- enqueued so a manual run is observable.
--
-- The NOT EXISTS dedupe is per (user_id), scoped to live (queued|running)
-- rows — once a recipient's prior digest drains to done/failed the next
-- weekly tick enqueues a fresh one. That's the intended weekly cadence:
-- one live digest per recipient, re-armed after the previous week's drains.
create or replace function enqueue_weekly_digests()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted integer;
begin
  insert into public.jobs (kind, payload)
  select 'weekly_digest', jsonb_build_object('user_id', s.user_id::text)
  from public.user_settings s
  where s.prefs->>'email_weekly_digest' = 'on'
    and not exists (
      select 1 from public.jobs j
      where j.kind = 'weekly_digest'
        and (j.payload->>'user_id') = s.user_id::text
        and j.status in ('queued', 'running')
    );
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

revoke execute on function enqueue_weekly_digests() from public;
grant execute on function enqueue_weekly_digests() to service_role;

-- ─────────────────── weekly schedule ───────────────────

-- Monday 08:00 UTC. Weekly (a recap of the prior 7 days, which the handler's
-- `digestWindow` look-back computes off `now()` at send time). pg_cron's
-- extension is already created by 20260602_001; `cron.schedule` is idempotent
-- on name, so re-applying this migration silently no-ops.
select cron.schedule(
  'enqueue-weekly-digest',
  '0 8 * * 1',
  $$select public.enqueue_weekly_digests()$$
);
