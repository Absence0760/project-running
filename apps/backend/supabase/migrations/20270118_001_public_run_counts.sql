-- Per-user public-run counts for the People-suggestions / search surface.
--
-- hydratePeopleSuggestions counted each candidate's public runs with
-- `runs.select('user_id').in('user_id', ids).eq('is_public', true)` and a
-- client-side tally. Two problems:
--   1. Perf: no limit → it transferred one row per public run across ALL
--      candidates (a populated club's prolific runners ship thousands of rows
--      to compute a handful of integers).
--   2. Correctness: since 20260701_001 dropped the public-anyone SELECT policy
--      on the base `runs` table (decisions §33 — non-owner reads go through the
--      public_runs view), that query returns ZERO rows for everyone but the
--      viewer, so the displayed public_runs_count was ~0 for other candidates.
--
-- public_run_counts is SECURITY DEFINER — REQUIRED here, because base-table RLS
-- blocks a non-owner from reading another user's public runs at all. It returns
-- ONLY (user_id, count of is_public runs); a public-run count is non-sensitive
-- (it's already shown on the public profile), and it never exposes a private
-- run's existence or any run content. The is_public filter is the hard gate.
create or replace function public_run_counts(p_user_ids uuid[])
returns table (user_id uuid, public_run_count bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.user_id, count(*) as public_run_count
  from runs r
  where r.user_id = any(p_user_ids)
    and r.is_public = true
  group by r.user_id;
$$;

grant execute on function public_run_counts(uuid[]) to authenticated;
