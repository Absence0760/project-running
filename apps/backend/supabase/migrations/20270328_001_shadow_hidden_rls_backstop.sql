-- Shadow-hidden RLS backstop for clubs + events.
--
-- `shadow_hidden` (auto-hide, 20270218_001) must drop a target from every
-- PUBLIC / SEARCH / DISCOVERY surface. That was enforced per-consumer — the
-- public_* views + the is_public_{club,event,route}_by_id definers all filter
-- it — but the BASE-TABLE SELECT policies for clubs + events gated only on
-- `is_public`. So any direct anon/authenticated read (e.g. the /share/*
-- SEO surfaces) saw shadow-hidden rows unless the caller remembered to add
-- the filter by hand — which is fragile and had already leaked once.
--
-- This makes the exclusion the RLS-enforced DEFAULT: a new anon read path
-- against clubs/events can no longer silently re-expose a moderator-hidden
-- row. It is a backstop UNDER the per-query filters those surfaces already
-- carry, not a replacement (layered defense).
--
-- Owner + admins/members still see their own hidden row (a soft-hide pending
-- review, not a deletion — 20270218_001): the member/owner policy is
-- broadened to cover their club regardless of is_public / shadow_hidden.
--
-- Admin moderation review is unaffected: it runs entirely through SECURITY
-- DEFINER RPCs (fetch_reports_for_target / admin_unhide_target), which bypass
-- RLS — there is no admin-read RLS policy anywhere, so none is added here.

-- ── clubs ──
drop policy "public clubs are readable by anyone" on clubs;
create policy "public clubs are readable by anyone"
  on clubs for select
  using (is_public = true and shadow_hidden = false);

-- Was: "(is_public = false) AND (owner OR member)". Drop the is_public=false
-- gate so an owner / active member keeps visibility of their own club even
-- when it is public-and-shadow-hidden (or private). Anon/non-members fall
-- through to the public policy above and so never see a hidden club.
drop policy "private clubs are readable by members" on clubs;
create policy "members and owners read their own club"
  on clubs for select
  using (owner_id = auth.uid() or private.is_club_member(id));

-- ── events ──
-- Preserve the event-level visibility contract (20270113_001): an event is
-- readable when the parent club is visible to the viewer AND (the event is
-- public OR the viewer is a club member). Only the club-public branch gains
-- the shadow_hidden exclusion, so anon no longer sees a hidden club's events
-- while its owner/members still do.
drop policy "events readable with their club" on events;
create policy "events readable with their club"
  on events for select
  using (
    exists (
      select 1 from clubs
      where clubs.id = events.club_id
        and (
          (clubs.is_public = true and clubs.shadow_hidden = false)
          or clubs.owner_id = auth.uid()
          or private.is_club_member(clubs.id)
        )
    )
    and (is_public = true or private.is_club_member(club_id))
  );
