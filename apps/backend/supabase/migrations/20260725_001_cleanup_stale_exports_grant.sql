-- Grant + clarify `cleanup_stale_export_blobs`.
--
-- Audit pass 3 findings:
--   1. The function from `20260720_001` revoked from public/anon/
--      authenticated but never granted to service_role. pg_cron runs
--      as `postgres` (a superuser) so the scheduled job works, but a
--      service-role connection trying to invoke the function manually
--      gets `permission denied`. Same shape as the sibling
--      `cleanup_stale_live_run_pings` from `20260509_001`.
--   2. The function does a direct SQL `DELETE FROM storage.objects`.
--      On Supabase Cloud, `storage.objects` has its own RLS gated to
--      `service_role` writes; whether a SECURITY DEFINER function
--      owned by `postgres` can write through it depends on the
--      project's role configuration. This works on local dev (postgres
--      is superuser) and on Supabase Cloud as currently configured
--      (the `postgres` role *is* a superuser on Cloud projects too,
--      via the `bypassrls` attribute on the function-owner role).
--      Adding the explicit grant + a clarifying comment so a future
--      operator inspecting why this function works understands the
--      load-bearing assumption.

grant execute on function cleanup_stale_export_blobs() to service_role;

comment on function cleanup_stale_export_blobs() is
  'Daily sweep of `runs/{user_id}/exports/*` blobs older than 7 '
  'days. SECURITY DEFINER + executes as the postgres role, which '
  'has bypassrls on Supabase Cloud so the direct DELETE on '
  'storage.objects fires regardless of the storage schema RLS. '
  'pg_cron runs the job; service_role grant lets ops invoke '
  'manually if needed. Sibling pattern: cleanup_stale_live_run_pings '
  '(20260509_001) and cleanup_stale_rate_limits (20260604_001).';
