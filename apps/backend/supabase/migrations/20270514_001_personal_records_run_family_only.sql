-- A bike ride can hold a running personal record.
--
-- `refresh_personal_records_for_user` buckets a run into a distance bracket
-- (5k / 10k / half / marathon / mile / 8k / 12k) and keeps the fastest per
-- bracket. It filters on `source` and `is_dnf` but never on `activity_type`,
-- which has been a real column on `runs` since `20261207_001` and carries
-- `run | walk | hike | cycle | stroller`. A 5 km bike ride logged at 9:00
-- therefore becomes the runner's "5K PR", permanently displacing their genuine
-- 25:00 run — verified against the local stack.
--
-- The client already has a rule for this and the cache disagrees with it: the
-- recap engine (`apps/web/src/lib/runs/recap.ts`, mirrored in
-- `apps/mobile_android/lib/recap.dart`) gates every "longest" and "fastest"
-- claim on `isRunFamily = (activity_type ?? 'run') !== 'cycle'`, deliberately
-- leaving TOTALS cross-modal. `challenge_leaderboard` /
-- `recompute_challenge_completion` likewise honour `challenges.activity_type`.
-- Only the PR engine and the distance-badge half of the achievements awarder
-- treat every activity as a run.
--
-- Fix, matching the client rule exactly rather than inventing a second one:
--
--   * `refresh_personal_records_for_user` — exclude `cycle` from all five
--     candidate branches (the whole-run bracket plus the four embedded-best
--     columns, which a bike ride also populates).
--   * `award_achievements_for_user` — exclude `cycle` from `v_longest_run_m`
--     and the `v_run_id` that sources the single-run distance badge (an 80 km
--     ride was earning the platinum 50 km tier). `v_lifetime_m` and the streak
--     stay cross-modal, matching the recap's "cross-modal totals" contract and
--     the client `computeRunStreaks`, which is fed every activity type.
--     Already-granted badges are not revoked — this awarder has never revoked
--     anything (it is insert-on-conflict-do-nothing, and a deleted run does not
--     take a badge away either); the change is forward-correct only.
--   * Both statement-level UPDATE triggers must watch `activity_type` now.
--     Without it, flipping a run from `cycle` to `run` (or the reverse) changes
--     what the authoritative query returns while leaving the cache untouched —
--     the exact drift class `docs/backend/derived_state.md` exists to prevent.
--
-- Backfill: `personal_records` is a small cache (at most one row per user per
-- bracket) and the refresher recomputes a single user from scratch under a
-- per-user advisory lock. The backfill is scoped to the only users whose cache
-- can currently be wrong — those with at least one non-DNF `cycle` run — and
-- walks them one at a time rather than as one unbounded statement, per
-- `docs/backend/migration_locks.md` § Large backfills. Selecting that user set
-- costs one sequential read of `runs` under `ACCESS SHARE` — readers and
-- writers proceed throughout. No index is added for it: a `CREATE INDEX` on
-- `runs` would take `ACCESS EXCLUSIVE` for the build, and `CONCURRENTLY` cannot
-- run inside the wrapped apply transaction, so the one-off scan is the online
-- choice.
--
-- `activity_type` is `not null default 'run'` (`20261207_001`), so
-- `<> 'cycle'` needs no null branch.
--
-- Bare-body `create or replace` strips prior fixes: both bodies below are the
-- COMPLETE live definitions (PR refresher: widened brackets `20260528000002`,
-- embedded bests `20260529000002` / `20270325_001`, DNF exclusion
-- `20260530000001`, mile bracket `20261021_001`, auth guard `20260904_001`,
-- consolidation `20261009_001`, parkrun/race sources `20270424_001`;
-- achievements: the `20270404_001` trigger-depth guard + the `20270424_001`
-- source widening) with only the run-family predicate added.
--
-- No column changes, so no row-type regeneration is owed.

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
        -- Run family only: a bicycle covers a PR bracket at speeds no runner
        -- reaches. Mirrors the client's `isRunFamily` in recap.ts.
        and activity_type <> 'cycle'
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
        and activity_type <> 'cycle'
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
        and activity_type <> 'cycle'
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
        and activity_type <> 'cycle'
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
        and activity_type <> 'cycle'
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
  -- LONGEST is run-family only (a bike ride is not a long run), matching the
  -- recap's isRunFamily rule; LIFETIME stays cross-modal, matching the same
  -- helper's cross-modal totals.
  select
    coalesce(max(distance_m) filter (where activity_type <> 'cycle'), 0),
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
    and activity_type <> 'cycle'
    and distance_m is not null
    and is_dnf = false
  order by distance_m desc, started_at asc
  limit 1;

  -- Best run streak in days. Distinct local-ish days (UTC date here; the
  -- client streak helper uses local time — close enough for a milestone
  -- threshold, and the helper is the display-side source of truth). Every
  -- activity type counts, as it does in the client's computeRunStreaks.
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

