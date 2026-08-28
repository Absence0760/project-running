-- Pins migration 20270213_001 (fundraising) donation-ledger integrity:
--   * donations writes are SERVICE-ROLE ONLY — a user-JWT cannot insert a
--     donation nor flip its status (the event_orders lock pattern);
--   * the service role (the donation webhook) CAN move status;
--   * the fundraiser_feed RPC returns only PAID rows, public-safe columns, and
--     honours is_anonymous (donor display_name hidden) + anchor visibility;
--   * fundraiser_totals sums only paid donations;
--   * a PARTIAL refund is representable (20270620_001) — the thermometer and
--     the feed both report what the charity KEPT, and the refunded amount is
--     bounded, coupled to the status, and writable only by the webhook;
--   * a donor's checkout idempotency key (20270620000002) can identify at most
--     one donation, so a retry resolves to the attempt already open rather
--     than opening a second one the donor could also pay.

begin;
select plan(20);

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

-- ── a partial refund is representable, and both public numbers net it ────────
-- 20270620_001. Before it, `donations` had no partially-refunded state and no
-- refunded-amount column, so a 12.00 refund on a 100.00 donation could only be
-- recorded as the whole donation coming back (erasing 100.00 from the
-- thermometer) or as nothing coming back (overstating by 12.00). decisions
-- § 769 took the second; this pins the third answer.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into donations (id, fundraiser_id, owner_user_id, display_name, message,
                       amount_cents, status, refunded_cents, is_anonymous, paid_at)
values
  ('fd000000-0000-0000-0000-0000000000d4', 'fd000000-0000-0000-0000-0000000000f1',
   'fd000000-0000-0000-0000-000000000001', 'Partly P.', 'Some came back',
   10000, 'partially_refunded', 1200, false, now()),
  ('fd000000-0000-0000-0000-0000000000d5', 'fd000000-0000-0000-0000-0000000000f1',
   'fd000000-0000-0000-0000-000000000001', 'Whole W.', 'All came back',
   4000, 'refunded', 4000, false, now());

-- The row the idempotency-key assertions at the foot of this file collide
-- with. Pending, so it is invisible to the totals and feed assertions above.
insert into donations (id, fundraiser_id, owner_user_id, amount_cents, status,
                       client_request_id)
values ('fd000000-0000-0000-0000-0000000000d6', 'fd000000-0000-0000-0000-0000000000f1',
        'fd000000-0000-0000-0000-000000000001', 2500, 'pending',
        'fd000000-0000-0000-0000-0000000000c1');

select is(
  (select raised_cents::int from fundraiser_totals('fd000000-0000-0000-0000-0000000000f1')),
  16300,
  'fundraiser_totals nets the refunded part (2500 + 5000 + 10000 - 1200), and a '
  'fully refunded donation adds nothing'
);
select is(
  (select donor_count::int from fundraiser_totals('fd000000-0000-0000-0000-0000000000f1')),
  3,
  'a partially refunded donor is still a donor; a fully refunded one is not'
);

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select count(*)::int from fundraiser_feed('fd000000-0000-0000-0000-0000000000f1', 50)),
  3,
  'fundraiser_feed keeps a partially refunded donation and drops a fully refunded one'
);
select is(
  (select count(*)::int from fundraiser_feed('fd000000-0000-0000-0000-0000000000f1', 50)
     where amount_cents = 10000),
  0,
  'fundraiser_feed never shows the GROSS amount of a partially refunded donation'
);
select is(
  (select count(*)::int from fundraiser_feed('fd000000-0000-0000-0000-0000000000f1', 50)
     where amount_cents = 8800),
  1,
  'fundraiser_feed shows what the charity kept (10000 - 1200)'
);

-- ── the refunded amount is bounded and coupled to the status ─────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select throws_ok(
  $$ update donations set refunded_cents = 20000
       where id = 'fd000000-0000-0000-0000-0000000000d4' $$,
  '23514',
  'new row for relation "donations" violates check constraint "donations_refunded_range_check"',
  'more cannot come back than went in'
);

select throws_ok(
  $$ update donations set refunded_cents = 0
       where id = 'fd000000-0000-0000-0000-0000000000d4' $$,
  '23514',
  'new row for relation "donations" violates check constraint "donations_partial_refund_check"',
  'a partially refunded donation cannot claim nothing came back'
);

-- Positive control: the two refusals above are their own constraints firing on
-- a row that exists, not the UPDATE matching nothing.
select lives_ok(
  $$ update donations set refunded_cents = 9999
       where id = 'fd000000-0000-0000-0000-0000000000d4' $$,
  'a legal refunded amount on the same row is accepted'
);
update donations set refunded_cents = 1200
  where id = 'fd000000-0000-0000-0000-0000000000d4';

-- ── refunded_cents is webhook-only, like status ──────────────────────────────
-- Run as the table OWNER with an `authenticated` role claim: RLS is bypassed,
-- so the row is visible and the UPDATE genuinely reaches the row. What refuses
-- is the lock trigger itself, not an empty result set.
reset role;
set local "request.jwt.claims" = '{"role":"authenticated"}';

select throws_ok(
  $$ update donations set refunded_cents = 3000
       where id = 'fd000000-0000-0000-0000-0000000000d4' $$,
  '42501',
  'donations.refunded_cents is read-only for non-service-role callers',
  'a non-service-role caller cannot move a donation''s refunded amount'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select lives_ok(
  $$ update donations set refunded_cents = 3000
       where id = 'fd000000-0000-0000-0000-0000000000d4' $$,
  'the service role (webhook) can record a refunded amount'
);

-- ── one donation per client idempotency key ─────────────────────────────────
-- 20270620000002. Without the unique index two concurrent attempts carrying one
-- key both open a donation, and the key stops meaning anything.
select throws_ok(
  $$ insert into donations (fundraiser_id, owner_user_id, amount_cents, status, client_request_id)
     values ('fd000000-0000-0000-0000-0000000000f1',
             'fd000000-0000-0000-0000-000000000001', 2500, 'pending',
             'fd000000-0000-0000-0000-0000000000c1') $$,
  '23505',
  'duplicate key value violates unique constraint "donations_client_request_idx"',
  'a client idempotency key can identify at most one donation'
);

-- The index is partial: every row written before 20270620000002 carries a null
-- key, and nulls must not collide with each other.
select lives_ok(
  $$ insert into donations (fundraiser_id, owner_user_id, amount_cents, status)
     values ('fd000000-0000-0000-0000-0000000000f1',
             'fd000000-0000-0000-0000-000000000001', 2500, 'pending'),
            ('fd000000-0000-0000-0000-0000000000f1',
             'fd000000-0000-0000-0000-000000000001', 2500, 'pending') $$,
  'donations carrying no key do not collide with one another'
);

select * from finish();
rollback;
