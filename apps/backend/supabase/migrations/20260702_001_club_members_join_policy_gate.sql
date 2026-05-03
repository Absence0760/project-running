-- Tighten the `club_members` INSERT policy so direct self-INSERTs honour
-- `clubs.join_policy`. Closes the audit/rls High finding from /audit/all
-- on 2026-05-03: the policy added in 20260416_001_clubs_and_events.sql
-- only checked `auth.uid() = user_id`, ignoring `join_policy` (added in
-- 20260417_001_phase2_social.sql) and `status`. An authenticated user
-- could direct-INSERT `(club_id, user_id, role='member', status='active')`
-- for any club — including invite-only and request-only ones — and
-- immediately gain SELECT on private clubs, their members roster,
-- posts, events, club-owned routes, and plan templates.
--
-- The replacement splits the single open policy into two narrower ones:
--
--   1. open-policy clubs   — self-INSERT with status='active' allowed
--      (matches the v1 behaviour the original policy was meant to
--      capture). Role pinned to 'member' so a self-joiner can't claim
--      'admin' / 'owner' / 'race_director' / 'event_organiser'.
--
--   2. request-policy clubs — self-INSERT with status='pending' allowed
--      so the user can register interest. Admin still needs to call
--      `approveMember` to flip status to 'active' (gated by the
--      pre-existing "admins can change roles" UPDATE policy).
--
-- Invite-policy clubs are deliberately not covered: they accept new
-- members only through `join_club_by_token`, which is SECURITY DEFINER
-- and bypasses RLS. Direct INSERT against an invite club is now
-- rejected by the row-level filter — exactly the gap this migration
-- closes.
--
-- The legacy "users can leave clubs" / "members readable with their
-- club" / admin DELETE / admin UPDATE policies are untouched.

drop policy if exists "authenticated users can join clubs" on club_members;

create policy "self-join open clubs"
  on club_members for insert
  with check (
    auth.uid() = user_id
    and role = 'member'
    and status = 'active'
    and exists (
      select 1 from clubs
      where clubs.id = club_members.club_id
        and clubs.join_policy = 'open'
    )
  );

create policy "self-request join request-policy clubs"
  on club_members for insert
  with check (
    auth.uid() = user_id
    and role = 'member'
    and status = 'pending'
    and exists (
      select 1 from clubs
      where clubs.id = club_members.club_id
        and clubs.join_policy = 'request'
    )
  );
