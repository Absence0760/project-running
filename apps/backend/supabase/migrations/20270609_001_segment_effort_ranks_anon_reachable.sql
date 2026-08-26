-- Make both segment-rank RPCs answerable for an anonymous caller again.
--
-- Found while removing the clients' `?? 1` rank degrade (decisions §746). The
-- degrade was described as a fallback that could not fire, because the RPCs
-- "always return a row". For a logged-out reader of a public run, neither of
-- them returns anything at all.
--
-- ── What broke, and when ──
-- `20270523_001` gave both rank RPCs the block filter, as
-- `where not public.is_blocked_either_way(auth.uid(), rival.user_id)`. Both
-- functions are SECURITY INVOKER, so that inner call is ACL-checked against
-- the CALLING role — and `is_blocked_either_way`'s anon EXECUTE grant was
-- revoked by `20261108_001` (anti-oracle defence-in-depth). `anon` holds
-- EXECUTE on `segment_effort_ranks` itself (20261223_001), so the call is
-- admitted and then raises 42501 inside the body.
--
-- 20270523_001's own header reasons the anon case through and concludes it
-- works — "an anon caller has `auth.uid() = null`, `is_blocked_either_way(null,
-- x)` is false, and nothing is filtered — correct, anon holds no blocks." That
-- is true of the PREDICATE and false of the PRIVILEGE. `20270402000001` had
-- already written the principle down for this very function, one layer up: a
-- function reference is ACL-checked at evaluation time for the querying role
-- regardless of short-circuiting, which is why the club policies could not name
-- `is_blocked_either_way` directly even behind an `auth.uid() is null` guard.
--
-- The failure is data-dependent, and the shape is the point: the predicate is
-- only evaluated once the rival subquery yields a row, so an anon caller gets a
-- clean answer for an effort with NO strictly-faster rival — a genuine #1 — and
-- an error as soon as any effort on the run has one. Paired with the clients'
-- `?? 1`, the RPC therefore succeeded exactly when the crown was real and
-- failed exactly when it was not: every logged-out reader of a public run saw
-- `#1` on every chip the runner had not actually won.
--
-- ── The fix: delegate to the helper that already exists ──
-- `20270402000001` created `private.viewer_blocks(target)` for precisely this
-- shape — a SECURITY DEFINER wrapper the anon/authenticated roles may execute,
-- keying on `auth.uid()` as the viewer, with `private` outside PostgREST's
-- exposed schemas so no anon RPC oracle is created. `viewer_blocks(t)` IS
-- `is_blocked_either_way(auth.uid(), t)`, so nothing about the counted
-- population changes for an authenticated caller; the anon caller gets `false`
-- (null viewer holds no blocks), which is the answer 20270523_001 intended.
-- Re-inlining a corrected copy is what created the §596 drift class, so this
-- calls the oracle rather than pasting one.
--
-- The catalogue twin additionally never had the role: `20270411_001` granted
-- EXECUTE to `authenticated` only, while `20270512_001` granted `anon` SELECT
-- on both catalogue tables. So even with the body fixed, a logged-out reader
-- could read the effort rows and not the ranks over them. Granting it admits
-- nothing new — SECURITY INVOKER means the function reads
-- `global_segment_efforts` under the caller's own RLS, the same policy as the
-- caller's own direct select, so it can only ask a question about rows anon
-- can already read.
--
-- ── Online safety ──
-- Two `create or replace function` bodies plus one EXECUTE grant. No table DDL,
-- so no lock on `segment_efforts` / `global_segment_efforts` (both high-volume
-- per docs/backend/migration_locks.md); signatures and return types are
-- unchanged, so no drop-and-recreate, the existing grants stand, and no
-- row-type regeneration is owed.

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
        where not private.viewer_blocks(rival.user_id)
      )
    )::integer as rank
  from public.segment_efforts e
  where e.run_id = p_run_id;
$$;

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
        where not private.viewer_blocks(rival.user_id)
      )
    )::integer as rank
  from public.global_segment_efforts e
  where e.run_id = p_run_id;
$$;

grant execute on function global_segment_effort_ranks(uuid) to anon;
