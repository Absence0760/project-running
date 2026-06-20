-- Account-deletion receipt email (decisions §121, followups "Account-deletion
-- receipt").
--
-- This lifecycle email needs a different mechanism than the others. The Go
-- worker resolves a recipient's address from auth.users via the GoTrue admin
-- API — but for a deletion receipt the user is GONE by send time (GoTrue 404s),
-- the delete-account Edge Function drains the user's pending jobs before the
-- auth-row cascade (so a normally-enqueued job is swept away), and the
-- lifecycle_email_log send-once guard has an `on delete cascade` FK to
-- auth.users, so its row would vanish with the user.
--
-- The fix has two halves:
--
--   1. The delete-account EF enqueues a `lifecycle_email` job AFTER the
--      job-drain whose payload carries the address INLINE (template
--      'account_deleted', { email, locale }) and NO user_id. Because the
--      drain filters on `payload->>user_id`, a payload without that key is
--      naturally exempt — no special-casing needed.
--
--   2. The send-once guard for this template can't live in lifecycle_email_log
--      (it cascades away). This table is its non-cascading replacement: keyed
--      by a SHA-256 hash of the lowercased email (not the raw address, not the
--      now-gone user_id), with NO foreign key, so nothing cascades it away. A
--      job retry — or a crash between send and finish_job — can't re-send.
--
-- account_deleted is a `lifecycle_email` template, so the jobs.kind allowlist
-- (last restated in 20270212_001) already permits it — no CHECK change here.

-- ─────────────────── non-cascading send-once record ───────────────────

-- One row per receipt the worker has sent, keyed by the email hash so it
-- survives the deleted user's auth-row cascade. Service-role only — the
-- worker is the sole reader/writer; RLS denies everyone else. The email
-- itself is never stored, only its hash, so the table is not a directory of
-- deleted-account addresses (mirrors deletion_audit_log's pseudonymisation
-- intent). Hash is hex SHA-256 of the lowercased, trimmed address.
create table account_deletion_receipts (
  email_hash text primary key,
  sent_at    timestamptz not null default now()
);

alter table account_deletion_receipts enable row level security;
-- No policies → no anon/authenticated access. The worker uses the service
-- role key, which bypasses RLS.

-- ─────────────────── retention ───────────────────

-- The send-once guard only needs to outlive the at-least-once delivery window
-- (a job's retry budget is minutes-to-hours). A row older than 30 days has no
-- further dedupe value, and keeping deleted-account hashes indefinitely is
-- needless data-minimisation debt. Reuse the same hourly pg_cron sweeper
-- pattern the rate-limit / webhook-event tables use.
create or replace function cleanup_account_deletion_receipts()
returns void
language sql
security definer
set search_path = public
as $$
  delete from account_deletion_receipts
  where sent_at < now() - interval '30 days';
$$;

revoke execute on function cleanup_account_deletion_receipts() from public;

select cron.schedule(
  'cleanup-account-deletion-receipts',
  '17 * * * *',
  $$select public.cleanup_account_deletion_receipts();$$
);
