-- Per-instance recurring-event cancellation + audit (parkrun / social-group
-- persona #39).
--
-- Before this, the only way to call off a single occurrence of a recurring
-- event was to delete the whole events row, nuking every future instance and
-- every RSVP/result. There was also no record of who cancelled what, when, or
-- why. This adds:
--
--   * event_exceptions — one row per cancelled (event_id, instance_start),
--     carrying the audit trail (cancelled_by, cancelled_at, reason). The
--     parent events row and the rest of the series are untouched; the web
--     instance picker filters cancelled occurrences out and blocks RSVPs.
--   * a fan-out trigger that notifies every attendee (going / maybe /
--     waitlisted) of the cancelled instance, via a new 'event_cancel'
--     notification kind.
--
-- Reinstating an occurrence is a DELETE of the exception row (organiser-only).

create table event_exceptions (
  event_id       uuid references events(id) on delete cascade not null,
  instance_start timestamptz not null,
  cancelled_by   uuid references auth.users(id) on delete set null,
  reason         text,
  cancelled_at   timestamptz not null default now(),
  primary key (event_id, instance_start)
);

create index event_exceptions_event on event_exceptions (event_id);

alter table event_exceptions enable row level security;

-- Readable by anyone who can see the parent event (same club-visibility
-- predicate the events SELECT policy uses) so every viewer's picker can hide
-- a cancelled occurrence.
create policy "exceptions readable with their event"
  on event_exceptions for select using (
    exists (
      select 1 from events e
      join clubs c on c.id = e.club_id
      where e.id = event_exceptions.event_id
        and (c.is_public = true or c.owner_id = auth.uid() or is_club_member(c.id))
    )
  );

-- Only an event organiser of the owning club can cancel an occurrence, and
-- the audit actor must be the caller (no forging cancelled_by).
create policy "organisers cancel their event occurrences"
  on event_exceptions for insert with check (
    cancelled_by = auth.uid()
    and exists (
      select 1 from events e
      where e.id = event_exceptions.event_id
        and is_event_organiser(e.club_id)
    )
  );

create policy "organisers reinstate their event occurrences"
  on event_exceptions for delete using (
    exists (
      select 1 from events e
      where e.id = event_exceptions.event_id
        and is_event_organiser(e.club_id)
    )
  );

-- Add the 'event_cancel' notification kind.
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (kind in ('kudos', 'comment', 'comment_reply', 'follow', 'event_rsvp', 'event_cancel'));

-- Fan out a notification to every attendee of the cancelled instance.
-- Bounded by the instance's attendee count (the social loop the organiser
-- opted into). Skips the canceller's own RSVP. ON CONFLICT is a no-op guard
-- against the (no unique index today) — kept for symmetry with notify_event_rsvp.
create or replace function notify_event_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into notifications (user_id, actor_id, kind, event_id)
  select a.user_id, new.cancelled_by, 'event_cancel', new.event_id
  from event_attendees a
  where a.event_id = new.event_id
    and a.instance_start = new.instance_start
    and a.status in ('going', 'maybe', 'waitlisted')
    and a.user_id is distinct from new.cancelled_by
  on conflict do nothing;
  return null;
end;
$$;

create trigger trg_notify_event_cancel
  after insert on event_exceptions
  for each row execute function notify_event_cancel();
