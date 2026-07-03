-- Public-rows audit High ×2: close the column wire-leak on the Phase-4
-- multi-modal tables `gym_workouts` and `food_log`
-- (audit-public-rows.md 2026-07-02; source table
-- 20261204_001_phase4_multimodal_foundation.sql).
--
-- Both tables shipped (2026-12-04) with the naive "owner or public read"
-- SELECT policy
--
--     using (user_id = auth.uid() or is_public)
--
-- and never went through the redaction hardening `runs` got in
-- 20260626_001 / 20260701_001. The `or is_public` branch opens the WHOLE
-- row to any reader, so
--
--     GET /rest/v1/gym_workouts?is_public=eq.true&select=*
--     GET /rest/v1/food_log?is_public=eq.true&select=*
--
-- leak, alongside the intended headline fields:
--
--   * external_id      — the per-user import/dedup crosswalk. Same class of
--                        leak that got `external_id` excluded from
--                        `public_runs` (20260626_001): one match links a
--                        public-share row to the runner's account/import
--                        source permanently.
--   * last_modified_at — the offline-sync clock. Classified owner-only for
--                        `runs` (leaks device-upload cadence); same here.
--   * notes            — gym_workouts free text (≤1000 chars). Never
--                        classified public-safe (audit Medium). This
--                        migration makes the explicit call: notes is
--                        OWNER-ONLY — it does NOT pass through the public
--                        projection. (docs/backend/api_database.md records
--                        the classification.)
--   * metadata         — gym_workouts jsonb bag (20270101_001): plan-link /
--                        planned-vs-actual internal state. Owner-only.
--
-- gym_workouts.is_public is live (GymEditor.svelte ships the toggle), so
-- real prod rows leak today. food_log has no UI toggle yet but a direct
-- REST PATCH `{is_public:true}` on an owned row (the owner-UPDATE policy has
-- no column guard) makes it exploitable all the same.
--
-- ── Why the redacted-VIEW pattern, not a column-grant lockdown ──
--
-- The column-grant shape (revoke SELECT + grant only safe columns — used on
-- clubs / events / user_profiles) is a NON-STARTER here: the OWNER read
-- paths use `select('*')` (data.ts `fetchGymWorkoutsWithError`,
-- `fetchGymWorkoutWithSets`, and the mobile twins). A column revoke is
-- role-wide, not row-scoped, so it would 42501 the owner's own reads — the
-- exact regression that got the clubs/events column lockdown reverted in
-- 20260817_001. So we mirror `public_runs` instead: the base table becomes
-- owner-only, and non-owner public reads go through a redacted view that
-- projects only the safe columns. Owner `select('*')` keeps working via the
-- `user_id = auth.uid()` branch; the leak is closed fail-closed.
--
-- The views are NOT `security_invoker` (default = run with the view owner's
-- rights), same rationale as `public_runs`: the view is the ONLY public read
-- path and pre-applies the redaction via `where is_public = true`. A
-- security_invoker view would re-apply the (now owner-only) base RLS on top
-- and serve nothing.
--
-- COMPANION CLIENT SWITCH (apply-pending, outside this migration's scope):
-- the one non-owner base-table reader — data.ts `fetchFollowingLifts`
-- (`from('gym_workouts').eq('is_public', true).select('id, user_id,
-- started_at, title, set_count, volume_kg')`) — must switch to
-- `from('public_gym_workouts')`, else the following-lift feed goes empty for
-- non-owners once the public branch is dropped. Its selected columns are all
-- in the view, so it is a one-line `.from()` change. No public food_log
-- reader exists today.
--
-- gym_sets is left as-is: its "visible via parent workout" policy delegates
-- to `w.user_id = auth.uid() or w.is_public`, and with the parent's public
-- branch gone the `or w.is_public` arm is now unreachable for a non-owner
-- (gym_workouts RLS hides public rows from them). Effect: gym_sets is
-- owner-only-effective = fail-closed. There is no non-owner consumer of a
-- public workout's per-set rows today (the feed reads only the headline
-- set_count / volume_kg columns). If a public gym-detail surface is ever
-- built, add a `public_gym_sets` view + a SECURITY DEFINER visibility helper
-- (mirroring is_run_visible_to) rather than re-opening the parent branch.

-- ─────────────── gym_workouts: owner-only base + redacted view ───────────────

drop policy "gym_workouts owner or public read" on public.gym_workouts;

create policy "gym_workouts owner read"
  on public.gym_workouts for select
  using (user_id = auth.uid());

create or replace view public.public_gym_workouts as
select
  w.id,
  w.user_id,
  w.started_at,
  w.title,
  w.duration_s,
  w.is_public,
  w.set_count,
  w.volume_kg,
  w.created_at
from public.gym_workouts w
where w.is_public = true;

grant select on public.public_gym_workouts to anon, authenticated;

-- ─────────────── food_log: owner-only base + redacted view ───────────────

drop policy "food_log owner or public read" on public.food_log;

create policy "food_log owner read"
  on public.food_log for select
  using (user_id = auth.uid());

create or replace view public.public_food_log as
select
  f.id,
  f.user_id,
  f.started_at,
  f.item_name,
  f.meal_slot,
  f.calories,
  f.protein_g,
  f.carbs_g,
  f.fat_g,
  f.is_public,
  f.created_at
from public.food_log f
where f.is_public = true;

grant select on public.public_food_log to anon, authenticated;
