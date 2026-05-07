-- /audit/all storage Medium: export blobs at
-- `runs/{user_id}/exports/<ts>.{csv,zip}` are reachable via the
-- owner-folder Storage SELECT policy from 20260410_001 — `(storage.
-- foldername(name))[1] = auth.uid()::text` matches `{user_id}` on
-- the FIRST segment, regardless of whether the rest of the path is
-- a track (`{run_id}.json.gz`) or an export (`exports/<ts>.csv`).
--
-- The `export-data` Edge Function returns a 10-min signed URL — the
-- intended access path. But during the 7-day retention window
-- (cleanup-stale-exports cron, 20260720_001), an authenticated owner
-- with their own session JWT can also pull the blob directly by
-- guessing or recalling the path — bypassing the time-bounded
-- signed URL. Owner-reading-own-data isn't a cross-user exploit, but
-- it widens the window during which a leaked CSV-with-Storage-paths
-- (or a snooped browser-history entry) is replayable.
--
-- Tighten by replacing the broad SELECT with one that excludes the
-- `exports/` subdirectory. The signed URL path is service-role-
-- created in the EF, so it bypasses this policy and keeps working.
-- The track-download path (RunDetail page calling
-- `fetchTrackByPath('{user_id}/{run_id}.json.gz')`) keeps working
-- because tracks live at the root of the user's prefix, not under
-- `exports/`.
--
-- Other operations (insert, update, delete) keep the original
-- broad-prefix policy: the `export-data` EF uses service-role for
-- writes anyway, and `delete-account` recursively walks both
-- prefixes via the admin client. Owners deleting their own tracks
-- still works.

drop policy "Users can read their own run tracks" on storage.objects;

create policy "Users can read their own run tracks"
on storage.objects for select
to authenticated
using (
  bucket_id = 'runs'
  and (storage.foldername(name))[1] = auth.uid()::text
  -- Exports are signed-URL-only. The path shape is
  -- `{user_id}/exports/<ts>.{csv,zip}`, i.e. `exports` is the second
  -- foldername segment. The owner-folder match above is the first
  -- segment, so the second-segment check below is the export gate.
  and coalesce((storage.foldername(name))[2], '') <> 'exports'
);
