-- Grouped engagement counts for a batch of runs (perf).
--
-- The activity feed batches kudos + comment counts for a page of run ids
-- (fetchEngagementSummaries). It used to do `select('run_id').in('run_id', …)`
-- against run_kudos AND run_comments and count the returned ROWS client-side —
-- so the wire payload + row count scaled with TOTAL engagement on the page
-- (a popular group-run share with hundreds of kudos shipped hundreds of rows
-- to compute one integer), not with the number of runs.
--
-- This RPC returns one small row per run with the two counts, computed by a
-- GROUP BY over the existing run_id indexes (run_kudos_run_id /
-- run_comments_run_id). SECURITY INVOKER: it runs with the caller's RLS, so a
-- count includes exactly the rows the caller could already SELECT (kudos /
-- comments are "readable when the run is readable", 20260522_001) — identical
-- result to the old client-side row count, just without shipping every row.
-- The viewer_has_kudos flag stays a narrow client-side .in() lookup.
create or replace function run_engagement_counts(p_run_ids uuid[])
returns table (run_id uuid, kudos_count bigint, comment_count bigint)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select
    ids.run_id,
    coalesce(k.cnt, 0) as kudos_count,
    coalesce(c.cnt, 0) as comment_count
  from unnest(p_run_ids) as ids(run_id)
  left join (
    select run_id, count(*) as cnt
    from run_kudos
    where run_id = any(p_run_ids)
    group by run_id
  ) k on k.run_id = ids.run_id
  left join (
    select run_id, count(*) as cnt
    from run_comments
    where run_id = any(p_run_ids)
    group by run_id
  ) c on c.run_id = ids.run_id;
$$;

grant execute on function run_engagement_counts(uuid[]) to anon, authenticated;
