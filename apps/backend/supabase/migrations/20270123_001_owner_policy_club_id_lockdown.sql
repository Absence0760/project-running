-- Owner-policy club_id lockdown — closes a content-injection hole on
-- routes / training_plans / session_plans.
--
-- Each table carries a permissive owner "FOR ALL" policy keyed only on
-- the row's own user/author id:
--   routes:         "users own their routes"          (20260405_001)
--   training_plans: "users own their plans"           (20260419_001)
--   session_plans:  "authors own their session plans" (20270103_001)
-- None constrained club_id. Postgres ORs permissive policies, so the
-- dedicated club-admin write policies (20260520_001 / 20260524_001 /
-- 20260614_001 / 20270103_001) — which DO gate on is_club_admin(club_id)
-- — could be bypassed: a normal INSERT/UPDATE that set user_id/author_id
-- = self and club_id = <any club> satisfied the unconstrained owner
-- policy and landed an attacker-authored row that the victim club's
-- members then read via the "club members read" SELECT policies. The
-- 20270109_001 header explicitly noted this for the session-planner
-- client publish ("lets a non-member author set an arbitrary club_id").
--
-- Fix: add a WITH CHECK to each owner policy that permits a non-null
-- club_id ONLY when the writer administers that club — i.e. fold the
-- club-admin gate into the owner path so the OR'd evaluation can't route
-- around it. Personal rows (club_id is null) are unaffected, and the
-- legitimate admin flows that set club_id via a direct write keep
-- working:
--   * setRouteClubId — transfer a personal route into a club you admin
--   * publishPlanAsTemplate — INSERT a club template (is_template = true)
--   * createSessionPlan with club_id — author a club-owned session plan
-- The USING clause stays user_id/author_id = self so an owner still
-- reads / updates / deletes their own club-owned rows; cross-member
-- admin writes continue through the separate club-admin policies.
--
-- All three use the private.is_club_admin oracle (the membership oracles
-- were moved to the private schema in 20261120_001; existing club policies
-- still resolve it by OID, but a NEW policy must qualify the name since
-- there is no public.is_club_admin to find on the search path). It is
-- granted to authenticated, so it is callable inside a policy expression.
-- club_id is null short-circuits the OR so the oracle is only called for a
-- club-bound write.

-- ───────────────────────── routes ─────────────────────────
drop policy if exists "users own their routes" on routes;
create policy "users own their routes"
  on routes for all
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (club_id is null or private.is_club_admin(club_id))
  );

-- ───────────────────────── training_plans ─────────────────────────
-- A club-owned training plan is always a template (the club read/write
-- policies gate on is_template = true), so mirror that on the club branch.
drop policy if exists "users own their plans" on training_plans;
create policy "users own their plans"
  on training_plans for all
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (club_id is null or (is_template = true and private.is_club_admin(club_id)))
  );

-- ───────────────────────── session_plans ─────────────────────────
drop policy if exists "authors own their session plans" on session_plans;
create policy "authors own their session plans"
  on session_plans for all
  using (auth.uid() = author_id)
  with check (
    auth.uid() = author_id
    and (club_id is null or private.is_club_admin(club_id))
  );
