-- Trigram GIN indexes for every leading-wildcard ILIKE search RPC (db-performance
-- audit, High cluster). A `col ilike '%term%'` predicate can only be served by a
-- pg_trgm GIN index — btree and tsvector GIN indexes cannot match it, so each of
-- these searches currently seq-scans its table (user_profiles unbounded; the
-- others bounded only by their is_public subset). Columns mirror the LIVE
-- function bodies exactly:
--   search_user_profiles (20270218_001)   -> user_profiles.display_name
--   search_public_routes (20261217_001)   -> routes.name (via public_routes)
--   search_clubs (20270218_001)           -> clubs.name, clubs.location_label
--   browse_public_challenges (20270308_001) -> challenges.title, challenges.description
--   search_public_events (20270113_001)   -> events.title (discipline already has
--                                            events_discipline_trgm, 20270110_001;
--                                            an OR needs BOTH branches indexed)
-- Plain CREATE INDEX (not CONCURRENTLY): the CLI runs migrations in a
-- transaction, where CONCURRENTLY hard-fails; these tables are small-to-medium
-- today, so the brief ShareLock is accepted (see the migration-locks review).

-- Hosted `supabase db push` sessions may lack `extensions` on the search_path
-- (and the CLI RESETs it before every file), so unqualified postgis/pg_trgm
-- references only resolve if each file sets it itself.
set search_path = public, extensions;

create extension if not exists pg_trgm with schema extensions;

create index if not exists user_profiles_display_name_trgm
  on user_profiles using gin (display_name extensions.gin_trgm_ops);

create index if not exists routes_name_trgm
  on routes using gin (name extensions.gin_trgm_ops);

create index if not exists clubs_name_trgm
  on clubs using gin (name extensions.gin_trgm_ops);

create index if not exists clubs_location_label_trgm
  on clubs using gin (location_label extensions.gin_trgm_ops);

create index if not exists challenges_title_trgm
  on challenges using gin (title extensions.gin_trgm_ops);

create index if not exists challenges_description_trgm
  on challenges using gin (description extensions.gin_trgm_ops);

create index if not exists events_title_trgm
  on events using gin (title extensions.gin_trgm_ops);

-- routes_name_search (20260407_001) is a to_tsvector('english', name) GIN index:
-- it only serves @@ tsquery operators, which nothing in the codebase uses against
-- routes.name — search_public_routes uses ILIKE, now covered by routes_name_trgm.
-- Dead weight on every routes write, and a false "already indexed" signal.
drop index if exists routes_name_search;
