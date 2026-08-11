-- Three narrow leaks, all in SECURITY DEFINER surfaces.
--
-- ── 1. A shadow-hidden route still feeds the anon discovery heatmap ────────
--
-- `heatmap_points_in_bbox` gates on `r.is_public = true` alone. Its sibling
-- `discoverable_routes_in_bbox` — the same anon-executable discovery family —
-- gates on `is_public = true AND shadow_hidden = false`, and so does the
-- `public_routes` view. Shadow-hiding is the moderator action that removes a
-- route from public surfaces without telling its author; leaving it out here
-- means the geometry of a hidden route keeps drawing heat for anon viewers.
-- That is the exact bypass class 20270329_001 was written to close.
--
-- Impact is bounded (points only — no id, no name, no author) which is why it
-- was not caught by the public-row audits, but it is still the hidden route's
-- shape on a public map.
--
-- ── 2. Two concurrent completions emit two "challenge complete" alerts ─────
--
-- `recompute_challenge_completion` checks `challenge_badges` for an existing
-- award, then later inserts the badge `on conflict do nothing` and inserts a
-- notification unconditionally. The check and the insert are not one atomic
-- step, so two callers racing the same completion both pass the check, both
-- reach the tail, and the badge dedupes while the NOTIFICATION does not — the
-- runner gets the same "challenge complete" twice.
--
-- The race is easy to hit now that the client fans the RPC opportunistically
-- on save (`recomputeChallengesForRun` on web, `SocialService
-- .recomputeChallengesForRuns` from SyncService on mobile) while the daily
-- cron sweep may be running the same recompute.
--
-- Fix: make the badge insert itself the serialization point. `INSERT … ON
-- CONFLICT DO NOTHING` sets FOUND false when it conflicts, so exactly one
-- caller proceeds to the participant stamp and the notification.
--
-- ── 3. clip_track_for_user is an executable privacy-zone oracle ────────────
--
-- 20260915_001 revoked EXECUTE from `anon` with the reasoning that the RPC
-- "lets a determined attacker iteratively probe the clipping output to
-- reconstruct approximate privacy-zone geometry", and kept the grant to
-- `authenticated` for "in-DB callers with a user JWT".
--
-- That reasoning applies unchanged to `authenticated`: signup is free and
-- unthrottled, so the role is not a trust boundary here. The function trims
-- LEADING in-zone points, so a 3-point probe returns length 2 when the probe
-- is inside a zone and length 3 when it is outside — a clean one-bit oracle.
-- Roughly 40 calls binary-search a victim's privacy-zone centre (usually their
-- home) to metre precision, and the radius follows. It is a PostgREST RPC, so
-- none of the Edge Function rate limiting applies.
--
-- Every legitimate consumer keeps working: `clip_route_for_viewer`,
-- `privacy_aware_route_geom`, `route_markers_for_viewer` and the
-- `clip-public-track` Edge Function are SECURITY DEFINER or service-role and
-- do not need the CALLER to hold the grant. The one direct client caller,
-- web's `clipTrackForUser`, had no production call sites left — the
-- unclipped-blob pattern it belonged to was removed by 20260619_001 — and is
-- deleted in the same change as this migration.

create or replace function heatmap_points_in_bbox(
  p_min_lng double precision,
  p_min_lat double precision,
  p_max_lng double precision,
  p_max_lat double precision,
  p_max_points integer default 5000
)
returns table(lng double precision, lat double precision)
language sql
stable parallel safe security definer
set search_path to 'public', 'extensions'
as $$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography as g
  ),
  hit_routes as (
    select r.geom, s.prefs->'privacy_zones' as zones
    from routes r
    left join user_settings s on s.user_id = r.user_id
    cross join bbox
    where r.is_public = true
      and r.shadow_hidden = false
      and r.geom is not null
      and r.geom && bbox.g
    limit 200
  ),
  densified as (
    select
      (ST_DumpPoints(
        ST_LineInterpolatePoints(
          hr.geom::geometry,
          least(1.0, 50.0 / greatest(ST_Length(hr.geom), 50.0))
        )
      )).geom as pt,
      hr.zones
    from hit_routes hr
  )
  select
    ST_X(pt) as lng,
    ST_Y(pt) as lat
  from densified
  where zones is null
     or not privacy_in_any_zone(ST_Y(pt), ST_X(pt), zones)
  limit p_max_points;
$$;

create or replace function recompute_challenge_completion(p_challenge_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_metric        text;
  v_activity_type text;
  v_goal          numeric;
  v_starts        timestamptz;
  v_ends          timestamptz;
  v_value         numeric;
begin
  -- auth.uid() is null for the cron sweep / service-role path. For an
  -- authenticated caller it must match the user whose completion is recomputed
  -- — no driving another user's badge / completed_at / notification.
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception
      'recompute_challenge_completion: caller cannot recompute another user'
      using errcode = '42501';
  end if;

  select c.metric, c.activity_type, c.goal_value, c.starts_at, c.ends_at
    into v_metric, v_activity_type, v_goal, v_starts, v_ends
  from challenges c
  where c.id = p_challenge_id;

  if v_metric is null or v_goal is null then
    return;
  end if;

  if not exists (
    select 1 from challenge_participants pp
    where pp.challenge_id = p_challenge_id and pp.user_id = p_user_id
  ) then
    return;
  end if;

  -- Cheap pre-check: skips the aggregate for the already-awarded common case.
  -- NOT the dedupe — the badge insert below is.
  if exists (
    select 1 from challenge_badges b
    where b.challenge_id = p_challenge_id and b.user_id = p_user_id
  ) then
    return;
  end if;

  select coalesce(
    case v_metric
      when 'distance' then sum(r.distance_m)
      when 'duration' then sum(r.duration_s)::numeric
      when 'vert' then sum(coalesce(r.elevation_gain_m, 0))
      when 'activity_count' then count(r.id)::numeric
      when 'streak_days' then count(distinct (r.started_at at time zone 'UTC')::date)::numeric
    end,
    0
  )
  into v_value
  from runs r
  where r.user_id = p_user_id
    and r.started_at >= v_starts
    and r.started_at < v_ends
    and r.is_dnf = false
    and (v_activity_type is null or r.activity_type = v_activity_type);

  if v_value >= v_goal then
    insert into challenge_badges (user_id, challenge_id, metric, final_value)
    values (p_user_id, p_challenge_id, v_metric, v_value)
    on conflict (user_id, challenge_id) do nothing;

    -- The badge insert is the serialization point. On conflict it inserts no
    -- row and FOUND is false, so the caller that lost the race stops here
    -- rather than emitting a second `challenge_complete` for the same award.
    if not found then
      return;
    end if;

    update challenge_participants
    set completed_at = now()
    where challenge_id = p_challenge_id
      and user_id = p_user_id
      and completed_at is null;

    insert into notifications (user_id, kind, challenge_id)
    values (p_user_id, 'challenge_complete', p_challenge_id);
  end if;
end;
$$;

revoke execute on function clip_track_for_user(uuid, jsonb) from authenticated;
