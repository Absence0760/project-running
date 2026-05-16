-- Personal-records refresh: serialize concurrent invocations per-user.
--
-- The trigger `runs_personal_records_delete` (and its insert/update
-- siblings) call `refresh_personal_records_for_user`, which does a
-- DELETE-then-INSERT against `personal_records` for the affected user.
-- When the client fires multiple parallel run DELETEs (e.g. bulk-delete
-- from the /runs page), the trigger executes once per row, in parallel
-- across separate transactions. Two concurrent invocations race:
--
--   Tx A:  DELETE personal_records WHERE user_id=X   (acquires locks)
--   Tx A:  INSERT into personal_records ...           (acquires new rows)
--   Tx A:  COMMIT
--   Tx B:  DELETE personal_records WHERE user_id=X   (blocked → wakes)
--   Tx B:  INSERT into personal_records ...
--           → DUPLICATE KEY VIOLATES UNIQUE CONSTRAINT personal_records_pkey
--
-- The conflicting row is the one Tx B just deleted in its own statement,
-- but PostgreSQL's MVCC for the INSERT sees A's still-committing rows
-- under the wrong snapshot in a small concurrency window. The 23505
-- error rolls back Tx B's runs.DELETE too, so the run row stays alive
-- and the user's "bulk delete 10" leaves half the rows behind.
--
-- Fix: an advisory transaction lock keyed by user_id. Only one
-- refresh_personal_records_for_user call runs per-user at a time;
-- everything else for that user waits until the current refresh commits.
-- The lock is released automatically at transaction end so we don't
-- need an explicit unlock. Per-user serialization is fine — PR refresh
-- is microseconds and only one user can ever be the subject anyway.

create or replace function refresh_personal_records_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Serialize per-user. hashtext gives a stable 32-bit hash; the two-int
  -- variant of advisory_xact_lock partitions the lock space cleanly so
  -- this can't collide with any other advisory lock the app uses.
  perform pg_advisory_xact_lock(
    hashtext('personal_records:' || p_user_id::text)
  );

  delete from personal_records where user_id = p_user_id;

  insert into personal_records (user_id, distance, best_time_s, run_id, achieved_at)
  select
    p_user_id,
    distance,
    duration_s,
    id,
    started_at
  from (
    select
      id,
      duration_s,
      started_at,
      case
        when distance_m between 4900  and 5100   then '5k'
        when distance_m between 9900  and 10100  then '10k'
        when distance_m between 21000 and 21200  then 'half_marathon'
        when distance_m between 42100 and 42300  then 'marathon'
      end as distance,
      row_number() over (
        partition by
          case
            when distance_m between 4900  and 5100   then '5k'
            when distance_m between 9900  and 10100  then '10k'
            when distance_m between 21000 and 21200  then 'half_marathon'
            when distance_m between 42100 and 42300  then 'marathon'
          end
        order by duration_s asc
      ) as rn
    from runs
    where user_id = p_user_id
      and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect')
      and distance_m is not null
      and duration_s is not null
  ) ranked
  where rn = 1 and distance is not null;
end;
$$;
