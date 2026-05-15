-- Security audit fix: 20260829_001 declared `segment_leaderboard_tiered`
-- as SECURITY INVOKER, but the body reads `user_profiles.date_of_birth`
-- and `user_profiles.gender` — columns that are deny-by-default per the
-- column-grant lockdown in 20260707_001 + 20260810_001. Every call from
-- `anon` (HTTP 401) and `authenticated` (HTTP 403) failed with
--     42501 permission denied for table user_profiles
-- The web caller (`fetchSegmentLeaderboardTiered`) masked the error with
-- `console.warn(...) + return []`, so the user-visible symptom was
-- silent-empty leaderboards across the entire v2 segments surface.
--
-- This forward migration:
--
-- 1. Promotes the function to SECURITY DEFINER so it can read the
--    column-gated demographics. The function owner (postgres) holds
--    full SELECT on `user_profiles`; bypassing the column grant is
--    intentional here — the gate is the function's auth.uid() check
--    + the visibility filter below, not the table grants.
--
-- 2. Manually replicates the visibility filter that RLS would have
--    enforced under SECURITY INVOKER. Route must be readable
--    (public OR own OR active club member, matching the policies
--    from 20260405_001 + 20260520_001), AND each effort's run must
--    pass `private.is_run_visible_to`. Without this, SECURITY DEFINER
--    would bypass `segment_efforts` SELECT RLS and leak private-route
--    leaderboards to any authenticated caller.
--
-- 3. Strips `gender` + computed `age` from cross-user rows. The
--    demographic filter parameters still operate on the actual
--    `user_profiles` columns internally (so the leaderboard cohort is
--    correct), but the returned `gender` and `age` columns carry the
--    caller's own values only — everyone else's row returns NULL for
--    both. Matches Strava's posture (you see the cohort, you don't
--    see the cohort members' exact age/gender).
--
-- 4. Drops the `anon` execute grant. Competitive leaderboards are
--    behind auth on every comparable platform; the share-page social
--    UI does not depend on this RPC. The old grant was a Low audit
--    finding paired with this fix.
--
-- 5. Rejects callers with `auth.uid() is null` explicitly with 42501.
--    Without this, a service-role or impersonating caller without a
--    JWT could read every public segment's leaderboard cohort silently.
--    The explicit raise also gives clients a meaningful failure shape
--    instead of "rows returned, but no idea why your own age is null".

create or replace function segment_leaderboard_tiered(
  p_segment_id uuid,
  p_gender text default null,
  p_age_band text default null,
  p_limit integer default 50
)
returns table (
  effort_id uuid,
  user_id uuid,
  run_id uuid,
  time_seconds integer,
  started_at timestamptz,
  display_name text,
  avatar_url text,
  gender text,
  age integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  age_min integer := null;
  age_max integer := null;
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'segment_leaderboard_tiered requires an authenticated caller'
      using errcode = '42501';
  end if;

  if p_age_band is not null then
    if p_age_band = '75+' then
      age_min := 75;
      age_max := 200;
    elsif p_age_band ~ '^[0-9]+-[0-9]+$' then
      age_min := split_part(p_age_band, '-', 1)::integer;
      age_max := split_part(p_age_band, '-', 2)::integer;
    else
      raise exception 'segment_leaderboard_tiered: invalid p_age_band %', p_age_band
        using errcode = '22023';
    end if;
  end if;

  return query
  select
    se.id                                                      as effort_id,
    se.user_id                                                 as user_id,
    se.run_id                                                  as run_id,
    -- segment_efforts.time_seconds is `numeric` (no precision); the
    -- function declares `integer` to match the v2 leaderboard client
    -- shape. Cast to int so plpgsql RETURN QUERY accepts the row.
    se.time_seconds::integer                                   as time_seconds,
    se.started_at,
    up.display_name,
    up.avatar_url,
    case when se.user_id = caller then up.gender else null end as gender,
    case
      when se.user_id = caller and up.date_of_birth is not null
        then extract(year from age(up.date_of_birth))::integer
      else null
    end                                                        as age
  from public.segment_efforts se
  join public.segments        s  on s.id  = se.segment_id
  join public.routes          r  on r.id  = s.route_id
  join public.user_profiles   up on up.id = se.user_id
  where se.segment_id = p_segment_id
    and (
      r.is_public = true
      or r.user_id = caller
      or (r.club_id is not null and is_club_member(r.club_id))
    )
    and private.is_run_visible_to(se.run_id, caller)
    and (p_gender is null or up.gender = p_gender)
    and (
      p_age_band is null
      or (
        up.date_of_birth is not null
        and extract(year from age(up.date_of_birth))::integer between age_min and age_max
      )
    )
  order by se.time_seconds asc, se.started_at asc
  limit p_limit;
end;
$$;

revoke execute on function segment_leaderboard_tiered(uuid, text, text, integer) from public, anon;
grant  execute on function segment_leaderboard_tiered(uuid, text, text, integer) to authenticated;
