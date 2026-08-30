-- Pins migration 20270623_001 (the refund that failed, decisions § 789):
--   * `event_orders_status_check` admits `refund_failed`, and still refuses a
--     status nobody defined,
--   * `refund_failed` does NOT back a seat — the invariant the webhook's
--     refusal to silently re-seat rests on, since a re-insert would have to
--     get past this trigger,
--   * the buyer self-cancel UPDATE policy does not admit a `refund_failed`
--     order (there is nothing left to cancel — the seat is already gone),
--   * the service role can still move it on when a re-issued refund lands.
--
-- Every claim is paired with the same claim against a `paid` order, so a
-- fixture that silently failed to build cannot pass as a refusal.

begin;
select plan(8);

-- ── Fixtures: host (club owner) + buyer ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa6230-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'rf-host@evt.local', '', now(), now()),
  ('aaaa6230-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'rf-buyer@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb6230-0000-0000-0000-000000000001',
        'aaaa6230-0000-0000-0000-000000000001', 'Studio RF', 'rf-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values ('cccc6230-0000-0000-0000-000000000001',
        'bbbb6230-0000-0000-0000-000000000001', 'Reformer Pilates',
        '2026-07-01 18:00+00', 'aaaa6230-0000-0000-0000-000000000001',
        'aaaa6230-0000-0000-0000-000000000001', 'class');

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('aaaa6230-0000-0000-0000-000000000001', 'acct_test_rf_host', true);

insert into event_pricing (event_id, price_cents, platform_fee_bps)
values ('cccc6230-0000-0000-0000-000000000001', 2200, 500);

-- Two orders for the same buyer on two occurrences: one that will be walked
-- through the failed-refund path, one that stays paid as the control.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at, refunded_at)
values
  ('dddd6230-0000-0000-0000-000000000001',
   'cccc6230-0000-0000-0000-000000000001', '2026-07-01 18:00+00',
   'aaaa6230-0000-0000-0000-000000000002', 'aaaa6230-0000-0000-0000-000000000001',
   2200, 110, 'refunded', now(), now()),
  ('dddd6230-0000-0000-0000-000000000002',
   'cccc6230-0000-0000-0000-000000000001', '2026-07-08 18:00+00',
   'aaaa6230-0000-0000-0000-000000000002', 'aaaa6230-0000-0000-0000-000000000001',
   2200, 110, 'paid', now(), null);

-- ── the status value exists ────────────────────────────────────────────────
select lives_ok(
  $$ update event_orders set status = 'refund_failed', refunded_at = null
      where id = 'dddd6230-0000-0000-0000-000000000001' $$,
  'the webhook can CAS a refunded order to refund_failed'
);

select throws_ok(
  $$ update event_orders set status = 'refund_bounced'
      where id = 'dddd6230-0000-0000-0000-000000000001' $$,
  '23514',
  null,
  'the widened CHECK still refuses a status nobody defined'
);

-- ── refund_failed backs no seat ────────────────────────────────────────────
-- This is what makes the webhook's refusal to re-seat a property of the schema
-- rather than of one handler: `enforce_paid_order_for_priced_event` accepts
-- only ('paid', 'partially_refunded'), so a re-insert could not succeed even
-- if some future caller tried it.
select throws_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status, order_id)
     values ('cccc6230-0000-0000-0000-000000000001',
             'aaaa6230-0000-0000-0000-000000000002', '2026-07-01 18:00+00', 'going',
             'dddd6230-0000-0000-0000-000000000001') $$,
  '23514',
  null,
  'a refund_failed order cannot seat the buyer whose refund was rejected'
);

-- The positive control on the same trigger, same buyer, same event: the paid
-- order for the other occurrence seats normally, so the refusal above is about
-- the status and not about a fixture that never built.
select lives_ok(
  $$ insert into event_attendees (event_id, user_id, instance_start, status, order_id)
     values ('cccc6230-0000-0000-0000-000000000001',
             'aaaa6230-0000-0000-0000-000000000002', '2026-07-08 18:00+00', 'going',
             'dddd6230-0000-0000-0000-000000000002') $$,
  'a paid order still seats its own occurrence'
);

-- ── the buyer cannot self-cancel what is already gone ──────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa6230-0000-0000-0000-000000000002","role":"authenticated"}';

update event_orders set refund_initiated_at = now()
 where id = 'dddd6230-0000-0000-0000-000000000001';

update event_orders set refund_initiated_at = now()
 where id = 'dddd6230-0000-0000-0000-000000000002';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select is(
  (select refund_initiated_at is null from event_orders
    where id = 'dddd6230-0000-0000-0000-000000000001'),
  true,
  'the buyer''s refund-request stamp does not land on a refund_failed order'
);

select is(
  (select refund_initiated_at is not null from event_orders
    where id = 'dddd6230-0000-0000-0000-000000000002'),
  true,
  'the same stamp from the same buyer lands on their paid order'
);

-- ── a re-issued refund can still finish the job ────────────────────────────
select lives_ok(
  $$ update event_orders set status = 'refunded', refunded_at = now()
      where id = 'dddd6230-0000-0000-0000-000000000001' $$,
  'a re-issued refund moves a refund_failed order to refunded'
);

select is(
  (select status from event_orders where id = 'dddd6230-0000-0000-0000-000000000001'),
  'refunded',
  'the re-issued refund is what the ledger ends up saying'
);

select * from finish();
rollback;
