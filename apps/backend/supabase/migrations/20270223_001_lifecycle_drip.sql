-- Lifecycle drip: staged engagement mail keyed off a user's own activity
-- timeline (roadmap "Email — engagement"). The third engagement stream after
-- the weekly digest, built on the SAME rails: the opt-in/suppression/
-- unsubscribe machinery from migration `20270108_001`, the `lifecycle_email`
-- transport shape, and the localized HTML/text builders.
--
-- ─────────────────── what a "drip" is ───────────────────
-- A new `lifecycle_drip` jobs.kind carrying `{user_id, template}`. Three
-- templates, one mechanism (mirrors how `lifecycle_email` carries welcome /
-- pro_welcome / payment_failed under one kind):
--   * drip_onboarding   — a brand-new account (created 2..6 days ago) that has
--                         never recorded a run. A "get your first run in" nudge.
--   * drip_reengagement — an established account (first run > 30 days ago) that
--                         went quiet: no activity in the last 30 days. A
--                         "we miss you" nudge.
--   * drip_streak        — an account on a live daily run streak (ran yesterday
--                         AND the day before) that has not yet run today. A
--                         "keep the streak alive" nudge.
--
-- ─────────────────────────────── THE GATE ───────────────────────────────
-- Like the weekly digest, this ships ENQUEUE-ONLY and FAIL-CLOSED at the
-- worker: a `lifecycle_drip` job that drains while `SMTP_HOST` is UNSET
-- finishes `done` WITHOUT sending (`handleLifecycleDrip` returns early when
-- `w.Email == nil`). In any environment without SMTP provisioned — including
-- prod until an operator provisions it — NOTHING is delivered; the cron is
-- harmless background churn until the send leg is turned on.
--
-- Even once SMTP is live, the worker hard-gates EVERY recipient on:
--   1. the opt-IN `email_lifecycle_drip = 'on'` pref (default off — a SEPARATE
--      marketing-consent key, never folded into the transactional
--      `email_notifications`, and SEPARATE from `email_weekly_digest`: opting
--      into one engagement stream is not consent to the other).
--   2. the `email_suppressions` hard-block list (bounce / complaint / prior
--      unsubscribe).
-- Both are re-checked in the handler (defence in depth — either can flip
-- between enqueue and send), and every drip carries an RFC 8058 one-click
-- unsubscribe.
--
-- Enabling an ACTUAL send is a deploy-time operator step, NOT a code change:
-- provision SMTP + `WEEKLY_DIGEST_UNSUB_SECRET` on the worker, land
-- SPF/DKIM/DMARC, and obtain CISO + counsel sign-off (bulk/promotional mail
-- under CAN-SPAM + GDPR/ePrivacy, unlike the transactional kinds). The code
-- path is built; the prod gate is the unset SMTP credential + the sign-off.
-- See docs/features/email.md § "Production ops".
-- ─────────────────────────────────────────────────────────────────────────
--
-- ─────────────────── jobs.kind: + lifecycle_drip ───────────────────
-- Three-file rule (apps/job_worker/CLAUDE.md): widen the CHECK here + add the
-- Go dispatch case (worker.go) + extend the pgtap test, all this commit.
-- Full re-statement at the chain end (the pattern docs in 20261211_001).
alter table public.jobs drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push', 'lifecycle_drip'
    )
  );

-- ─────────────────── enqueue function ───────────────────
--
-- ONE SECURITY DEFINER function selects all three drip cohorts and enqueues a
-- `{user_id, template}` row per match. SECURITY DEFINER so it can write
-- public.jobs (RLS-denied to everyone but service_role), the same shape as
-- enqueue_weekly_digests() / enqueue_event_reminders(). Fired by cron; an
-- operator may also invoke it manually. Returns the number of jobs enqueued so
-- a manual run is observable.
--
-- The selection is opt-IN-aware at the SQL layer (only `email_lifecycle_drip =
-- 'on'` recipients are considered) AND dedupe-safe per (user_id, template):
-- a recipient gets at most ONE queued/running drip of a given template at a
-- time. The handler tolerates at-least-once delivery (the opt-in + suppression
-- gates are the only dedupe it needs), so a coalesced backlog is strictly
-- better than a duplicated one. The opt-in is re-checked in the handler too —
-- a stale candidate here is harmless.
--
-- "Activity" for re-engagement spans the run family AND cross-modal logging
-- (gym workouts, food log) via the `activities` view (migration 20261204_001)
-- so a user who's been lifting every day isn't told "we miss you". The streak
-- cohort is run-only (a streak is a running streak), keyed off `runs`.
create or replace function enqueue_lifecycle_drip()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted integer := 0;
  n integer;
