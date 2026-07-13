-- Challenge distance/duration/vert/count/streak goals exclude DNF runs
-- (bughunt-backend.md finding #5). The two challenge aggregates
-- (challenge_leaderboard + recompute_challenge_completion) summed every run in
-- the window with no is_dnf filter, so a runner who DNFs an ultra at 42 km still
-- contributed 42 km toward a "run 100 km this month" goal and its leaderboard
-- value. That is inconsistent with the personal-records refresher
-- (20261207_001) and the achievements awarder (20270208_001), which both
-- exclude DNF efforts (`and is_dnf = false`). Align the challenge engine with
-- them: a DNF is not a completed effort, so it should not bank progress.
--
-- Bare-body create-or-replace: each function's COMPLETE latest body is re-emitted
-- and only the `and r.is_dnf = false` predicate is added, per the
-- create-or-replace-strips-prior-fixes rule. The latest bodies:
--   * challenge_leaderboard — 20270302_001 (added the 'vert' metric branch);
--   * recompute_challenge_completion — 20270306_001 (added the 'vert' branch AND
--     the caller-ownership guard). Both are carried forward verbatim here.
-- The predicate lands in each run join/scan, so it applies uniformly to every
-- metric (a DNF also drops out of activity_count + streak_days, matching how a
-- DNF never counts as a completed activity elsewhere).

-- ── challenge_leaderboard: exclude DNF runs from the per-user/team aggregate ──
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
      p.display_name,
      pu.team_club_id,
      pu.value,
      rank() over (order by pu.value desc) as rank
    from per_user pu
    left join user_profiles p on p.id = pu.user_id
    order by rank, pu.user_id nulls last;
  end if;
end;
$$;

grant execute on function challenge_leaderboard(uuid, boolean) to authenticated, anon;

-- ── recompute_challenge_completion: exclude DNF runs from the value sum ──────
create or replace function recompute_challenge_completion(
  p_challenge_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
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

revoke execute on function recompute_challenge_completion(uuid, uuid) from public, anon;
grant execute on function recompute_challenge_completion(uuid, uuid) to authenticated;
