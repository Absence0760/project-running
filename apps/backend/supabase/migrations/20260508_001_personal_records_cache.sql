-- Personal records cache + trigger.
--
-- The existing `personal_records()` SQL function
-- (`apps/backend/supabase/migrations/20260406_001_database_functions.sql`
-- and updated in `20260504_001_personal_records_watch_source.sql`)
-- recomputes every PB by scanning all of a user's runs on every call.
-- That's fine at single-user scale; Phase 2's dashboard + future
-- leaderboards hammer it. This migration introduces a `personal_records`
-- summary table backed by triggers on `runs` so reads are a single
-- indexed lookup.
--
-- Invariants:
--   - One row per (user_id, distance), where `distance` is
--     `5k | 10k | half_marathon | marathon`.
--   - `run_id` points at the run that currently holds the PB for that
--     distance; `on delete set null` so deleting the run detaches
--     without cascading the whole PB row.
--   - The trigger recomputes the full set of PBs for the affected user
--     on every insert / update / delete rather than trying to
--     incrementally update the matching bucket. Full rebuild is simpler
--     to reason about (run deletion that was the current PB, source
--     column flip, distance edit) and each user only owns hundreds of
--     runs at most, so the scan cost is flat.
--
-- The existing `personal_records()` function is left intact — callers
-- that want the live view still get it. New callers should select from
-- this table instead.

create table personal_records (
  user_id       uuid not null references auth.users(id) on delete cascade,
  distance      text not null check (distance in ('5k', '10k', 'half_marathon', 'marathon')),
  best_time_s   integer not null,
  run_id        uuid references runs(id) on delete set null,
  achieved_at   timestamptz not null,
  updated_at    timestamptz not null default now(),
  primary key (user_id, distance)
);

-- Read path: "all of my PBs" (4 rows). Primary key already indexes this
-- but leaderboards also want "best 10k times across all users" — the
-- second index powers that shape without scanning the whole table.
create index personal_records_distance_time
  on personal_records (distance, best_time_s asc);

alter table personal_records enable row level security;

-- Public-ish by design: PBs are the sort of thing that appears on a
-- leaderboard. Today we scope reads to the owner to match every other
-- RLS policy in this schema; broader read is a follow-up when the
-- leaderboard UI lands and we know how we want to scope it.
create policy personal_records_self_select on personal_records
  for select using (user_id = auth.uid());

-- Writes come only from the trigger (security definer). No user-level
-- insert / update / delete policies — direct writes would break the
-- invariant that the row reflects the actual PB in `runs`.

-- Recompute the full PB set for one user. Called from the trigger on
-- any run insert / update / delete. `security definer` so the trigger
-- can write regardless of the caller's RLS.
create or replace function refresh_personal_records_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
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

grant execute on function refresh_personal_records_for_user(uuid) to authenticated;

-- Trigger shim — dispatches to the recompute function for the run's
-- owner. One function covers insert / update / delete so the three
-- triggers below all route through the same code path.
create or replace function trigger_refresh_personal_records()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform refresh_personal_records_for_user(old.user_id);
    return old;
  else
    perform refresh_personal_records_for_user(new.user_id);
    -- If the run moved owners (rare — we don't support reassignment
    -- but guard in case), recompute the old owner too.
    if tg_op = 'UPDATE' and new.user_id <> old.user_id then
      perform refresh_personal_records_for_user(old.user_id);
    end if;
    return new;
  end if;
end;
$$;

create trigger runs_personal_records_insert
  after insert on runs
  for each row
  execute function trigger_refresh_personal_records();

create trigger runs_personal_records_update
  after update of distance_m, duration_s, source, user_id on runs
  for each row
  execute function trigger_refresh_personal_records();

create trigger runs_personal_records_delete
  after delete on runs
  for each row
  execute function trigger_refresh_personal_records();

-- Backfill — one row per existing (user, distance) that has a run in
-- the qualifying distance bracket. Done via the same helper function
-- so the backfill shape is identical to the trigger path.
do $$
declare
  uid uuid;
begin
  for uid in select distinct user_id from runs loop
    perform refresh_personal_records_for_user(uid);
  end loop;
end;
$$;
