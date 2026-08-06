-- Length caps on the club + profile identity text the two tab-host screens
-- render (issue #666 C12 remainder, decisions § 545).
--
-- `20261124_001_content_length_caps.sql` capped `club_posts.body` and
-- `events.description` in one "free-text user content" pass and skipped the
-- club's own name / description / location and `user_profiles.display_name`.
-- Those four are the hero band of `club_detail` and `profile` on every client,
-- so an unbounded value is a layout input, not merely a storage question — and
-- a direct API write bypasses whatever the composer allows.
--
-- The caps are the numbers the clients already state, so nothing a composer can
-- produce is rejected:
--   clubs.name              80    both composers already cap at 80
--   clubs.description     2000    the sibling standard (events.description,
--                                 challenges.description); web's composer said
--                                 600 and mobile's 500, and both now say 2000
--   clubs.location_label    80    both composers already cap at 80
--   user_profiles.display_name 60 both setup wizards already cap at 60; the two
--                                 settings screens capped at nothing
--
-- One source of truth per client: `apps/web/src/lib/core/text_limits.ts` and
-- `apps/mobile_android/lib/text_limits.dart` carry these same four numbers and
-- `text_limits_test` on each side parses THIS FILE to prove they match, so a
-- client cap and the constraint cannot drift into a 23514 the user cannot see.
--
-- `clubs` and `user_profiles` are small bounded tables, so per
-- docs/backend/migration_locks.md the online form here is ceremony rather than
-- safety — but the ceremony is cheap and the VALIDATE is what § 537's
-- predecessor migration never emitted, leaving its rows permanently unchecked.
-- Detection query to run before applying to a populated instance:
--
--   select count(*) from clubs where char_length(name) > 80
--      or char_length(coalesce(description, '')) > 2000
--      or char_length(coalesce(location_label, '')) > 80;
--   select count(*) from user_profiles where char_length(display_name) > 60;
--
-- Both must be 0, or the VALIDATE below fails and the offending rows need
-- truncating first.

alter table clubs
  add constraint clubs_name_len_chk
  check (char_length(name) <= 80) not valid;

alter table clubs
  add constraint clubs_description_len_chk
  check (description is null or char_length(description) <= 2000) not valid;

alter table clubs
  add constraint clubs_location_label_len_chk
  check (location_label is null or char_length(location_label) <= 80)
  not valid;

alter table user_profiles
  add constraint user_profiles_display_name_len_chk
  check (display_name is null or char_length(display_name) <= 60) not valid;

alter table clubs validate constraint clubs_name_len_chk;
alter table clubs validate constraint clubs_description_len_chk;
alter table clubs validate constraint clubs_location_label_len_chk;
alter table user_profiles validate constraint user_profiles_display_name_len_chk;
