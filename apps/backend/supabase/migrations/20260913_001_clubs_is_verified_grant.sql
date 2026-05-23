-- Repair two regressions introduced after the column-level lockdown
-- on `clubs` (20260818_001_redo_column_grant_lockdowns.sql).
--
-- The lockdown does `revoke select on clubs from authenticated, anon`
-- and then re-grants column-by-column. That makes every column added
-- to `clubs` after it deny-by-default until an explicit
-- `grant select (col) on clubs to authenticated, anon` lands, AND it
-- makes `select c.*` from any SECURITY INVOKER function body fail
-- under those roles because `invite_token` is (by design)
-- never granted.
--
-- ── 1. Grant SELECT on clubs.is_verified ──
--
-- 20260905_001 (location_point) and 20260906_001 (member_count) got
-- the new-column grant right. 20260909_001_clubs_is_verified.sql
-- missed it — the migration's own comment ("Anon + auth viewers can
-- SELECT the column via the existing `clubs` SELECT policies (no
-- policy change needed)") is wrong: row-level policies do not bypass
-- column-level grants. Both clients enumerate `is_verified` in their
-- `_clubSelectCols` (`apps/web/src/lib/data.ts:1199`,
-- `apps/mobile_android/lib/social_service.dart:20`), so every read
-- against `clubs` from a non-service-role caller fails with 42501
-- `permission denied for table clubs`. The api_client integration
-- suite caught it (`browseClubs`, `fetchClubBySlug`, `searchClubs`,
-- `fetchMyClubs`, `createClub`, `joinClub`, `createEvent` — 11 tests
-- failing on the 20260912 CI run).
--
-- ── 2. Rewrite search_clubs to honour the lockdown ──
--
-- `search_clubs` (20260905_001, refined in 20260906_001) is
-- SECURITY INVOKER and uses `select c.*`. Under the column-level
-- lockdown, that pulls in `invite_token` (intentionally ungranted
-- per 20260801_001's audit-High fix) and the entire statement
-- fails with the same 42501 — which is why the RPC falls back to
-- the client-side filter and the geocode test ("with a region
-- geocode + matching text returns a hit") returns empty.
--
-- The matching options at the call site:
--   * Granting `invite_token` would defeat 20260801_001 (anon could
--     enumerate every public club's token via the RPC).
--   * Flipping to SECURITY DEFINER would also leak `invite_token`
--     into the RPC result, because the function returns the full
--     `clubs` composite type to the caller — the function owner's
--     elevated read can't be narrowed by a column-level grant on
--     the output type.
-- So enumerate columns explicitly with `null::text as invite_token`
-- to satisfy the composite type without ever touching the sensitive
-- column. Keeps the lockdown intact AND the RPC functional.

grant select (is_verified) on clubs to authenticated, anon;

create or replace function search_clubs(
  p_query text default null,
  p_center_lng double precision default null,
  p_center_lat double precision default null,
  p_radius_m double precision default 80000,
  p_limit int default 60
) returns setof clubs language sql stable security invoker as $$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select
    c.id,
    c.owner_id,
    c.name,
    c.slug,
    c.description,
    c.avatar_url,
    c.location_label,
    c.is_public,
    c.created_at,
    c.updated_at,
    c.join_policy,
    -- invite_token: intentionally redacted to honour the
    -- 20260801_001 lockdown. Admin reads go through
    -- get_club_invite_token().
    null::text,
    c.location_point,
    c.member_count,
    c.is_verified
  from clubs c, center
  where c.is_public = true
    and (
      p_query is null
      or c.name ilike '%' || p_query || '%'
      or c.location_label ilike '%' || p_query || '%'
      or (
        center.pt is not null
        and c.location_point is not null
        and ST_DWithin(c.location_point, center.pt, p_radius_m)
      )
    )
  order by
    case when center.pt is not null and c.location_point is not null
      then ST_Distance(c.location_point, center.pt)
      else null
    end asc nulls last,
    c.member_count desc,
    c.created_at desc
  limit p_limit;
$$;
