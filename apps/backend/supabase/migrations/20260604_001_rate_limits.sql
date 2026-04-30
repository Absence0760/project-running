-- Per-user rate limits for Edge Functions.
--
-- Edge Functions run on per-invocation isolates without a shared
-- cache; in-memory counters reset on every cold start and don't
-- coordinate across instances. We need a durable counter that
-- survives EF lifecycles, so the buckets live in Postgres.
--
-- Window strategy: fixed-window, not sliding. A "10 per 3600s" call
-- is bucketed by `floor(epoch / 3600) * 3600` so all hits in the same
-- clock hour share a row. Sliding windows would double the write rate
-- (one row per request rather than one row per window) and the
-- abuse-protection job here doesn't need sub-window precision.

create table rate_limits (
  user_id        uuid not null,
  bucket         text not null,
  window_start   timestamptz not null,
  count          integer not null default 0,
  primary key (user_id, bucket, window_start)
);

-- For the cleanup sweep: scan rows older than the cutoff without
-- needing the full primary key.
create index rate_limits_window_start_idx
  on rate_limits (window_start);

-- ──────────────────── check_rate_limit ────────────────────
--
-- Atomic increment-and-check. SECURITY DEFINER so the EFs can call
-- it with the user's JWT — they don't need direct table grants.
-- Even denied calls increment, which means once a user hits the
-- ceiling they stay at ceiling+N until the window rolls; no extra
-- punishment but no way to reset by hammering, either.
create or replace function check_rate_limit(
  p_user_id uuid,
  p_bucket text,
  p_max integer,
  p_window_seconds integer
)
returns table (allowed boolean, retry_after_seconds integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_count integer;
begin
  if p_max <= 0 or p_window_seconds <= 0 then
    raise exception 'check_rate_limit: max and window must be positive';
  end if;

  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );
  v_window_end := v_window_start + make_interval(secs => p_window_seconds);

  insert into rate_limits (user_id, bucket, window_start, count)
    values (p_user_id, p_bucket, v_window_start, 1)
    on conflict (user_id, bucket, window_start) do update
      set count = rate_limits.count + 1
    returning rate_limits.count into v_count;

  if v_count > p_max then
    return query
      select false, greatest(1, ceil(extract(epoch from v_window_end - now()))::integer);
  else
    return query select true, 0;
  end if;
end;
$$;

revoke all on function check_rate_limit(uuid, text, integer, integer) from public;
grant execute on function check_rate_limit(uuid, text, integer, integer) to authenticated, service_role;

-- ──────────────────── Cleanup ────────────────────
--
-- Old rows pile up forever otherwise. Anything more than 24 hours
-- old is meaningless — no rate-limit window in this codebase is
-- longer than an hour, and a 24h grace lets us forensically diagnose
-- a recent spike before the trail evaporates.

create or replace function cleanup_stale_rate_limits()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from rate_limits where window_start < now() - interval '24 hours';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Hourly sweep is fine — the table grows slowly and the cleanup is
-- a single DELETE with the index above.
select cron.schedule(
  'cleanup-stale-rate-limits',
  '0 * * * *',
  $$select public.cleanup_stale_rate_limits()$$
);

-- RLS: users have no business reading the rate-limits table directly,
-- and the SECURITY DEFINER function bypasses RLS by design. Enable
-- RLS with no policies as a defence-in-depth measure — anyone with
-- direct REST access to the table sees zero rows.
alter table rate_limits enable row level security;
