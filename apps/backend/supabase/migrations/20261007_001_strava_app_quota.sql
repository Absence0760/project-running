-- audit/strava May 2026 Medium #7 — global Strava-quota gate.
--
-- Strava's API rate-limit terms cap us at 100 requests / 15 min and
-- 1000 / day per app. Per-user `rate_limits` (4/h free, 16/h pro)
-- protects against individual abuse but doesn't bound the aggregate:
-- on a weekend morning when 500 users sync + the cron sweep fires
-- + every user's webhook fires, the per-app budget is at risk.
--
-- A breached app-level quota gets the app suspended by Strava.
--
-- Schema: a single-row-per-window counter keyed by `(provider,
-- window_start_kind)`. `kind` ∈ {15min, day}. The helper RPC
-- `try_consume_strava_quota()` increments + returns whether the
-- caller may proceed.
--
-- Mirrors the `rate_limits` table shape but globally keyed (no
-- user_id) — the gate is the same fixed-window-bucketing math.

create table public.app_quota (
  provider     text not null,
  window_kind  text not null check (window_kind in ('short', 'day')),
  window_start timestamptz not null,
  count        integer not null default 0,
  primary key (provider, window_kind, window_start)
);

comment on table public.app_quota is
  'Aggregate per-app rate-limit counters. Strava: 100/15min + '
  '1000/day. /audit/strava M7.';

-- Soft floor (90% of Strava limit) so we hit our gate before
-- Strava's. Tunable via the RPC args.
create or replace function try_consume_strava_quota(
  p_short_limit integer default 90,    -- 90/15min (vs Strava 100)
  p_day_limit   integer default 900    -- 900/day  (vs Strava 1000)
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_short_window timestamptz := date_trunc('minute', now())
    - (extract(minute from now())::int % 15) * interval '1 minute';
  v_day_window   timestamptz := date_trunc('day', now());
  v_short_count integer;
  v_day_count   integer;
begin
  -- Increment + read in one round-trip per window. INSERT ... ON
  -- CONFLICT DO UPDATE atomically bumps the counter; the RETURNING
  -- clause hands back the post-increment value for the gate check.
  insert into app_quota (provider, window_kind, window_start, count)
    values ('strava', 'short', v_short_window, 1)
    on conflict (provider, window_kind, window_start) do update
      set count = app_quota.count + 1
    returning count into v_short_count;
  insert into app_quota (provider, window_kind, window_start, count)
    values ('strava', 'day', v_day_window, 1)
    on conflict (provider, window_kind, window_start) do update
      set count = app_quota.count + 1
    returning count into v_day_count;

  -- Either window exceeded → deny. Caller (Strava-bound code path)
  -- backs off + retries later. The cron sweeps clear old rows.
  if v_short_count > p_short_limit or v_day_count > p_day_limit then
    return false;
  end if;
  return true;
end;
$$;

revoke all on function try_consume_strava_quota(integer, integer) from public;
grant execute on function try_consume_strava_quota(integer, integer) to service_role;

comment on function try_consume_strava_quota(integer, integer) is
  'Increment both 15min + day buckets atomically + return whether '
  'the caller is under the soft floor (90% of Strava''s published '
  'limit). Callers: Go worker handler_token_refresh, EF strava-'
  'import, EF strava-webhook. Returns false once the floor is hit; '
  'caller backs off. /audit/strava M7.';

-- Cleanup cron: drop counter rows older than 1 day. Avoids
-- unbounded growth without forcing every caller to do the math.
select cron.schedule(
  'cleanup-stale-app-quota',
  '15 4 * * *',  -- 04:15 UTC daily, off-peak.
  $$delete from app_quota where window_start < now() - interval '2 days'$$
);
