-- Segment effort ranks for a run — replaces a client-side N+1 count loop.
--
-- The run-detail page renders "Climb of doom — 4:21, #3 of 17" for every
-- segment effort attached to a run. `fetchEffortsForRun()` used to issue one
-- `count(time_seconds < x)` query PER effort, awaited serially — a run over a
-- 30-segment route fired 30 sequential round-trips before the panel rendered
-- (perf-hunt 2026-06-10).
--
-- This RPC computes every effort's rank in ONE round-trip. Rank = 1 + the
-- number of efforts on the same segment that are strictly faster AND visible
-- to the caller. SECURITY INVOKER (like `segment_leaderboard_tiered`) so the
-- segment_efforts RLS policy (EXISTS-through-route → routes.is_public, plus
-- owner access) filters both the run's efforts and the comparison set exactly
-- as the per-effort client count did — the rank a caller sees is unchanged,
-- just computed server-side instead of in N serial queries.
--
-- Tie semantics match the prior `count(strictly-faster) + 1`: two efforts at
-- the same best time both rank 1, the next ranks 3 (standard competition
-- ranking). The covering index on segment_efforts(segment_id, time_seconds)
-- (migration 20260516_001) keeps the correlated count an index range scan.

create or replace function segment_effort_ranks(p_run_id uuid)
returns table (
  effort_id uuid,
  rank integer
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    e.id as effort_id,
    (
      1 + (
        select count(*)
        from public.segment_efforts f
        where f.segment_id = e.segment_id
          and f.time_seconds < e.time_seconds
      )
    )::integer as rank
  from public.segment_efforts e
  where e.run_id = p_run_id;
$$;

revoke execute on function segment_effort_ranks(uuid) from public;
grant  execute on function segment_effort_ranks(uuid) to anon, authenticated;
