-- Pins migration 20270212_001 (fundraising) donation-ledger integrity:
--   * donations writes are SERVICE-ROLE ONLY — a user-JWT cannot insert a
--     donation nor flip its status (the event_orders lock pattern);
--   * the service role (the donation webhook) CAN move status;
--   * the fundraiser_feed RPC returns only PAID rows, public-safe columns, and
--     honours is_anonymous (donor display_name hidden) + anchor visibility;
--   * fundraiser_totals sums only paid donations.

begin;
select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('fd000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'fr-owner@don.local', '', now(), now()),
  ('fd000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'fr-donor@don.local', '', now(), now());

set local role service_role;

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('fd000000-0000-0000-0000-000000000001', 'acct_test_don_owner', true);

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('fd000000-0000-0000-0000-0000000000a1',
        'fd000000-0000-0000-0000-000000000001', now(), 5000, 1500, 'app', true,
        '{"activity_type":"run"}');

insert into fundraisers (id, owner_user_id, run_id, charity_name, title, goal_cents)
values ('fd000000-0000-0000-0000-0000000000f1',
        'fd000000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-0000000000a1',
        'Charity', 'Run fundraiser', 100000);

-- A paid donation (named), a paid anonymous donation, and a pending one — all
-- written by the service role (the webhook).
insert into donations (id, fundraiser_id, owner_user_id, display_name, message,
                       amount_cents, status, is_anonymous, paid_at)
values
  ('fd000000-0000-0000-0000-0000000000d1', 'fd000000-0000-0000-0000-0000000000f1',
   'fd000000-0000-0000-0000-000000000001', 'Jane D.', 'Go go go!', 2500, 'paid', false, now()),
  ('fd000000-0000-0000-0000-0000000000d2', 'fd000000-0000-0000-0000-0000000000f1',
   'fd000000-0000-0000-0000-000000000001', 'Bob S.', 'Anonymous gift', 5000, 'paid', true, now()),
  ('fd000000-0000-0000-0000-0000000000d3', 'fd000000-0000-0000-0000-0000000000f1',
   'fd000000-0000-0000-0000-000000000001', 'Pending P.', 'Not yet', 9999, 'pending', false, null);

-- ── totals sum only paid donations ──
select is(
  (select raised_cents::int from fundraiser_totals('fd000000-0000-0000-0000-0000000000f1')),
  7500,
  'fundraiser_totals sums only paid donations (2500 + 5000)'
);
select is(
  (select donor_count::int from fundraiser_totals('fd000000-0000-0000-0000-0000000000f1')),
  2,
  'fundraiser_totals counts only paid donors'
);

-- ── a user-JWT cannot insert a donation ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"fd000000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$ insert into donations (fundraiser_id, owner_user_id, amount_cents, status)
     values ('fd000000-0000-0000-0000-0000000000f1',
             'fd000000-0000-0000-0000-000000000001', 2500, 'paid') $$,
  '42501',
  null,
  'a user-JWT cannot insert a donation'
);

-- ── a user-JWT cannot flip a donation's status ──
-- No permissive client UPDATE policy → RLS USING filter hides the row, the
-- update is a no-op; the lock trigger is the second defence layer.
update donations set status = 'refunded'
  where id = 'fd000000-0000-0000-0000-0000000000d1';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select is(
  (select status from donations where id = 'fd000000-0000-0000-0000-0000000000d1'),
  'paid',
  'a user-JWT UPDATE cannot flip donations.status (stays paid)'
);

-- Positive control: the service role (webhook) CAN move status.
select lives_ok(
  $$ update donations set status = 'refunded', refunded_at = now()
     where id = 'fd000000-0000-0000-0000-0000000000d2' $$,
  'the service role (webhook) can move a donation''s status'
);
-- restore for the feed test
update donations set status = 'paid', refunded_at = null
  where id = 'fd000000-0000-0000-0000-0000000000d2';

-- ── the feed RPC: paid-only, public-safe, anonymised ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select count(*)::int from fundraiser_feed('fd000000-0000-0000-0000-0000000000f1', 50)),
  2,
  'fundraiser_feed returns only paid donations (pending excluded)'
);

select is(
  (select display_name from fundraiser_feed('fd000000-0000-0000-0000-0000000000f1', 50)
     where amount_cents = 5000),
  null,
  'fundraiser_feed hides the display_name of an anonymous donation'
);

select is(
  (select display_name from fundraiser_feed('fd000000-0000-0000-0000-0000000000f1', 50)
     where amount_cents = 2500),
  'Jane D.',
  'fundraiser_feed surfaces a named donor''s display_name'
);

select * from finish();
rollback;
