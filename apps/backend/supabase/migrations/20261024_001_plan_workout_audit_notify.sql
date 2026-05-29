-- Plan-edit audit columns + athlete notification (coach persona #48).
--
-- `updatePlanWorkout` was silent: nothing recorded who last changed a
-- workout or when, and an athlete got no signal if someone other than
-- them edited their plan. This adds:
--
--   1. plan_workouts.updated_by + updated_at — stamped on every UPDATE
--      by a BEFORE trigger from auth.uid() / now().
--   2. notifications.plan_id + a 'plan_update' notification kind.
--   3. An AFTER UPDATE trigger that notifies the plan owner when the
--      editor is someone OTHER than the owner. That cross-user edit path
--      lands with the coach-athlete roster (persona #46); until then the
--      trigger is dormant because RLS only lets the owner update their
--      own plan_workouts. The audit columns are useful immediately.

alter table plan_workouts
  add column updated_by uuid references auth.users(id) on delete set null,
  add column updated_at timestamptz;

create or replace function stamp_plan_workout_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_stamp_plan_workout_audit
  before update on plan_workouts
  for each row execute function stamp_plan_workout_audit();

-- Plan-scoped notification link. ON DELETE CASCADE so deleting a plan
-- clears its notifications, matching the run_id / event_id columns.
alter table notifications
  add column plan_id uuid references training_plans(id) on delete cascade;

alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update'
    )
  );

create or replace function notify_plan_workout_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  plan_owner  uuid;
  the_plan_id uuid;
  editor      uuid := auth.uid();
begin
  if editor is null then
    return new;
  end if;
  select tp.user_id, tp.id
    into plan_owner, the_plan_id
  from plan_weeks pw
  join training_plans tp on tp.id = pw.plan_id
  where pw.id = new.week_id;
  -- Only notify when someone other than the owner made the edit.
  if plan_owner is null or plan_owner = editor then
    return new;
  end if;
  insert into notifications (user_id, actor_id, kind, plan_id)
    values (plan_owner, editor, 'plan_update', the_plan_id);
  return new;
end;
$$;

create trigger trg_notify_plan_workout_update
  after update on plan_workouts
  for each row execute function notify_plan_workout_update();
