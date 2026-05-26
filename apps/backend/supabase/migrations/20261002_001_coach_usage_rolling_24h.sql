-- audit:coach May 2026 Medium #5 — timezone-gaming the daily cap.
--
-- `usage_date default current_date` (migration 20260430_001) buckets
-- coach-message counts by UTC calendar day. A user in UTC+14 can use
-- their 2 free messages at 23:00 UTC May 25, then 2 more at 01:00
-- UTC May 26, effectively 4/day inside a 2-hour wall-clock window.
-- Not catastrophic (TIER_LIMITS.free.dailyLimit=2 keeps the abuse
-- bounded) but it bypasses the cost model the rest of the project
-- is sized against.
--
-- Fix: keep the daily-bucket TABLE shape (existing rows, existing
-- on-conflict semantics, existing RLS, existing FK) and switch the
-- three RPCs' return value from "today's bucket count" to "rolling
-- 24h sum across the last 1-2 buckets". The sum is a slight
-- overcount near the UTC midnight (the partial yesterday bucket
-- counts in full), which makes the cap STRICTER than today, not
-- looser — the correct direction for a cost gate.
--
-- The INSERT path still bumps today's bucket — only the returned
-- count changes. Existing rows continue to roll off via the
-- cleanup_stale_user_coach_usage cron (20260706_001).

create or replace function increment_coach_usage(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'increment_coach_usage: not authorized'
      using errcode = '42501';
  end if;

  insert into user_coach_usage (user_id, usage_date, message_count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, usage_date) do update
    set message_count = user_coach_usage.message_count + 1;

  -- Rolling 24h sum across the last 1-2 daily buckets. The
  -- `>= (now() - interval '24 hours')::date` predicate matches
  -- today's bucket always, plus yesterday's bucket if the window
  -- straddles the UTC midnight. Overcounting the partial-yesterday
  -- bucket is the conservative direction — the cap stays stricter
  -- than a wall-clock-precise count.
  select coalesce(sum(message_count), 0)::integer into v_count
  from user_coach_usage
  where user_id = p_user_id
    and usage_date >= (now() - interval '24 hours')::date;
  return v_count;
end;
$$;

create or replace function get_coach_usage(p_user_id uuid)
returns integer
language plpgsql
stable
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
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'get_coach_usage: not authorized'
      using errcode = '42501';
  end if;

  return coalesce(
    (select sum(message_count)::integer from user_coach_usage
      where user_id = p_user_id
        and usage_date >= (now() - interval '24 hours')::date),
    0
  );
end;
$$;

create or replace function decrement_coach_usage(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  if v_role <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id)
  then
    raise exception 'decrement_coach_usage: not authorized'
      using errcode = '42501';
  end if;

  update user_coach_usage
    set message_count = greatest(0, message_count - 1)
    where user_id = p_user_id and usage_date = current_date;

  -- Same rolling sum as increment / get.
  select coalesce(sum(message_count), 0)::integer into v_count
  from user_coach_usage
  where user_id = p_user_id
    and usage_date >= (now() - interval '24 hours')::date;
  return v_count;
end;
$$;

comment on function increment_coach_usage(uuid) is
  'Increments today''s coach-usage bucket and returns the rolling '
  '24h sum across the last 1-2 daily buckets. The rolling shape '
  'closes the UTC-midnight gaming window flagged by audit/coach '
  'Medium #5; the cap is strictly more restrictive than the prior '
  'today-only count.';
