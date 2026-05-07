-- /audit/all High: `event_results.run_id` is exposed to every
-- authenticated user who can read any public-club event's
-- leaderboard. `run_id` is the uuid of a `runs` row; when a
-- participant submits a result and links it to a private run, the
-- leaderboard surface returns that run uuid in clear to all readers.
-- Combined with `is_run_visible_to(run_id, auth.uid())` (granted to
-- anon for the share-page social affordances), a caller can confirm
-- the existence of the linked run — bridging the public leaderboard
-- to a private run the participant never chose to share.
--
-- Fix: introduce `event_results_redacted` view that masks `run_id`
-- with NULL for non-owner viewers and switch `fetchEventResults` over
-- to read from the view. The view runs `security_invoker = on` so
-- the existing RLS on `event_results` (which gates visibility through
-- the parent event/club) still applies — we only narrow which
-- columns each row exposes.
--
-- Owner reads keep working: the owner's own row evaluates the
-- `case when user_id = auth.uid()` branch as true and returns their
-- run_id unchanged. Non-owner rows resolve to null. Anon callers
-- (auth.uid() is null) get null on every row, which matches intent.

create or replace view event_results_redacted as
select
  event_id,
  instance_start,
  user_id,
  duration_s,
  distance_m,
  rank,
  finisher_status,
  age_grade_pct,
  note,
  created_at,
  updated_at,
  organiser_approved,
  case
    when user_id = auth.uid() then run_id
    else null
  end as run_id
from event_results;

alter view event_results_redacted set (security_invoker = on);

grant select on event_results_redacted to anon, authenticated;

comment on view event_results_redacted is
  'Leaderboard read surface for event_results. Masks run_id for non-owner '
  'viewers — closes the cross-link from a public leaderboard to a private '
  'run that the participant linked to their result. Owner reads return the '
  'unmasked run_id via the auth.uid() case branch.';
