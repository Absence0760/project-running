-- Scope `runs.external_id` uniqueness per-user instead of globally.
--
-- Pre-fix the initial_schema migration applied two redundant guards:
--   column constraint:    `external_id text unique`
--   partial unique index: `unique on runs (external_id) where ... not null`
--
-- Both guard a GLOBAL uniqueness: no two rows in the entire table
-- can share an external_id. That breaks legitimate cross-user import
-- patterns:
--
--   * Two friends both import a group run from Strava — one with the
--     Strava activity ID their account owns, the other re-uploaded by
--     a teammate to that runner's own Strava (legitimately separate
--     activity but technically the same `strava:<id>` external_id if
--     they're sharing a recorded file).
--
--   * Two users sharing a parkrun event id `parkrun:<event>-<date>`.
--     The parkrun-import EF currently uses athlete-number namespacing
--     but a future re-tasking that drops the prefix would collide.
--
--   * Any cross-source dedupe shape that namespaces under `<source>:`
--     and assumes per-user scope at the application layer.
--
-- The right scope is per-user: the dedupe key `external_id` identifies
-- THIS user's import of THAT activity. Two users importing the same
-- ID is allowed.
--
-- The strava-zip importer (apps/web/src/lib/strava-zip.ts) and the
-- mobile importer already dedupe per-user via `metadata.strava_id`, so
-- the application-layer guard is already correctly scoped. The DB
-- constraint just has to follow.
--
-- Persona-hunt finding Intermediate #2.

-- Drop the global constraint + the redundant index.
alter table runs drop constraint if exists runs_external_id_key;
drop index if exists runs_external_id;

-- Per-user partial unique. Partial because external_id is nullable
-- (most rows are native captures with no upstream id).
create unique index runs_user_external_id
  on runs (user_id, external_id)
  where external_id is not null;
