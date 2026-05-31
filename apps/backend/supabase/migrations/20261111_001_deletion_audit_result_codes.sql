-- audit-findings 2026-05-30 Medium [compliance/account-deletion]: the
-- deletion saga drains user jobs, rate_limits, and anonymises authored
-- segments before the auth-row cascade, but on failure all three logged
-- the misleading `reports_cleanup_failed` result code (the CHECK from
-- 20260917_001 didn't have codes for them), so the Art 17(2) audit trail
-- mis-attributes which step failed. Add specific result codes; the EF is
-- updated in the same change to emit them.
alter table public.deletion_audit_log
  drop constraint if exists deletion_audit_log_result_check;

alter table public.deletion_audit_log
  add constraint deletion_audit_log_result_check
  check (result in (
    'ok',
    'storage_drain_failed',
    'auth_delete_failed',
    'reports_cleanup_failed',
    'vault_cleanup_failed',
    'jobs_drain_failed',
    'rate_limits_drain_failed',
    'segments_anonymise_failed'
  ));
