-- RLS hardening — closes two High-severity findings from the
-- /audit/rls sweep:
--
-- 1. plan_weeks / plan_workouts: 20260524_001 relaxed both tables'
--    `for all using (...)` policies to a plain EXISTS against
--    training_plans. The intent was "members can SELECT club
--    templates"; the side effect is "members can INSERT / UPDATE /
--    DELETE the workouts of any club template they can see." The
--    write authority on training_plans (gated to is_club_admin or
--    user_id = auth.uid()) did not flow to the children. Split the
--    `for all` into a relaxed SELECT and a tightened
--    INSERT/UPDATE/DELETE that re-asserts the parent's write rule.
--
-- 2. event_results_insert_self: 20260424_001 gates INSERT only on
--    `auth.uid() = user_id`, with no check that the event exists or
--    is visible to the caller. An authenticated user with a guessed
--    event_id can plant a self-attributed result on any event,
--    including private clubs they cannot read. Mirror the SELECT
--    policy's event-visibility test in the INSERT WITH CHECK so the
--    caller must be able to see the event before they can write to
--    its leaderboard.

-- ─────────────────── plan_weeks ───────────────────

drop policy if exists "users own their plan weeks" on plan_weeks;

create policy "users read plan weeks they can see the plan for"
  on plan_weeks for select
  using (
    exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id
    )
  );

create policy "users write plan weeks of plans they own or admin"
  on plan_weeks for insert
  with check (
    exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id
        and (
          p.user_id = auth.uid()
          or (p.club_id is not null and is_club_admin(p.club_id))
        )
    )
  );

create policy "users update plan weeks of plans they own or admin"
  on plan_weeks for update
  using (
    exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id
        and (
          p.user_id = auth.uid()
          or (p.club_id is not null and is_club_admin(p.club_id))
        )
    )
  )
  with check (
    exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id
        and (
          p.user_id = auth.uid()
          or (p.club_id is not null and is_club_admin(p.club_id))
        )
    )
  );

create policy "users delete plan weeks of plans they own or admin"
  on plan_weeks for delete
  using (
    exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id
        and (
          p.user_id = auth.uid()
          or (p.club_id is not null and is_club_admin(p.club_id))
        )
    )
  );

-- ─────────────────── plan_workouts ───────────────────

drop policy if exists "users own their plan workouts" on plan_workouts;

create policy "users read plan workouts they can see the plan for"
  on plan_workouts for select
  using (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
    )
  );

create policy "users write plan workouts of plans they own or admin"
  on plan_workouts for insert
  with check (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
        and (
          p.user_id = auth.uid()
          or (p.club_id is not null and is_club_admin(p.club_id))
        )
    )
  );

create policy "users update plan workouts of plans they own or admin"
  on plan_workouts for update
  using (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
        and (
          p.user_id = auth.uid()
          or (p.club_id is not null and is_club_admin(p.club_id))
        )
    )
  )
  with check (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
        and (
          p.user_id = auth.uid()
          or (p.club_id is not null and is_club_admin(p.club_id))
        )
    )
  );

create policy "users delete plan workouts of plans they own or admin"
  on plan_workouts for delete
  using (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
        and (
          p.user_id = auth.uid()
          or (p.club_id is not null and is_club_admin(p.club_id))
        )
    )
  );

-- ─────────────────── event_results ───────────────────

drop policy if exists event_results_insert_self on event_results;

create policy event_results_insert_self
  on event_results for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from events e
      left join clubs c on c.id = e.club_id
      where e.id = event_results.event_id
        and (
          c.id is null
          or c.is_public = true
          or c.owner_id = auth.uid()
          or is_club_member(c.id)
        )
    )
  );