-- ─────────────── UPDATE watch lists gain activity_type ───────────────

create or replace function trigger_refresh_personal_records()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if tg_op = 'INSERT' then
    for v_user_id in select distinct user_id from changed_runs loop
      perform refresh_personal_records_for_user(v_user_id);
    end loop;
  elsif tg_op = 'UPDATE' then
    for v_user_id in
      select u.user_id
      from (
        select n.user_id
        from changed_runs n
        join old_runs o on o.id = n.id
        where (n.distance_m, n.duration_s, n.source, n.user_id, n.is_dnf,
               n.activity_type, n.fastest_5k_s, n.fastest_10k_s,
               n.fastest_half_marathon_s, n.fastest_marathon_s)
          is distinct from
          (o.distance_m, o.duration_s, o.source, o.user_id, o.is_dnf,
           o.activity_type, o.fastest_5k_s, o.fastest_10k_s,
           o.fastest_half_marathon_s, o.fastest_marathon_s)
        union
        select o.user_id
        from old_runs o
        join changed_runs n on n.id = o.id
        where (n.distance_m, n.duration_s, n.source, n.user_id, n.is_dnf,
               n.activity_type, n.fastest_5k_s, n.fastest_10k_s,
               n.fastest_half_marathon_s, n.fastest_marathon_s)
          is distinct from
          (o.distance_m, o.duration_s, o.source, o.user_id, o.is_dnf,
           o.activity_type, o.fastest_5k_s, o.fastest_10k_s,
           o.fastest_half_marathon_s, o.fastest_marathon_s)
      ) u
    loop
      perform refresh_personal_records_for_user(v_user_id);
    end loop;
  else
    for v_user_id in select distinct user_id from old_runs loop
      perform refresh_personal_records_for_user(v_user_id);
    end loop;
  end if;
  return null;
end;
$$;

create or replace function trigger_award_achievements_runs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if tg_op = 'INSERT' then
    for v_user_id in select distinct user_id from new_runs loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  elsif tg_op = 'UPDATE' then
    for v_user_id in
      select u.user_id
      from (
        select n.user_id
        from new_runs n
        join old_runs o on o.id = n.id
        where (n.distance_m, n.source, n.is_dnf, n.user_id, n.activity_type)
          is distinct from (o.distance_m, o.source, o.is_dnf, o.user_id, o.activity_type)
        union
        select o.user_id
        from old_runs o
        join new_runs n on n.id = o.id
        where (n.distance_m, n.source, n.is_dnf, n.user_id, n.activity_type)
          is distinct from (o.distance_m, o.source, o.is_dnf, o.user_id, o.activity_type)
      ) u
    loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  else
    for v_user_id in select distinct user_id from old_runs loop
      perform award_achievements_for_user(v_user_id);
    end loop;
  end if;
  return null;
end;
$$;

-- ─────────────────────────── scoped backfill ───────────────────────────

do $$
declare
  v_user uuid;
begin
  for v_user in
    select distinct user_id
    from runs
    where activity_type = 'cycle'
      and is_dnf = false
      and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
  loop
    perform refresh_personal_records_for_user(v_user);
  end loop;
end;
$$;
