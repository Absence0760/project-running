-- Fan the event-RSVP notification out to the event-ops team, not just the
-- creator (persona round-5 social-group).
--
-- 20260903_001 notified only events.created_by. If the founder delegates
-- an event to a co-organiser (the `event_organiser` / `race_director`
-- club roles exist for exactly this), that organiser saw no RSVPs — the
-- "is anyone coming?" signal dead-ended at a creator who'd handed the
-- event off. Notify the creator PLUS anyone holding an event-ops role in
-- the club. Generic admins/owners are deliberately NOT fanned out to
-- (that's the spam concern the original migration called out) unless they
-- created the event. The RSVPer never notifies themselves, and the
-- existing (user_id, actor_id, event_id) partial unique index de-dupes
-- per recipient.

create or replace function notify_event_rsvp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_club uuid;
  v_creator uuid;
begin
  if NEW.status is distinct from 'going' then
    return NEW;
  end if;

  if TG_OP = 'UPDATE' and OLD.status = 'going' then
    return NEW;
  end if;

  select club_id, created_by into v_club, v_creator
  from events where id = NEW.event_id;
  if v_club is null then
    return NEW;
  end if;

  insert into notifications (user_id, actor_id, kind, event_id)
  select recipient, NEW.user_id, 'event_rsvp', NEW.event_id
  from (
    select v_creator as recipient
    union
    select cm.user_id
    from club_members cm
    where cm.club_id = v_club
      and cm.status = 'active'
      and cm.role in ('event_organiser', 'race_director')
  ) recipients
  where recipient is not null
    and recipient <> NEW.user_id
  on conflict do nothing;

  return NEW;
end;
$$;
