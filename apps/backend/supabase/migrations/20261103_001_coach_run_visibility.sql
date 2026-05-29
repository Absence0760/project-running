-- Consent-gated coach run visibility (persona #47).
--
-- Background: after 20260701_001 the `runs` base table has no public
-- SELECT policy -- non-owners read public runs only through the
-- column-redacted `public_runs` view, and the SECURITY DEFINER helper
-- `is_run_visible_to(run_id, user_id)` (now `private.is_run_visible_to`
-- after 20260812_001) decides "owner OR public" for the five sibling
-- social tables (run_kudos, run_comments, run_photos, segment_efforts,
-- live_run_pings) plus the run-photo Storage bytes.
--
-- 20261102_001 added the coach-athlete link model: an athlete redeems a
-- coach's invite token, which forms a `status = 'active'` row in
-- coach_athletes. That redemption IS the consent -- the athlete chose to
-- share their training with this specific coach. This migration spends
-- that consent: an active coach can read their athletes' runs (public
-- AND private) and the social rows hanging off them.
--
-- Two changes, both additive (OR'd into existing permissive policies):
--   1. `private.is_active_coach_of(coach, athlete)` -- a definer helper
--      mirroring the club-membership EXISTS inside is_route_visible_to.
--      Used by both the new runs SELECT policy (caller context) and the
--      extended is_run_visible_to (so it doesn't lean on coach_athletes
--      RLS from inside the runs policy).
--   2. A `runs` SELECT policy + the coach branch in is_run_visible_to.
--
-- What this deliberately does NOT do:
--   - The raw GPS track stays owner-only. The `runs` Storage bucket
--     SELECT policy (20260410_001) is unchanged, so a coach reads the
--     run row + stats but not the track bytes. Non-owner track access
--     runs through clip_track_for_user (privacy zones, decisions §33);
--     a coach track tier is a separate privacy decision + Edge Function
--     change, left for a follow-up rather than silently bypassing the
--     privacy-zone clip here.
--   - Letting the coach read social rows on private runs also lets the
--     coach kudos/comment on them (the INSERT policies gate on the same
--     is_run_visible_to). That is intended -- coach feedback on an
--     athlete's run is the point -- and falls out of the helper.
--
-- Ending the link (status -> 'ended', either party) revokes everything
-- immediately: the helper only matches 'active'.

create or replace function private.is_active_coach_of(p_coach_id uuid, p_athlete_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from coach_athletes ca
    where ca.coach_id = p_coach_id
      and ca.athlete_id = p_athlete_id
      and ca.status = 'active'
  );
$$;

grant usage on schema private to anon, authenticated, service_role;
revoke execute on function private.is_active_coach_of(uuid, uuid) from public;
grant execute on function private.is_active_coach_of(uuid, uuid)
  to anon, authenticated, service_role;

-- Recreate is_run_visible_to with the complete 20260812_001 body PLUS
-- the coach branch. Bare-body create-or-replace strips any prior fix,
-- so this is the full live definition, not a partial patch.
create or replace function private.is_run_visible_to(p_run_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from runs r
    where r.id = p_run_id
      and (
        r.user_id = p_user_id
        or r.is_public = true
        or private.is_active_coach_of(p_user_id, r.user_id)
      )
  );
$$;

-- An active coach can read their athletes' run rows directly (the
-- `public_runs` view is is-public-only, so private runs are reachable
-- only through this base-table policy). Additive to "users own their
-- runs" (FOR ALL) from 20260405_001 -- SELECT permissive policies OR.
-- SELECT only: a coach never gains write access to an athlete's runs.
create policy "active coach reads athlete runs"
  on runs for select
  using (private.is_active_coach_of(auth.uid(), user_id));
