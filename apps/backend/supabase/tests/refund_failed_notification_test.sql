-- Pins migration 20270701000001 (decisions § 825): the person the money is
-- owed to is told, on both ledgers.
--
-- § 789 gave a bank-reversed refund an honest terminal status and an operator
-- worklist. It gave it no reader — from the buyer's side the registration just
-- vanished and the refund never arrived. The repair is one notifications row,
-- because that one row is what the AFTER-INSERT fan-out turns into the inbox
-- entry, the email and both pushes; and because on the DONATION ledger it is
-- the only surface that can exist at all (`donations` has no client SELECT
-- policy, so a donor cannot read their own row anywhere).
--
-- Four properties, and three of them are about NOT announcing:
--
--   * the transition into refund_failed announces exactly once, on each ledger;
--   * an UPDATE that does not move the status announces nothing — that is the
--     replay guard, since the webhook CASes against the status it read and a
--     redelivery therefore updates no row;
--   * an anonymous donation (donor_user_id null) announces nothing AND does
--     not abort the ledger move with a 23502 it would drag the CAS down with;
--   * the order arm carries event_id + instance_start so the CTA can reach the
--     event page, and the donation arm carries neither.

begin;
select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('4efe0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'rfn-host@evt.local', '', now(), now()),
  ('4efe0000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'rfn-buyer@evt.local', '', now(), now()),
  ('4efe0000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'rfn-donor@evt.local', '', now(), now());

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('4efe0000-0000-0000-0000-000000000001', 'acct_test_rfn_host', true);

insert into clubs (id, owner_id, name, slug, is_public)
values ('4efe0000-0000-0000-0000-0000000000c1',
        '4efe0000-0000-0000-0000-000000000001', 'Reversal Studio', 'rfn-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values ('4efe0000-0000-0000-0000-0000000000e1',
        '4efe0000-0000-0000-0000-0000000000c1', 'Barre',
        '2026-07-02 18:00+00', '4efe0000-0000-0000-0000-000000000001',
        '4efe0000-0000-0000-0000-000000000001', 'class');

-- The order starts where § 789 leaves it: refunded, seat already released.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, currency, platform_fee_cents, status, paid_at)
values ('4efe0000-0000-0000-0000-0000000000a1',
        '4efe0000-0000-0000-0000-0000000000e1', '2026-07-02 18:00+00',
        '4efe0000-0000-0000-0000-000000000002',
        '4efe0000-0000-0000-0000-000000000001',
        2200, 'usd', 110, 'refunded', now());

-- ── 1. the order arm ────────────────────────────────────────────────────────

select is(
  (select count(*) from notifications
    where kind = 'refund_failed' and user_id = '4efe0000-0000-0000-0000-000000000002'),
  0::bigint,
  'nothing is announced while the order still reads refunded'
);

update event_orders set status = 'refund_failed', refunded_at = now()
where id = '4efe0000-0000-0000-0000-0000000000a1';

select is(
  (select count(*) from notifications
    where kind = 'refund_failed' and user_id = '4efe0000-0000-0000-0000-000000000002'),
  1::bigint,
  'the transition into refund_failed tells the buyer once'
);

select is(
  (select event_id from notifications
    where kind = 'refund_failed' and user_id = '4efe0000-0000-0000-0000-000000000002'),
  '4efe0000-0000-0000-0000-0000000000e1'::uuid,
  'the order arm carries the event so the CTA can reach the page that explains it'
);

select is(
  (select event_instance_start from notifications
    where kind = 'refund_failed' and user_id = '4efe0000-0000-0000-0000-000000000002'),
  '2026-07-02 18:00+00'::timestamptz,
  'and the instance, so a recurring series points at the right occurrence'
);

-- The webhook CASes against the status it read, so a redelivery updates no
-- row at all; this is the belt for an UPDATE that touches the row for some
-- other reason once the status is already there.
update event_orders set refunded_at = now() + interval '1 minute'
where id = '4efe0000-0000-0000-0000-0000000000a1';
update event_orders set status = 'refund_failed'
where id = '4efe0000-0000-0000-0000-0000000000a1';

select is(
  (select count(*) from notifications
    where kind = 'refund_failed' and user_id = '4efe0000-0000-0000-0000-000000000002'),
  1::bigint,
  'a later touch of the same row re-announces nothing'
);

-- ── 2. the donation arm ─────────────────────────────────────────────────────

insert into fundraisers (id, owner_user_id, event_id, charity_name, title, goal_cents)
values ('4efe0000-0000-0000-0000-0000000000f1',
        '4efe0000-0000-0000-0000-000000000001',
        '4efe0000-0000-0000-0000-0000000000e1',
        'Reversal Trust', 'Barre for the Trust', 100000);

insert into donations (id, fundraiser_id, donor_user_id, owner_user_id, amount_cents,
                       currency, platform_fee_cents, status, paid_at)
values
  ('4efe0000-0000-0000-0000-0000000000d1', '4efe0000-0000-0000-0000-0000000000f1',
   '4efe0000-0000-0000-0000-000000000003', '4efe0000-0000-0000-0000-000000000001',
   2500, 'usd', 0, 'refunded', now()),
  ('4efe0000-0000-0000-0000-0000000000d2', '4efe0000-0000-0000-0000-0000000000f1',
   null, '4efe0000-0000-0000-0000-000000000001',
   2500, 'usd', 0, 'refunded', now());

update donations set status = 'refund_failed'
where id = '4efe0000-0000-0000-0000-0000000000d1';

select is(
  (select count(*) from notifications
    where kind = 'refund_failed' and user_id = '4efe0000-0000-0000-0000-000000000003'),
  1::bigint,
  'a signed-in donor is told their refund was reversed'
);

select ok(
  (select event_id is null and event_instance_start is null from notifications
    where kind = 'refund_failed' and user_id = '4efe0000-0000-0000-0000-000000000003'),
  'the donation arm carries no FK — donations has no donor-readable row to point at'
);

-- An anonymous donation has no account to notify. The guard has to be in the
-- function: letting the insert raise 23502 would abort the webhook's own
-- UPDATE and roll the ledger move back with it.
update donations set status = 'refund_failed'
where id = '4efe0000-0000-0000-0000-0000000000d2';

select is(
  (select status from donations where id = '4efe0000-0000-0000-0000-0000000000d2'),
  'refund_failed',
  'an anonymous donation still moves — the missing donor does not abort the ledger'
);

select is(
  (select count(*) from notifications where kind = 'refund_failed'),
  2::bigint,
  'and announces nothing: this rail cannot reach a donor who was never signed in'
);

-- ── 3. the kind itself ──────────────────────────────────────────────────────

select is(
  (select count(*) from notifications
    where kind = 'refund_failed' and user_id = '4efe0000-0000-0000-0000-000000000001'),
  0::bigint,
  'the host is not told — this is the payer''s money, not theirs'
);

select throws_ok(
  $$ insert into notifications (user_id, kind)
     values ('4efe0000-0000-0000-0000-000000000002', 'refund_reversed') $$,
  '23514',
  null,
  'the kind widening is an allowlist edit — a near-miss spelling is still refused'
);

select * from finish();
rollback;
