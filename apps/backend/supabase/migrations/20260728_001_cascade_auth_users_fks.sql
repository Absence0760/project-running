-- Add ON DELETE CASCADE to every public-schema FK that references
-- auth.users. Eight tables hold a `references auth.users` without
-- `on delete cascade`:
--   routes.user_id, runs.user_id, integrations.user_id,
--   user_profiles.id, route_reviews.user_id, clubs.owner_id,
--   events.created_by, club_posts.author_id
--
-- Net effect today: the `delete-account` Edge Function calls
-- `auth.admin.deleteUser(user.id)` after draining Storage. The admin
-- API issues a hard DELETE on auth.users, which raises a 23503 FK
-- violation against any of the eight tables above for any user that
-- has even a single row in them — and every authenticated user has a
-- user_profiles row by virtue of fetchUser's upsert-on-first-sign-in.
-- So `delete-account` 500s in production for **every** user, denying
-- the GDPR / CCPA right-to-erasure that the EF exists to satisfy.
--
-- Fix: re-create each FK with `on delete cascade`. The semantic is:
-- when a user deletes their own account, every row they own (runs,
-- routes, integrations, profile, reviews, clubs they own, events
-- they created, posts they authored) goes with them. Mirrors the
-- saga-users.ts OWNER_TABLES sweep — that helper was the workaround,
-- this migration is the fix.
--
-- Cascade chain after this migration:
--   auth.users delete →
--     runs (CASCADE) → run_kudos (already CASCADE) +
--                      run_comments (already CASCADE) +
--                      run_photos (already CASCADE) +
--                      segment_efforts (already CASCADE) +
--                      run_matched_tracks (already CASCADE) +
--                      live_run_pings (already CASCADE) +
--                      notifications (already CASCADE)
--     routes (CASCADE) → route_reviews (CASCADE here) +
--                        route_tags (already CASCADE) +
--                        runs.route_id (already SET NULL)
--     clubs (CASCADE)  → club_members (already CASCADE) +
--                        club_posts (already CASCADE) +
--                        events (already CASCADE) +
--                        ... (all club-scoped tables)
--     user_profiles (CASCADE)
--     user_settings (already CASCADE)
--     ... (every other table that already cascades)
--
-- The discovery path: e2e saga `account-deletion.spec.ts` planted an
-- ephemeral user, planted a run, drove the /settings/account UI flow,
-- and the EF returned 500 with `{"error":"delete failed"}`. The
-- saga-users.ts fixture had been masking this by sweeping the eight
-- tables explicitly before its own teardown — but real users don't
-- have that fixture; they have the EF.
--
-- Discovery path (matches the rate-limit + paywall-bypass discoveries
-- earlier this month — same anti-pattern of "looks-correct, never
-- verified end-to-end"). The privacy audit caught Storage-drain
-- regression; this catches the FK regression.

alter table runs
  drop constraint runs_user_id_fkey,
  add constraint runs_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade;

alter table routes
  drop constraint routes_user_id_fkey,
  add constraint routes_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade;

alter table integrations
  drop constraint integrations_user_id_fkey,
  add constraint integrations_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade;

alter table user_profiles
  drop constraint user_profiles_id_fkey,
  add constraint user_profiles_id_fkey
    foreign key (id) references auth.users (id) on delete cascade;

alter table route_reviews
  drop constraint route_reviews_user_id_fkey,
  add constraint route_reviews_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade;

alter table clubs
  drop constraint clubs_owner_id_fkey,
  add constraint clubs_owner_id_fkey
    foreign key (owner_id) references auth.users (id) on delete cascade;

alter table events
  drop constraint events_created_by_fkey,
  add constraint events_created_by_fkey
    foreign key (created_by) references auth.users (id) on delete cascade;

alter table club_posts
  drop constraint club_posts_author_id_fkey,
  add constraint club_posts_author_id_fkey
    foreign key (author_id) references auth.users (id) on delete cascade;
