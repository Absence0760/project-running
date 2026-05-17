-- Notify the event creator when someone RSVPs "Going" to their event.
--
-- The notifications inbox (decisions §38, migration 20260528_001) wired
-- triggers on run_kudos, run_comments, and user_follows only. Club
-- events were deferred there because the original concern was fan-out
-- on a big-club event ("500 people RSVP" → 500 inbox rows for the
-- creator). In practice events are creator-scoped and the fan-out goes
-- the *other* way — one notification per RSVP, fanning into the
-- creator's inbox. That's the same shape as kudos: cheap, bounded by
-- the social loop the creator opted into by making the event.
--
-- Scope: only the event creator gets notified. Club admins are NOT
-- notified — the creator is already an admin (events RLS requires
-- is_club_admin to insert), so they're already covered, and notifying
-- every admin on every RSVP turns into spam on bigger clubs.
--
-- Trigger fires on INSERT OR UPDATE so a Maybe→Going flip still
-- notifies. Status flips Going→Maybe→Going are de-duped by the partial
-- unique index below: re-RSVPing "Going" on the same instance is the
-- same notification. ON CONFLICT DO NOTHING keeps the trigger silent
-- under upsert churn.

alter table notifications
  add column event_id uuid references events(id) on delete cascade;

alter table notifications drop constraint notifications_kind_check;

alter table notifications
  add constraint notifications_kind_check
  check (kind in ('kudos', 'comment', 'comment_reply', 'follow', 'event_rsvp'));

create unique index notifications_event_rsvp_uniq
  on notifications (user_id, actor_id, event_id)
  where kind = 'event_rsvp';

create or replace function notify_event_rsvp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  event_owner uuid;
begin
  if NEW.status is distinct from 'going' then
    return NEW;
  end if;

  if TG_OP = 'UPDATE' and OLD.status = 'going' then
    return NEW;
  end if;

  select created_by into event_owner from events where id = NEW.event_id;
  if event_owner is null or event_owner = NEW.user_id then
    return NEW;
  end if;

  insert into notifications (user_id, actor_id, kind, event_id)
    values (event_owner, NEW.user_id, 'event_rsvp', NEW.event_id)
    on conflict do nothing;

  return NEW;
end;
$$;

create trigger event_attendees_notify
  after insert or update on event_attendees
  for each row execute function notify_event_rsvp();
