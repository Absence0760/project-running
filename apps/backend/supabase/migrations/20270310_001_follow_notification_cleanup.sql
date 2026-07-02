-- Retract a "started following you" notification when the follow is undone.
--
-- `notify_user_follow` (20260528000001) inserts a `kind='follow'`
-- notification on every `user_follows` INSERT, but nothing removed it when
-- the follow was deleted: unfollowing right after following left the
-- followee's inbox showing "X started following you" forever, and a rapid
-- follow → unfollow → re-follow minted a SECOND row for the same
-- relationship (the INSERT trigger fired again) instead of reconciling to
-- one. `notifications` has no FK back to `user_follows`, so there was no
-- cascade to lean on.
--
-- Fix both halves at the source:
--   1. Make the INSERT coalescing — skip the insert when an UNREAD follow
--      notification for this (followee, follower) pair already exists, so
--      re-following while the first is still unread doesn't fan out a dup.
--   2. Add an AFTER DELETE trigger that removes the UNREAD follow
--      notification for the pair, so an unfollow retracts the still-pending
--      "started following you". A follow the user already saw (read) is left
--      alone — it's a truthful record of something that happened.

create or replace function notify_user_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.follower_id = NEW.followee_id then
    return NEW;
  end if;
  -- Coalesce: don't stack a second unread follow notification for the same
  -- pair (rapid re-follow while the first is still unread).
  if exists (
    select 1 from notifications
     where user_id = NEW.followee_id
       and actor_id = NEW.follower_id
       and kind = 'follow'
       and read_at is null
  ) then
    return NEW;
  end if;
  insert into notifications (user_id, actor_id, kind)
    values (NEW.followee_id, NEW.follower_id, 'follow');
  return NEW;
end;
$$;

create or replace function cleanup_user_follow_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from notifications
   where user_id = OLD.followee_id
     and actor_id = OLD.follower_id
     and kind = 'follow'
     and read_at is null;
  return OLD;
end;
$$;

create trigger user_follows_notify_cleanup
  after delete on user_follows
  for each row execute function cleanup_user_follow_notification();
