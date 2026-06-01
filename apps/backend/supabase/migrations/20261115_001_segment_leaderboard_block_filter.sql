-- Exclude blocked users from the segment leaderboard (persona round-5,
-- runner-woman, Critical). `segment_leaderboard_tiered` filtered efforts by
-- run visibility (`private.is_run_visible_to`) but NOT by the block graph,
-- so a runner the caller has blocked — or who has blocked the caller — still
-- appeared on the board the caller sees. A harassment vector: blocking
-- someone didn't remove them from a shared segment's leaderboard.
--
-- Fix: add `not is_blocked_either_way(caller, se.user_id)` to the WHERE. The
-- caller is already guaranteed non-null (the function raises 42501 for anon),
-- and is_blocked_either_way(caller, caller) is false, so the caller's own
-- effort is never hidden.
--
-- Bare-body create-or-replace strips prior fixes, so this is the COMPLETE
-- live definition (20261022_001 club-filter build) plus the one new clause.
-- The signature is unchanged, so no drop-and-recreate is needed.

create or replace function segment_leaderboard_tiered(
  p_segment_id uuid,
  p_gender text default null,
  p_age_band text default null,
  p_limit integer default 50,
  p_club_id uuid default null
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

  -- A club filter only applies when the caller is a member of that club;
  -- otherwise it collapses the board to empty rather than leaking membership.
  if p_club_id is not null and not is_club_member(p_club_id) then
    return;
  end if;

  return query
  select
    se.id                                                      as effort_id,
    se.user_id                                                 as user_id,
    se.run_id                                                  as run_id,
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
    -- Block-aware: hide efforts by users the caller has blocked (or who
    -- have blocked the caller). Own effort survives (block of self is false).
    and not is_blocked_either_way(caller, se.user_id)
    and (p_gender is null or up.gender = p_gender)
    and (
      p_age_band is null
      or (
        up.date_of_birth is not null
        and extract(year from age(up.date_of_birth))::integer between age_min and age_max
      )
    )
    and (
      p_club_id is null
      or exists (
        select 1 from public.club_members cm
        where cm.club_id = p_club_id
          and cm.user_id = se.user_id
          and cm.status = 'active'
      )
    )
  order by se.time_seconds asc, se.started_at asc
  limit p_limit;
end;
$$;
