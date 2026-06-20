-- Achievements / badges — persisted awards + the SECURITY DEFINER award
-- function + triggers + the 'achievement' notification kind.
--
-- The badge CATALOGUE (which badges exist, their tiers + thresholds) lives in
-- code: apps/web/src/lib/social/badges.ts ↔ apps/mobile_android/lib/badges.dart.
-- This migration stores only AWARDS — which user earned which badge/tier, when,
-- off which numeric. The thresholds in award_achievements_for_user below are a
-- LOCKSTEP CONTRACT with the catalogue helper's threshold constants; if you
-- change a number in one, change it in the other. achievements_test.sql pins
-- the contract so drift fails CI.
--
-- Derivation mirrors personal_records (20260508_001): a full per-user rebuild
-- is simpler to reason about than incremental bucket maintenance, and each user
-- owns at most hundreds of source rows so the scan is flat-cost. `insert ... on
-- conflict do nothing` makes re-runs idempotent; the function returns only the
-- NEWLY inserted awards so the AFTER INSERT notification trigger fires once per
-- new badge, not on every re-derive.

create table achievements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  badge_key   text not null,
  tier        text not null default 'bronze'
                check (tier in ('bronze', 'silver', 'gold', 'platinum')),
  source_kind text not null
                check (source_kind in ('pr', 'segment', 'streak', 'distance', 'plan')),
  source_id   uuid,
  value_num   double precision,
  earned_at   timestamptz not null default now(),
  is_public   boolean not null default true,
  constraint achievements_user_badge_uk unique (user_id, badge_key, tier)
);

create index achievements_user_earned on achievements (user_id, earned_at desc);

alter table achievements enable row level security;

-- Owner can read all of their own badges (incl. private).
create policy achievements_self_select on achievements
  for select using (user_id = auth.uid());

-- Public-read path: a follower's feed/profile + the anonymous share page read
-- only public badges of others. Fail-closed — no policy means no leak.
create policy achievements_public_select on achievements
  for select using (is_public = true);

-- Owner-only UPDATE for the is_public toggle. The using/with-check pair keeps
-- ownership invariant (can't reassign user_id). No INSERT/DELETE policies —
-- awards are written only by the award function (security definer).
create policy achievements_owner_update on achievements
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Definer-owner grant pattern (coach_athletes): the function runs as the table
-- owner and needs direct DML; clients never get insert/delete via RLS.
grant select, insert, update, delete on achievements to postgres;

-- ───────────────────────── notification kind ─────────────────────────
-- Extend the kind allowlist to add 'achievement'. Full re-statement at the
-- chain end (the documented pattern) — do not edit the prior file. Latest to
-- touch this CHECK was 20270107_001_notify_plan_assigned (12 values).
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement'
    )
  );

-- Link a notification back to the award. activity_kind is CHECK-limited to
-- run|lift|meal, so add a dedicated nullable FK instead of widening it.
alter table notifications
  add column achievement_id uuid references achievements(id) on delete cascade;

-- ───────────────────── award function (security definer) ─────────────────────
-- Recompute the user's full earned set from personal_records + runs aggregates +
-- completed plans, insert any newly-earned (badge_key, tier) and return the rows
-- newly inserted. Thresholds duplicate badges.ts — keep in lockstep.
create or replace function award_achievements_for_user(p_user uuid)
returns setof achievements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_longest_run_m   double precision;
  v_lifetime_m      double precision;
  v_best_streak     integer;
  v_pr_count        integer;
  v_plan_count      integer;
  v_run_id          uuid;
begin
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

grant execute on function award_achievements_for_user(uuid) to authenticated;

-- Trigger shim on the source tables — dispatch to the award function for the
-- affected user. The function itself is idempotent + returns only new rows.
create or replace function trigger_award_achievements()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform award_achievements_for_user(old.user_id);
    return old;
  else
    perform award_achievements_for_user(new.user_id);
    return new;
  end if;
end;
$$;

create trigger runs_award_achievements
  after insert or update of distance_m, source, is_dnf, user_id or delete on runs
  for each row execute function trigger_award_achievements();

create trigger personal_records_award_achievements
  after insert or update or delete on personal_records
  for each row execute function trigger_award_achievements();

create trigger training_plans_award_achievements
  after insert or update of status or delete on training_plans
  for each row execute function trigger_award_achievements();

-- Write a bell notification for each newly-earned award (owner-only, no actor).
-- A new kind doesn't enqueue email/push unless added to those allowlists, so
-- this stays bell-only by default.
create or replace function notify_achievement_earned()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into notifications (user_id, kind, achievement_id)
    values (new.user_id, 'achievement', new.id);
  return new;
end;
$$;

create trigger trg_notify_achievement_earned
  after insert on achievements
  for each row execute function notify_achievement_earned();

-- Back-fill every existing user's earned badges (pre-launch; the set is tiny).
do $$
declare
  uid uuid;
begin
  for uid in select distinct user_id from runs loop
    perform award_achievements_for_user(uid);
  end loop;
end;
$$;
