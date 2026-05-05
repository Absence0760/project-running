-- Daily sweep of stale `runs/{user_id}/exports/*` blobs.
--
-- Audit pass 2 finding: `export-data` writes CSV / GPX zip exports
-- to `runs/{user_id}/exports/<ts>.{csv,zip}` and returns a 10-minute
-- signed URL. After the URL expires nothing prunes the blob; a
-- power user can accumulate hundreds of multi-MB exports across a
-- year, each holding their full run history. `delete-account`
-- recurses into `exports/` correctly, so account deletion is
-- handled — the gap is the absence of a sweep during normal life.
--
-- Approach: a SECURITY DEFINER function that DELETEs from
-- `storage.objects` for the `runs` bucket where the path matches
-- `*/exports/*` and the object is older than 7 days. The Storage
-- service handles the actual blob deletion via cascade. Same shape
-- as `cleanup_stale_live_run_pings` — defined here, scheduled via
-- pg_cron in the same migration.
--
-- Why 7 days: signed URLs are 10-min, so a user can't legitimately
-- need a previously-generated export they didn't save locally —
-- they can re-run `export-data` to regenerate. 7 days is comfortable
-- buffer for a user who downloaded the URL, mailed it to themselves,
-- and clicks the link a few days later (link is dead by then either
-- way; the blob existing or not is invisible to them).

create or replace function cleanup_stale_export_blobs()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  delete from storage.objects
  where bucket_id = 'runs'
    and name like '%/exports/%'
    and created_at < now() - interval '7 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke execute on function cleanup_stale_export_blobs() from public, anon, authenticated;

select cron.schedule(
  'cleanup-stale-export-blobs',
  '23 4 * * *',
  $$select public.cleanup_stale_export_blobs()$$
);
