-- audit/storage + audit/public-rows (2026-05-25) Medium: pin the
-- removal of `track_url` from the `public_runs` view (migration
-- 20260924_001). A future migration that adds the column back to
-- the SELECT list would silently re-expose the `{user_id}/{run_id}
-- .json.gz` Storage path to anon callers, which is defence-in-depth
-- weak even with the bucket-level SELECT-to-anon policy already
-- dropped. The clip-public-track Edge Function derives the path
-- directly from user_id + runId, so the column has no legitimate
-- consumer on the view.
--
-- 20261105_001 re-added a boolean `has_track` (derived from
-- `track_url IS NOT NULL`) so the feed / profile map-thumbnail gate has a
-- safe signal. The view now references track_url internally to compute
-- that boolean, but must never EXPOSE the path column — the two assertions
-- below pin both halves of that contract.

begin;

select plan(3);

select hasnt_column(
  'public_runs', 'track_url',
  'public_runs view must not expose track_url — see audit/storage (2026-05-25)'
);

select has_column(
  'public_runs', 'has_track',
  'public_runs exposes the boolean has_track existence signal (20261105_001)'
);

-- Assert the underlying view definition still exists. (It now references
-- track_url in the has_track predicate; that derives a boolean only and
-- never selects the path column — pinned by hasnt_column above.)
select isnt(
  (
    select view_definition
      from information_schema.views
     where table_schema = 'public'
       and table_name = 'public_runs'
  )::text,
  null,
  'public_runs view definition exists in information_schema'
);

select * from finish();
rollback;
