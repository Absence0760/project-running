-- Athlete notification when a coach assigns them a plan (decisions §143 follow-up).
--
-- assign_plan_to_athlete (20270106_001) inserts an athlete-owned training_plans
-- row with assigned_by_coach_id set, but the plan appeared silently. This adds a
-- 'plan_assigned' notification kind + an AFTER INSERT trigger that notifies the
-- athlete, mirroring the 'plan_update' coach-edit notification (20261024_001).
-- Distinct kind from 'plan_update' because the message differs ("assigned you a
-- plan" vs "updated your plan"); reuses the existing notifications.plan_id link.
--
-- In-app only: a new kind does not enqueue email/web-push unless added to those
-- channels' allowlists, so this stays a bell notification by default.

-- Widen the kind allowlist. Full re-statement at the chain end (the pattern the
-- consolidate migration 20261211_001 documents); do not edit that file.
alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned'
    )
  );

create or replace function notify_plan_assigned()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only assigned plans (a coach gave this to the athlete); self-assign is
  -- already blocked upstream, but skip it defensively like the kudos trigger.
  if new.assigned_by_coach_id is null or new.assigned_by_coach_id = new.user_id then
    return new;
  end if;
  insert into notifications (user_id, actor_id, kind, plan_id)
    values (new.user_id, new.assigned_by_coach_id, 'plan_assigned', new.id);
  return new;
end;
$$;

create trigger trg_notify_plan_assigned
  after insert on training_plans
  for each row execute function notify_plan_assigned();
