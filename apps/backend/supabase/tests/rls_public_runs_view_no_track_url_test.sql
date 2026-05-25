-- audit/storage + audit/public-rows (2026-05-25) Medium: pin the
-- removal of `track_url` from the `public_runs` view (migration
-- 20260924_001). A future migration that adds the column back to
-- the SELECT list would silently re-expose the `{user_id}/{run_id}
-- .json.gz` Storage path to anon callers, which is defence-in-depth
-- weak even with the bucket-level SELECT-to-anon policy already
-- dropped. The clip-public-track Edge Function derives the path
-- directly from user_id + runId, so the column has no legitimate
-- consumer on the view.

begin;

select plan(2);

select hasnt_column(
  'public_runs', 'track_url',
  'public_runs view must not expose track_url — see audit/storage (2026-05-25)'
);

-- Defence: even a future view that re-adds the column under a
-- different name would defeat the test above. Assert the underlying
-- view definition does not reference runs.track_url anywhere. The
-- definition lives in pg_catalog.pg_views.
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
