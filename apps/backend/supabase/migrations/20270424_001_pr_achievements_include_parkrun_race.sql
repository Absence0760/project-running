-- PRs + achievements silently excluded parkrun and official race runs (#378).
--
-- Both `refresh_personal_records_for_user` and `award_achievements_for_user`
-- filtered eligible runs with
--   source in ('app','watch','strava','garmin','healthkit','healthconnect')
-- which omits the two remaining valid `runs.source` CHECK values
-- (`20260505_001`): 'parkrun' (a weekly certified 5K) and 'race' (chip-timed
-- official results — the MOST authoritative source). A runner's fastest 5K at
-- parkrun never earned a PR row, and lifetime/single-run distance from race
-- efforts never counted toward a distance badge. Add both sources to every
-- source-list filter in both function bodies.
--
-- Per the backend "bare CREATE OR REPLACE strips prior fixes" gotcha, each body
-- below is the LATEST live definition re-emitted verbatim with ONLY the source
-- lists widened:
--   refresh_personal_records_for_user  ← 20270405_001 (deterministic tiebreaker
--     + auth guard + advisory lock + widened brackets + promoted fastest_*
--     embedded-best branches + DNF exclusion + 8k/12k brackets)
--   award_achievements_for_user        ← 20270421_001 (pg_trigger_depth() abuse
--     guard + advisory lock + longest/lifetime/streak/pr/plan derivation +
--     idempotent on-conflict insert; execute grant stays revoked)

create or replace function refresh_personal_records_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  if v_role <> 'service_role' and v_role <> '' then
    if auth.uid() is null or auth.uid() is distinct from p_user_id then
      raise exception 'refresh_personal_records_for_user: not authorized'
        using errcode = '42501';
    end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('personal_records:' || p_user_id::text)
  );

  delete from personal_records where user_id = p_user_id;

  insert into personal_records (user_id, distance, best_time_s, run_id, achieved_at)
  select
    p_user_id, distance, duration_s, run_id, achieved_at
  from (
    select
      run_id, duration_s, achieved_at, distance,
      row_number() over (
        partition by distance
        order by duration_s asc, achieved_at asc, run_id asc
      ) as rn
    from (
      -- Whole-run candidates, widened brackets, DNFs excluded.
      select
        id as run_id,
        duration_s,
        started_at as achieved_at,
        case
          when distance_m between 1559  and 1659   then '1_mile'
          when distance_m between 4900  and 5100   then '5k'
          when distance_m between 7840  and 8160   then '8k'
          when distance_m between 9800  and 10200  then '10k'
          when distance_m between 11760 and 12240  then '12k'
          when distance_m between 20675 and 21519  then 'half_marathon'
          when distance_m between 41351 and 43039  then 'marathon'
        end as distance
      from runs
      where user_id = p_user_id
        -- 'parkrun' (certified weekly 5K) + 'race' (chip-timed official results,
        -- the most authoritative source) are valid runs.source values (#378).
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and distance_m is not null
        and duration_s is not null
        and is_dnf = false

      union all

      -- Embedded-best 5k from the promoted fastest_5k_s column.
      select
        id as run_id, fastest_5k_s,
        started_at as achieved_at, '5k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and fastest_5k_s is not null
        and fastest_5k_s >= 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_10k_s,
        started_at as achieved_at, '10k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and fastest_10k_s is not null
        and fastest_10k_s >= 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_half_marathon_s,
        started_at as achieved_at, 'half_marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and fastest_half_marathon_s is not null
        and fastest_half_marathon_s >= 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_marathon_s,
        started_at as achieved_at, 'marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and fastest_marathon_s is not null
        and fastest_marathon_s >= 0
        and is_dnf = false
    ) candidates
    where distance is not null
  ) ranked
  where rn = 1;
end;
$$;

create or replace function award_achievements_for_user(p_user uuid)
returns setof achievements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role            text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
  v_longest_run_m   double precision;
  v_lifetime_m      double precision;
  v_best_streak     integer;
  v_pr_count        integer;
  v_plan_count      integer;
  v_run_id          uuid;
begin
  -- Abuse guard. The only legitimate callers are the statement-level award
  -- triggers (20270404_001), which always run at pg_trigger_depth() > 0 —
  -- including the ones that legitimately fire for a user who is NOT the caller
  -- (assign_plan_to_athlete inserts the athlete's training_plans row inside the
  -- coach's session; its own consent gate is the authorization). So we canNOT
  -- gate on auth.uid() = p_user the way the sibling p_user RPCs do — award has a
  -- legitimate cross-user trigger path they don't. The real abuse vector is a
  -- DIRECT call over a user JWT (already blocked by the revoked execute grant
  -- below); block it here too as defence in depth: at trigger depth 0, only
  -- service_role and direct-SQL/empty-role (seed.sql, admin psql) callers pass.
  if pg_trigger_depth() = 0 and v_role <> 'service_role' and v_role <> '' then
    raise exception 'award_achievements_for_user: not authorized' using errcode = '42501';
  end if;

  -- Serialize per-user so concurrent trigger fires don't double-derive.
  perform pg_advisory_xact_lock(hashtext('achievements:' || p_user::text));

  -- Eligible-run filter mirrors refresh_personal_records_for_user exactly so
  -- distance badges and PRs agree on what counts as a real run. 'parkrun' +
  -- 'race' are valid runs.source values that were being excluded (#378).
  select
    coalesce(max(distance_m), 0),
    coalesce(sum(distance_m), 0)
  into v_longest_run_m, v_lifetime_m
  from runs
  where user_id = p_user
    and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
    and distance_m is not null
    and is_dnf = false;

  -- The single run that holds the longest distance — used as source_id for the
  -- single-run distance badge (nullable for aggregates like lifetime).
  select id into v_run_id
  from runs
  where user_id = p_user
    and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
    and distance_m is not null
    and is_dnf = false
  order by distance_m desc, started_at asc
  limit 1;

  -- Best run streak in days. Distinct local-ish days (UTC date here; the
  -- client streak helper uses local time — close enough for a milestone
  -- threshold, and the helper is the display-side source of truth).
  with run_days as (
    select distinct (started_at at time zone 'UTC')::date as d
    from runs
    where user_id = p_user
      and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
      and is_dnf = false
  ),
  grouped as (
    select d, d - (row_number() over (order by d))::int as grp
    from run_days
  )
  select coalesce(max(cnt), 0) into v_best_streak
  from (select count(*) as cnt from grouped group by grp) s;

  select count(*) into v_pr_count from personal_records where user_id = p_user;

  select count(*) into v_plan_count
  from training_plans
  where user_id = p_user and status = 'completed' and is_template = false;

  -- Each branch inserts the highest earned tier per family (DISTINCT ON over a
  -- tier-ranked VALUES list). on conflict do nothing makes the rebuild
  -- idempotent. RETURNING feeds the notification trigger only the new rows.
  return query
  with candidates as (
    -- single-run distance
    select 'distance_single'::text as badge_key, t.tier, 'distance'::text as source_kind,
           v_run_id as source_id, v_longest_run_m as value_num, t.rank
    from (values ('bronze',5000,1),('silver',21097,2),('gold',42195,3),('platinum',50000,4)) as t(tier,thr,rank)
    where v_longest_run_m >= t.thr
    union all
    -- lifetime distance
    select 'distance_lifetime', t.tier, 'distance', null::uuid, v_lifetime_m, t.rank
    from (values ('bronze',100000,1),('silver',500000,2),('gold',1000000,3),('platinum',5000000,4)) as t(tier,thr,rank)
    where v_lifetime_m >= t.thr
    union all
    -- streak
    select 'streak', t.tier, 'streak', null::uuid, v_best_streak::double precision, t.rank
    from (values ('bronze',7,1),('silver',30,2),('gold',100,3),('platinum',365,4)) as t(tier,thr,rank)
    where v_best_streak >= t.thr
    union all
    -- personal records held
    select 'pr', t.tier, 'pr', null::uuid, v_pr_count::double precision, t.rank
    from (values ('bronze',1,1),('silver',3,2),('gold',5,3)) as t(tier,thr,rank)
    where v_pr_count >= t.thr
    union all
    -- completed plans
    select 'plan_finisher', t.tier, 'plan', null::uuid, v_plan_count::double precision, t.rank
    from (values ('bronze',1,1),('silver',3,2),('gold',10,3)) as t(tier,thr,rank)
    where v_plan_count >= t.thr
  ),
  top_per_family as (
    select distinct on (badge_key) badge_key, tier, source_kind, source_id, value_num
    from candidates
    order by badge_key, rank desc
  ),
  inserted as (
    insert into achievements (user_id, badge_key, tier, source_kind, source_id, value_num)
    select p_user, badge_key, tier, source_kind, source_id, value_num from top_per_family
    on conflict (user_id, badge_key, tier) do nothing
    returning *
  )
  select * from inserted;
end;
$$;

-- create-or-replace preserves the revoked grant from 20270421_001, but re-emit
-- it so the RPC stays unreachable over a user JWT regardless of apply order.
revoke execute on function award_achievements_for_user(uuid) from public, authenticated, anon;

-- One-time backfill: rebuild PRs + achievements for every user who has a
-- parkrun or race run, since those runs were previously invisible to both
-- derivations. Bounded to only the affected users — a user with no parkrun/race
-- run has an unchanged eligible set. The refreshers are idempotent, so a
-- concurrent trigger fire during the backfill is harmless. Runs at trigger
-- depth 0 with an empty role (migration context), which both guards permit.
do $$
declare
  u uuid;
begin
  for u in
    select distinct user_id from runs where source in ('parkrun', 'race')
  loop
    perform refresh_personal_records_for_user(u);
    perform award_achievements_for_user(u);
  end loop;
end;
$$;
