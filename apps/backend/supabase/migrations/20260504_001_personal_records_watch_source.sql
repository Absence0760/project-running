-- Add 'watch' to the source filter in personal_records().
--
-- Both watch platforms (Wear OS + Apple Watch) will now write
-- source = 'watch' instead of 'app'. Without this change the migration
-- that fixes the source value would silently drop all watch-recorded runs
-- from PB calculations.

create or replace function personal_records()
returns table (distance text, best_time_s integer, achieved_at timestamptz)
language sql stable
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
    and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
  group by 1
  having count(*) > 0;
$$;
