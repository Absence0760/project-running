-- Close the §206 shadow-hidden backstop on the five SECURITY DEFINER bodies
-- that inlined a copy of a visibility predicate instead of calling it.
--
-- `20270329_001` tightened `private.is_route_visible_to` and the
-- `user_profiles` SELECT policy; `20270328_001` tightened the clubs + events
-- policies. Every consumer that CALLS those inherited the fix. The consumers
-- that had pasted the predicate into their own body did not, and SECURITY
-- DEFINER means RLS cannot back them up — so the moderation control fails
-- open exactly where it is least visible.
--
-- Verified live before the fix, on the schema this migration lands against:
-- a stranger reading `segment_leaderboard_tiered` for a segment on a
-- shadow-hidden public route got 1 board row, while the same caller reading
-- `segment_efforts` under RLS got 0 and `private.is_route_visible_to` returned
-- false for that route.
--
-- The five, and what each was leaking:
--
--   1. segment_leaderboard_tiered — route branch `r.is_public = true`, where
--      `private.is_route_visible_to` also demands `shadow_hidden = false`. A
--      caller holding a segment id read a moderation-hidden route's entire
--      board, after 20270329_001 closed that route's waypoints, photos,
--      reviews, segments, markers and condition reports.
--   2. segment_leaderboard_tiered, 3. global_segment_leaderboard,
--   4. challenge_leaderboard — all three join `user_profiles` under DEFINER,
--      bypassing "authenticated read profiles except shadow-hidden", so a
--      moderation-hidden athlete's display name and avatar kept rendering on
--      a public leaderboard.
--   5. is_event_visible (and 6. claim_event_result, which pastes the same
--      predicate and whose comment calls itself a "mirror of the event_results
--      SELECT visibility chain") — club branch `c.is_public = true` where the
--      events RLS policy has read `is_public and shadow_hidden = false` since
--      20270328_001. `is_event_visible` is the oracle behind the
--      `event_pricing`, `event_checkpoints` and `checkpoint_crossings` SELECT
--      policies, so a hidden club's pricing, checkpoints and runner crossing
--      times stayed readable through the base tables the events policy had
--      already closed.
--
-- ── Delegate, don't re-inline ──
-- Re-inlining is what created this drift, so each fix calls the canonical
-- oracle rather than pasting a corrected copy: `private.is_route_visible_to`
-- for routes, `is_public_club_by_id` (`is_public and not shadow_hidden`,
-- coalesced false) for clubs. In `segment_leaderboard_tiered` the route check
-- also moves OUT of the per-row CTE: every effort on a segment shares one
-- route, so the visibility question is asked once per call instead of once per
-- effort row, and the `routes` join disappears with it. The segment lookup
-- that join used to provide is preserved by the null-route_id early return.
--
-- The profile half stays an inline `(shadow_hidden = false or id = caller)`
-- clause, matching the form `search_user_profiles` / `public_profile_by_id` /
-- `discoverable_runners_near` already use. It is one column on an already
-- joined row rather than a three-branch predicate with a membership subquery,
-- and inventing an oracle for it here would leave those three inconsistent
-- with it — the drift risk this migration is about.
--
-- ── Redact the identity, do not drop the row ──
-- On all three leaderboards a hidden athlete keeps their row and their rank;
-- only `display_name` + `avatar_url` go null. Dropping the row would be the
-- wrong kind of narrowing twice over: it would shift every slower athlete's
-- displayed rank, misreporting a ranking whose underlying efforts the viewer
-- is entitled to see, and it would silently reintroduce the §594 divergence —
-- `segment_effort_ranks` is SECURITY INVOKER over `segment_efforts`, which
-- carries no profile gate, so the chip would keep counting an athlete the
-- board had dropped. Moderation hides a person, not other people's positions.
-- Both web surfaces already render a null name through a fallback label
-- (`segments.runnerFallback`, `checkpoint.anonymousRunner`), so no client
-- change is owed. The caller's own row is exempt, mirroring the soft-hide
-- carve-out in the policy itself (hidden pending review, not a deletion).
--
-- ── Direction of travel: closing only ──
-- Every change removes rows or blanks a name; none admits anything new. A
-- route that was visible stays visible (`is_route_visible_to`'s owner and
-- club-member branches are the same two the inline predicate had, and its
-- public branch is strictly narrower), a club that was visible stays visible,
-- and a non-hidden athlete's name is untouched. `is_public_club_by_id`
-- coalesces a missing club to false, so the club branch fails closed on a
-- dangling reference too.
--
-- ── Online safety ──
-- `create or replace function` only, five bodies, no table DDL — no lock is
-- taken on any table (docs/backend/migration_locks.md). Signatures, return
-- types, volatility and search_path are unchanged, so no drop-and-recreate,
-- the existing grants stand, and no row-type regeneration is owed. Each body
-- below is the COMPLETE live definition per the bare-body rule: a
-- create-or-replace that dropped a prior fix would be a silent regression, so
-- the per-athlete reduction (§594 / issue #393), the block filter, the club
-- filter and the demographic masking are all carried through unchanged.

-- ── 1. segment_leaderboard_tiered ──
-- Live body is 20270424000003 (the per-athlete reduction), threaded through
-- the delegated route check + the profile carve-out. search_path must keep
-- `private`: is_club_member moved there in 20261120_001.
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
set search_path = public, private
as $$
declare
  age_min integer := null;
  age_max integer := null;
  caller uuid := auth.uid();
  v_route_id uuid;
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

  -- Every effort on a segment hangs off ONE route, so route visibility is a
  -- per-call question, not a per-row one. A missing segment leaves v_route_id
  -- null and collapses the board, which is also what the dropped
  -- `join segments` used to do.
  select s.route_id into v_route_id
  from public.segments s
  where s.id = p_segment_id;

  if v_route_id is null or not private.is_route_visible_to(v_route_id, caller) then
    return;
  end if;

  -- A club filter only applies when the caller is a member of that club;
  -- otherwise it collapses the board to empty rather than leaking membership.
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
    from public.segment_efforts se
    join public.user_profiles   up on up.id = se.user_id
    where se.segment_id = p_segment_id
      and private.is_run_visible_to(se.run_id, caller)
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
    case when up.shadow_hidden = false or up.id = caller
      then up.display_name end                                 as display_name,
    case when up.shadow_hidden = false or up.id = caller
      then up.avatar_url end                                   as avatar_url,
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

-- ── 2. global_segment_leaderboard ──
-- Live body is 20270513_001. Catalogue segments have no parent route, so only
-- the profile carve-out applies here.
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
    case when up.shadow_hidden = false or up.id = caller
      then up.display_name end                                 as display_name,
    case when up.shadow_hidden = false or up.id = caller
      then up.avatar_url end                                   as avatar_url,
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

-- ── 3. challenge_leaderboard ──
-- Live body is 20270407_001 (the DNF exclusion). The left join stays a left
-- join: a participant with no profile row already yielded a null name, and a
-- hidden participant now degrades to exactly that same shape rather than
-- vanishing from the ranking. search_path is `public` only — this body calls
-- no private helper.
create or replace function challenge_leaderboard(
  p_challenge_id uuid,
  p_by_team boolean default false
)
returns table (
  user_id uuid,
  display_name text,
  team_club_id uuid,
  value numeric,
  rank bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_metric        text;
  v_activity_type text;
  v_starts        timestamptz;
  v_ends          timestamptz;
begin
  if not is_challenge_visible(p_challenge_id) then
    return;
  end if;

  select c.metric, c.activity_type, c.starts_at, c.ends_at
    into v_metric, v_activity_type, v_starts, v_ends
  from challenges c
  where c.id = p_challenge_id;

  if v_metric is null then
    return;
  end if;

  if p_by_team then
    return query
    with per_team as (
      select
        pp.team_club_id,
        coalesce(
          case v_metric
            when 'distance' then sum(r.distance_m)
            when 'duration' then sum(r.duration_s)::numeric
            when 'vert' then sum(coalesce(r.elevation_gain_m, 0))
            when 'activity_count' then count(r.id)::numeric
            when 'streak_days' then count(distinct (r.started_at at time zone 'UTC')::date)::numeric
          end,
          0
        ) as value
      from challenge_participants pp
      left join runs r
        on r.user_id = pp.user_id
       and r.started_at >= v_starts
       and r.started_at < v_ends
       and r.is_dnf = false
       and (v_activity_type is null or r.activity_type = v_activity_type)
      where pp.challenge_id = p_challenge_id
      group by pp.team_club_id
    )
    select
      null::uuid as user_id,
      null::text as display_name,
      pt.team_club_id,
      pt.value,
      rank() over (order by pt.value desc) as rank
    from per_team pt
    order by rank, pt.team_club_id nulls last;
  else
    return query
    with per_user as (
      select
        pp.user_id,
        pp.team_club_id,
        coalesce(
          case v_metric
            when 'distance' then sum(r.distance_m)
            when 'duration' then sum(r.duration_s)::numeric
            when 'vert' then sum(coalesce(r.elevation_gain_m, 0))
            when 'activity_count' then count(r.id)::numeric
            when 'streak_days' then count(distinct (r.started_at at time zone 'UTC')::date)::numeric
          end,
          0
        ) as value
      from challenge_participants pp
      left join runs r
        on r.user_id = pp.user_id
       and r.started_at >= v_starts
       and r.started_at < v_ends
       and r.is_dnf = false
       and (v_activity_type is null or r.activity_type = v_activity_type)
      where pp.challenge_id = p_challenge_id
      group by pp.user_id, pp.team_club_id
    )
    select
      pu.user_id,
      case when p.shadow_hidden = false or p.id = auth.uid()
        then p.display_name end as display_name,
      pu.team_club_id,
      pu.value,
      rank() over (order by pu.value desc) as rank
    from per_user pu
    left join user_profiles p on p.id = pu.user_id
    order by rank, pu.user_id nulls last;
  end if;
end;
$$;

-- ── 4. is_event_visible ──
-- Live body is 20270113_001's predicate; only the club-public branch changes,
-- delegating to the same oracle the public_routes view uses. The owner and
-- member branches are untouched, so a hidden club's own people keep their
-- events. search_path keeps `private` for is_club_member.
create or replace function is_event_visible(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1 from events e
    join clubs c on c.id = e.club_id
    where e.id = p_event_id
      and (is_public_club_by_id(c.id) or c.owner_id = auth.uid() or is_club_member(c.id))
      and (e.is_public = true or is_club_member(c.id))
  );
$$;

-- ── 5. claim_event_result ──
-- Live body is 20260924_001 as amended; the only change is the club-public
-- branch of its inline visibility mirror, which the events RLS policy has
-- carried since 20270328_001. The `c.id is null` allowance for a club-less
-- event stays.
create or replace function claim_event_result(p_result_id uuid)
returns event_result_claims
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_res event_results;
  v_visible boolean;
  v_claim event_result_claims;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_res from event_results where id = p_result_id;
  if v_res.id is null then
    raise exception 'Result not found';
  end if;
  if v_res.user_id is not null then
    raise exception 'This result already belongs to an account';
  end if;

  -- Caller must be able to see the parent event (mirror of the
  -- event_results SELECT visibility chain).
  select exists (
    select 1 from events e
    left join clubs c on c.id = e.club_id
    where e.id = v_res.event_id
      and (
        c.id is null
        or is_public_club_by_id(c.id)
        or c.owner_id = auth.uid()
        or is_club_member(c.id)
      )
  ) into v_visible;
  if not v_visible then
    raise exception 'Not authorised to claim this result';
  end if;

  if exists (
    select 1 from event_results
    where event_id = v_res.event_id
      and instance_start = v_res.instance_start
      and user_id = auth.uid()
  ) then
    raise exception 'You already have a result for this event';
  end if;

  insert into event_result_claims (result_id, claimant_id)
  values (p_result_id, auth.uid())
  on conflict (result_id, claimant_id)
    -- Re-requesting after a rejection re-opens the claim.
    do update set status = 'pending', decided_by = null, decided_at = null,
                  created_at = now()
  returning * into v_claim;
  return v_claim;
end;
$$;
