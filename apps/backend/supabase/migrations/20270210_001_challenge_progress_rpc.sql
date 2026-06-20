-- Challenge progress + completion engine (challenges.md): the no-N+1 read path
-- and the completion side-effect writer.
--
-- All progress is computed at read time from the `activities` view filtered to
-- the challenge window. N participants -> 1 round trip, 0 per-user fetches.
-- Completion is an explicit RPC (called opportunistically on run-save + by a
-- daily cron sweep), not a per-run fan-out trigger — that bounds write
-- amplification (challenges.md decision + decisions.md entry).

-- ─────────────────────── notification kind + link column ───────────────────────
-- Add challenge_id source FK + the 'challenge_complete' kind. Bare-body trap:
-- re-state the FULL kind CHECK from the chain end (20270107_001) plus the new
-- value. A new in-app kind stays bell-only — it's not on the email/web-push
-- channel allowlists.
alter table notifications
  add column challenge_id uuid references challenges(id) on delete cascade;

alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'challenge_complete'
    )
  );

-- ─────────────────────── leaderboard ───────────────────────
-- One query joining participants to a per-user aggregate over each runner's
-- runs within [starts_at, ends_at). SECURITY DEFINER, gated on
-- is_challenge_visible(p_challenge_id) so a private/club board can't be read by
-- a non-member: participants opted in by joining, so a board can sum a
-- participant's PRIVATE runs too (the run rows are never exposed — only the
-- per-user SUM, exactly like event_results). A non-DEFINER read can't do this
-- because the public-runs SELECT policy on `runs` was retired (public access
-- now flows through the public_runs view / clip-public-track), so an INVOKER
-- aggregate would see only the caller's own runs and zero every competitor.
-- When p_by_team, regroups the aggregate by team_club_id for club_vs_club.
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

-- ─────────────────────── my active challenges (self-hide driver) ───────────────────────
-- Returns ONLY challenges the caller has joined that are live now or recently
-- ended (7-day tail so a just-finished challenge still shows its result). An
-- empty result set is the signal to render nothing. SECURITY INVOKER.
create or replace function my_active_challenges()
returns table (
  id uuid,
  creator_id uuid,
  club_id uuid,
  title text,
  description text,
  metric text,
  scope text,
  goal_value numeric,
  activity_type text,
  starts_at timestamptz,
  ends_at timestamptz,
  is_public boolean,
  created_at timestamptz,
  my_value numeric,
  my_rank bigint,
  participant_count bigint,
  completed_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  with mine as (
    select c.*
    from challenges c
    join challenge_participants pp
      on pp.challenge_id = c.id and pp.user_id = auth.uid()
    where now() >= c.starts_at
      and now() < c.ends_at + interval '7 days'
  )
  select
    m.id, m.creator_id, m.club_id, m.title, m.description, m.metric, m.scope,
    m.goal_value, m.activity_type, m.starts_at, m.ends_at, m.is_public, m.created_at,
    lb.value as my_value,
    lb.rank as my_rank,
    (select count(*) from challenge_participants pc where pc.challenge_id = m.id) as participant_count,
    (select pp.completed_at from challenge_participants pp
       where pp.challenge_id = m.id and pp.user_id = auth.uid()) as completed_at
  from mine m
  left join lateral (
    select value, rank
    from challenge_leaderboard(m.id, false) l
    where l.user_id = auth.uid()
  ) lb on true
  order by m.ends_at asc;
$$;

grant execute on function my_active_challenges() to authenticated;

-- ─────────────────────── completion ───────────────────────
-- Recompute the caller's value via the same aggregate; when goal_value is met
-- and no badge exists, award the badge + stamp completed_at + notify. Idempotent
-- (the unique(user_id, challenge_id) badge row guards double-award). SECURITY
-- DEFINER so it can write completed_at + the badge + the notification, all of
-- which are locked against direct client writes.
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
  select c.metric, c.activity_type, c.goal_value, c.starts_at, c.ends_at
    into v_metric, v_activity_type, v_goal, v_starts, v_ends
  from challenges c
  where c.id = p_challenge_id;

  -- No goal => pure-ranking board, nothing to complete. Caller must be a
  -- participant.
  if v_metric is null or v_goal is null then
    return;
  end if;

  if not exists (
    select 1 from challenge_participants pp
    where pp.challenge_id = p_challenge_id and pp.user_id = p_user_id
  ) then
    return;
  end if;

  -- Already awarded: idempotent no-op.
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

revoke execute on function recompute_challenge_completion(uuid, uuid) from public;
grant execute on function recompute_challenge_completion(uuid, uuid) to authenticated;

-- ─────────────────────── daily completion sweep ───────────────────────
-- Robustness net for completions the opportunistic client call missed (a run
-- imported from Strava, a goal crossed by a run logged on another device). Walks
-- every live, goal-bearing challenge's participants who lack a badge and
-- recomputes. SECURITY DEFINER; cron-invoked, not client-callable.
create or replace function sweep_challenge_completions()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
begin
  for rec in
    select pp.challenge_id, pp.user_id
    from challenge_participants pp
    join challenges c on c.id = pp.challenge_id
    where c.goal_value is not null
      and now() >= c.starts_at
      and now() < c.ends_at + interval '1 day'
      and not exists (
        select 1 from challenge_badges b
        where b.challenge_id = pp.challenge_id and b.user_id = pp.user_id
      )
  loop
    perform recompute_challenge_completion(rec.challenge_id, rec.user_id);
  end loop;
end;
$$;

revoke execute on function sweep_challenge_completions() from public, authenticated, anon;

select cron.schedule(
  'sweep-challenge-completions',
  '17 2 * * *',
  $$ select sweep_challenge_completions(); $$
);
