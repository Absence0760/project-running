-- Bound the deletion evidence trail, and say on both deletion tables what
-- their hashes actually are.
--
-- ── Why `deletion_audit_log` needed a decision, not a default ───────────────
-- It was the only personal-data table in `docs/compliance/retention.md` with no
-- window at all: `20260917_001` created it, `20260920_001` made it append-only,
-- `20261111_001` widened its result codes, and nothing ever swept it. That is
-- defensible -- it is Art 17(2) and Art 5(2) accountability evidence,
-- deliberately outliving the account it records, and "did you erase user X on
-- date Y" is exactly what it answers after the auth row is gone. But Art 5(1)(e)
-- asks for a STATED period, and "nobody decided" is not one (decisions § 1551).
--
-- ── The number, and where it comes from ─────────────────────────────────────
-- What bounds the need is the period in which someone could still assert that
-- we failed to erase: a civil claim, or a supervisory-authority inquiry opened
-- on one. The GDPR sets no limitation period for an Art 82 claim, so national
-- law governs, and the LONGEST ordinary period among the jurisdictions this
-- service is offered in is six years (UK Limitation Act 1980 ss. 2 and 5;
-- Ireland's Statute of Limitations 1957 s. 11; several US states for contract).
-- Germany's BGB § 195 is three. Six years plus one year of margin -- a claim
-- issued on the last day is served later, and the inquiry it provokes runs
-- after that -- gives SEVEN YEARS, which is what the sweep below enforces.
--
-- What is given up is stated rather than left implicit: past seven years we can
-- no longer evidence a particular erasure, only the policy that performed it.
-- That is the trade Art 5(1)(e) asks a controller to make.
--
-- ── This destroys nothing for seven years, which is the point ───────────────
-- `deleted_at` defaults to `now()` and only the delete-account Edge Function
-- writes the table, so no row can be backdated. The oldest row this schema can
-- hold was written after `20260917_001` applied (2026-09-17), so the first row
-- the sweep can remove becomes eligible in September 2033. The schedule is live
-- from today and irreversibly deletes nothing for seven years, which is ample
-- runway for counsel to shorten or lengthen the window by editing the interval
-- in this function body -- the same single-file edit every other retention
-- window in the register takes. It is therefore landed rather than parked
-- behind a flag: there is no user-visible effect to gate, and a fail-closed
-- default here would mean leaving the period undecided, which is the defect.
--
-- ── Lock impact (migration_locks.md) ────────────────────────────────────────
-- `CREATE OR REPLACE FUNCTION`, `REVOKE`, `GRANT`, `COMMENT` and
-- `cron.schedule` touch catalogue rows only. No table is scanned, rewritten or
-- locked ACCESS EXCLUSIVE, and no constraint is added, so the `NOT VALID` +
-- `VALIDATE` split does not apply. The sweep itself runs at 03:53 UTC and
-- deletes by `deleted_at`, which `deletion_audit_log_deleted_at` already
-- indexes descending.

create or replace function public.cleanup_deletion_audit_log()
returns void
language sql
security definer
set search_path = public
as $$
  delete from deletion_audit_log
  where deleted_at < now() - interval '7 years';
$$;

-- Same lockdown as its siblings (20270625000001): the body is an unqualified
-- DELETE on accountability evidence, so no client role may reach it, and
-- service_role keeps it so ops can invoke it by hand. pg_cron runs it as
-- postgres, the owner, whose EXECUTE does not come from this ACL.
revoke execute on function public.cleanup_deletion_audit_log() from public, anon, authenticated;
grant  execute on function public.cleanup_deletion_audit_log() to service_role;

comment on function public.cleanup_deletion_audit_log() is
  'Daily pg_cron sweep of deletion_audit_log rows whose deleted_at is over '
  'seven years old -- six years being the longest ordinary civil limitation '
  'period among the jurisdictions served, plus a year of margin. SECURITY '
  'DEFINER, run by cron as postgres; service_role may invoke it by hand. '
  'Tighten or extend the window by editing the interval here and moving the '
  'row in docs/compliance/retention.md, which a guard holds to this file.';

select cron.schedule(
  'cleanup-deletion-audit-log',
  '53 3 * * *',
  $$select public.cleanup_deletion_audit_log();$$
);

-- ── The two deletion tables say what their hashes are ───────────────────────
-- `20270217_001`'s header claims the receipt table "mirrors deletion_audit_log's
-- pseudonymisation intent". The intent is shared; the SHAPE is not, and the
-- difference is the whole of the risk (decisions § 1551). Both comments now
-- state their own input so a reader of the live schema is not left to infer one
-- table's properties from the other's.

comment on table public.deletion_audit_log is
  'Art 17(2) + Art 5(2) accountability evidence: one append-only row per '
  'account-deletion attempt, holding a hash of the USER ID, the timestamp, a '
  'result code and the per-table deleted-row counts. Service-role only; no user '
  'read path. The hash input is a 122-bit random UUID, so there is no candidate '
  'to guess and the legacy salt being a source constant costs nothing; setting '
  'DELETION_AUDIT_KEY upgrades new rows to HMAC-SHA256. Retention: seven years '
  'from deleted_at, swept daily by cleanup_deletion_audit_log(). decisions '
  '§ 1551.';

comment on table public.account_deletion_receipts is
  'Send-once guard for the account-deletion receipt email, keyed by a hash of '
  'the ADDRESS and carrying no FK so it survives the auth.users cascade that '
  'takes a lifecycle_email_log row with it. This is PERSONAL DATA and is not '
  'the same shape as deletion_audit_log despite 20270217_001 saying it mirrors '
  'it: an email address is a guessable input, so an unkeyed digest can be '
  'recomputed from a candidate address and the table ASKED whether that person '
  'deleted their account -- it cannot be enumerated, but it can be queried. '
  'Setting DELETION_AUDIT_KEY in the Go worker''s environment moves new rows to '
  'HMAC-SHA256 over a domain-separated input, which ends that test rather than '
  'time-bounding it; unset, the worker still writes the legacy unkeyed SHA-256 '
  'and reads both digests so a changeover re-sends nothing. Retention: 30 days '
  'from sent_at. decisions § 1551.';
