-- The behavioural half of migration 20270621_001 (decisions § 781).
--
-- `20261229_001` and `20270213_001` each wrote `revoke select (cols) on <table>
-- from anon, authenticated` while the roles still held a TABLE-level SELECT,
-- which Postgres answers with the broadest grant — so both revokes were no-ops
-- for the life of their tables, and left no column ACL for a catalogue reader
-- to notice. `20270621_001` applied `20260707_001`'s own prescription instead:
-- revoke the table grant, re-grant per column.
--
-- `column_grant_lockdown_registry_test` and `role_grant_matrix_test` read the
-- catalogue, which is the right instrument for detecting drift and the wrong
-- one for this defect: a no-op revoke produces a catalogue indistinguishable
-- from a table that never had a lockdown. § 781 reproduced the consequence by
-- hand — the host's raw `acct_…` Connect id came back to the browser, and the
-- same query afterwards is `42501` — inside a rolled-back transaction against
-- the shared stack. This is that reproduction, landed.
--
-- The point of asserting the readable columns beside the withheld ones is that
-- the lockdown has two failure directions: a re-grant that widens it, and a
-- revoke that takes a column the payout UI or the Art 20 export needs.

begin;
select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('9ac70000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'pcl-host@pay.local', '', now(), now()),
  ('9ac70000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'pcl-stranger@pay.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit)
values ('9ac70000-0000-0000-0000-000000000001', 'Pcl Host', 'km'),
       ('9ac70000-0000-0000-0000-000000000002', 'Pcl Stranger', 'km');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into instructor_payout_accounts
  (user_id, stripe_connect_account_id, charges_enabled, payouts_enabled, details_submitted)
values ('9ac70000-0000-0000-0000-000000000001', 'acct_PCLNOTFORTHECLIENT', true, true, true);

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('9ac70000-0000-0000-0000-0000000000a1', '9ac70000-0000-0000-0000-000000000001',
        now(), 5000, 1500, 'app', true, '{"activity_type":"run"}');

insert into fundraisers (id, owner_user_id, run_id, charity_name, title, goal_cents)
values ('9ac70000-0000-0000-0000-0000000000f1', '9ac70000-0000-0000-0000-000000000001',
        '9ac70000-0000-0000-0000-0000000000a1', 'Charity', 'Pcl fundraiser', 100000);

insert into donations (id, fundraiser_id, owner_user_id, donor_user_id, display_name,
                       message, amount_cents, status, is_anonymous, paid_at,
                       stripe_payment_intent_id)
values ('9ac70000-0000-0000-0000-0000000000d1', '9ac70000-0000-0000-0000-0000000000f1',
        '9ac70000-0000-0000-0000-000000000001', '9ac70000-0000-0000-0000-000000000002',
        'Pcl Donor', 'Take it', 2500, 'paid', false, now(), 'pi_PCLNOTFORTHECLIENT');

-- ── the host reading their OWN payout row ───────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"9ac70000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ select stripe_connect_account_id from instructor_payout_accounts
      where user_id = auth.uid() $$,
  '42501',
  null,
  'the owner cannot read their own raw Connect account id'
);

-- `select *` names every column, which is why every client read of this table
-- is an enumerated projection.
select throws_ok(
  $$ select * from instructor_payout_accounts where user_id = auth.uid() $$,
  '42501',
  null,
  'a select * over the payout table is refused, withheld column and all'
);

select is(
  (select count(*)::int from (
     select user_id, charges_enabled, payouts_enabled, details_submitted, onboarded_at
       from instructor_payout_accounts where user_id = auth.uid()) p),
  1,
  'the five columns the payout screen selects still answer for the owner'
);

select is(
  (select host_can_take_payment('9ac70000-0000-0000-0000-000000000001')),
  true,
  'the definer oracle still answers over the withheld column'
);

-- ── a stranger is stopped by RLS, one layer above the grant ─────────────────
set local "request.jwt.claims" = '{"sub":"9ac70000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from (
     select user_id, charges_enabled from instructor_payout_accounts) p),
  0,
  'a stranger cannot see another host''s payout row at all'
);

select is(
  (select host_can_take_payment('9ac70000-0000-0000-0000-000000000001')),
  true,
  'the oracle answers a yes/no about another host without disclosing the id'
);

-- ── the donation ledger's own withheld columns ──────────────────────────────
-- 20270213_001 named five columns; the withheld set has to be wider, because a
-- per-column re-grant is cumulative and `refunded_cents` (20270620_001) and
-- `client_request_id` (20270620000002) would have arrived deny-by-default had
-- the lockdown ever worked.
select throws_ok(
  $$ select stripe_payment_intent_id from donations $$,
  '42501', null,
  'the payment intent id is withheld from a signed-in client'
);

select throws_ok(
  $$ select refunded_cents from donations $$,
  '42501', null,
  'the refunded amount is withheld too — it arrived after the lockdown'
);

select throws_ok(
  $$ select client_request_id from donations $$,
  '42501', null,
  'the checkout idempotency key is withheld'
);

-- `display_name` is the column `fundraiser_feed` nulls on an anonymous row. A
-- column grant cannot be conditional on a row value, so granting it would hand
-- the client the name the feed exists to hide.
select throws_ok(
  $$ select display_name from donations $$,
  '42501', null,
  'the donor display name is withheld — the feed decides per row, a grant cannot'
);

select throws_ok(
  $$ select * from donations $$,
  '42501', null,
  'a select * over donations is refused'
);

-- The granted columns are granted, and RLS is still what returns nothing:
-- donations carries no permissive client SELECT policy at all, so the
-- defence-in-depth the migration names sits on top of a row gate that already
-- holds. Both facts are asserted, because a table-wide re-grant would satisfy
-- the second on its own.
select ok(
  has_column_privilege('authenticated', 'public.donations', 'amount_cents', 'SELECT'),
  'the amount is granted — the lockdown is per column, not a blanket revoke'
);

select is(
  (select count(*)::int from (select amount_cents from donations) d),
  0,
  'and a granted column still reads nothing, because no policy admits a client'
);

-- ── service_role keeps the whole row, which is what the Art 20 export reads ─
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select is(
  (select count(*)::int from (
     select stripe_connect_account_id from instructor_payout_accounts
      where user_id = '9ac70000-0000-0000-0000-000000000001') p),
  1,
  'service_role keeps the table grant — both export rails read the row with select *'
);

select * from finish();
rollback;
