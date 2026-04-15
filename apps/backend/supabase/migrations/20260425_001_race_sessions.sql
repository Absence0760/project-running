-- Live race mode for club events. Layers onto the existing event_results
-- leaderboard by giving the organiser a server-authoritative Start signal
-- that every attendee's watch / phone subscribes to via realtime.
--
-- State machine:
--   armed     → organiser has pressed "Arm race"; attendees see the
--               armed screen and wait. No recording yet.
--   running   → organiser pressed "Start". `started_at` is the canonical
--               zero-time for every client (server wall clock — clients
--               render elapsed as `now() - started_at` instead of each
--               running their own stopwatch).
--   finished  → organiser pressed "End", or everyone submitted a result.
--               New results past this point need manual approval.
--   cancelled → organiser abandoned before starting.
--
-- `auto_approve` controls whether submitted results land as approved or
-- pending. For most clubs, default-on is fine (trust-based); for leagues
-- / tournament events, organisers flip it off and verify each result.

create table race_sessions (
  event_id uuid not null references events(id) on delete cascade,
  instance_start timestamptz not null,
  status text not null default 'armed'
    check (status in ('armed', 'running', 'finished', 'cancelled')),
  started_at timestamptz,
  started_by uuid references auth.users(id) on delete set null,
  finished_at timestamptz,
  auto_approve boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, instance_start)
);

alter table race_sessions enable row level security;

-- Visible to anyone who can see the event.
create policy race_sessions_visible_when_event_is
  on race_sessions for select
  using (
    exists (
      select 1 from events e
      left join clubs c on c.id = e.club_id
      where e.id = race_sessions.event_id
        and (
          c.id is null
          or c.is_public = true
          or c.owner_id = auth.uid()
          or is_club_member(c.id)
        )
    )
  );

-- Only club admins arm / start / end a race.
create policy race_sessions_admin_insert
  on race_sessions for insert
  with check (
    exists (
      select 1 from events e
      where e.id = race_sessions.event_id
        and is_club_admin(e.club_id)
    )
  );

create policy race_sessions_admin_update
  on race_sessions for update
  using (
    exists (
      select 1 from events e
      where e.id = race_sessions.event_id
        and is_club_admin(e.club_id)
    )
  );

create policy race_sessions_admin_delete
  on race_sessions for delete
  using (
    exists (
      select 1 from events e
      where e.id = race_sessions.event_id
        and is_club_admin(e.club_id)
    )
  );

-- Live ping feed — one row per GPS sample uploaded by a racing client,
-- ~every 10s. Used by the spectator map and (less frequently) by the
-- organiser dashboard. Pings are ephemeral; we TTL them by deleting on
-- `race_sessions` finish (see function below).
create table race_pings (
  id bigserial primary key,
  event_id uuid not null references events(id) on delete cascade,
  instance_start timestamptz not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  at timestamptz not null default now(),
  lat double precision not null,
  lng double precision not null,
  distance_m double precision,
  elapsed_s integer,
  bpm integer
);

create index race_pings_by_race_at
  on race_pings(event_id, instance_start, at desc);
create index race_pings_by_race_user
  on race_pings(event_id, instance_start, user_id, at desc);

alter table race_pings enable row level security;

-- Anyone who can see the parent race can read pings.
create policy race_pings_visible_when_race_is
  on race_pings for select
  using (
    exists (
      select 1 from race_sessions rs
      where rs.event_id = race_pings.event_id
        and rs.instance_start = race_pings.instance_start
    )
  );

-- A user can only write their own pings, and only while the race is
-- running. A late ping or a ping for someone else is silently rejected.
create policy race_pings_insert_self_while_running
  on race_pings for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from race_sessions rs
      where rs.event_id = race_pings.event_id
        and rs.instance_start = race_pings.instance_start
        and rs.status = 'running'
    )
  );

-- Admin cleanup of an abandoned race.
create policy race_pings_admin_delete
  on race_pings for delete
  using (
    exists (
      select 1 from events e
      where e.id = race_pings.event_id
        and is_club_admin(e.club_id)
    )
  );

-- Approval columns on event_results. For `auto_approve = true` sessions
-- (most clubs), inserts default to approved. For manual-verify sessions,
-- a trigger flips them to pending on insert and the organiser approves
-- later via `approve_event_result()`.
alter table event_results
  add column organiser_approved boolean not null default true,
  add column organiser_approved_by uuid references auth.users(id) on delete set null,
  add column organiser_approved_at timestamptz;

create index event_results_pending
  on event_results(event_id, instance_start)
  where organiser_approved = false;

create or replace function event_results_set_approval_default()
returns trigger language plpgsql as $$
declare
  v_auto boolean;
begin
  -- Only fire on insert; updates shouldn't silently flip approval.
  if (tg_op <> 'INSERT') then
    return new;
  end if;
  select auto_approve into v_auto
  from race_sessions
  where event_id = new.event_id and instance_start = new.instance_start;
  if v_auto is not null and v_auto = false then
    new.organiser_approved := false;
    new.organiser_approved_by := null;
    new.organiser_approved_at := null;
  else
    new.organiser_approved := true;
    new.organiser_approved_by := new.user_id;  -- self-approved implicit
    new.organiser_approved_at := now();
  end if;
  return new;
end;
$$;

create trigger event_results_set_approval_before_insert
  before insert on event_results
  for each row execute function event_results_set_approval_default();

-- Convenience RPC for the organiser's Approve / Reject row actions.
-- Returns the updated row for the client to replace in-place.
create or replace function approve_event_result(
  p_event_id uuid,
  p_instance_start timestamptz,
  p_user_id uuid,
  p_approve boolean
) returns event_results language plpgsql security definer set search_path = public as $$
declare
  v_row event_results;
  v_club uuid;
begin
  select club_id into v_club from events where id = p_event_id;
  if v_club is null or not is_club_admin(v_club) then
    raise exception 'Not authorised to approve results for this event';
  end if;
  update event_results
    set organiser_approved = p_approve,
        organiser_approved_by = auth.uid(),
        organiser_approved_at = now(),
        updated_at = now()
    where event_id = p_event_id
      and instance_start = p_instance_start
      and user_id = p_user_id
    returning * into v_row;
  return v_row;
end;
$$;

grant execute on function approve_event_result(uuid, timestamptz, uuid, boolean)
  to authenticated;

-- Add race_sessions + race_pings + event_results to the realtime
-- publication so both organiser and spectator clients see changes without
-- polling. Uses the same pattern as 20260418_001_social_realtime.sql.
alter publication supabase_realtime add table race_sessions;
alter publication supabase_realtime add table race_pings;
alter publication supabase_realtime add table event_results;
