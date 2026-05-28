-- Event capacity enforcement + waitlist (event-organizer persona #42).
--
-- `events.capacity` was stored at create time but never enforced: rsvpEvent
-- upserts an event_attendees row with status='going' and nothing checked the
-- current headcount, so a capped 10k charity run could take unlimited
-- "Going" RSVPs. This adds:
--
--   1. enforce_event_capacity (BEFORE INSERT OR UPDATE): when a row would land
--      'going' and the event's per-instance 'going' count is already at
--      capacity, the row is demoted to 'waitlisted' instead.
--   2. promote_event_waitlist (AFTER UPDATE OR DELETE): when a 'going' slot
--      frees (someone drops to maybe/declined or deletes their RSVP), the
--      earliest-joined 'waitlisted' attendee for that instance is promoted to
--      'going'.
--
-- Capacity is per (event_id, instance_start) — a recurring event's occurrences
-- each have their own headcount. capacity IS NULL means unlimited (no
-- waitlisting). 'maybe' / 'declined' / 'waitlisted' never count against
-- capacity; only 'going' does.
--
-- Both triggers take a per-(event, instance) transaction advisory lock so two
-- concurrent "I'm in" clicks can't both read headcount < capacity and both
-- land 'going' (the race the naive client-side check would have).
--
-- 'waitlisted' is added to the RsvpStatus values. event_attendees.status has
-- no DB CHECK constraint today (it predates the narrow-union convention), so
-- no constraint change is needed; the web RsvpStatus union is updated in
-- lockstep.

create or replace function enforce_event_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cap integer;
  going_count integer;
begin
  if new.status <> 'going' then
    return new;
  end if;

  select capacity into cap from events where id = new.event_id;
  if cap is null then
    return new;  -- unlimited
  end if;

  -- Serialize concurrent capacity checks per (event, instance) so two
  -- simultaneous "I'm in" clicks can't both read going_count < cap.
  perform pg_advisory_xact_lock(
    hashtextextended(new.event_id::text || '|' || new.instance_start::text, 0)
  );

  select count(*) into going_count
  from event_attendees
  where event_id = new.event_id
    and instance_start = new.instance_start
    and status = 'going'
    and user_id <> new.user_id;  -- exclude the row being upserted

  if going_count >= cap then
    new.status := 'waitlisted';
  end if;

  return new;
end;
$$;

create or replace function promote_event_waitlist()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cap integer;
  going_count integer;
  next_user uuid;
begin
  -- Only act when a 'going' slot was actually vacated.
  if old.status <> 'going' then
    return null;
  end if;
  if tg_op = 'UPDATE' and new.status = 'going' then
    return null;  -- still going, nothing freed
  end if;

  select capacity into cap from events where id = old.event_id;
  if cap is null then
    return null;  -- unlimited: there can be no waitlist to promote
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(old.event_id::text || '|' || old.instance_start::text, 0)
  );

  select count(*) into going_count
  from event_attendees
  where event_id = old.event_id
    and instance_start = old.instance_start
    and status = 'going';

  if going_count >= cap then
    return null;  -- still full (shouldn't happen, but be safe)
  end if;

  select user_id into next_user
  from event_attendees
  where event_id = old.event_id
    and instance_start = old.instance_start
    and status = 'waitlisted'
  order by joined_at asc, user_id asc
  limit 1;

  if next_user is not null then
    update event_attendees
    set status = 'going'
    where event_id = old.event_id
      and instance_start = old.instance_start
      and user_id = next_user;
  end if;

  return null;
end;
$$;

create trigger trg_enforce_event_capacity
  before insert or update of status on event_attendees
  for each row execute function enforce_event_capacity();

create trigger trg_promote_event_waitlist
  after update of status or delete on event_attendees
  for each row execute function promote_event_waitlist();
