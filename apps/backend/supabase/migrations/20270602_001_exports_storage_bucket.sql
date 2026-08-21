-- A dedicated Storage bucket for Art 20 export artifacts.
--
-- decisions.md §703 removed the export's 5000-run cap and its
-- 50,000-row-per-section ceiling by streaming the archive into Storage
-- in 6 MiB tus chunks. That exposed a tighter bound sitting underneath
-- both of them, which nothing documented: the artifacts were written to
-- the `runs` bucket, and `runs` carries `file_size_limit = 25 MB`
-- (20260620_001). A gzipped track is ~0.2-1 MB and the `backup` format
-- archives every one of them verbatim, so the real ceiling on a
-- full-history export was on the order of tens of runs — far below
-- either documented cap. storage-api enforces file_size_limit for every
-- role including `service_role`, so it is not bypassable from the
-- server, and it surfaces as a failed upload rather than as a short
-- archive: the subject gets an error, not a truncated export.
--
-- 25 MB is the right cap for what else lives in `runs` (a single
-- gzipped track; the decoder's own `MAX_TRACK_GZIP_BYTES` is 5 MB), and
-- `file_size_limit` is per bucket rather than per prefix, so one bucket
-- cannot serve both. Exports get their own.
--
-- **No policies at all on this bucket, deliberately.** 20260816_001
-- deliberately carved `exports/` out of the owner-folder SELECT policy
-- on `runs`: an export is reachable through the 10-min signed URL the
-- function issues and nothing else, so an owner cannot replay a
-- recalled path with a live session JWT during the retention window.
-- Re-adding an owner SELECT here would reverse that decision. Every
-- writer and reader of this bucket is `service_role`, which is
-- RLS-exempt, so zero policies is the correct and tightest expression:
-- RLS is enabled on storage.objects and denies by default.
--
-- Legacy artifacts already written under `runs/{uid}/exports/` stay
-- where they are; `delete-account` drains both buckets, the retention
-- sweep below covers both, and the export's own orphan sweep continues
-- to skip that prefix, so nothing is stranded and no export ever
-- archives a previous export.
--
-- OPERATOR STEP, pre-deploy (not expressible in SQL): Supabase also
-- enforces a PROJECT-level upload size limit (Dashboard -> Storage ->
-- Settings), 50 MB by default. The effective ceiling is the LOWER of
-- that and this bucket's limit, so raising the bucket alone changes
-- nothing. Until the project limit is raised, the project setting is
-- the export's honest bound.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'exports',
  'exports',
  false,
  5368709120, -- 5 GiB; tus resumable uploads support far more
  array['text/csv', 'application/zip']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Widen the 7-day retention sweep to the new bucket. Without this an
-- archive holding the subject's ENTIRE history would sit in Storage
-- forever after its 10-minute signed URL died — the exact accumulation
-- 20260720_001 exists to prevent, just relocated.
--
-- Complete body re-emitted (the bare-body trap): the live definition is
-- 20260720_001's, and 20260725_001 added only a grant + comment, both
-- of which survive a `create or replace`.
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
  where (
      (bucket_id = 'runs' and name like '%/exports/%')
      or bucket_id = 'exports'
    )
    and created_at < now() - interval '7 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function cleanup_stale_export_blobs() is
  'Daily sweep of Art 20 export artifacts older than 7 days, across '
  'both the `exports` bucket (20270602_001) and the legacy '
  '`runs/{user_id}/exports/*` prefix. SECURITY DEFINER + executes as '
  'the postgres role, which has bypassrls on Supabase Cloud so the '
  'direct DELETE on storage.objects fires regardless of the storage '
  'schema RLS. pg_cron runs the job; service_role grant lets ops '
  'invoke manually if needed. Sibling pattern: '
  'cleanup_stale_live_run_pings (20260509_001) and '
  'cleanup_stale_rate_limits (20260604_001).';
