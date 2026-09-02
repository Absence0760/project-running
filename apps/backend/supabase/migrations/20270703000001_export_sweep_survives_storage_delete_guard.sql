-- The Art 20 retention sweep is refused by storage-api's own delete guard, on
-- every image this repo can start — and a refusal was indistinguishable from a
-- clean sweep.
--
-- storage-api migration `0055-prevent-direct-deletes` installs
-- `storage.protect_delete()` behind a BEFORE DELETE FOR EACH STATEMENT trigger
-- on both `storage.objects` and `storage.buckets`. It raises 42501 ("Direct
-- deletion from storage tables is not allowed. Use the Storage API instead.")
-- unless `storage.allow_delete_query` is `'true'` for the transaction.
--
-- decisions.md § 839 recorded this as a forward risk — "newer storage-api
-- images", "a no-op on CI's pinned 2.84.2". Measured, that is wrong in the
-- direction that matters. CLI 2.84.2 (CI's pin) starts storage-api v1.44.11
-- and CLI 2.109.1 (the workstation) starts v1.62.5; `0055` is present in BOTH,
-- so the trigger is on CI too, and a Supabase Cloud project running anything
-- at or past that line has it as well.
--
-- Two consequences, and the first is why this is not a forward risk:
--
--   * The trigger is STATEMENT-level, so it fires on a DELETE that matches no
--     rows. The nightly `cleanup-stale-export-blobs` cron job therefore raises
--     every night whether or not anything is stale — it has never had to find
--     a stale archive to fail.
--   * The DELETE precedes `expire_stale_export_jobs()` in the composed body,
--     so the raise takes the whole transaction with it: no object is removed
--     AND no `ready` row is expired. An archive holding a subject's entire
--     history outlives its 10-minute signed URL indefinitely, and the row
--     keeps claiming the download is collectable.
--
-- Two changes, and they are separate claims.
--
-- 1. The sweep sets the escape GUC itself, transaction-locally, exactly as
--    20260927_001's orphan-blob cleanup already does. That is the precedent
--    this repo set the first time it met the trigger, and it makes the body
--    behave identically on an image with the trigger and one without.
--
-- 2. The sweep verifies its own post-condition. `get diagnostics row_count`
--    reports what the statement deleted, not what the retention window
--    required, so a delete that is FILTERED rather than refused — a row-level
--    trigger returning null, an RLS policy on `storage.objects`, a future
--    guard that skips instead of raising — returns 0 and reads exactly like a
--    night with nothing to sweep. Then `expire_stale_export_jobs()` runs and
--    marks the row `expired` while the archive is still there, which is the
--    worst of the three outcomes: the object survives and the only record
--    pointing at it is gone. So the surviving stale objects are counted after
--    the delete and a non-zero count raises, before the expiry runs. A sweep
--    that could not sweep now fails loudly and leaves the job rows alone.
--
-- What is NOT decided here, and is on the followups list for the owner: this
-- deletes `storage.objects` ROWS, and the guard the trigger implements exists
-- because that is not the same as deleting the object. 20260927_001 recorded
-- the belief that "the actual blob bytes are reaped by the storage backend's
-- background sweeper once the row is gone"; that belief is not measured here.
-- Moving the sweep onto the Storage API (a job kind in the Go worker, which
-- already writes the archive through that API) is the alternative, and it is a
-- structural change to a shipped retention path.
--
-- No table DDL, no constraint, no backfill: one `create or replace function`
-- and its comment. `migration_locks.md` has nothing to say about it.

create or replace function cleanup_stale_export_blobs()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
  v_remaining integer;
begin
  -- storage-api's protect_delete() trigger refuses a direct DELETE from
  -- storage.objects unless this is set. Transaction-local, so it is gone the
  -- moment the sweep returns.
  perform set_config('storage.allow_delete_query', 'true', true);

  delete from storage.objects
  where (
      (bucket_id = 'runs' and name like '%/exports/%')
      or bucket_id = 'exports'
    )
    and created_at < now() - interval '7 days';
  get diagnostics v_deleted = row_count;

  select count(*) into v_remaining
  from storage.objects
  where (
      (bucket_id = 'runs' and name like '%/exports/%')
      or bucket_id = 'exports'
    )
    and created_at < now() - interval '7 days';

  if v_remaining > 0 then
    raise exception
      'cleanup_stale_export_blobs removed % stale export object(s) but % remain past the 7-day retention window',
      v_deleted, v_remaining
      using errcode = 'P0001',
            hint = 'A DELETE on storage.objects was filtered rather than refused. '
                   'Art 20 archives are still readable through the Storage API and '
                   'data_export_jobs rows have deliberately NOT been expired. Check '
                   'for a row-level trigger or an RLS policy on storage.objects.';
  end if;

  perform expire_stale_export_jobs();

  return v_deleted;
end;
$$;

comment on function cleanup_stale_export_blobs() is
  'Daily sweep of Art 20 export artifacts older than 7 days, across '
  'both the `exports` bucket (20270602_001) and the legacy '
  '`runs/{user_id}/exports/*` prefix, then expire_stale_export_jobs() '
  'for the data_export_jobs rows that pointed at them (20270603_001). '
  'Sets storage.allow_delete_query transaction-locally so storage-api''s '
  'protect_delete() trigger admits the DELETE, and raises if any stale '
  'object survives it, so a blocked sweep cannot read as an empty one '
  '(20270703000001). SECURITY DEFINER + executes as the postgres role, '
  'which has bypassrls on Supabase Cloud so the direct DELETE on '
  'storage.objects fires regardless of the storage schema RLS. pg_cron '
  'runs the job; service_role grant lets ops invoke manually if needed. '
  'Sibling pattern: cleanup_stale_live_run_pings (20260509_001) and '
  'cleanup_stale_rate_limits (20260604_001).';