begin
  -- Opted-in recipients only, materialised once so each cohort query joins
  -- against it rather than re-scanning user_settings three times.
  create temporary table _drip_optin on commit drop as
    select s.user_id
    from public.user_settings s
    where s.prefs->>'email_lifecycle_drip' = 'on';

  -- ── 1. onboarding: account 2..6 days old, never recorded a run ──
  -- The 2-day floor lets the welcome land first; the 6-day ceiling stops the
  -- nudge from chasing a user forever (after a week, silence is the answer).
  -- "Never recorded a run" is the whole point — a user who's run is onboarded.
  insert into public.jobs (kind, payload)
  select 'lifecycle_drip',
         jsonb_build_object('user_id', o.user_id::text, 'template', 'drip_onboarding')
  from _drip_optin o
  join public.user_profiles p on p.id = o.user_id
  where p.created_at >= now() - interval '6 days'
    and p.created_at <  now() - interval '2 days'
    and not exists (
      select 1 from public.runs r where r.user_id = o.user_id
    )
    and not exists (
      select 1 from public.jobs j
      where j.kind = 'lifecycle_drip'
        and (j.payload->>'user_id') = o.user_id::text
        and (j.payload->>'template') = 'drip_onboarding'
        and j.status in ('queued', 'running')
    );
  get diagnostics n = row_count;
  inserted := inserted + n;

  -- ── 2. re-engagement: first run > 30 days ago, no activity in 30 days ──
  -- Established (has a running history) but gone quiet. "Activity" is the
  -- cross-modal union so a user still lifting/logging food isn't pestered.
  insert into public.jobs (kind, payload)
  select 'lifecycle_drip',
         jsonb_build_object('user_id', o.user_id::text, 'template', 'drip_reengagement')
  from _drip_optin o
  where exists (
      select 1 from public.runs r
      where r.user_id = o.user_id
        and r.started_at < now() - interval '30 days'
    )
    and not exists (
      select 1 from public.activities a
      where a.user_id = o.user_id
        and a.started_at >= now() - interval '30 days'
    )
    and not exists (
      select 1 from public.jobs j
      where j.kind = 'lifecycle_drip'
        and (j.payload->>'user_id') = o.user_id::text
        and (j.payload->>'template') = 'drip_reengagement'
        and j.status in ('queued', 'running')
    );
  get diagnostics n = row_count;
  inserted := inserted + n;

  -- ── 3. streak: ran yesterday AND the day before, not yet today ──
  -- A live 2+-day run streak at risk of breaking. Day bucketing is in UTC
  -- here (the cron tick is UTC); the copy never quotes a specific day count,
  -- so a one-day boundary skew at the timezone edge can't make the email lie.
  -- "Not yet today" avoids nudging a runner who already banked today's run.
  insert into public.jobs (kind, payload)
  select 'lifecycle_drip',
         jsonb_build_object('user_id', o.user_id::text, 'template', 'drip_streak')
  from _drip_optin o
  where exists (
      select 1 from public.runs r
      where r.user_id = o.user_id
        and r.started_at >= (current_date - 1)::timestamptz
        and r.started_at <  current_date::timestamptz
    )
    and exists (
      select 1 from public.runs r
      where r.user_id = o.user_id
        and r.started_at >= (current_date - 2)::timestamptz
        and r.started_at <  (current_date - 1)::timestamptz
    )
    and not exists (
      select 1 from public.runs r
      where r.user_id = o.user_id
        and r.started_at >= current_date::timestamptz
    )
    and not exists (
      select 1 from public.jobs j
      where j.kind = 'lifecycle_drip'
        and (j.payload->>'user_id') = o.user_id::text
        and (j.payload->>'template') = 'drip_streak'
        and j.status in ('queued', 'running')
    );
  get diagnostics n = row_count;
  inserted := inserted + n;

  drop table if exists _drip_optin;
  return inserted;
end;
$$;

revoke execute on function enqueue_lifecycle_drip() from public;
grant execute on function enqueue_lifecycle_drip() to service_role;

-- ─────────────────── schedule ───────────────────
--
-- Daily 09:00 UTC. The onboarding + re-engagement cohorts are slow-moving
-- (membership changes day to day); the streak cohort is intrinsically daily
-- (a streak is at risk every day). One daily tick covers all three. pg_cron's
-- extension is created by 20260602_001; `cron.schedule` is idempotent on name,
-- so re-applying this migration silently no-ops. The per-template enqueue
-- dedupe means a backlogged worker never produces a duplicate drip.
select cron.schedule(
  'enqueue-lifecycle-drip',
  '0 9 * * *',
  $$select public.enqueue_lifecycle_drip()$$
);
