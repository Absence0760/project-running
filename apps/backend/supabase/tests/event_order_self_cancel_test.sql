-- Pins migration 20270303_001 (paid events, slice P2 — buyer self-cancel +
-- refund coupling):
--   * a buyer CAN stamp refund_initiated_at on their OWN paid order (the
--     "refund requested" mark the events-cancel EF writes before the
--     charge.refunded webhook confirms),
--   * a buyer CANNOT flip status via that same UPDATE (the webhook stays the
--     sole status writer),
--   * a buyer CANNOT touch any other ledger column (amount_cents, etc.) under
--     the new policy,
--   * a buyer CANNOT stamp another buyer's order,
--   * a buyer CANNOT stamp a still-pending order (policy is scoped to 'paid'),
--   * the service role (the webhook) still moves status freely.

begin;
select plan(7);

-- ── Fixtures: host (club owner), buyer, stranger ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa3303-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'sc-host@evt.local', '', now(), now()),
  ('aaaa3303-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'sc-buyer@evt.local', '', now(), now()),
  ('aaaa3303-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'sc-stranger@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb3303-0000-0000-0000-000000000001',
        'aaaa3303-0000-0000-0000-000000000001', 'Studio P2', 'sc-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values ('cccc3303-0000-0000-0000-000000000001',
        'bbbb3303-0000-0000-0000-000000000001', 'Reformer Pilates',
        '2026-07-01 18:00+00', 'aaaa3303-0000-0000-0000-000000000001',
        'aaaa3303-0000-0000-0000-000000000001', 'class');

-- The buyer's PAID order, and a PENDING order (to prove the policy is
-- scoped to 'paid').
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
values
  ('dddd3303-0000-0000-0000-000000000001',
   'cccc3303-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa3303-0000-0000-0000-000000000002', 'aaaa3303-0000-0000-0000-000000000001',
   2200, 110, 'paid', now()),
  ('dddd3303-0000-0000-0000-000000000002',
   'cccc3303-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa3303-0000-0000-0000-000000000002', 'aaaa3303-0000-0000-0000-000000000001',
   2200, 110, 'pending', null);

-- ── as the BUYER ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa3303-0000-0000-0000-000000000002","role":"authenticated"}';

-- The buyer CAN stamp refund_initiated_at on their own paid order.
select lives_ok(
  $$ update event_orders set refund_initiated_at = now()
     where id = 'dddd3303-0000-0000-0000-000000000001' $$,
  'buyer can stamp refund_initiated_at on their own paid order'
);

-- The buyer CANNOT flip status (the trigger rejects the status change even
-- though the row is visible to the buyer UPDATE policy).
select throws_ok(
  $$ update event_orders set status = 'refunded'
     where id = 'dddd3303-0000-0000-0000-000000000001' $$,
  '42501',
  null,
  'buyer cannot flip event_orders.status (webhook is sole status writer)'
);

-- The buyer CANNOT alter any other ledger column (amount) — even though the
-- row is theirs and paid, the trigger blocks every column except the stamp.
select throws_ok(
  $$ update event_orders set amount_cents = 1
     where id = 'dddd3303-0000-0000-0000-000000000001' $$,
  '42501',
  null,
  'buyer cannot alter amount_cents (only refund_initiated_at is buyer-writable)'
);

-- The buyer CANNOT stamp a still-PENDING order (policy USING is status='paid').
-- The row is invisible to the UPDATE's RLS filter -> zero rows change (silent
-- no-op), so refund_initiated_at stays null. Assert the OUTCOME.
update event_orders set refund_initiated_at = now()
  where id = 'dddd3303-0000-0000-0000-000000000002';

-- ── as the STRANGER ──
set local "request.jwt.claims" = '{"sub":"aaaa3303-0000-0000-0000-000000000003","role":"authenticated"}';

-- A stranger cannot stamp the buyer's order (row invisible to the policy USING
-- buyer_user_id = auth.uid()) -> silent no-op. Assert via service-role re-read.
update event_orders set refund_initiated_at = '1999-01-01'
  where id = 'dddd3303-0000-0000-0000-000000000001';

-- ── re-read as service role ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select is(
  (select status from event_orders where id = 'dddd3303-0000-0000-0000-000000000001'),
  'paid',
  'the buyer''s status-flip + amount edits never landed (stays paid)'
);

select isnt(
  (select refund_initiated_at from event_orders where id = 'dddd3303-0000-0000-0000-000000000001'),
  '1999-01-01'::timestamptz,
  'a stranger''s stamp on the buyer''s order never landed'
);

select is(
  (select refund_initiated_at from event_orders where id = 'dddd3303-0000-0000-0000-000000000002'),
  null::timestamptz,
  'the pending order''s refund stamp never landed (policy scoped to paid)'
);

-- Positive control: the service role (the webhook) still moves status freely.
select lives_ok(
  $$ update event_orders set status = 'refunded', refunded_at = now()
     where id = 'dddd3303-0000-0000-0000-000000000001' $$,
  'the service role (webhook) can move an order''s status to refunded'
);

select * from finish();
rollback;
