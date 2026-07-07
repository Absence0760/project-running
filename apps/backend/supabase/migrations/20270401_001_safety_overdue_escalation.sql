-- Safety net: overdue-runner escalation (docs/features/safety.md).
--
-- 1. Fix the live-stub mis-fire in the two run-INSERT notifiers: a live
--    broadcast pre-creates the runs row (beginLiveBroadcast — is_public,
--    duration 0, metadata.in_progress=true), so `runs_enqueue_safety_finish`
--    and `trg_notify_run_completed` fired a bogus "finished" at share START,
--    and the real save (an upsert-UPDATE on the same row) fired nothing.
--    Both now skip in-progress rows and fire on the in_progress→saved
--    transition instead. Auto-live-share would have turned this from an
--    edge case into every-run behaviour.
-- 2. enqueue_safety_overdue_emails(): pg_cron scan (every 5 min) that emails
--    every confirmed safety contact once when a live-broadcast run has gone
--    silent past the owner's `safety_overdue_minutes` pref (null = off,
--    fail-closed). Idempotent via a metadata.safety_escalated_at stamp.
-- 3. public_runs: strip the new server-written metadata key.

-- ─────────────────── 1a. safety finish emails: skip stubs, fire on save ───────────────────

create or replace function enqueue_safety_finish_emails()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A live-broadcast stub is not a finish. The finish for a broadcast run
  -- arrives as the saveRun upsert-UPDATE that clears metadata.in_progress.
  if coalesce(new.metadata->>'in_progress', '') = 'true' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and coalesce(old.metadata->>'in_progress', '') <> 'true' then
    -- Ordinary edits (title, privacy, gear) must not re-alert.
    return new;
  end if;

  if new.started_at < now() - interval '24 hours' then
    return new;
  end if;

  insert into public.jobs (kind, payload)
  select
    'safety_email',
    jsonb_build_object(
      'template', 'finish',
      'contact_user_id', sc.contact_user_id,
      'contact_email', sc.contact_email,
      'owner_name', coalesce(p.display_name, ''),
      'run_id', new.id::text,
      'distance_m', new.distance_m,
      'duration_s', new.duration_s
    )
  from safety_contacts sc
  left join user_profiles p on p.id = new.user_id
  where sc.owner_id = new.user_id
    and sc.confirmed_at is not null;

  return new;
end;
$$;

revoke execute on function enqueue_safety_finish_emails() from public;

drop trigger if exists runs_enqueue_safety_finish on runs;
create trigger runs_enqueue_safety_finish
  after insert or update on runs
  for each row execute function enqueue_safety_finish_emails();

-- ─────────────────── 1b. follower run_completed: same transition fix ───────────────────

create or replace function notify_run_completed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.metadata->>'in_progress', '') = 'true' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and coalesce(old.metadata->>'in_progress', '') <> 'true' then
    return new;
  end if;

  if new.is_public is not true
     or new.started_at < now() - interval '24 hours' then
    return new;
  end if;

  insert into notifications (user_id, actor_id, kind, run_id)
  select f.follower_id, new.user_id, 'run_completed', new.id
  from user_follows f
  where f.followee_id = new.user_id
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists trg_notify_run_completed on runs;
create trigger trg_notify_run_completed
  after insert or update on runs
  for each row execute function notify_run_completed();

-- ─────────────────── 2. overdue scan ───────────────────

