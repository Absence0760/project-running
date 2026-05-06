-- Public-runs read path with column- and metadata-key-level redaction
-- (decisions §33 wire-leak follow-up, pre-prod public-rows audit High).
--
-- Background: the runs table's `is_public = true` SELECT policy
-- (20260413_001) opens the *whole row* — every column, plus the
-- entire `metadata` jsonb bag. Pre-prod audit found four classes of
-- column / key that leak alongside the public flag:
--
--   1. `external_id` — for runs imported from Strava / Garmin / parkrun
--      this is `strava:<activity_id>`, `garmin:<file_id>`, or
--      `parkrun:<event>:<date>`. One match links a public-share link
--      to the runner's Strava / Garmin / parkrun account permanently.
--   2. `metadata` keys — `strava_id`, `garmin_id`, `imported_from`,
--      `health_connect_type`, `last_modified_at` (sync-state internal),
--      `plan_workout_id` + `workout_step_results` + `workout_adherence`
--      (training-plan linkage — leaks the runner's structured-workout
--      paces and adherence to anyone with a share link),
--      `recovered_from_crash` / `in_progress*` / `manual_entry` /
--      `indoor_estimated` / `distance_source` (internal recording state).
--   3. `route_id` — when a public run is linked to a *private* route,
--      the row exposes the route id even though RLS hides the route
--      itself. A determined viewer can probe `/share/route/<id>` and
--      learn the runner has a private course they haven't shared.
--   4. `event_id` — same shape: a public run linked to a private-club
--      event proves the user attended that club's gathering.
--
-- This migration adds a `public_runs` view that:
--   - omits `external_id` entirely (no defensible public consumer),
--   - applies a denylist of metadata keys (the audit-only / sync-state
--     / training-plan-linkage keys above),
--   - nulls `route_id` when the joined route isn't public,
--   - nulls `event_id` when the joined event's club isn't public,
--   - exposes only rows where `is_public = true`.
--
-- Two helper functions encapsulate the join checks so the view body
-- stays readable: `is_public_route_by_id` / `is_public_event_by_id`.
-- Both are SECURITY DEFINER so the public_runs view (which is
-- callable by anon / authenticated through the GRANT below) can
-- ask the join question without exposing the routes / events rows
-- directly. They return false (not null) for missing input, so
-- runs that link to a deleted route are treated as non-public-link.
--
-- The view is granted to anon + authenticated. The base table's
-- existing "public runs are readable by anyone" policy (from
-- 20260413_001) stays in place for now — a follow-up migration
-- drops it once every public-runs reader (web `fetchPublicRun` /
-- `fetchFollowingFeed` / `fetchPublicRunsByUser`, mobile
-- `api_client` equivalents, share pages, feed) has switched over.
-- This migration is intentionally additive so the client switch
-- can land independently and be revertible.
--
-- The view is NOT `security_invoker`. Default postgres views run
-- with the OWNER's permissions, which is what we want here: the
-- view is the *only* path that serves these rows publicly, and it
-- pre-applies the redaction. If we set `security_invoker = true`,
-- the underlying runs RLS would re-apply on top, defeating the
-- "tighter than the base table" intent.

create or replace function is_public_route_by_id(p_route_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_public from routes where id = p_route_id),
    false
  );
$$;

create or replace function is_public_event_by_id(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select c.is_public
      from events e
      join clubs c on c.id = e.club_id
      where e.id = p_event_id
    ),
    false
  );
$$;

grant execute on function is_public_route_by_id(uuid) to anon, authenticated;
grant execute on function is_public_event_by_id(uuid) to anon, authenticated;

-- The metadata strip list. Every audit-only / sync-state /
-- training-plan-linkage / private-recorder-state key the registry
-- (docs/metadata.md) classifies as non-public-safe. Keep this list
-- in lockstep with that document — there's a CI guard planned to
-- enforce it, but for now this list is the source of truth.
create or replace view public_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.source,
  r.is_public,
  r.track_url,
  r.created_at,
  r.updated_at,
  -- Existence-leak guards: null the link when the join target
  -- isn't itself public.
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  -- Metadata redaction. Public-safe keys (activity_type, steps, laps,
  -- title, notes, event, position, age_grade, avg_bpm, elevation_m)
  -- survive. Audit-only / private-linkage / internal keys are
  -- stripped. (`cadence` was in this list historically but is not
  -- written by any code path — derived client-side from steps /
  -- moving_time; removed from the comment in audit pass 3.)
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
    - 'manual_entry'
    - 'indoor_estimated'
    - 'distance_source'
    as metadata
from runs r
where r.is_public = true;

grant select on public_runs to anon, authenticated;
