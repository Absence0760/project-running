-- run_matched_tracks.source_track_url + trigger update.
--
-- The job_worker had a residual TOCTOU window in the re-upload race:
-- the pre-write recheck (read runs.track_url, compare to the URL we
-- matched against) closed the gap from O(match duration) to O(network
-- round-trip), but a re-upload landing between recheck and PATCH could
-- still have the worker overwrite the trigger's pending reset with a
-- 'matched' state pointing at a stale gz.
--
-- The clean close is a server-side CAS. The trigger now stamps
-- source_track_url with NEW.track_url on every insert/reset; the
-- worker PATCHes conditionally on
--   ?source_track_url=eq.<value-it-read-at-match-start>
-- and PostgREST returns 0 rows when the trigger has already reset it
-- behind the worker's back. The worker treats 0 rows as "discard
-- cleanly" — the OLD job exits via finish_job(done), the NEW job
-- already queued by the trigger produces the right result.

alter table run_matched_tracks
  add column source_track_url text;

-- Backfill: existing rows match against their parent's current track_url.
-- Worker will eventually rematch and populate the column for real; until
-- then the CAS just compares the value it captured (which equals
-- runs.track_url) against this backfilled value, and they match.
update run_matched_tracks rmt
   set source_track_url = r.track_url
  from runs r
 where r.id = rmt.run_id
   and rmt.source_track_url is null;

-- Trigger update: write source_track_url alongside the status reset
-- on every insert and every track_url change.
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

  insert into jobs (kind, payload)
  values (
    'map_match',
    jsonb_build_object('run_id', NEW.id, 'user_id', NEW.user_id)
  )
  on conflict do nothing;

  return NEW;
end;
$$;
