-- Social-layer RLS hardening (audit:rls May 2026 round).
--
-- Three independent findings, each pinned with pgtap tests in the
-- companion suite `rls_social_audit_hardening_test.sql`:
--
-- 1. The `reports` table had a direct INSERT policy
--    (`"reporters insert their own reports"`) that let any
--    authenticated caller POST /rest/v1/reports without going
--    through `submit_report`. That bypassed the rate-limit + target-
--    existence checks the RPC enforces. The comment on the original
--    table said all inserts route through the RPC; the policy
--    contradicted the intent. Drop the policy — submit_report is
--    SECURITY DEFINER and bypasses RLS, so the migration doesn't
--    break the supported insert path.
--
-- 2. The `club_members` SELECT policy `"members readable with their
--    club"` returned every row regardless of `status`. For a public
--    club, anon could enumerate pending join requests by querying
--    `?club_id=eq.<id>&status=eq.pending`. Tighten the policy to
--    `status='active'`, then add a sibling `"admins can read
--    pending requests"` policy so club admins keep the visibility
--    they need to approve. A pending requester sees their OWN
--    pending row via the existing `"users can see their own
--    membership"` policy from 20260417, so the requester UX is
--    unchanged.
--
-- 3. `join_club_by_token(text)` and `clone_plan_template(uuid, date)`
--    are SECURITY DEFINER but never had `revoke execute … from
--    public, anon` — the project-wide implicit `grant execute to
--    public` left both anon-callable. Both functions explicitly
--    check `auth.uid() is null` and raise, so no privilege escalation
--    exists today, but the pattern matches the audit-pass-1 fixes
--    landed in 20260711_001 (`is_route_visible_to`) and 20260814_001
--    (`approve_event_result`) — defence-in-depth that means a future
--    edit that drops the inner auth check doesn't silently open an
--    anon mutation path.
--
-- A fourth low-severity finding (an owner can give kudos on their
-- own run, despite the trigger comment claiming RLS prevents it) is
-- also pinned with a CHECK constraint here — keeps the trigger
-- comment honest and prevents the "100 kudos all from yourself"
-- vanity inflation.

-- ─────────────────────────────────────────────────────────────────────
-- 1. reports — drop the direct-INSERT policy.
-- ─────────────────────────────────────────────────────────────────────
drop policy "reporters insert their own reports" on reports;

-- Read policy stays (`"reporters read their own reports"`) so a
-- caller can list their own pending / actioned reports for the
-- moderation-status badge in the UI. submit_report continues to
-- write via service_role (SECURITY DEFINER), which bypasses RLS,
-- so the supported insert path is unaffected.

-- ─────────────────────────────────────────────────────────────────────
-- 2. club_members — split the SELECT policy by status.
-- ─────────────────────────────────────────────────────────────────────
drop policy "members readable with their club" on club_members;

-- Active members are visible to anyone who can SELECT the club
-- (public clubs → anon; private → members + owner). Pending and
-- left/removed rows stay hidden from non-admins.
create policy "active members readable with their club"
  on club_members for select using (
    club_members.status = 'active'
    and exists (
      select 1 from clubs
      where clubs.id = club_members.club_id
        and (
          clubs.is_public = true
          or clubs.owner_id = auth.uid()
          or is_club_member(clubs.id)
        )
    )
  );

-- Private clubs are closed groups — active members can still see
-- pending / rejected rows for their own club. The visibility leak
-- the audit caught was specifically PUBLIC clubs where any anon
-- caller could enumerate `?club_id=eq.<id>&status=eq.pending`. For
-- private clubs, the existing chain (is_club_member check below)
-- already restricts access to the closed roster, so pending
-- visibility there is OK.
create policy "private-club members read pending rows"
  on club_members for select using (
    club_members.status in ('pending', 'rejected')
    and exists (
      select 1 from clubs c
      where c.id = club_members.club_id
        and c.is_public = false
        and (c.owner_id = auth.uid() or is_club_member(c.id))
    )
  );

