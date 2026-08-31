-- Pins migration 20270624000001 (decisions § 789): a refund that FAILS is a
-- state of its own on both money ledgers.
--
-- Stripe emits `charge.refunded` when a refund is CREATED, including one whose
-- status is still `pending`, so the webhook has already moved the order to
-- `refunded` and deleted the buyer's seat by the time the bank can reject it.
-- `refund_failed` says what is then true: the registration is gone and the
-- money never reached the payer. § 789 shipped it with no pgtap at all — the
-- round did not hold the local stack — so every claim it makes about the
-- database is pinned here:
--
--   * both ledgers' status CHECK admits the value and still refuses an
--     unknown one (the widening is an allowlist edit, not an opening);
--   * enforce_paid_order_for_priced_event excludes it, on INSERT and on the
--     re-validating UPDATE, for `going` and for `waitlisted`, while
--     `partially_refunded` keeps its seat;
--   * the buyer-cancel RLS policy excludes it, so the failed order offers no
--     second automated refund at a rail Stripe has said cannot deliver;
--   * nothing re-seats the buyer, and the waitlisted runner who took the
--     released seat keeps it;
--   * fundraiser_totals and fundraiser_feed exclude it — the money is owed
--     back out, not raised.
--
-- fundraiser_totals / fundraiser_feed are called as `anon`, the public
-- thermometer's real caller. Calling them as service_role is what makes
-- donations_status_lock_test fail on a workstation CLI image (decisions § 799).

begin;
select plan(29);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('4efd0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'rf-host@evt.local', '', now(), now()),
  ('4efd0000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'rf-paid@evt.local', '', now(), now()),
  ('4efd0000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'rf-part@evt.local', '', now(), now()),
  ('4efd0000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'rf-failed@evt.local', '', now(), now()),
  ('4efd0000-0000-0000-0000-000000000005', 'authenticated', 'authenticated',
   'rf-refunded@evt.local', '', now(), now()),
  ('4efd0000-0000-0000-0000-000000000006', 'authenticated', 'authenticated',
   'rf-next@evt.local', '', now(), now());

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('4efd0000-0000-0000-0000-000000000001', 'acct_test_rf_host', true);

insert into clubs (id, owner_id, name, slug, is_public)
values ('4efd0000-0000-0000-0000-0000000000c1',
        '4efd0000-0000-0000-0000-000000000001', 'Refund Studio', 'rf-studio', true);

-- E1 is uncapped, so the seat-gate assertions cannot be confused with a
-- capacity demotion. E2 has capacity 1 and carries the waitlist scenario.
insert into events (id, club_id, title, starts_at, author_id, host_user_id, category, capacity)
values
  ('4efd0000-0000-0000-0000-0000000000e1',
   '4efd0000-0000-0000-0000-0000000000c1', 'Reformer Pilates',
   '2026-07-01 18:00+00', '4efd0000-0000-0000-0000-000000000001',
   '4efd0000-0000-0000-0000-000000000001', 'class', null),
  ('4efd0000-0000-0000-0000-0000000000e2',
   '4efd0000-0000-0000-0000-0000000000c1', 'Barre (one mat)',
   '2026-07-02 18:00+00', '4efd0000-0000-0000-0000-000000000001',
   '4efd0000-0000-0000-0000-000000000001', 'class', 1);

insert into event_pricing (event_id, price_cents, platform_fee_bps)
values ('4efd0000-0000-0000-0000-0000000000e1', 2200, 500),
       ('4efd0000-0000-0000-0000-0000000000e2', 2200, 500);

-- One order per buyer, so the trigger's (buyer, event, instance) match is
-- satisfied by construction and only `status` decides the verdict.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at, refunded_at)
values
  ('4efd0000-0000-0000-0000-0000000000a1', '4efd0000-0000-0000-0000-0000000000e1',
   '2026-07-01 18:00+00', '4efd0000-0000-0000-0000-000000000002',
   '4efd0000-0000-0000-0000-000000000001', 2200, 110, 'paid', now(), null),
  ('4efd0000-0000-0000-0000-0000000000a2', '4efd0000-0000-0000-0000-0000000000e1',
   '2026-07-01 18:00+00', '4efd0000-0000-0000-0000-000000000003',
   '4efd0000-0000-0000-0000-000000000001', 2200, 110, 'partially_refunded', now(), null),
  ('4efd0000-0000-0000-0000-0000000000a3', '4efd0000-0000-0000-0000-0000000000e1',
   '2026-07-01 18:00+00', '4efd0000-0000-0000-0000-000000000004',
   '4efd0000-0000-0000-0000-000000000001', 2200, 110, 'refunded', now(), now()),
  ('4efd0000-0000-0000-0000-0000000000a4', '4efd0000-0000-0000-0000-0000000000e1',
   '2026-07-01 18:00+00', '4efd0000-0000-0000-0000-000000000005',
   '4efd0000-0000-0000-0000-000000000001', 2200, 110, 'refunded', now(), now()),
  ('4efd0000-0000-0000-0000-0000000000b1', '4efd0000-0000-0000-0000-0000000000e2',
   '2026-07-02 18:00+00', '4efd0000-0000-0000-0000-000000000002',
   '4efd0000-0000-0000-0000-000000000001', 2200, 110, 'paid', now(), null),
  ('4efd0000-0000-0000-0000-0000000000b2', '4efd0000-0000-0000-0000-0000000000e2',
   '2026-07-02 18:00+00', '4efd0000-0000-0000-0000-000000000006',
   '4efd0000-0000-0000-0000-000000000001', 2200, 110, 'paid', now(), null);

-- ── 1. the status vocabulary ────────────────────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select lives_ok(
  $$ update event_orders set status = 'refund_failed'
      where id = '4efd0000-0000-0000-0000-0000000000a3' $$,
  'event_orders_status_check admits refund_failed'
);

select throws_ok(
  $$ update event_orders set status = 'refund_reversed'
      where id = '4efd0000-0000-0000-0000-0000000000a3' $$,
  '23514',
  null,
  'event_orders_status_check still refuses a status outside its allowlist'
);

-- ── 2. the seat predicate refuses it on INSERT ──────────────────────────────
reset role;

select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status, order_id)
     values ('4efd0000-0000-0000-0000-0000000000e1',
             '4efd0000-0000-0000-0000-000000000004', '2026-07-01 18:00+00', 'going',
             '4efd0000-0000-0000-0000-0000000000a3') $$,
  '23514',
  null,
  'a refund_failed order cannot seat a going attendee'
);

select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status, order_id)
     values ('4efd0000-0000-0000-0000-0000000000e1',
             '4efd0000-0000-0000-0000-000000000004', '2026-07-01 18:00+00', 'waitlisted',
             '4efd0000-0000-0000-0000-0000000000a3') $$,
  '23514',
  null,
  'a refund_failed order cannot hold a waitlisted place either'
);

