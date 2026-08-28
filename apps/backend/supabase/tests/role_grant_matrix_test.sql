-- Pins migration 20270408_001 (version-controlled public-schema grant matrix).
--
-- Prod onboarding broke on 2026-07-13 with `42501 permission denied for
-- table user_profiles` / `user_settings` because the `authenticated` role
-- had lost base table privileges that lived only in Supabase's implicit
-- default privileges, never a migration. This test fails CI if that class
-- of gap returns.
--
--   1. Catch-all: every public base table EXCEPT the deliberately
--      service_role-only ones must be readable by `authenticated` via a
--      table-level or column-level SELECT. A table shipped without a
--      SELECT grant (the user_settings-shaped regression) fails HERE.
--   2. Functional probes on the exact incident columns + the DML surface
--      onboarding needs.
--   3. The column-SELECT lockdown on user_profiles is preserved (no
--      table-level SELECT leaked back in).
--   4. The same for the two payment tables, which this migration granted a
--      table-level SELECT while its own header claimed it "never grants
--      table-level SELECT on a column-locked table". It was generated from
--      the fully-migrated schema, and 20261229_001 / 20270213_001 had written
--      their lockdowns as COLUMN-level revokes — a no-op under a table-level
--      grant, leaving no column ACL for the generator to see. 20270621_001
--      re-cut both to the prescribed shape; these pin that the matrix does not
--      widen them back, and that the columns the payout UI reads survived.

begin;

select plan(12);

-- (1) Catch-all — readability. Only app_quota, deletion_audit_log and
-- data_export_jobs are intentionally service_role-only (no anon/authenticated
-- grant at all). data_export_jobs (20270603_001) holds the state of an Art 20
-- export request; the row is useless to a client without a signed URL, which
-- only the service role can mint, so the whole read goes through the Go
-- worker's JWT-authed status endpoint and the table needs no client grant.
select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
     where c.relkind = 'r'
       and c.relname not in ('app_quota', 'deletion_audit_log', 'data_export_jobs')
       and not has_table_privilege('authenticated', c.oid, 'SELECT')
       and not exists (
         select 1 from information_schema.role_column_grants g
         where g.table_schema = 'public'
           and g.table_name = c.relname
           and g.grantee = 'authenticated'
           and g.privilege_type = 'SELECT')),
  0,
  'every public base table (except the service_role-only allow-list) is '
  'readable by authenticated via a table- or column-level SELECT grant'
);

-- (2) The exact incident: authenticated writes its own profile + reads its settings.
select ok(
  has_table_privilege('authenticated', 'public.user_profiles', 'UPDATE'),
  'authenticated has UPDATE on user_profiles (onboarding profile PATCH)'
);
select ok(
  has_table_privilege('authenticated', 'public.user_profiles', 'INSERT'),
  'authenticated has INSERT on user_profiles (first-write profile bootstrap)'
);
select ok(
  has_column_privilege('authenticated', 'public.user_settings', 'prefs', 'SELECT'),
  'authenticated can SELECT user_settings.prefs (onboarding + prefs reads)'
);
select ok(
  has_table_privilege('authenticated', 'public.user_settings', 'UPDATE'),
  'authenticated has UPDATE on user_settings (prefs writes)'
);

-- (3) Lockdown preserved: user_profiles table-level SELECT stays revoked
-- (privacy columns are column-granted only), but the public-safe columns
-- remain readable.
select ok(
  not has_table_privilege('authenticated', 'public.user_profiles', 'SELECT'),
  'user_profiles has NO table-level SELECT for authenticated — the '
  'column-lockdown (20260707_001/20260810_001) is intact'
);
select ok(
  has_column_privilege('authenticated', 'public.user_profiles', 'display_name', 'SELECT'),
  'user_profiles.display_name stays column-readable by authenticated'
);

-- (4) The two payment tables 20270621_001 re-cut. Assertion (1) above is
-- satisfied by their per-column grants, so it cannot tell a lockdown from a
-- table-wide grant; these say which one is in force.
select ok(
  not has_table_privilege('authenticated', 'public.donations', 'SELECT'),
  'donations has NO table-level SELECT for authenticated — 20270213_001''s '
  'column revoke bites now instead of being absorbed by a table grant'
);
select ok(
  not has_column_privilege('authenticated', 'public.donations', 'stripe_payment_intent_id', 'SELECT'),
  'donations.stripe_payment_intent_id is withheld from authenticated'
);
select ok(
  has_column_privilege('authenticated', 'public.donations', 'amount_cents', 'SELECT'),
  'donations.amount_cents keeps the column grant that satisfies the catch-all above'
);
select ok(
  not has_column_privilege('authenticated', 'public.instructor_payout_accounts',
                           'stripe_connect_account_id', 'SELECT'),
  'the raw Stripe Connect account id is withheld from the host''s own-row read'
);
select ok(
  has_column_privilege('authenticated', 'public.instructor_payout_accounts',
                       'charges_enabled', 'SELECT'),
  'instructor_payout_accounts.charges_enabled stays readable — fetchPayoutAccount '
  'selects it on /settings/payouts'
);

select * from finish();
rollback;
