-- Training-plan hardening: DB-level guardrails on fields the v1 migration
-- left as bare text, plus a uniqueness constraint that would have caught
-- the "null kind" regression earlier.
--
-- Why not phase 1: these constraints weren't needed to ship the surface,
-- but they close the blast radius if a client-side bug sends us a bad
-- status string or duplicates a date. Adding them now is safer than
-- discovering a corrupted active-plan query in production.

alter table training_plans
  add constraint training_plans_status_check
  check (status in ('active', 'completed', 'abandoned'));

alter table training_plans
  add constraint training_plans_source_check
  check (source in ('generated', 'imported', 'manual'));

-- Exactly one workout per date per week. Generator already guarantees this;
-- the constraint makes the invariant authoritative and catches any future
-- regression at write time.
alter table plan_workouts
  add constraint plan_workouts_one_per_day
  unique (week_id, scheduled_date);

-- A workout's pace-progression end must be no slower than its start — we
-- use start = slower end, end = faster end by convention. Null-tolerant.
alter table plan_workouts
  add constraint plan_workouts_pace_progression_ordered
  check (
    target_pace_end_sec_per_km is null
    or target_pace_sec_per_km is null
    or target_pace_end_sec_per_km <= target_pace_sec_per_km
  );

-- Day-count bounds: already enforced in the v1 migration via check on
-- training_plans.days_per_week. Idempotent safety here.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'training_plans_days_per_week_check'
  ) then
    alter table training_plans
      add constraint training_plans_days_per_week_check
      check (days_per_week between 3 and 7);
  end if;
end $$;
