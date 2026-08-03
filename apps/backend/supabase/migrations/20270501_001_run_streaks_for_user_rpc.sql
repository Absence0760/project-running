-- All-time run streaks, aggregated server-side.
--
-- /dashboard's streak card used to compute best-streak client-side from the
-- bounded ~2-year fetchRunsForDashboard() window, so a best streak that ended
-- before the window read low and one spanning the boundary was truncated to
-- its in-window part (decisions § 470 / § 471 — the last surviving half of the
-- issue #332 follow-up). The card is on the paint path, so neither a wider
-- fetch nor a lazy load is acceptable; like gym_exercise_records, an all-time
-- figure gets a one-row SQL aggregate instead.
--
-- Gaps-and-islands over distinct run days (the same CTE shape as the streak
-- badge inside award_achievements_for_user), but bucketed by the runner's
-- LOCAL day, not the awarder's UTC-date shortcut: the display-side
-- computeRunStreaks helper (apps/web/src/lib/runs/streaks.ts) keys days in
-- client-local time, and this RPC is its all-time source of truth, so the two
-- must agree on what "a day" is. The client passes its IANA zone name
-- (Intl.DateTimeFormat().resolvedOptions().timeZone); an unrecognized zone
-- errors, which the caller treats as a failed fetch (fail-closed — the card
-- suppresses the all-time claim rather than showing a windowed number).
--
-- Semantics mirror computeRunStreaks exactly:
--   * a day counts once no matter how many runs it holds
--   * days after local today are ignored (fast-clock clamp; server now() in
--     p_tz is the anchor)
--   * current streak carries the Strava grace rule — an island ending
--     yesterday still counts as current until a full local day passes
--   * no DNF or source-family exclusion: the display helper counts every run
--     the dashboard lists, unlike the awarder's milestone filter
--   * p_source scopes both figures to one source, matching the dashboard's
--     source-filter chips, so the sub-label's all-time claim stays true under
--     a filter (§ 471)
--
-- SECURITY INVOKER + explicit auth.uid() filter. The explicit filter is
-- load-bearing here (not just clarity): runs RLS lets a caller read other
-- users' public runs, and this must never aggregate a stranger's days.
-- Served by the runs_user_started_at (user_id, started_at) index; a
-- trigger-maintained cache was considered and rejected in § 470 (an
-- index-only scan over a few thousand rows, and a delete can lower a best
-- streak).

create or replace function run_streaks_for_user(
  p_tz text default 'UTC',
  p_source text default null
)
returns table (current_streak integer, best_streak integer)
language sql
stable
security invoker
set search_path = public
as $$
  with days as (
    select distinct (r.started_at at time zone p_tz)::date as d
    from runs r
    where r.user_id = auth.uid()
      and (p_source is null or r.source = p_source)
      and (r.started_at at time zone p_tz)::date <= (now() at time zone p_tz)::date
  ),
  islands as (
    select d, d - (row_number() over (order by d))::int as grp
    from days
  ),
  lens as (
    select count(*)::int as len, max(d) as island_end
    from islands
    group by grp
  )
  select
    -- At most one island can end on local today/yesterday: two islands ending
    -- on consecutive days would be one island.
    coalesce((
      select len from lens
      where island_end >= (now() at time zone p_tz)::date - 1
    ), 0) as current_streak,
    coalesce((select max(len) from lens), 0) as best_streak;
$$;

revoke execute on function run_streaks_for_user(text, text) from public, anon;
grant  execute on function run_streaks_for_user(text, text) to authenticated;
