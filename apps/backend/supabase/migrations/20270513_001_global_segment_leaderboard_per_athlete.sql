-- One row per athlete on the CATALOGUE segment leaderboard.
--
-- `20270424000003` fixed exactly this on the route-segment board
-- (`segment_leaderboard_tiered`, issue #393): the KOM/QOM crown UI assumes a
-- Strava-style board where each athlete holds at most one rank, but the RPC
-- selected every matching effort row (order by time asc, limit p_limit) with no
-- per-athlete reduction. `global_segment_leaderboard` was written from the same
-- template and never received the fix, so the free-standing famous-segment
-- catalogue still has the original defect.
--
-- `global_segment_efforts` is unique on `(global_segment_id, run_id)`, so an
-- athlete earns one effort per run over the segment — a runner who does their
-- local famous climb weekly accumulates dozens. Against a segment where A holds
-- 60/61/62s and B holds 70s, `p_limit = 3` returns A three times and drops B
-- from the board entirely. The client cannot recover B: it calls
-- `assignCompetitionRanks` over whatever rows come back, and the LIMIT is
-- applied server-side over raw efforts, so the excluded athletes are simply not
-- in the response.
--
-- Fix: reduce to each athlete's best VISIBLE effort with a
-- `distinct on (se.user_id)` CTE BEFORE ordering + limiting, exactly as the
-- route-segment board does. Every gender / age-band / club / run-visibility /
-- block filter moves inside the CTE so the reduction picks the fastest effort
-- the caller is allowed to see — a filtered-out faster effort cannot mask a
-- slower visible one for the same athlete. `p_limit` now counts distinct
-- athletes.
--
-- Bare-body create-or-replace strips prior fixes, so this is the COMPLETE live
-- definition: the 20270411_001 body threaded through the new per-athlete CTE.
-- Signature unchanged, so no drop-and-recreate and the existing grants stand.
-- No column changes, so no row-type regeneration is owed.

create or replace function global_segment_leaderboard(
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
set search_path = public, private
as $$
declare
  age_min integer := null;
  age_max integer := null;
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'global_segment_leaderboard requires an authenticated caller'
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
      raise exception 'global_segment_leaderboard: invalid p_age_band %', p_age_band
        using errcode = '22023';
    end if;
  end if;

  -- A club filter only applies when the caller is a member of that club;
  -- otherwise it collapses to empty rather than leaking membership.
  if p_club_id is not null and not is_club_member(p_club_id) then
    return;
  end if;

  return query
  with best_per_athlete as (
    -- Each athlete's fastest effort the caller is allowed to see. All
    -- gender/age/club/visibility/block filters live HERE so the reduction
    -- ranks over the visible set — a hidden faster effort can't suppress a
    -- slower visible one for the same athlete.
    select distinct on (se.user_id)
      se.id           as effort_id,
      se.user_id      as user_id,
      se.run_id       as run_id,
      se.time_seconds as time_seconds,
      se.started_at   as started_at
    from public.global_segment_efforts se
    join public.global_segments      gs on gs.id = se.global_segment_id
    join public.user_profiles        up on up.id = se.user_id
    where se.global_segment_id = p_segment_id
      and gs.is_active = true
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
    order by se.user_id, se.time_seconds asc, se.started_at asc
  )
  select
    b.effort_id,
    b.user_id,
    b.run_id,
    b.time_seconds::integer                                    as time_seconds,
    b.started_at,
    up.display_name,
    up.avatar_url,
    case when b.user_id = caller then up.gender else null end  as gender,
    case
      when b.user_id = caller and up.date_of_birth is not null
        then extract(year from age(up.date_of_birth))::integer
      else null
    end                                                        as age
  from best_per_athlete b
  join public.user_profiles up on up.id = b.user_id
  order by b.time_seconds asc, b.started_at asc
  limit p_limit;
end;
$$;
