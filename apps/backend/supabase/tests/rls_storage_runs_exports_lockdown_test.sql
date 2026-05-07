-- Pin the runs-bucket configuration changes from /audit/all 2026-05-07:
--
--   20260814_001 — `approve_event_result` SECURITY DEFINER must be
--                  callable only by authenticated, never by public/anon.
--   20260815_001 — `runs` Storage bucket gets a MIME allow-list
--                  (gzip / octet-stream / csv / zip) so a future writer
--                  can't land an `image/svg+xml` blob there.
--   20260816_001 — owner SELECT on `runs/<uid>/exports/*` is gated
--                  off; export blobs are signed-URL-only during
--                  the 7-day retention window.
--
-- Coverage:
--   1. anon EXECUTE on approve_event_result is denied.
--   2. authenticated EXECUTE on approve_event_result is granted
--      (the function is callable; the body's `is_race_director`
--      guard is what actually decides whether the approval lands).
--   3. runs bucket has the canonical 4-entry MIME allow-list.
--   4. The owner-folder SELECT policy excludes the `exports/`
--      sub-prefix.

begin;

select plan(4);

-- 1. anon CANNOT execute approve_event_result.
select is(
  has_function_privilege(
    'anon',
    'approve_event_result(uuid, timestamptz, uuid, boolean)',
    'execute'
  ),
  false,
  'anon CANNOT EXECUTE approve_event_result (definer-grant hygiene; '
  '20260814_001 revoked the implicit public grant)'
);

-- 2. authenticated CAN execute approve_event_result.
select is(
  has_function_privilege(
    'authenticated',
    'approve_event_result(uuid, timestamptz, uuid, boolean)',
    'execute'
  ),
  true,
  'authenticated CAN EXECUTE approve_event_result (re-granted in 20260814_001)'
);

-- 3. runs bucket MIME allow-list pins the 4 expected types.
select results_eq(
  $$ select array_length(allowed_mime_types, 1)::int,
            'application/gzip' = any(allowed_mime_types),
            'application/octet-stream' = any(allowed_mime_types),
            'text/csv' = any(allowed_mime_types),
            'application/zip' = any(allowed_mime_types)
     from storage.buckets where id = 'runs' $$,
  $$ values (4, true, true, true, true) $$,
  'runs bucket allowed_mime_types pins gzip / octet-stream / csv / zip (20260815_001)'
);

-- 4. The runs-bucket owner SELECT policy excludes the `exports/` sub-prefix.
--    Inspect the policy expression text directly so a future migration
--    that re-broadens the policy fails CI here, not in production.
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Users can read their own run tracks'
      and qual ilike '%exports%'
  ),
  'runs SELECT policy excludes exports/ sub-prefix (signed-URL-only path; 20260816_001)'
);

select * from finish();

rollback;