-- Club admins keep the visibility they need to approve pending
-- requests on PUBLIC clubs (private-club admins are covered by the
-- policy above). The existing `"users can see their own
-- membership"` policy from 20260417 covers a pending requester
-- reading their own row, so the requester UX is unchanged.
create policy "admins can read pending requests for their club"
  on club_members for select using (
    club_members.status in ('pending', 'rejected')
    and is_club_admin(club_members.club_id)
  );

-- ─────────────────────────────────────────────────────────────────────
-- 3. Revoke anon EXECUTE on SECURITY DEFINER mutation RPCs.
-- ─────────────────────────────────────────────────────────────────────
-- Matches the lockdown pattern from 20260711_001 + 20260814_001.
-- Both functions raise on a null auth.uid() internally; the revoke
-- is defence-in-depth against a future edit that drops the inner
-- check.
revoke execute on function join_club_by_token(text) from public, anon;
revoke execute on function clone_plan_template(uuid, date) from public, anon;

-- ─────────────────────────────────────────────────────────────────────
-- 4. run_kudos — prevent self-kudos.
-- ─────────────────────────────────────────────────────────────────────
-- The notify_run_kudos trigger comment from 20260522_001 claimed
-- "skip self-kudos which RLS forbids anyway" — that was wrong.
-- The kudos INSERT policy gates on `is_run_visible_to(run_id,
-- auth.uid())`, which returns true for the run owner, so an owner
-- can self-kudos for vanity inflation. CHECK constraints can't
-- subselect another table to read the run's owner, so the gate
-- is a BEFORE INSERT trigger.
--
-- The trigger short-circuits when there's no authenticated caller
-- (service-role / migration / seed inserts) — the RLS INSERT policy
-- (`auth.uid() = user_id`) already blocks signed-out client inserts,
-- so the only callers that hit a null auth.uid() are trusted setup
-- paths that legitimately need to plant fixtures (the wire-leak
-- regression suite in seed.sql plants a "user kudos their own run"
-- row to verify is_run_visible_to surfaces it on the runner's own
-- detail page).
create or replace function run_kudos_reject_self()
returns trigger
language plpgsql
as $$
declare
  v_role text := coalesce(current_setting('request.jwt.claim.role', true), '');
begin
  -- Service-role bypass — matches the project pattern from
  -- 20260616_001 (rate-limits), 20260709_001 (coach usage), and
  -- 20260718_001 (subscription tier insert guard). Service-role
  -- callers (Edge Functions, migrations, seed setup) are trusted to
  -- plant fixtures + cross-user setup state.
  if v_role = 'service_role' then return NEW; end if;
  -- Defensive null-check on the off chance an RPC fires the trigger
  -- with no auth context. The RLS INSERT policy already blocks
  -- anon client inserts, but a SECURITY DEFINER caller could in
  -- principle reach here with auth.uid() null after a refactor.
  if auth.uid() is null then return NEW; end if;
  if exists (
    select 1 from runs r
    where r.id = NEW.run_id
      and r.user_id = NEW.user_id
  ) then
    raise exception 'self_kudos_not_allowed'
      using errcode = 'check_violation';
  end if;
  return NEW;
end;
$$;

drop trigger if exists run_kudos_reject_self_trigger on run_kudos;
create trigger run_kudos_reject_self_trigger
  before insert on run_kudos
  for each row execute function run_kudos_reject_self();

-- One-shot cleanup of any historical client-inserted self-kudos
-- already in the table — leftover rows would not fire the trigger
-- but would inflate kudos counts. Seed-planted self-kudos (used by
-- the wire-leak regression suite) are re-planted on every db reset
-- so this DELETE is safe to run unconditionally.
delete from run_kudos k
  using runs r
 where r.id = k.run_id
   and r.user_id = k.user_id;
