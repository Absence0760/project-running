-- search_clubs returns `setof clubs` with an EXPLICIT column list (it can't
-- use `select c.*` because invite_token is column-grant-redacted by the
-- 20260801_001 lockdown — see 20260913_001). Migration 20261023_001 later
-- added `clubs.requires_activity_waiver`, growing the clubs rowtype to 16
-- columns, but search_clubs was never recreated. Postgres does not
-- re-validate an existing SQL-function body when a table it returns is
-- altered, so the function stayed creatable but became invalid at CALL time:
--
--   42P13 return type mismatch in function declared to return clubs:
--   Final statement returns too few columns
--
-- Recreate it with the missing column appended in the table's column order.
-- (SocialService.searchClubs falls back to a direct table query on RPC
-- failure, which masked this in the UI, but the RPC itself was dead.)

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
    c.is_verified,
    c.requires_activity_waiver
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

grant execute on function search_clubs(
  text, double precision, double precision, double precision, int
) to authenticated, anon;
