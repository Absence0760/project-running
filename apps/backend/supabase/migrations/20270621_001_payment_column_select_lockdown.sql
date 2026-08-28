-- Make the two payment tables' column-level SELECT lockdowns real.
--
-- `20261229_001` wrote `revoke select (stripe_connect_account_id) on
-- instructor_payout_accounts from authenticated, anon` and `20270213_001`
-- wrote the same shape over five columns of `donations`, calling it defence in
-- depth. Neither revoked anything. Postgres resolves a privilege from the
-- BROADEST grant, so revoking one at column level while the role still holds
-- it at table level changes nothing: the statement reports REVOKE, no column
-- ACL is created, and `has_column_privilege` stays true. Measured against the
-- live catalog before this file: `pg_attribute.attacl` is null for every
-- column of both tables and `has_column_privilege` is true for anon and
-- authenticated on all five donations columns and on the Connect account id.
--
-- `20260707_001` documents this exact trap in its own header and prescribes
-- the shape below — revoke the TABLE-level privilege, re-grant per column —
-- which is why `user_profiles`, `clubs`, `events` and `checkpoint_crossings`
-- lock down correctly and these two did not. `20270408_001` then granted both
-- tables a table-level SELECT while its header claimed it "never grants
-- table-level SELECT on a column-locked table": the matrix was generated from
-- the fully-migrated schema, where a no-op revoke had left no column ACL to
-- reproduce, so the lockdown was invisible to the generator.
--
-- What the defect actually cost, measured rather than assumed:
--
--   * `instructor_payout_accounts` has a permissive own-row SELECT policy, so
--     a host reads their own raw `acct_…` Connect id today — against
--     `20261229_001`'s explicit statement that "even the own-row SELECT policy
--     should not hand the raw id to the client". `fetchPayoutAccount` in
--     apps/web already enumerates the safe columns and its comment already
--     claims the revoke holds; this makes that true.
--   * `donations` has no permissive client SELECT policy at all, so a client
--     read returns zero rows either way and nothing leaked. The defence in
--     depth the migration named is what was missing, not the defence.
--
-- The withheld sets below are wider than the two revoke lists, in the one
-- direction the shape makes inevitable: a per-column re-grant is CUMULATIVE,
-- so a column added after a lockdown is deny-by-default until an explicit
-- grant lands. Had `20270213_001` worked, `refunded_cents` (20270620_001) and
-- `client_request_id` (20270620000002) would have arrived ungranted. They are
-- withheld here for that reason and for their own. `donations.display_name` is
-- the one addition that is not mechanical: `fundraiser_feed` nulls it on an
-- `is_anonymous` row, a column grant cannot be conditional on a row value, and
-- handing the client the name the feed exists to hide is the deanonymisation
-- the withheld `donor_user_id` was already about.
--
-- Every client read path on both tables is SECURITY DEFINER and therefore
-- unaffected: `fundraiser_feed` + `fundraiser_totals` for donations,
-- `host_can_take_payment` for the payout capability. Both Art 20 export rails
-- (the export-data EF and the Go worker) read `*` under the service role,
-- which keeps its table-level grant. The reasons per column are registered in
-- `column_grant_lockdown_registry_test.sql`, which fails when a later column
-- lands ungranted or a registered withholding is granted away.
--
-- Online-safety (docs/backend/migration_locks.md): GRANT and REVOKE take no
-- lock on the relation at all — measured, the only lock either statement holds
-- is an AccessShareLock on the catalog object. There is no scan, no rewrite
-- and no constraint to validate, so neither table is blocked for readers or
-- writers for any part of this.

revoke select on public.donations from anon, authenticated;

grant select (
  id,
  fundraiser_id,
  message,
  amount_cents,
  currency,
  status,
  is_anonymous,
  created_at,
  paid_at,
  refunded_at
) on public.donations to anon, authenticated;

revoke select on public.instructor_payout_accounts from anon, authenticated;

grant select (
  user_id,
  charges_enabled,
  payouts_enabled,
  details_submitted,
  country,
  default_currency,
  onboarded_at,
  created_at,
  updated_at
) on public.instructor_payout_accounts to anon, authenticated;
