-- search_clubs must project the FULL clubs rowtype. It `returns setof clubs`
-- with an explicit column list (it can't `select c.*` because invite_token is
-- grant-redacted, the 20260801_001 lockdown). 20270131_001 added four club
-- link columns (website_url / instagram_url / strava_url / facebook_url)
-- without widening this function, so it returned four columns short and threw
-- 42P13 ("Final statement returns too few columns") at call time — the same
-- trap 20261220_001 fixed for requires_activity_waiver.
--
-- Re-emits the full latest body (per the "create or replace strips prior
-- fixes" rule) with the four link columns appended in clubs column order
-- (positions 17-20). The four are cross-user-readable (granted in
-- 20270131_001), so projecting them directly is fine.

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
    c.requires_activity_waiver,
    c.website_url,
    c.instagram_url,
    c.strava_url,
    c.facebook_url
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
