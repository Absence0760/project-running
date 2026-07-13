-- Add a 'paused' status to training_plans so a runner can pause a plan and
-- resume it later — a first-class, reversible primitive distinct from
-- complete / abandon (persona runner-woman, decisions §231).
--
-- The training_plans_one_active partial unique index is `where status =
-- 'active'`, so pausing a plan frees the active slot (no conflict), and
-- resuming flips it back to 'active' — re-entering the one-active constraint,
-- which the resume path checks for so a second active plan can't slip in.
--
-- `status` is a bare text column (no Dart enum, generated TS type stays
-- `string`), so adding a value to the CHECK needs no type regeneration; the
-- hand-maintained PlanStatus TS union in apps/web/src/lib/types.ts is updated
-- alongside this migration.

alter table training_plans
  drop constraint training_plans_status_check;

alter table training_plans
  add constraint training_plans_status_check
  check (status in ('active', 'completed', 'abandoned', 'paused'));
