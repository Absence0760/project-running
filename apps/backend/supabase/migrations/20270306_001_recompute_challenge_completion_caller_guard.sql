-- audit/auth: recompute_challenge_completion(p_challenge_id, p_user_id) is
-- SECURITY DEFINER and accepted any p_user_id without checking it against the
-- caller. Both clients always pass their own auth.uid(), but a hand-rolled
-- PostgREST call could pass a VICTIM's id: the RPC would then aggregate over the
-- victim's PRIVATE runs and — when the victim had genuinely crossed the goal —
-- write a badge, stamp completed_at, and insert a 'challenge_complete'
-- notification onto the victim's account, all driven by an unrelated caller.
-- That's a cross-user write with no ownership gate (the /audit/auth invariant:
-- never trust a client-passed user_id over auth.uid()).
--
-- Fix mirrors job_scheduled_at_for_user (20260914_001): block when auth.uid()
-- is set and differs from p_user_id. The legitimate callers are preserved —
--   - the web/mobile recomputeChallengeCompletion paths pass auth.user.id, so
--     auth.uid() = p_user_id and the guard is a no-op;
--   - sweep_challenge_completions() runs SECURITY DEFINER as the table owner
--     with auth.uid() = NULL, so the cron/service path is unaffected.
--
-- Bare-body create-or-replace: re-emit the COMPLETE latest body (20270302_001,
-- which added the 'vert' metric branch) and prepend only the caller guard, per
-- the create-or-replace-strips-prior-fixes rule.

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
