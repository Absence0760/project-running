-- Defence-in-depth: tighten `plan_workouts` SELECT to the same
-- owner-or-club-member predicate `plan_weeks` got in `20260708_001`.
--
-- Audit pass 2 finding: the original SELECT policy from
-- `20260613_001_rls_hardening.sql:89-97` checks only that an `EXISTS`
-- join through `plan_weeks → training_plans` returns a row, with no
-- explicit owner / membership predicate. The fix in `20260708_001`
-- tightened `plan_weeks` so that the join chain is now safe in
-- practice — but `plan_workouts` should not depend on a sibling
-- table's RLS standing firm. A future loosening of `plan_weeks`
-- would silently re-open the workout enumeration surface.
--
-- This migration restates the predicate at the `plan_workouts` layer
-- so the policy is independently safe.

drop policy if exists "users read plan workouts they can see the plan for"
  on plan_workouts;

create policy "users read plan workouts they can see the plan for"
  on plan_workouts for select
  using (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
        and (
          p.user_id = auth.uid()
          or (
            p.club_id is not null
            and is_club_member(p.club_id)
          )
        )
    )
  );
