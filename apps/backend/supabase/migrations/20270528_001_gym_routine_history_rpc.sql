-- Per-routine session history, aggregated server-side.
--
-- The routine-detail history panel (web GymRoutineHistory.svelte, mobile
-- routine_detail_screen.dart) used to read every gym_workouts row carrying
-- `metadata.routine_id` and reduce them in the client just to show a count, a
-- last-done date, and five rows. Both platforms bounded that read at 500 —
-- because an unbounded PostgREST select truncates silently at `db.max-rows`
-- and still answers 200 — so a lifter running one routine weekly for a decade
-- was shown a capped figure with nothing marking it as capped.
--
-- A count is an aggregate, so no windowed client read can serve it honestly;
-- the durable fix is to aggregate in SQL, the shape gym_exercise_records
-- (20261224_001) and run_streaks_for_user (20270501_001) already took. This
-- RPC returns exactly one row: the complete counts plus an explicitly bounded
-- page of the most recent sessions for the list the panel renders. One call,
-- one snapshot — so the page can never disagree with the count it sits under.
--
-- The two exclusions ARE the contract, and they mirror
-- gym/routine_history.ts ↔ routine_history.dart (decisions § 617):
--   * A row still carrying a `gym_session_draft` object is an in-flight
--     session, not a session performed. Counting one would let a resume
--     inflate the routine's usage. It is dropped from BOTH the count and the
--     page. (`jsonb_typeof(...) = 'object'` matches how both writers stamp the
--     marker, per gym_session_draft.ts#draftMetadata.)
--   * A "save as is" row keeps `routine_id` and deliberately claims no
--     adherence verdict. It happened, so it counts as a session, but it sits
--     OUTSIDE the graded denominator rather than counting as a miss.
-- `days since last` stays client-side: it is floored against the READER's
-- clock and clamped so a row stamped ahead of it reads as today, which is a
-- display rule, not a stored fact.
--
-- SECURITY INVOKER with a load-bearing explicit `auth.uid()` filter: the
-- gym_workouts select policy also admits `is_public` rows belonging to other
-- users, so without it a caller could aggregate a stranger's sessions.
--
-- Lock impact (migration_locks.md): one function body. No table DDL, no
-- constraint, no backfill — CREATE FUNCTION locks the pg_proc entry only.
--
-- p_recent_limit is clamped to [0, 50]: the panel asks for 5, and a cap keeps
-- a caller from re-opening the unbounded read this RPC exists to close.

create or replace function gym_routine_history(
  p_routine_id uuid,
  p_recent_limit integer default 5
)
returns table (
  session_count integer,
  last_performed_at timestamptz,
  graded_count integer,
  completed_count integer,
  recent_sessions jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with performed as (
    select
      gw.id,
      gw.started_at,
      gw.title,
      gw.metadata,
      gw.metadata ->> 'gym_adherence' as verdict
    from gym_workouts gw
    where gw.user_id = auth.uid()
      and gw.metadata ->> 'routine_id' = p_routine_id::text
      and jsonb_typeof(gw.metadata -> 'gym_session_draft') is distinct from 'object'
  ),
  recent as (
    select id, started_at, title, metadata
    from performed
    order by started_at desc, id
    limit least(greatest(coalesce(p_recent_limit, 5), 0), 50)
  )
  select
    (select count(*)::int from performed),
    (select max(started_at) from performed),
    (select count(*)::int from performed
      where verdict in ('completed', 'partial', 'abandoned')),
    (select count(*)::int from performed where verdict = 'completed'),
    coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'id', id,
                  'started_at', started_at,
                  'title', title,
                  'metadata', metadata
                )
                order by started_at desc, id)
       from recent),
      '[]'::jsonb);
$$;

revoke execute on function gym_routine_history(uuid, integer) from public;
grant  execute on function gym_routine_history(uuid, integer) to authenticated;