select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status, order_id)
     values ('4efd0000-0000-0000-0000-0000000000e1',
             '4efd0000-0000-0000-0000-000000000005', '2026-07-01 18:00+00', 'going',
             '4efd0000-0000-0000-0000-0000000000a4') $$,
  '23514',
  null,
  'a refunded order cannot seat a going attendee (the state refund_failed comes from)'
);

select lives_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status, order_id)
     values ('4efd0000-0000-0000-0000-0000000000e1',
             '4efd0000-0000-0000-0000-000000000003', '2026-07-01 18:00+00', 'going',
             '4efd0000-0000-0000-0000-0000000000a2') $$,
  'a partially_refunded order still seats its attendee (20270522_001 stands)'
);

select is(
  (select count(*)::int from event_attendees
    where event_id = '4efd0000-0000-0000-0000-0000000000e1'),
  1,
  'only the partially_refunded buyer holds a seat on the priced event'
);

-- ── 3. the gate re-validates on UPDATE ──────────────────────────────────────
-- `before insert or update` with no WHEN clause, so an attendance-only write
-- re-runs it. The order's status can move under a seat that already exists.
insert into event_attendees (event_id, user_id, instance_start, status, order_id)
values ('4efd0000-0000-0000-0000-0000000000e1',
        '4efd0000-0000-0000-0000-000000000002', '2026-07-01 18:00+00', 'going',
        '4efd0000-0000-0000-0000-0000000000a1');

