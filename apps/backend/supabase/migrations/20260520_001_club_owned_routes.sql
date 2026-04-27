-- Club-owned routes + saved-route references.
--
-- Two complementary changes that together make the "club hosts a recurring
-- race" scenario coherent (decisions.md § 30):
--
--   1. routes.club_id (nullable) — when set, the route is club-owned: any
--      club admin can edit it, any club member can read it regardless of
--      is_public, and the course survives the original uploader leaving
--      the role. user_id stays non-null and means "uploader" (audit
--      trail), not authority.
--
--   2. saved_routes — a (user_id, route_id) join table. RouteExplorer's
--      bookmark icon will INSERT a reference here instead of cloning the
--      row, killing the duplicate-route accumulation that the previous
--      "save to library" flow caused. /routes My routes UNIONs personal
--      routes with saved_routes so bookmarks still appear in the user's
--      library view.

-- ─────────────────────── routes.club_id ───────────────────────

alter table routes
  add column club_id uuid references clubs(id) on delete cascade;

create index routes_club_id
  on routes (club_id, created_at desc)
  where club_id is not null;

-- Existing policies keep working unchanged:
--   "users own their routes"          for all using (auth.uid() = user_id)
--   "public routes are readable…"     for select using (is_public = true)
--
-- Two new policies layer on top for club ownership. They use the existing
-- is_club_member / is_club_admin helpers from 20260416_001_clubs_and_events.

create policy "club members read club routes"
  on routes for select
  using (club_id is not null and is_club_member(club_id));

create policy "club admins write club routes"
  on routes for all
  using (club_id is not null and is_club_admin(club_id));

-- ─────────────────────── saved_routes ───────────────────────

create table saved_routes (
  user_id  uuid references auth.users(id) on delete cascade not null,
  route_id uuid references routes(id) on delete cascade not null,
  saved_at timestamptz not null default now(),
  primary key (user_id, route_id)
);

create index saved_routes_user_id on saved_routes (user_id, saved_at desc);
create index saved_routes_route_id on saved_routes (route_id);

alter table saved_routes enable row level security;

-- A user manages their own saves; nothing else is readable. The route
-- row itself is gated by routes RLS (public + own + club-member).
create policy "users manage their own saves"
  on saved_routes for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
