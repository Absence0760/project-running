-- public_gym_sets — the anon-readable per-set projection of a PUBLIC gym
-- workout, closing the gap 20270313_001 left open.
--
-- That migration dropped gym_workouts' public-read RLS branch and asserted
-- "there is no non-owner consumer of a public workout's per-set rows today" —
-- but the /share/workout/[id] page (share_workout_lookup.ts) was exactly that
-- consumer: with the parent branch gone, the gym_sets "visible via parent
-- workout" policy became owner-only-effective, the anon sets read returned
-- empty, and (with the headline read also still on the base table) every
-- public workout share page rendered "Workout not found" (CI run
-- 28707481878, share/workout.spec.ts). This is the `public_gym_sets` view
-- that migration prescribed for the day a public per-set surface existed.
--
-- Same shape as public_gym_workouts: owner-rights view (NOT
-- security_invoker — the base RLS is owner-only, so an invoker view would
-- serve nothing), the `is_public = true` predicate baked into the join, and
-- only the safe columns projected: rpe (subjective effort the owner never
-- chose to publish) stays base-table-only.

create view public.public_gym_sets as
select
  s.id,
  s.workout_id,
  s.set_index,
  s.exercise_name,
  s.reps,
  s.weight_kg,
  s.duration_s
from public.gym_sets s
join public.gym_workouts w on w.id = s.workout_id
where w.is_public = true;

-- Mandatory view privilege reset (20270324_001 / view_write_privileges_test):
-- default privileges would otherwise leave the view writable by anon.
revoke all on public.public_gym_sets from public, anon, authenticated;
grant select on public.public_gym_sets to anon, authenticated;
