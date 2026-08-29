-- personal_records() lost 'watch' in a search_path hardening pass, and never
-- gained 'parkrun' / 'race'.
--
-- `20260504_001_personal_records_watch_source.sql` added 'watch' to this
-- function's source filter, and said why: "Both watch platforms (Wear OS +
-- Apple Watch) will now write source = 'watch' instead of 'app'. Without this
-- change the migration that fixes the source value would silently drop all
-- watch-recorded runs from PB calculations."
--
-- `20260710_001_database_functions_search_path.sql` then re-issued the
-- function to add `set search_path = public` — and re-issued the ORIGINAL
-- `20260406_001` body to do it, dropping 'watch' back out. Nothing rejected
-- anything: a narrower `in` list is valid SQL, so the only symptom was watch
-- runs quietly absent from this RPC's answer.
--
-- #378's later widening to 'parkrun' + 'race' reached
-- refresh_personal_records_for_user and award_achievements_for_user
-- (`20270424_001`, carried forward by `20270514_001`) and never reached here,
-- because nothing tied the three filters together.
--
-- The function stays: `20260508_001` left it in place "for callers that
-- haven't migrated" to the `personal_records` cache table, and it is still
-- reachable over PostgREST. This restores the eligible-run vocabulary its two
-- siblings use, which is `runs_source_check`'s own value set.
-- `scripts/check_shared_constants.mjs` now reads all three filters and the
-- constraint and fails when they diverge again (decisions.md § 787).
--
-- No DDL on a table: a `create or replace function` takes no lock a reader or
-- writer waits on.

create or replace function personal_records()
returns table (distance text, best_time_s integer, achieved_at timestamptz)
language sql stable
set search_path = public
as $$
  select
    case
      when distance_m between 4900 and 5100 then '5k'
      when distance_m between 9900 and 10100 then '10k'
      when distance_m between 21000 and 21200 then 'Half marathon'
      when distance_m between 42100 and 42300 then 'Marathon'
    end as distance,
    min(duration_s) as best_time_s,
    (array_agg(started_at order by duration_s))[1] as achieved_at
  from runs
  where
    user_id = auth.uid()
    and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
  group by 1
  having count(*) > 0;
$$;
