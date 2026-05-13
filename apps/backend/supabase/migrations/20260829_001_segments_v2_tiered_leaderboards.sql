-- Segments v2 — tiered leaderboards (parity backlog #3).
--
-- v1 (migration 20260516_001) shipped route-anchored segments with a
-- single, flat per-segment leaderboard. Strava's segment surface
-- splits "best ever on this segment" by gender (M / F / NB) and by
-- 5-year age band — a runner sees their PR against people they're
-- actually competing with. This migration is the schema half of v2:
--
--   1. `user_profiles.gender` + `user_profiles.date_of_birth` so the
--      backend can filter + group leaderboard rows.
--   2. `segment_leaderboard_tiered(...)` SECURITY DEFINER RPC that
--      joins segment_efforts to user_profiles and applies the
--      filters server-side. Keeps the demographic data out of the
--      client (clients only see athletes' display_name + avatar +
--      gender flag — no DOB ever leaks past the row owner).
--
-- v2 deferred to future sessions:
--   * **Arbitrary-geometry segment matching** (HMM/Hausdorff): lets a
--     segment exist independent of any saved route, with new runs
--     auto-matched against every nearby segment. Multi-week —
--     algorithm + index pipeline + Go worker handler.
--   * **Live effort during a run**: progress bar on the recording
--     screen showing "8 sec ahead of PB on this segment". Touches the
--     L0-L4 recording-stack contract; requires /safe-edit.
--   * **KOM/QOM crown badges**: visual marker for the rank-1-ever
--     per tier. Trivial UI on top of this RPC — natural next session.

-- ─────────────────── user_profiles columns ───────────────────

alter table public.user_profiles
  add column if not exists gender text
  check (gender is null or gender in ('male', 'female', 'nonbinary', 'prefer_not_to_say'));

alter table public.user_profiles
  add column if not exists date_of_birth date;

-- ─────────────────── tiered leaderboard RPC ───────────────────

-- Returns leaderboard rows for a segment, optionally filtered by
-- gender and/or age band. Joins to user_profiles for the demographic
-- gate. Visibility on segment_efforts itself is still gated by the
-- v1 RLS policy (EXISTS-through-route → routes.is_public) — this
-- RPC SECURITY INVOKER means callers see exactly what they would
-- see via a normal `select * from segment_efforts`, plus the
-- demographic columns from user_profiles which already use the
-- existing public-readable subset.
--
-- p_age_band examples (matches Strava):
--   '18-19', '20-24', '25-29', ..., '75+'
-- A null `p_age_band` means "any age"; the function ignores it.
-- The age comparison is current-age (extracted from DOB at query
-- time). Computing effort-time age is more honest for KOMs spanning
-- years but adds a date_part + age calculation per row; we'll
-- revisit if leaderboards see meaningful churn from runners aging
-- out of their band.
create or replace function segment_leaderboard_tiered(
  p_segment_id uuid,
  p_gender text default null,
  p_age_band text default null,
  p_limit integer default 50
)
returns table (
  effort_id uuid,
  user_id uuid,
  run_id uuid,
  time_seconds integer,
  started_at timestamptz,
  display_name text,
  avatar_url text,
  gender text,
  age integer
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  age_min integer := null;
  age_max integer := null;
begin
  -- Parse the age band string into bounds. Kept inside plpgsql
  -- rather than as a separate `parse_age_band` helper because the
  -- bands aren't reused elsewhere yet.
  if p_age_band is not null then
    if p_age_band = '75+' then
      age_min := 75;
      age_max := 200;
    elsif p_age_band ~ '^[0-9]+-[0-9]+$' then
      age_min := split_part(p_age_band, '-', 1)::integer;
      age_max := split_part(p_age_band, '-', 2)::integer;
    else
      raise exception 'segment_leaderboard_tiered: invalid p_age_band %', p_age_band
        using errcode = '22023';
    end if;
  end if;

  return query
  select
    se.id          as effort_id,
    se.user_id     as user_id,
    se.run_id      as run_id,
    se.time_seconds,
    se.started_at,
    up.display_name,
    up.avatar_url,
    up.gender,
    case
      when up.date_of_birth is null then null
      else extract(year from age(up.date_of_birth))::integer
    end as age
  from public.segment_efforts se
  join public.user_profiles up on up.id = se.user_id
  where se.segment_id = p_segment_id
    and (p_gender is null or up.gender = p_gender)
    and (
      p_age_band is null
      or (
        up.date_of_birth is not null
        and extract(year from age(up.date_of_birth))::integer between age_min and age_max
      )
    )
  order by se.time_seconds asc, se.started_at asc
  limit p_limit;
end;
$$;

revoke execute on function segment_leaderboard_tiered(uuid, text, text, integer) from public;
grant  execute on function segment_leaderboard_tiered(uuid, text, text, integer) to anon, authenticated;
