-- audit:gdpr + audit:account-deletion-completeness May 2026 closeouts.
-- Each section closes a specific finding from the compliance-auditor
-- report; the per-section preamble names the regime + the audit row.
--
-- Out of scope here (separate commits / operator tasks):
--   * Privacy / terms legal-entity TODOs — counsel input required.
--   * DPA executions for Supabase / AWS / Sentry / RevenueCat /
--     Anthropic / OpenAI / Fly — provider-console click-throughs.
--   * Sentry opt-out toggle, server-side age gate, CloudFront log
--     lifecycle — ship as their own commits.
--   * `segment_leaderboard_tiered` "derived age exposure" — the audit
--     cites 20260829_001, but 20260830_001 already restricts both
--     `gender` and `age` to `case when se.user_id = caller`, so
--     non-caller rows return `null`. No fix needed.

-- ─────────────────────────────────────────────────────────────────────
-- 1. jobs retention — GDPR Art 5(1)(e) storage limitation.
-- ─────────────────────────────────────────────────────────────────────
-- The `jobs` queue table (20260609_001) holds `payload jsonb` with the
-- user's UUID embedded. Completed and failed rows accumulate forever
-- — no FK to auth.users, no purge — which keeps the user's UUID
-- visible in the table indefinitely after account deletion. Schedule
-- a daily sweep of terminal rows older than 30 days.
--
-- Why 30 days, not 7: a `map_match` failure may need investigation by
-- an operator (Sentry alert → check the row's `last_error`). 30 days
-- gives a comfortable window for that before storage-limitation kicks
-- in. The `delete-account` EF (commit + 1) also drains a user's jobs
-- immediately at deletion time, so this cron is the long-tail safety
-- net for live users' completed jobs.

create or replace function private.purge_stale_jobs()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
begin
  with deleted as (
    delete from jobs
    where status in ('done', 'failed', 'cancelled')
      and finished_at is not null
      and finished_at < now() - interval '30 days'
    returning 1
  )
  select count(*) into v_deleted from deleted;
  if v_deleted > 0 then
    raise notice 'purge_stale_jobs: removed % row(s)', v_deleted;
  end if;
end;
$$;

revoke all on function private.purge_stale_jobs() from public, anon, authenticated;

select cron.schedule(
  'purge-stale-jobs',
  '35 3 * * *',  -- 03:35 UTC daily — sits after the 03:17 / 03:23 /
                  -- 03:29 retention jobs from 20260922_001.
  $$select private.purge_stale_jobs()$$
);

comment on function private.purge_stale_jobs() is
  'GDPR Art 5(1)(e) storage-limitation: purges terminal `jobs` rows '
  '(done / failed / cancelled, finished_at older than 30 days). '
  'Scheduled by pg_cron entry `purge-stale-jobs` (03:35 UTC daily). '
  'See audit/gdpr May 2026.';

-- ─────────────────────────────────────────────────────────────────────
-- 2. rate_limits cascade — GDPR Art 17 right to erasure.
-- ─────────────────────────────────────────────────────────────────────
-- `rate_limits.user_id` (20260604_001) is `uuid not null` with no FK
-- to auth.users. The 24-hour `cleanup_stale_rate_limits` job purges
-- old rows, but during that window the deleted user's UUID survives
-- in plaintext after `admin.deleteUser`. Add a deferred FK with
-- `on delete cascade` so the deletion-event sync is immediate.
--
-- The existing table has historical rows that may reference UUIDs no
-- longer in auth.users (the table predates this FK by ~6 months and
-- has no integrity contract). Drop any orphan rows before adding the
-- FK so the validation step doesn't fail. The orphans are already
-- expired data — the 24-hour cleanup would have got them on the next
-- pass anyway.

delete from public.rate_limits r
  where not exists (
    select 1 from auth.users u where u.id = r.user_id
  );

alter table public.rate_limits
  add constraint rate_limits_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

-- ─────────────────────────────────────────────────────────────────────
-- 3. deletion_audit_log.third_party_outcomes — Art 17(2) recipient
--    notification evidence trail.
-- ─────────────────────────────────────────────────────────────────────
-- Today the `delete-account` EF calls Strava `/oauth/deauthorize`,
-- RevenueCat `DELETE /v1/subscribers`, and FCM `batchRemove` as
-- best-effort. Errors are logged to Sentry but the audit-log row
-- only records the top-level result. Art 17(2) requires the
-- controller to take "reasonable steps" to inform recipients of
-- erasure and (implicit in the broader Art 5(2) accountability
-- principle) to be able to demonstrate those steps. Record each
-- third-party outcome inline so a regulator's "did you notify
-- Strava?" question has a structured answer.
--
-- jsonb so future third parties can land without a schema change.
-- Expected keys (set by delete-account/index.ts):
--   strava_deauth      : 'ok' | 'skipped' | 'failed'
--   revenuecat_delete  : 'ok' | 'skipped' | 'failed'
--   fcm_remove         : 'ok' | 'skipped' | 'failed'  (skipped = no Android tokens)
-- The `skipped` state is meaningful — "we didn't call Strava because
-- the user never connected" is different from "we called Strava and
-- it errored".

alter table public.deletion_audit_log
  add column if not exists third_party_outcomes jsonb;

comment on column public.deletion_audit_log.third_party_outcomes is
  'Structured per-third-party cleanup outcomes recorded by delete-account. '
  'Keys: strava_deauth, revenuecat_delete, fcm_remove. '
  'Values: ok | skipped | failed. Evidence trail for GDPR Art 17(2).';

-- ─────────────────────────────────────────────────────────────────────
-- 4. Vault-key documentation pin for the audit hash.
-- ─────────────────────────────────────────────────────────────────────
-- The current hash in delete-account/lib.ts is SHA-256(salt || uid).
-- audit/account-deletion-completeness flagged this as a low-priority
-- hardening item: HMAC-SHA256 with a Vault-stored key is meaningfully
-- pseudonymous against an adversary who has a UUID and wants to test
-- whether that user has been deleted. The EF in the matching commit
-- reads `DELETION_AUDIT_KEY` from the environment; when set, the
-- hash flips to HMAC, when unset it falls back to the existing salted
-- SHA-256 so the migration is non-breaking. No schema change here —
-- this comment-only DO block pins the contract so a future contributor
-- finds it before considering a column rewrite.
do $$ begin null; end $$;
