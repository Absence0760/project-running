-- Let an active coach read + edit their athletes' training plans (persona
-- round-5 runner-coach, High). `plan_workouts` / `plan_weeks` /
-- `training_plans` were owner-or-club only, so a coach who reviews an
-- athlete's runs (20261103_001) couldn't see — let alone adjust — the plan
-- they're coaching. The coach-athlete link is the consent: the athlete
-- redeemed the coach's invite (status='active' in coach_athletes), the same
-- consent that 20261103_001 spent to grant run read.
--
-- Additive policies only — RLS OR's permissive policies, so these grant the
-- coach access WITHOUT touching the owner / club policies (no bare-body
-- rewrite, nothing to strip). `private.is_active_coach_of` (20261103_001) is
-- the SECURITY DEFINER helper; an ended link (status != 'active') makes it
-- return false, so access revokes immediately for both parties.
--
-- Scope: READ on all three plan tables; EDIT (UPDATE) on plan_workouts only
-- — a coach adjusts the prescription (target pace / distance / notes) on
-- existing workouts. Adding/deleting workouts and editing plan structure
-- stay owner/club-admin; the coach edits within the athlete's plan shape.
-- Templates are excluded (a coach reads an athlete's *personal* plans).

create policy "coaches read athlete plans"
  on training_plans for select
  using (
    coalesce(is_template, false) = false
    and private.is_active_coach_of(auth.uid(), user_id)
  );

create policy "coaches read athlete plan weeks"
  on plan_weeks for select
  using (
    exists (
      select 1 from training_plans p
      where p.id = plan_weeks.plan_id
        and coalesce(p.is_template, false) = false
        and private.is_active_coach_of(auth.uid(), p.user_id)
    )
  );

create policy "coaches read athlete plan workouts"
  on plan_workouts for select
  using (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
        and coalesce(p.is_template, false) = false
        and private.is_active_coach_of(auth.uid(), p.user_id)
    )
  );

create policy "coaches edit athlete plan workouts"
  on plan_workouts for update
  using (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
        and coalesce(p.is_template, false) = false
        and private.is_active_coach_of(auth.uid(), p.user_id)
    )
  )
  with check (
    exists (
      select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
      where w.id = plan_workouts.week_id
        and coalesce(p.is_template, false) = false
        and private.is_active_coach_of(auth.uid(), p.user_id)
    )
  );
