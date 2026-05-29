-- Notification fan-out: club posts + completed runs (persona #38).
--
-- The notifications inbox (decisions §38, migration 20260528000001) grew
-- one kind at a time — kudos / comment / follow, then event_rsvp,
-- event_cancel, plan_update, message. Two community-facing fan-outs were
-- still missing, and the club-home copy already *promised* one of them
-- ("Posts here notify every active member") without a trigger behind it:
--
--   * club_post — a new post in a club feed fans out to every *active*
--     member of that club except the author (pending join-requests are
--     skipped). Bounded by club membership, which is the loop each member
--     opted into by joining. Makes the existing club-home copy ("Posts
--     here notify every active member") truthful.
--   * run_completed — a freshly-finished public run fans out to the
--     runner's followers. Bounded by follower count (the loop they opted
--     into by following). Gated on a 24-hour recency window so a bulk
--     history import (Strava/Garmin ZIP, parkrun backfill, CSV restore)
--     can't explode every follower's inbox with years of old activity —
--     only runs that actually finished in the last day notify. The window
--     is wide enough to cover an ultra-length single session (decisions
--     §96). Source-agnostic: a fresh run synced via the Strava webhook an
--     hour after finishing still notifies; a 90-day backfill does not.
--
-- Device push (FCM/APNs) for these kinds is still deferred per roadmap
-- Phase 4b — the sender is blocked on user-supplied Firebase/APNs
-- credentials. The notifications row IS the delivery surface today; the
-- in-app inbox (web NotificationsList / NotificationBell, mobile
-- profile_screen) renders them. When the push sender lands it reads the
-- same rows; nothing here changes.

-- ─────────────────────── schema ───────────────────────

-- club_post navigation target. ON DELETE CASCADE so deleting a club
-- clears its notifications, matching run_id / event_id / plan_id.
alter table notifications
  add column club_id uuid references clubs(id) on delete cascade;

alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed'
    )
  );

-- Defensive dedupe: one run_completed per (recipient, run). The trigger
-- only fires on INSERT of a brand-new run so a conflict can't happen
-- today, but the index keeps the invariant if the trigger ever grows an
-- UPDATE path.
create unique index notifications_run_completed_uniq
  on notifications (user_id, run_id)
  where kind = 'run_completed';

-- ─────────────────────── triggers ───────────────────────

-- New club post → notify every member of the club except the author.
create or replace function notify_club_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into notifications (user_id, actor_id, kind, club_id)
  select m.user_id, new.author_id, 'club_post', new.club_id
  from club_members m
  where m.club_id = new.club_id
    and m.status = 'active'
    and m.user_id is distinct from new.author_id;
  return new;
end;
$$;

create trigger trg_notify_club_post
  after insert on club_posts
  for each row execute function notify_club_post();

-- New public run → notify the runner's followers. Skips non-public runs
-- and anything older than 24 h (the bulk-import / late-sync guard).
create or replace function notify_run_completed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_public is not true
     or new.started_at < now() - interval '24 hours' then
    return new;
  end if;

  insert into notifications (user_id, actor_id, kind, run_id)
  select f.follower_id, new.user_id, 'run_completed', new.id
  from user_follows f
  where f.followee_id = new.user_id
  on conflict do nothing;

  return new;
end;
$$;

create trigger trg_notify_run_completed
  after insert on runs
  for each row execute function notify_run_completed();
