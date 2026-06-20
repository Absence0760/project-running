-- Pins migration 20261229_001 (paid events, slice P1 — the money ledger):
--   * event_orders RLS: a buyer reads their own orders; a host (event
--     organiser) reads orders for their events; a third party reads neither.
--   * event_orders writes are SERVICE-ROLE ONLY — a user-JWT cannot insert an
--     order nor flip its status (the subscription_tier lock pattern).
--   * event_pricing requires the host to have a charges-enabled payout account
--     (trigger-enforced, not just UI) — a direct write with no charges-enabled
--     account is rejected.
--   * the paid-order-required-for-priced-going rule — a going / waitlisted row
--     on a priced event without a paid order is rejected; a free event is
--     unaffected.

begin;
select plan(12);

-- ── Fixtures: host (also club owner), buyer, stranger ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa1111-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'pe-host@evt.local', '', now(), now()),
  ('aaaa1111-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'pe-buyer@evt.local', '', now(), now()),
  ('aaaa1111-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'pe-stranger@evt.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb1111-0000-0000-0000-000000000001',
        'aaaa1111-0000-0000-0000-000000000001', 'Pilates Studio', 'pe-studio', true);

-- The club-insert trigger already seeds the owner as an active 'owner'
-- club_member, so is_event_organiser(club) is true for the host — no explicit
-- membership insert needed.

-- A priced class event hosted by the host.
insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values ('cccc1111-0000-0000-0000-000000000001',
        'bbbb1111-0000-0000-0000-000000000001', 'Reformer Pilates',
        '2026-07-01 18:00+00', 'aaaa1111-0000-0000-0000-000000000001',
        'aaaa1111-0000-0000-0000-000000000001', 'class');

-- A free social event (no pricing) for the negative side of the priced gate.
insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values ('cccc1111-0000-0000-0000-000000000002',
        'bbbb1111-0000-0000-0000-000000000001', 'Coffee Meetup',
        '2026-07-02 09:00+00', 'aaaa1111-0000-0000-0000-000000000001',
        'aaaa1111-0000-0000-0000-000000000001', 'social');

-- ── pricing requires charges_enabled ──────────────────────────────────────
-- No payout account yet → pricing the event must be rejected by the trigger.
select throws_ok(
  $$ insert into event_pricing (event_id, price_cents)
     values ('cccc1111-0000-0000-0000-000000000001', 2200) $$,
  '23514',
  null,
  'event_pricing insert is rejected when host has no charges-enabled account'
);

-- Give the host a payout account but NOT charges_enabled → still rejected.
insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('aaaa1111-0000-0000-0000-000000000001', 'acct_test_host', false);

select throws_ok(
  $$ insert into event_pricing (event_id, price_cents)
     values ('cccc1111-0000-0000-0000-000000000001', 2200) $$,
  '23514',
  null,
  'event_pricing insert is rejected when host account is not charges-enabled'
);

-- Flip charges_enabled on → pricing now succeeds.
update instructor_payout_accounts set charges_enabled = true
  where user_id = 'aaaa1111-0000-0000-0000-000000000001';

select lives_ok(
  $$ insert into event_pricing (event_id, price_cents, platform_fee_bps)
     values ('cccc1111-0000-0000-0000-000000000001', 2200, 500) $$,
  'event_pricing insert succeeds once host is charges-enabled'
);

-- ── a paid order, written by service role ──────────────────────────────────
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
values ('dddd1111-0000-0000-0000-000000000001',
        'cccc1111-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
        'aaaa1111-0000-0000-0000-000000000002', 'aaaa1111-0000-0000-0000-000000000001',
        2200, 110, 'paid', now());

-- A second pending order belonging to the stranger, to prove read scoping.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, status)
values ('dddd1111-0000-0000-0000-000000000002',
        'cccc1111-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
        'aaaa1111-0000-0000-0000-000000000003', 'aaaa1111-0000-0000-0000-000000000001',
        2200, 'pending');

