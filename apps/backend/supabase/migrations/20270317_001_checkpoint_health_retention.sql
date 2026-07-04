-- GDPR Art 5(1)(e) storage-limitation for the Art 9 health fields on
-- checkpoint_crossings (audit/db-design 2026-07-03; source table
-- 20270201_001_race_director_checkpoints.sql).
--
-- The weigh-in / medical fields (body_weight_kg, body_weight_pct,
-- medical_hold, medical_note) exist to keep a runner safe DURING a race and to
-- support the immediate post-race medical follow-up. They have no long-term
-- purpose, unlike the crossing's in/out stamps, which ARE the race's split
-- results (public results page, same permanence as event_results).
--
-- So this purge SCRUBS the health columns rather than deleting rows: 90 days
-- after a crossing was first recorded (recorded_at), the Art 9 fields are
-- nulled and the split times survive. 90 days mirrors the notifications
-- window from 20260922_001 — enough headroom for an incident/medical review
-- after a race, defensible under storage-limitation, and the interval lives
-- in one place here so counsel can tighten it.

create or replace function private.purge_stale_checkpoint_health_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scrubbed bigint;
begin
  with scrubbed as (
    update checkpoint_crossings
    set body_weight_kg  = null,
        body_weight_pct = null,
        medical_hold    = false,
        medical_note    = null
    where recorded_at < now() - interval '90 days'
      and (body_weight_kg is not null
        or body_weight_pct is not null
        or medical_hold
        or medical_note is not null)
    returning 1
  )
  select count(*) into v_scrubbed from scrubbed;
  if v_scrubbed > 0 then
    raise notice 'purge_stale_checkpoint_health_data: scrubbed % row(s)', v_scrubbed;
  end if;
end;
$$;

revoke all on function private.purge_stale_checkpoint_health_data() from public, anon, authenticated;

select cron.schedule(
  'purge-stale-checkpoint-health-data',
  '47 3 * * *',
  $$select private.purge_stale_checkpoint_health_data()$$
);

comment on function private.purge_stale_checkpoint_health_data() is
  'GDPR Art 5(1)(e) storage-limitation for Art 9 health data: nulls the '
  'weigh-in / medical columns on checkpoint_crossings 90 days after '
  'recorded_at, keeping the in/out split times (they are race results). '
  'Scheduled by pg_cron entry `purge-stale-checkpoint-health-data` '
  '(03:47 UTC daily). Window can be tightened by editing the interval here.';