-- One alert per run, ever: the CTE stamps metadata.safety_escalated_at in
-- the same statement that selects the rows, so a concurrent double-fire of
-- the cron can't enqueue twice (the second run no longer matches). The
-- stamp UPDATE keeps in_progress=true, so the transition triggers above
-- don't see a stub→saved edge and stay quiet. The eventual saveRun upsert
-- overwrites metadata wholesale, which is fine — the run is finished and
-- out of the scan's predicate by then.
create or replace function public.enqueue_safety_overdue_emails()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with overdue as (
    select
      r.id,
      r.user_id,
      r.started_at,
      greatest(r.started_at, coalesce(max(p.at), r.started_at)) as last_seen_at,
      max(p.at) is not null as has_ping
    from runs r
    join user_settings us on us.user_id = r.user_id
    left join live_run_pings p on p.run_id = r.id
    where coalesce(r.metadata->>'in_progress', '') = 'true'
      and r.metadata->>'safety_escalated_at' is null
      and r.started_at > now() - interval '24 hours'
      and us.prefs->>'safety_overdue_minutes' ~ '^[0-9]+$'
      and (us.prefs->>'safety_overdue_minutes')::int >= 10
      and exists (
        select 1 from safety_contacts sc
        where sc.owner_id = r.user_id and sc.confirmed_at is not null
      )
    group by r.id, r.user_id, r.started_at,
             (us.prefs->>'safety_overdue_minutes')::int
    having greatest(r.started_at, coalesce(max(p.at), r.started_at))
           < now() - make_interval(mins => (us.prefs->>'safety_overdue_minutes')::int)
  ),
  stamped as (
    update runs r
    set metadata = coalesce(r.metadata, '{}'::jsonb)
                   || jsonb_build_object('safety_escalated_at', now())
    from overdue o
    where r.id = o.id
    returning r.id, o.user_id, o.started_at, o.last_seen_at, o.has_ping
  )
  insert into public.jobs (kind, payload)
  select
    'safety_email',
    -- strip_nulls: a broadcast with zero pings has no last_seen_at at
    -- all (started_at is the floor), and an external contact has no
    -- contact_user_id — omit rather than carry JSON nulls.
    jsonb_strip_nulls(jsonb_build_object(
      'template', 'overdue',
      'contact_user_id', sc.contact_user_id,
      'contact_email', sc.contact_email,
      'owner_name', coalesce(pr.display_name, ''),
      'run_id', s.id::text,
      'started_at', s.started_at,
      'last_seen_at', case when s.has_ping then s.last_seen_at end
    ))
  from stamped s
  join safety_contacts sc
    on sc.owner_id = s.user_id and sc.confirmed_at is not null
  left join user_profiles pr on pr.id = s.user_id;
end;
$$;

revoke execute on function public.enqueue_safety_overdue_emails() from public, anon, authenticated;

-- The in-progress + unstamped scan predicate is a tiny partial set; index
-- it so the 5-minute cron never seq-scans a large runs table.
create index if not exists runs_live_in_progress_idx
  on runs (started_at)
  where (metadata->>'in_progress') = 'true';

select cron.schedule(
  'enqueue-safety-overdue-emails',
  '*/5 * * * *',
  $$select public.enqueue_safety_overdue_emails()$$
);

-- ─────────────────── 3. public_runs strips the stamp ───────────────────

-- Same column list as 20270325_001 — only the metadata denylist grows, so
-- CREATE OR REPLACE is safe (no column-shape change).
create or replace view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.elevation_gain_m,
  r.source,
  r.activity_type,
  r.is_dnf,
  r.is_public,
  r.created_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  r.race_listing_id,
  (r.track_url is not null) as has_track,
  r.fastest_5k_s,
  r.fastest_10k_s,
  r.fastest_half_marathon_s,
  r.fastest_marathon_s,
  coalesce(r.metadata, '{}'::jsonb)
    - 'strava_id'
    - 'garmin_id'
    - 'imported_from'
    - 'imported_at'
    - 'health_connect_type'
    - 'strava_activity_type'
    - 'source_file'
    - 'max_bpm'
    - 'plan_workout_id'
    - 'workout_step_results'
    - 'workout_adherence'
    - 'last_modified_at'
    - 'recovered_from_crash'
    - 'in_progress_saved_at'
    - 'in_progress'
    - 'safety_escalated_at'
    - 'manual_entry'
    - 'indoor_estimated'
    - 'distance_source'
    - 'race_name'
    - 'bib'
    - 'overall_place'
    - 'chip_time'
    - 'gun_time'
    - 'age_group_place'
    - 'age_group'
    - 'perceived_effort'
    - 'run_number'
    as metadata
from runs r
where r.is_public = true;

revoke all on public.public_runs from public, anon, authenticated;
grant select on public_runs to anon, authenticated;
