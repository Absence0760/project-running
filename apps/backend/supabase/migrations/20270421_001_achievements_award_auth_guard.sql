-- award_achievements_for_user is SECURITY DEFINER and bypasses the achievements
-- RLS (which has no INSERT policy on purpose — the function was meant to be the
-- enforcement point). Its live body (20270208_001) takes p_user straight from
-- the caller with no ownership check, so any authenticated user could call the
-- RPC against an arbitrary victim id: force-writing rows into the victim's
-- achievements, firing unsolicited 'achievement' bell notifications, and
-- hammering several full scans over the victim's runs/PRs/plans under a
-- per-victim advisory lock (an unrate-limited resource-abuse vector). No client
-- ever calls this RPC directly — the only real callers are the statement-level
-- triggers (20270404_001), which run inside the row-owner's own write (or as
-- service_role for webhook/worker inserts), so both pass the guard.
--
-- Re-emit the full 20270208_001 body (bare-body rule: never hand-edit that
-- migration) with the same ownership guard every sibling p_user RPC carries
-- (refresh_personal_records_for_user / check_rate_limit / *_coach_usage), and
-- drop the pointless `authenticated` execute grant so the RPC isn't reachable
-- from a user JWT at all.

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
  -- Ownership guard: service_role (webhook / worker inserts) and direct-SQL /
  -- empty-role callers (the statement-level triggers running in the row-owner's
  -- own write, and seed.sql) are trusted. Every other role (authenticated,
  -- anon, future custom roles) must be the row owner. Mirrors the sibling
  -- p_user RPC refresh_personal_records_for_user's guard exactly — an
  -- empty-role bypass is what keeps seed.sql / trigger inserts working while
  -- still blocking a cross-user call over an authenticated JWT.
  if v_role <> 'service_role' and v_role <> '' then
    if auth.uid() is null or auth.uid() is distinct from p_user then
      raise exception 'award_achievements_for_user: not authorized' using errcode = '42501';
    end if;
  end if;

  -- Serialize per-user so concurrent trigger fires don't double-derive.
  perform pg_advisory_xact_lock(hashtext('achievements:' || p_user::text));

  -- Eligible-run filter mirrors refresh_personal_records_for_user exactly so
  -- distance badges and PRs agree on what counts as a real run.
  select
    coalesce(max(distance_m), 0),
    coalesce(sum(distance_m), 0)
  into v_longest_run_m, v_lifetime_m
  from runs
  where user_id = p_user
    and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
    and distance_m is not null
    and is_dnf = false;

  -- The single run that holds the longest distance — used as source_id for the
  -- single-run distance badge (nullable for aggregates like lifetime).
  select id into v_run_id
  from runs
  where user_id = p_user
    and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
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
      and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
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

-- The RPC has no legitimate direct caller (only the statement-level triggers,
-- which run as the function's definer regardless of grant). Revoke every
-- execute grant so it can't be invoked from PostgREST at all — from PUBLIC too,
-- since create-or-replace leaves the original CREATE's implicit PUBLIC execute
-- in place and authenticated/anon inherit it. The body guard above is the real
-- enforcement; this makes the RPC simply unreachable over a user JWT.
revoke execute on function award_achievements_for_user(uuid) from public, authenticated, anon;