select lives_ok(
  $$ update event_attendees set attendance = 'attended'
      where event_id = '4efd0000-0000-0000-0000-0000000000e1'
        and user_id = '4efd0000-0000-0000-0000-000000000002' $$,
  'the host can mark a paid attendee present'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update event_orders set status = 'refund_failed', refunded_at = now()
  where id = '4efd0000-0000-0000-0000-0000000000a1';
reset role;

select throws_ok(
  $$ update event_attendees set attendance = 'no_show'
      where event_id = '4efd0000-0000-0000-0000-0000000000e1'
        and user_id = '4efd0000-0000-0000-0000-000000000002' $$,
  '23514',
  null,
  'once the order reads refund_failed the seat no longer re-validates'
);

-- ── 4. nothing re-seats the buyer, and the promoted runner keeps the mat ────
-- E2 seats one. The buyer cancels: the webhook deletes their going row, the
-- waitlisted runner is promoted, and only then does the refund fail.
insert into event_attendees (event_id, user_id, instance_start, status, order_id)
values ('4efd0000-0000-0000-0000-0000000000e2',
        '4efd0000-0000-0000-0000-000000000002', '2026-07-02 18:00+00', 'going',
        '4efd0000-0000-0000-0000-0000000000b1'),
       ('4efd0000-0000-0000-0000-0000000000e2',
        '4efd0000-0000-0000-0000-000000000006', '2026-07-02 18:00+00', 'waitlisted',
        '4efd0000-0000-0000-0000-0000000000b2');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update event_orders set status = 'refunded', refunded_at = now()
  where id = '4efd0000-0000-0000-0000-0000000000b1';
reset role;
delete from event_attendees
 where event_id = '4efd0000-0000-0000-0000-0000000000e2'
   and user_id = '4efd0000-0000-0000-0000-000000000002';

select is(
  (select status from event_attendees
    where event_id = '4efd0000-0000-0000-0000-0000000000e2'
      and user_id = '4efd0000-0000-0000-0000-000000000006'),
  'going',
  'releasing the seat promoted the waitlisted runner'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update event_orders set status = 'refund_failed'
  where id = '4efd0000-0000-0000-0000-0000000000b1';
reset role;

select is(
  (select status from event_attendees
    where event_id = '4efd0000-0000-0000-0000-0000000000e2'
      and user_id = '4efd0000-0000-0000-0000-000000000006'),
  'going',
  'the failed refund does not take the promoted runner''s seat back'
);

select is(
  (select count(*)::int from event_attendees
    where event_id = '4efd0000-0000-0000-0000-0000000000e2'
      and user_id = '4efd0000-0000-0000-0000-000000000002'),
  0,
  'nothing re-seats the buyer when their refund fails'
);

-- ── 5. the buyer-cancel policy excludes it ──────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update event_orders set refund_initiated_at = '2026-06-30 00:00+00'
  where id in ('4efd0000-0000-0000-0000-0000000000a1',
               '4efd0000-0000-0000-0000-0000000000a2');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"4efd0000-0000-0000-0000-000000000003","role":"authenticated"}';

select lives_ok(
  $$ update event_orders set refund_initiated_at = '2099-01-01 00:00+00'
      where id = '4efd0000-0000-0000-0000-0000000000a2' $$,
  'a buyer can still stamp a partially_refunded order (control for the policy''s IN-list)'
);

set local "request.jwt.claims" = '{"sub":"4efd0000-0000-0000-0000-000000000002","role":"authenticated"}';
update event_orders set refund_initiated_at = '2099-01-01 00:00+00'
  where id = '4efd0000-0000-0000-0000-0000000000a1';

-- A no-op on the real policy: the row is outside its USING, so zero rows
-- change and the status lock trigger is never reached. Wrapped so that a
-- policy widened to admit refund_failed reports itself here — the trigger
-- raises 42501 the moment the row becomes visible — rather than aborting the
-- file at an unnamed statement.
select lives_ok(
  $$ update event_orders set status = 'paid'
      where id = '4efd0000-0000-0000-0000-0000000000a1' $$,
  'a refund_failed order is outside the buyer-cancel policy, so the flip touches no row'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select is(
  (select refund_initiated_at from event_orders
    where id = '4efd0000-0000-0000-0000-0000000000a2'),
  '2099-01-01 00:00+00'::timestamptz,
  'the partially_refunded buyer''s stamp landed'
);

select is(
  (select refund_initiated_at from event_orders
    where id = '4efd0000-0000-0000-0000-0000000000a1'),
  '2026-06-30 00:00+00'::timestamptz,
  'the buyer cannot re-request a refund on their refund_failed order'
);

select is(
  (select status from event_orders where id = '4efd0000-0000-0000-0000-0000000000a1'),
  'refund_failed',
  'the buyer cannot walk their refund_failed order back to paid'
);

-- ── 6. the donation ledger ──────────────────────────────────────────────────
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('4efd0000-0000-0000-0000-0000000000f0',
        '4efd0000-0000-0000-0000-000000000001', now(), 5000, 1500, 'app', true,
        '{"activity_type":"run"}');

insert into fundraisers (id, owner_user_id, run_id, charity_name, title, goal_cents)
values ('4efd0000-0000-0000-0000-0000000000f1',
        '4efd0000-0000-0000-0000-000000000001', '4efd0000-0000-0000-0000-0000000000f0',
        'Charity', 'Refund fundraiser', 100000);

-- d3 is the reconciliation cohort 20270620_001's header names: a row whose
-- refunded amount was never recorded. It is the one that separates "excluded"
-- from "netted to zero" — d2 nets to zero on its own, so a filter widened to
-- admit refund_failed would leave the thermometer unmoved on d2 alone.
insert into donations (id, fundraiser_id, owner_user_id, display_name, message,
                       amount_cents, status, is_anonymous, paid_at)
values
  ('4efd0000-0000-0000-0000-0000000000d1', '4efd0000-0000-0000-0000-0000000000f1',
   '4efd0000-0000-0000-0000-000000000001', 'Kept K.', 'Stays', 2500, 'paid', false, now()),
  ('4efd0000-0000-0000-0000-0000000000d2', '4efd0000-0000-0000-0000-0000000000f1',
   '4efd0000-0000-0000-0000-000000000001', 'Reversed R.', 'Bank said no', 7000, 'paid', false, now()),
  ('4efd0000-0000-0000-0000-0000000000d3', '4efd0000-0000-0000-0000-0000000000f1',
   '4efd0000-0000-0000-0000-000000000001', 'Unrecorded U.', 'Amount unknown', 4000, 'paid', false, now());

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select raised_cents::int from fundraiser_totals('4efd0000-0000-0000-0000-0000000000f1')),
  13500,
  'all three donations count while all three are paid'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select lives_ok(
  $$ update donations set status = 'refunded', refunded_cents = 7000
      where id = '4efd0000-0000-0000-0000-0000000000d2' $$,
  'the webhook records the full refund'
);

select lives_ok(
  $$ update donations set status = 'refund_failed'
      where id = '4efd0000-0000-0000-0000-0000000000d2' $$,
  'donations_status_check admits refund_failed'
);

select throws_ok(
  $$ update donations set status = 'refund_reversed'
      where id = '4efd0000-0000-0000-0000-0000000000d2' $$,
  '23514',
  null,
  'donations_status_check still refuses a status outside its allowlist'
);

select throws_ok(
  $$ update donations set refunded_cents = 7001
      where id = '4efd0000-0000-0000-0000-0000000000d2' $$,
  '23514',
  null,
  'a refund_failed row still cannot report more refunded than was given'
);

select lives_ok(
  $$ update donations set status = 'refunded', refunded_cents = 0
      where id = '4efd0000-0000-0000-0000-0000000000d3' $$,
  'a refunded row may carry no recorded amount (the pre-20270620_001 cohort)'
);

select lives_ok(
  $$ update donations set status = 'refund_failed'
      where id = '4efd0000-0000-0000-0000-0000000000d3' $$,
  'a refund_failed row may carry no recorded amount either (the partial-refund CHECK does not reach it)'
);

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select raised_cents::int from fundraiser_totals('4efd0000-0000-0000-0000-0000000000f1')),
  2500,
  'a refund_failed donation is excluded from raised_cents (the money is owed back out, not raised)'
);

