-- RLS audit Medium: weekly_mileage() and personal_records() in
-- `20260406_001_database_functions.sql` are SECURITY INVOKER but missing
-- `set search_path = public`. A session that has redirected its
-- search_path to a shadow schema could re-route the `runs` reference to
-- an attacker-controlled table. Supabase PostgREST sessions don't have
-- search_path write access by default, so this is hygiene rather than an
-- exploitable gap, but every other function in the migration set pins
-- the path; these two are the outliers.

create or replace function weekly_mileage(weeks_back integer default 12)
returns table (week_start date, total_distance_m numeric)
language sql stable
set search_path = public
as $$
  select
    date_trunc('week', started_at)::date as week_start,
    sum(distance_m) as total_distance_m
  from runs
  where
    user_id = auth.uid()
    and started_at >= now() - (weeks_back || ' weeks')::interval
  group by 1
  order by 1;
$$;

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
    and source in ('app', 'strava', 'garmin', 'healthkit', 'healthconnect')
  group by 1
  having count(*) > 0;
$$;
