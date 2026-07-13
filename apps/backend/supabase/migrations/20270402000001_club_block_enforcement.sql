-- Enforce user blocks inside shared clubs — roster + post feed.
--
-- Persona-hunt (woman runner, Round run 2026-07-12) Critical finding.
-- Every other social read path carries the symmetric block predicate
-- `is_blocked_either_way` (run_kudos / run_comments / user_follows —
-- 20261012_001 + 20270204_001; direct_messages — 20261026_001; segment
-- leaderboards — 20261115_001; public_profile_by_id — 20270204_001 /
-- 20270307_001). The two club-scoped SELECT surfaces did not: they
-- gated purely on shared club membership, so a blocked harasser who
-- shares any club with the victim stayed fully visible in the club
-- roster (`club_members`) and kept appearing in the club post feed
-- (`club_posts`) — a durable, block-proof channel to see her name /
-- avatar and to keep posting where she reads it. Symmetric: the block
-- hides each party from the other in both directions.
--
-- These re-create the CURRENT authoritative policy bodies (bare-body
-- rule) and ADD ONLY the block guard:
--   * club_members SELECT was split by status in 20260926_001 into
--     "active members readable with their club" (the roster) and
--     "private-club members read pending rows" (active members of a
--     private club seeing pending/rejected rows). Both expose ANOTHER
--     member's row to a fellow member, so both get the guard, keyed on
--     the row's `user_id`.
--   * club_posts SELECT was last re-created in 20270113_001 (with the
--     event-level existence branch). Guarded on the post's `author_id`.
--
-- Deliberately NOT guarded:
--   * "users can see their own membership" (20260417_001) — self row;
--     is_blocked_either_way(uid, uid) is false anyway (the block table
--     has `check (blocker_id <> blocked_id)`), so self is never hidden.
--   * "admins can read pending requests for their club" (20260926_001)
--     — an admin's join-request moderation queue. Hiding a pending
--     requester the admin happens to have blocked would strand the
--     request with nobody able to approve or reject it; block is a
--     social-visibility primitive, not a reason to break moderation.
--
-- Anon callers must stay able to read public-club rosters and posts.
-- `is_blocked_either_way`'s anon EXECUTE grant was deliberately revoked
-- (20261108_001, anti-oracle defence-in-depth), so anon calling it at
-- all raises 42501 — and these policies are reached by anon transitively
-- (the `challenges` SELECT policy sub-queries `club_members`). A block is
-- meaningless without a viewer identity anyway, so each guard is written
-- `auth.uid() is null or not is_blocked_either_way(...)`: for anon the
-- left operand is true and the OR short-circuits, so the function is
-- never invoked (public rosters/posts stay readable, the oracle stays
-- closed); only an authenticated viewer evaluates the block predicate.

-- ── club_members roster ──
drop policy "active members readable with their club" on club_members;
create policy "active members readable with their club"
  on club_members for select using (
    club_members.status = 'active'
    and exists (
      select 1 from clubs
      where clubs.id = club_members.club_id
        and (
          clubs.is_public = true
          or clubs.owner_id = auth.uid()
          or private.is_club_member(clubs.id)
        )
    )
    and (auth.uid() is null or not is_blocked_either_way(auth.uid(), club_members.user_id))
  );

drop policy "private-club members read pending rows" on club_members;
create policy "private-club members read pending rows"
  on club_members for select using (
    club_members.status in ('pending', 'rejected')
    and exists (
      select 1 from clubs c
      where c.id = club_members.club_id
        and c.is_public = false
        and (c.owner_id = auth.uid() or private.is_club_member(c.id))
    )
    and (auth.uid() is null or not is_blocked_either_way(auth.uid(), club_members.user_id))
  );

-- ── club_posts feed ──
drop policy "posts readable with their club" on club_posts;
create policy "posts readable with their club"
  on club_posts for select using (
    exists (
      select 1 from clubs
      where clubs.id = club_posts.club_id
        and (clubs.is_public = true or clubs.owner_id = auth.uid() or private.is_club_member(clubs.id))
    )
    and (
      club_posts.event_id is null
      or exists (select 1 from events e where e.id = club_posts.event_id)
    )
    and (auth.uid() is null or not is_blocked_either_way(auth.uid(), club_posts.author_id))
  );
