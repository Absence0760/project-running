-- Lifecycle drip: add the drip_first_week cohort (hunt-newrunner 2026-07-02).
--
-- A new runner who signs up, records their first run, then lapses for a few
-- days fell between the existing cohorts: drip_onboarding excludes anyone
-- who has ever logged a run, and drip_reengagement waits for 30 days of
-- silence. The 2-6-day window right after the first run is the single
-- highest-churn stretch for a brand-new runner, so a fourth template —
-- drip_first_week, "the second run makes it a habit" — covers exactly it:
-- 1-2 runs total, the most recent 2..5 days ago, none since.
--
-- Same rails as 20270223_001: enqueue-only + fail-closed at the worker
-- (nothing sends without SMTP + the opt-IN email_lifecycle_drip pref + the
-- suppression hard-block; the CISO/counsel sign-off gates the send leg, not
-- this code). The worker's dripTemplates set + localized catalogue gained
-- the template in the same commit (three-file rule; jobs.kind unchanged —
-- the new template rides the existing lifecycle_drip kind).
--
-- Per the backend "bare CREATE OR REPLACE strips prior fixes" gotcha, the
-- function below is the LATEST live body (20270223_001) with only the
-- fourth cohort block added — NOT rewritten.

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


  -- ── 4. first-week lapse: 1-2 runs total, the latest 2..5 days ago ──
  -- The habit-formation gap between the other two cohorts (hunt-newrunner
  -- 2026-07-02): drip_onboarding stops matching the moment run #1 lands, and
  -- drip_reengagement needs 30 days of silence — so a runner who logged their
  -- first run or two and then went quiet in the very week habits form got no
  -- nudge at all. One-shot per user: unlike the other cohorts this dedupe
  -- includes 'done' (jobs retention is 30 days, migration 20260928_001 — far
  -- beyond the 3-day cohort window), so the nudge can never fire twice.
  insert into public.jobs (kind, payload)
  select 'lifecycle_drip',
         jsonb_build_object('user_id', o.user_id::text, 'template', 'drip_first_week')
  from _drip_optin o
  where (select count(*) from public.runs r where r.user_id = o.user_id) between 1 and 2
    and (select max(r.started_at) from public.runs r where r.user_id = o.user_id)
          >= now() - interval '5 days'
    and (select max(r.started_at) from public.runs r where r.user_id = o.user_id)
          <  now() - interval '2 days'
    and not exists (
      select 1 from public.jobs j
      where j.kind = 'lifecycle_drip'
        and (j.payload->>'user_id') = o.user_id::text
        and (j.payload->>'template') = 'drip_first_week'
        and j.status in ('queued', 'running', 'done')
    );
  get diagnostics n = row_count;
  inserted := inserted + n;

  drop table if exists _drip_optin;
  return inserted;
end;
$$;
