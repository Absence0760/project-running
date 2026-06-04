-- F15: make notifications.* reference polymorphic ahead of the Phase 4 social
-- expansion (kudos on a lift, comment on a meal).
--
-- Today notifications point at a run via run_id (a hard FK to runs) and the
-- run-specific kinds. The moment a non-run activity becomes feed-shareable
-- there's no way to point a notification at a gym_workouts / food_log row.
-- While there is no prod data, add nullable (activity_kind, activity_id):
--   * activity_kind matches the activities-view modality tag ('run' | 'lift'
--     | 'meal'); CHECK-constrained, nullable for non-activity notifications
--     (follow / message / club_post / plan_update / event_*).
--   * activity_id is a bare uuid — it can't be a single FK because it spans
--     three tables. Referential integrity for the existing run path stays on
--     run_id (kept as the transition bridge, retired when the social-lift work
--     lands and the new triggers populate the polymorphic pair for every
--     activity kind).
-- Backfill every existing run-linked row as ('run', run_id) and have the three
-- run-notification triggers populate the pair going forward.

alter table notifications
  add column activity_kind text
    check (activity_kind is null or activity_kind in ('run', 'lift', 'meal'));
alter table notifications
  add column activity_id uuid;

create index notifications_activity
  on notifications (activity_kind, activity_id)
  where activity_id is not null;

update notifications
  set activity_kind = 'run', activity_id = run_id
  where run_id is not null and activity_id is null;

-- ─────────── triggers: also populate (activity_kind, activity_id) ───────────
-- Full bodies re-emitted (bare-body trap): notify_run_kudos / notify_run_comment
-- are unchanged since 20260528000001; notify_run_completed since 20261101_001.
-- Only the INSERT column lists gain activity_kind/activity_id = ('run', <run>).

create or replace function notify_run_kudos()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  run_owner uuid;
begin
  select user_id into run_owner from runs where id = NEW.run_id;
  if run_owner is null or run_owner = NEW.user_id then
    return NEW;
  end if;
  insert into notifications (user_id, actor_id, kind, run_id, activity_kind, activity_id)
    values (run_owner, NEW.user_id, 'kudos', NEW.run_id, 'run', NEW.run_id);
  return NEW;
end;
$$;

create or replace function notify_run_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  run_owner     uuid;
  parent_author uuid;
begin
  if NEW.parent_comment_id is null then
    select user_id into run_owner from runs where id = NEW.run_id;
    if run_owner is null or run_owner = NEW.author_id then
      return NEW;
    end if;
    insert into notifications (user_id, actor_id, kind, run_id, comment_id, activity_kind, activity_id)
      values (run_owner, NEW.author_id, 'comment', NEW.run_id, NEW.id, 'run', NEW.run_id);
  else
    select author_id into parent_author
      from run_comments where id = NEW.parent_comment_id;
    if parent_author is null or parent_author = NEW.author_id then
      return NEW;
    end if;
    insert into notifications (user_id, actor_id, kind, run_id, comment_id, activity_kind, activity_id)
      values (parent_author, NEW.author_id, 'comment_reply', NEW.run_id, NEW.id, 'run', NEW.run_id);
  end if;
  return NEW;
end;
$$;

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

  insert into notifications (user_id, actor_id, kind, run_id, activity_kind, activity_id)
  select f.follower_id, new.user_id, 'run_completed', new.id, 'run', new.id
  from user_follows f
  where f.followee_id = new.user_id
  on conflict do nothing;

  return new;
end;
$$;
