-- Rank a run's segment efforts against the same population the leaderboard
-- ranks — one row per athlete, not one per effort.
--
-- `20270424000003` (issue #393) reduced `segment_leaderboard_tiered` to each
-- athlete's best VISIBLE effort with a `distinct on (se.user_id)` CTE before
-- ranking, and `20270513_001` did the same for the catalogue board. Neither
-- touched the rank RPCs that feed the run-detail chips, which still count RAW
-- effort rows. The two surfaces therefore answer the same question from
-- different populations:
--
--   A holds 60 s and 65 s on a segment, B holds 70 s.
--   Board  → [A 60, B 70]                  → B is #2.
--   Chip   → 1 + count(60, 65 < 70) = 3    → B is #3 on their own run page.
--
-- One athlete, one segment, two ranks — and the chip links straight to the
-- board that contradicts it. A's repeat efforts inflate every slower athlete's
-- chip rank without limit; on a popular local climb the chip drifts arbitrarily
-- far from the board.
--
-- ── The population ──
-- Count DISTINCT rival athletes holding at least one strictly-faster visible
-- effort. That IS the per-athlete-best reduction: an athlete's best time is
-- below `t` exactly when they hold some effort below `t`, so `count(distinct
-- user_id)` over the strictly-faster rows equals `count(*)` over the deduped
-- bests — without materialising the dedupe, and still riding the
-- `segment_efforts_segment (segment_id, time_seconds)` range scan the RPC was
-- built on (20261223_001, perf-hunt 2026-06-10).
--
-- ── Why the effort's own athlete is excluded ──
-- On a per-athlete board you are not your own competitor. Dropping `f.user_id
-- <> e.user_id` would count A's 60 s against A's 65 s and report #2 for it —
-- reintroducing on the chip the exact "one athlete holds two ranks" artifact
-- #393 removed from the board. With the exclusion, the effort the board
-- actually shows (each athlete's best) gets precisely its board rank, and a
-- slower repeat effort reports where THAT time would place among the other
-- athletes' bests. Ties are unaffected: equal times are not strictly faster, so
-- standard competition ranking (tied fastest both 1, next 3) still holds.
--
-- ── Visibility: the block graph, deliberately ──
-- Both boards are SECURITY DEFINER and filter `not is_blocked_either_way`; the
-- rank RPCs are SECURITY INVOKER and leaned on RLS alone, which carries route
-- visibility (`private.is_route_visible_to` via the segments EXISTS) and run
-- visibility (`private.is_run_visible_to`) but knows nothing about blocks. So a
-- blocked athlete's faster effort still pushed the caller's rank down while
-- being absent from the board. Adding the filter NARROWS the counted set — it
-- can only remove rivals, never admit a row RLS excluded, so it fails closed —
-- and it closes the inference channel where a blocked user's times remain
-- observable through a rank number.
--
-- It is applied to the COMPARISON set only, not to the run's own efforts: a
-- caller reading a blocked athlete's public run must still get a rank row,
-- because the web client falls back to `rank ?? 1` on a missing row and would
-- print a crown (`fetchEffortsForRun`, `core/data.ts`).
--
-- An anon caller has `auth.uid() = null`, `is_blocked_either_way(null, x)` is
-- false, and nothing is filtered — correct, anon holds no blocks.
--
-- Still deliberately NOT mirrored from the boards: their `p_gender` /
-- `p_age_band` / `p_club_id` tiers. The chip shows a standing on the default
-- all-comers board, which is the board a reader lands on.
--
-- ── Online safety ──
-- `create or replace function` only. No table DDL, so no lock is taken on
-- `segment_efforts` (a high-volume table per docs/backend/migration_locks.md);
-- signatures are unchanged, so no drop-and-recreate and the existing grants
-- stand. No new index: making the distinct count index-only would need
-- `user_id` in the covering index, and `create index` on a high-volume table
-- blocks writes for the build while `concurrently` cannot run inside Supabase's
-- wrapped apply transaction. No column or return-type changes, so no row-type
-- regeneration is owed.
--
-- 20261223_001's header also claimed the RPC was "SECURITY INVOKER (like
-- `segment_leaderboard_tiered`)". The board has been SECURITY DEFINER since
-- `20260830_001` — it was already false when written, and the assumed
-- equivalence it rested on is the defect this migration fixes.

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
        from (
          select distinct f.user_id
          from public.segment_efforts f
          where f.segment_id = e.segment_id
            and f.time_seconds < e.time_seconds
            and f.user_id <> e.user_id
        ) rival
        where not public.is_blocked_either_way(auth.uid(), rival.user_id)
      )
    )::integer as rank
  from public.segment_efforts e
  where e.run_id = p_run_id;
$$;

-- The catalogue twin (20270411_001) carries the identical defect against
-- `global_segment_leaderboard`, which got its per-athlete reduction in
-- 20270513_001. `global_segment_efforts` is unique on (segment, run), so a
-- runner who repeats their local famous climb weekly accumulates an effort per
-- run — the divergence grows with every repetition.
create or replace function global_segment_effort_ranks(p_run_id uuid)
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
        from (
          select distinct f.user_id
          from public.global_segment_efforts f
          where f.global_segment_id = e.global_segment_id
            and f.time_seconds < e.time_seconds
            and f.user_id <> e.user_id
        ) rival
        where not public.is_blocked_either_way(auth.uid(), rival.user_id)
      )
    )::integer as rank
  from public.global_segment_efforts e
  where e.run_id = p_run_id;
$$;
