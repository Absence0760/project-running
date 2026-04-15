-- Race-style results for club events. A per-(event, instance, user) table
-- that ranks finishers by duration — the same shape a parkrun barcode
-- produces, but for any event a club creates.
--
-- Why a dedicated table instead of just stamping `runs.metadata.event_id`:
--
--   1. One user can log DNF / DNS without a run row — manual entries
--      (they forgot to hit Start, or they were volunteering) still need
--      to appear on the leaderboard.
--   2. An organiser needs to edit a time or disqualify a runner without
--      mutating the underlying `runs` row (the run is the user's; the
--      result is the event's).
--   3. `rank` is recomputed after every insert / update / delete; doing
--      that on a join through `runs` + `runs.metadata->>'event_id'`
--      would mean a GIN scan on every write.
--
-- We still add `runs.event_id` as a convenience link so we can go from
-- a run detail page back to the event it was part of, and so the watch
-- / phone "record for this event" flow has a first-class column to
-- stamp at save time.

alter table runs
  add column event_id uuid references events(id) on delete set null;

create index runs_event_id_idx on runs(event_id) where event_id is not null;

create table event_results (
  event_id uuid not null references events(id) on delete cascade,
  -- Matches `event_attendees.instance_start` — recurring events rank
  -- per-instance, not per-series, so Tuesday-this-week's 5 km has its
  -- own leaderboard separate from Tuesday-next-week's.
  instance_start timestamptz not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  run_id uuid references runs(id) on delete set null,
  duration_s integer not null check (duration_s >= 0),
  distance_m double precision not null check (distance_m >= 0),
  rank integer,
  finisher_status text not null default 'finished'
    check (finisher_status in ('finished', 'dnf', 'dns')),
  age_grade_pct double precision
    check (age_grade_pct is null or (age_grade_pct >= 0 and age_grade_pct <= 200)),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, instance_start, user_id)
);

create index event_results_by_event_instance
  on event_results(event_id, instance_start, rank);
create index event_results_by_user on event_results(user_id);

alter table event_results enable row level security;

-- Results are as visible as the parent event. Reuses the same "can see
-- this event?" logic that `events` already has — club_id visibility rules
-- flow through via the FK join.
create policy event_results_visible_when_event_is
  on event_results for select
  using (
    exists (
      select 1 from events e
      left join clubs c on c.id = e.club_id
      where e.id = event_results.event_id
        and (
          c.id is null
          or c.is_public = true
          or c.owner_id = auth.uid()
          or is_club_member(c.id)
        )
    )
  );

create policy event_results_insert_self
  on event_results for insert
  with check (auth.uid() = user_id);

create policy event_results_update_self_or_admin
  on event_results for update
  using (
    auth.uid() = user_id
    or exists (
      select 1 from events e
      where e.id = event_results.event_id
        and is_club_admin(e.club_id)
    )
  )
  with check (
    auth.uid() = user_id
    or exists (
      select 1 from events e
      where e.id = event_results.event_id
        and is_club_admin(e.club_id)
    )
  );

create policy event_results_delete_self_or_admin
  on event_results for delete
  using (
    auth.uid() = user_id
    or exists (
      select 1 from events e
      where e.id = event_results.event_id
        and is_club_admin(e.club_id)
    )
  );

-- Rank recomputation. Runs on every insert / update / delete touching a
-- single (event_id, instance_start) group. Finishers rank by ascending
-- duration; DNF / DNS rows never get a rank (the trigger leaves them
-- null so the leaderboard can show them with a em-dash).
create or replace function recompute_event_ranks(
  p_event_id uuid,
  p_instance_start timestamptz
) returns void language plpgsql as $$
begin
  with ranked as (
    select
      ctid,
      case
        when finisher_status = 'finished'
          then rank() over (order by duration_s asc, created_at asc)
        else null
      end as new_rank
    from event_results
    where event_id = p_event_id and instance_start = p_instance_start
  )
  update event_results er
  set rank = ranked.new_rank,
      updated_at = now()
  from ranked
  where er.ctid = ranked.ctid
    and er.rank is distinct from ranked.new_rank;
end;
$$;

create or replace function event_results_rerank_trigger()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'DELETE') then
    perform recompute_event_ranks(old.event_id, old.instance_start);
    return old;
  else
    perform recompute_event_ranks(new.event_id, new.instance_start);
    return new;
  end if;
end;
$$;

create trigger event_results_rerank_after_change
  after insert or update of duration_s, finisher_status or delete
  on event_results
  for each row execute function event_results_rerank_trigger();
