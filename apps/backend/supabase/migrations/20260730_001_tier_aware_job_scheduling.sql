-- Tier-aware job scheduling. Pro / lifetime users jump the queue;
-- free users wait FREE_TIER_DELAY_SECONDS (30 s today) before their
-- enqueued job becomes claimable. The worker's claim_next_job already
-- filters `scheduled_at <= now()` and orders by `scheduled_at, id`,
-- so a Pro job (scheduled_at = now()) is always claimable strictly
-- before a free job (scheduled_at = now() + 30 s) enqueued at the
-- same wall-clock moment.
--
-- Why this shape (vs. a `priority` integer column):
--   - The existing `jobs_queued` partial index on (scheduled_at, kind)
--     already gives the worker the right ordering. Adding a column
--     would cost an index rebuild + a worker change.
--   - `scheduled_at` already meant "claimable when ≥ now()", so
--     overloading it with priority semantics keeps the data model
--     small.
--   - 30 s is short enough that free users still see "matched track"
--     within a minute under nominal load; long enough that Pro users
--     measurably jump the queue under contention. Tunable via this
--     migration if real-world numbers want a different number.
--
-- Redeems the existing /settings/upgrade Pro promise — "Priority
-- processing — Faster responses when the service is under heavy
-- load." Until this migration that copy was unredeemed in code:
-- claim_next_job took FIFO only and the trigger stamped scheduled_at
-- with default `now()` for everyone.
--
-- The helper `job_scheduled_at_for_user(p_user_id uuid)` is the
-- single source of truth. ANY future job kind (strava_backfill,
-- bulk_rematch, photo_transform, …) calls this helper at enqueue
-- time so the tier-priority semantic is consistent across the
-- queue. Don't inline `case ... subscription_tier ...` at enqueue
-- sites; use the helper.
--
-- Free-tier delay constant: bump it here in one place if real-world
-- numbers want a different number. Watch the `decisions.md` entry
-- when you do — the tier semantic is documented there too.

-- ============================================================
-- 1. Helper: scheduled_at for a job belonging to user p_user_id
-- ============================================================
--
-- Returns now() for pro / lifetime; now() + 30 s for free or any
-- other / unknown tier (conservative — better to defer than to
-- accidentally promote an unknown caller). SECURITY DEFINER so the
-- trigger / RPC callers don't need direct user_profiles SELECT.

create or replace function job_scheduled_at_for_user(p_user_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select case
    when coalesce(
           (select subscription_tier
              from user_profiles
             where id = p_user_id),
           'free'
         ) in ('pro', 'lifetime')
    then now()
    else now() + interval '30 seconds'
  end;
$$;

revoke execute on function job_scheduled_at_for_user(uuid) from public;
grant execute on function job_scheduled_at_for_user(uuid) to authenticated, service_role;

-- ============================================================
-- 2. Update the auto-enqueue trigger to apply tier-priority
-- ============================================================
--
-- Re-create the trigger function from 20260611_001 with the helper
-- threaded into the `insert into jobs (..., scheduled_at) ...`
-- line. Same body otherwise.

create or replace function runs_enqueue_match_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.track_url is null or NEW.track_url = '' then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    insert into run_matched_tracks (run_id, status, source_track_url)
    values (NEW.id, 'pending', NEW.track_url)
    on conflict (run_id) do nothing;
  elsif TG_OP = 'UPDATE'
        and NEW.track_url is distinct from OLD.track_url then
    insert into run_matched_tracks (run_id, status, source_track_url)
    values (NEW.id, 'pending', NEW.track_url)
    on conflict (run_id) do update
    set status = 'pending',
        source_track_url = NEW.track_url,
        matched_track_url = null,
        attempts = 0,
        matched_at = null,
        error_message = null,
        algorithm = null,
        algorithm_version = null;
  else
    return NEW;
  end if;

  -- Queue the matcher with tier-aware scheduled_at. Idempotent
  -- against jobs_dedupe_map_match.
  insert into jobs (kind, payload, scheduled_at)
  values (
    'map_match',
    jsonb_build_object('run_id', NEW.id, 'user_id', NEW.user_id),
    job_scheduled_at_for_user(NEW.user_id)
  )
  on conflict do nothing;

  return NEW;
end;
$$;

-- ============================================================
-- 3. Update the manual re-match RPC to apply tier-priority
-- ============================================================
--
-- Rebuild enqueue_run_rematch (20260612_001) with the helper.
-- Manual user-driven re-match should also respect tier priority —
-- a Pro user clicking "Re-match this run" goes to the front of the
-- queue, a free user waits 30 s.

create or replace function enqueue_run_rematch(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_run_user_id uuid;
  v_track_url text;
begin
  if v_caller is null then
    raise exception 'enqueue_run_rematch: not authenticated' using errcode = '42501';
  end if;

  select user_id, track_url into v_run_user_id, v_track_url
  from runs where id = p_run_id;

  if v_run_user_id is null then
    raise exception 'enqueue_run_rematch: run not found' using errcode = 'P0002';
  end if;
  if v_run_user_id <> v_caller then
    raise exception 'enqueue_run_rematch: not the run owner' using errcode = '42501';
  end if;
  if v_track_url is null or v_track_url = '' then
    raise exception 'enqueue_run_rematch: run has no track' using errcode = '22000';
  end if;

  insert into run_matched_tracks (run_id, status, source_track_url)
  values (p_run_id, 'pending', v_track_url)
  on conflict (run_id) do update
  set status = 'pending',
      source_track_url = v_track_url,
      matched_track_url = null,
      attempts = 0,
      matched_at = null,
      error_message = null,
      algorithm = null,
      algorithm_version = null;

  insert into jobs (kind, payload, scheduled_at)
  values (
    'map_match',
    jsonb_build_object('run_id', p_run_id, 'user_id', v_run_user_id),
    job_scheduled_at_for_user(v_run_user_id)
  )
  on conflict do nothing;

  return jsonb_build_object('ok', true);
end;
$$;
