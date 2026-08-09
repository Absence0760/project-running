-- Narrow the client's UPDATE surface on `achievements` to the one column the
-- product actually lets an owner change.
--
-- Awards are written only by `award_achievements_for_user` (SECURITY DEFINER,
-- execute revoked from anon/authenticated in 20270424_001). The single
-- legitimate client write is the owner's visibility toggle — `setBadgeVisibility`
-- in apps/web/src/lib/core/data.ts sets `is_public` and nothing else, and
-- 20270208_001's policy comment says so ("Owner-only UPDATE for the is_public
-- toggle").
--
-- The policy only pins ownership, though, and 20270408_001's grant matrix hands
-- table-wide UPDATE to anon + authenticated. So the owner of any award — every
-- account earns a bronze one automatically — can rewrite the award itself:
--
--   PATCH /rest/v1/achievements?id=eq.<own bronze row>
--   {"badge_key":"distance","tier":"platinum","value_num":1000000,
--    "earned_at":"2024-01-01T00:00:00Z"}
--
-- and the forged badge then renders on their profile, in every follower's badge
-- feed, and on the logged-out /share/badge page. `achievements_user_badge_uk`
-- does not stop it: the row is being renamed, not duplicated.
--
-- Fix at the privilege layer, the same idiom already used for coach_messages,
-- challenge_participants and event_attendees: the ownership policy stays the
-- row gate, the column grant becomes the column gate.

revoke update on public.achievements from anon, authenticated;
grant update (is_public) on public.achievements to authenticated;