-- ── paid-order-required-for-priced-going rule ──────────────────────────────
-- Going on the priced event WITHOUT an order → rejected.
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status)
     values ('cccc1111-0000-0000-0000-000000000001',
             'aaaa1111-0000-0000-0000-000000000002', '2026-07-01 18:00+00', 'going') $$,
  '23514',
  null,
  'going on a priced event without a paid order is rejected'
);

-- Going on the priced event WITH the buyer's paid order → succeeds.
select lives_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status, order_id)
     values ('cccc1111-0000-0000-0000-000000000001',
             'aaaa1111-0000-0000-0000-000000000002', '2026-07-01 18:00+00', 'going',
             'dddd1111-0000-0000-0000-000000000001') $$,
  'going on a priced event with a matching paid order succeeds'
);

-- A free event needs no order.
select lives_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status)
     values ('cccc1111-0000-0000-0000-000000000002',
             'aaaa1111-0000-0000-0000-000000000002', '2026-07-02 09:00+00', 'going') $$,
  'going on a free event needs no order'
);

-- ── RLS: order read scoping ────────────────────────────────────────────────
-- Buyer reads their own order, not the stranger's.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa1111-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from event_orders),
  1,
  'buyer sees exactly their own order (RLS hides the stranger''s)'
);

-- Host (event organiser) reads ALL orders for their event.
set local "request.jwt.claims" = '{"sub":"aaaa1111-0000-0000-0000-000000000001","role":"authenticated"}';

select is(
  (select count(*)::int from event_orders),
  2,
  'event organiser sees every order for their events'
);

-- ── RLS: a user-JWT cannot write order status ──────────────────────────────
-- Buyer tries to flip their own pending... they own the paid order; try to
-- mark a fresh insert. First, an INSERT attempt as the buyer is rejected (no
-- permissive client policy + the service-role lock trigger).
set local "request.jwt.claims" = '{"sub":"aaaa1111-0000-0000-0000-000000000002","role":"authenticated"}';

select throws_ok(
  $$ insert into event_orders (event_id, instance_start, buyer_user_id, host_user_id,
                               amount_cents, status)
     values ('cccc1111-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
             'aaaa1111-0000-0000-0000-000000000002', 'aaaa1111-0000-0000-0000-000000000001',
             2200, 'paid') $$,
  '42501',
  null,
  'a user-JWT cannot insert an event_orders row'
);

-- And the buyer cannot flip the status of the order they can read. Slice P2
-- (20270303_001) added a buyer UPDATE policy scoped to refund_initiated_at on
-- their own paid order, so the row is now VISIBLE to the UPDATE's RLS filter —
-- but the lock_event_order_status trigger rejects the status change with 42501.
-- The invariant under test is unchanged (a user-JWT cannot move order status);
-- the outcome is now an explicit throw rather than a silent zero-row no-op.
select throws_ok(
  $$ update event_orders set status = 'refunded'
     where id = 'dddd1111-0000-0000-0000-000000000001' $$,
  '42501',
  null,
  'a user-JWT UPDATE cannot flip event_orders.status (trigger rejects)'
);

-- Re-read as service role to confirm the status is untouched. Reset the JWT
-- claims to the service role too — a lingering authenticated claims blob would
-- otherwise drive the lock trigger's role detection (it reads
-- request.jwt.claims, not just the SQL role).
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select is(
  (select status from event_orders where id = 'dddd1111-0000-0000-0000-000000000001'),
  'paid',
  'event_orders.status stays paid after the rejected user-JWT UPDATE'
);

-- Positive control: the service role (the webhook) CAN move status — the lock
-- is targeted at non-service callers, not a blanket freeze on the ledger.
select lives_ok(
  $$ update event_orders set status = 'refunded', refunded_at = now()
     where id = 'dddd1111-0000-0000-0000-000000000001' $$,
  'the service role (webhook) can move an order''s status'
);

select * from finish();
rollback;