select is(
  (select donor_count::int from fundraiser_totals('4efd0000-0000-0000-0000-0000000000f1')),
  1,
  'a refund_failed donation is excluded from donor_count'
);

-- The feed's amounts are pinned as a SET rather than as a count of the absent
-- one: a read that returned nothing satisfies the second and not the first
-- (decisions § 778).
select is(
  (select array_agg(amount_cents order by amount_cents)
     from fundraiser_feed('4efd0000-0000-0000-0000-0000000000f1', 50)),
  array[2500],
  'fundraiser_feed carries the kept donation and not the reversed one'
);

-- ── 7. no client role can open or move a refund_failed ledger row ───────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"4efd0000-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$ insert into donations (fundraiser_id, owner_user_id, amount_cents, status)
     values ('4efd0000-0000-0000-0000-0000000000f1',
             '4efd0000-0000-0000-0000-000000000001', 100, 'refund_failed') $$,
  '42501',
  null,
  'an authenticated caller cannot open a refund_failed donation'
);

select throws_ok(
  $$ insert into event_orders (event_id, instance_start, buyer_user_id, host_user_id,
                               amount_cents, status)
     values ('4efd0000-0000-0000-0000-0000000000e1', '2026-07-01 18:00+00',
             '4efd0000-0000-0000-0000-000000000002',
             '4efd0000-0000-0000-0000-000000000001', 2200, 'refund_failed') $$,
  '42501',
  null,
  'an authenticated caller cannot open a refund_failed event order'
);

select * from finish();
rollback;
