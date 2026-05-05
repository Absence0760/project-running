-- RLS audit High: `plan_weeks` SELECT policy from `20260613_001_rls_hardening`
-- gates only on `exists (select 1 from training_plans p where p.id = plan_weeks.plan_id)`
-- with no owner / club-membership predicate. Under a SECURITY DEFINER
-- caller (e.g. `clone_plan_template`), the inner subquery runs in the
-- definer's context and bypasses the policies on `training_plans`, making
-- every plan_weeks row reachable regardless of who owns the parent plan.
--
-- Fix: add the same owner-or-club-member predicate the WRITE policies in
-- `20260613_001` use, so the SELECT policy is no longer transitively
-- weaker than the writes.

drop policy if exists "users read plan weeks they can see the plan for"
  on plan_weeks;

create policy "users read plan weeks they can see the plan for"
  on plan_weeks for select
  using (
    exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id
        and (
          p.user_id = auth.uid()
          or (
            p.club_id is not null
            and is_club_member(p.club_id)
          )
        )
    )
  );
