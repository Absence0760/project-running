-- Pins migration 20270630000001 (decisions § 823): a Stripe Refund is a ROW,
-- so a refund that failed is queryable rather than a `console.error`.
--
-- § 789 built `refund_failed` and refused to move `partially_refunded` on
-- either ledger — rightly, on both counts. What it left was a partial refund
-- whose failure had no representation anywhere: `event_orders` carries no
-- refunded amount at all, and `donations.refunded_cents` went on stating an
-- instalment that had come back to us. The answer is not a status; it is the
-- missing noun. Every claim § 823 makes about the database is pinned here:
--
--   * the reversal correction: a failed refund on a `partially_refunded`
--     donation puts its amount back into the thermometer and the feed, and a
--     SUCCEEDED one does not;
--   * idempotency BY CONSTRUCTION: replaying one refund id leaves one row and
--     moves no total — the property the arithmetic § 789 refused cannot have;
--   * the terminal latch: a benign out-of-order `pending` cannot un-say a
--     failure that already landed;
--   * the clamp: no child row can push a donation past its own amount;
--   * exactly one parent ledger per refund, and a status the CHECK admits;
--   * no client role can read the table at all, and only the service role can
--     write it.
--
-- fundraiser_totals / fundraiser_feed are called as `anon`, the public
-- thermometer's real caller. Calling them as service_role is what makes
-- donations_status_lock_test fail on a workstation CLI image (§ 799).

begin;
select plan(23);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('9ef00000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'pr-owner@ref.local', '', now(), now()),
  ('9ef00000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'pr-buyer@ref.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('9ef00000-0000-0000-0000-000000000001', 'acct_test_pr_owner', true);

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('9ef00000-0000-0000-0000-0000000000a1',
        '9ef00000-0000-0000-0000-000000000001', now(), 5000, 1500, 'app', true,
        '{"activity_type":"run"}');

insert into fundraisers (id, owner_user_id, run_id, charity_name, title, goal_cents)
values ('9ef00000-0000-0000-0000-0000000000f1',
        '9ef00000-0000-0000-0000-000000000001', '9ef00000-0000-0000-0000-0000000000a1',
        'Charity', 'Run fundraiser', 100000);

-- One donation, partly refunded. 10000 in, 1200 recorded as gone back out.
insert into donations (id, fundraiser_id, owner_user_id, display_name,
                       amount_cents, status, refunded_cents, is_anonymous, paid_at,
                       stripe_payment_intent_id)
values ('9ef00000-0000-0000-0000-0000000000d1', '9ef00000-0000-0000-0000-0000000000f1',
        '9ef00000-0000-0000-0000-000000000001', 'Partly P.',
        10000, 'partially_refunded', 1200, false, now(), 'pi_pr_1');

-- An event order, so the second ledger's arm is exercised on a real parent.
insert into clubs (id, owner_id, name, slug, is_public)
values ('9ef00000-0000-0000-0000-0000000000c1',
        '9ef00000-0000-0000-0000-000000000001', 'Refund Studio', 'pr-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values ('9ef00000-0000-0000-0000-0000000000e1',
        '9ef00000-0000-0000-0000-0000000000c1', 'Reformer Pilates',
        '2026-07-01 18:00+00', '9ef00000-0000-0000-0000-000000000001',
        '9ef00000-0000-0000-0000-000000000001', 'class');

insert into event_pricing (event_id, price_cents, platform_fee_bps)
values ('9ef00000-0000-0000-0000-0000000000e1', 2200, 500);

insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
values ('9ef00000-0000-0000-0000-0000000000b1', '9ef00000-0000-0000-0000-0000000000e1',
        '2026-07-01 18:00+00', '9ef00000-0000-0000-0000-000000000002',
        '9ef00000-0000-0000-0000-000000000001', 2200, 110, 'partially_refunded', now());

-- ── 1. the baseline § 789 shipped: the refunded part is simply gone ─────────
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select raised_cents::int from fundraiser_totals('9ef00000-0000-0000-0000-0000000000f1')),
  8800,
  'with no refund rows the thermometer reports amount - refunded_cents (10000 - 1200)'
);

-- ── 2. a FAILED refund puts its amount back ─────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into payment_refunds (stripe_refund_id, donation_id, amount_cents, status, failure_reason)
values ('re_pr_failed', '9ef00000-0000-0000-0000-0000000000d1', 1200, 'failed',
        'insufficient_funds');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select raised_cents::int from fundraiser_totals('9ef00000-0000-0000-0000-0000000000f1')),
  10000,
  'a refund the bank sent back is money the charity still has (10000 - 1200 + 1200)'
);
-- The whole set, not the absence of the understated figure: an emptiness over
-- a definer relation reads as an access-control claim to the refusal-assertion
-- guard, and this one is about which NUMBER the feed reports (§ 778).
select is(
  (select array_agg(amount_cents::int order by amount_cents)
     from fundraiser_feed('9ef00000-0000-0000-0000-0000000000f1', 50)),
  array[10000],
  'the feed reports the same corrected figure as the thermometer'
);
select is(
  (select donor_count::int from fundraiser_totals('9ef00000-0000-0000-0000-0000000000f1')),
  1,
  'a reversal changes what was raised, never who donated'
);

-- ── 3. idempotency BY CONSTRUCTION ──────────────────────────────────────────
-- This is the property § 789 could not have. `refunded_cents -= amount` moves
-- once per delivery; an upsert on the Stripe Refund id does not move at all on
-- the second, and the assertion is on the TOTAL rather than on the row count,
-- because it is the total a double-apply corrupts.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into payment_refunds (stripe_refund_id, donation_id, amount_cents, status, failure_reason)
values ('re_pr_failed', '9ef00000-0000-0000-0000-0000000000d1', 1200, 'failed',
        'insufficient_funds')
on conflict (stripe_refund_id) do update
  set status = excluded.status,
      amount_cents = excluded.amount_cents,
      failure_reason = excluded.failure_reason;

insert into payment_refunds (stripe_refund_id, donation_id, amount_cents, status, failure_reason)
values ('re_pr_failed', '9ef00000-0000-0000-0000-0000000000d1', 1200, 'failed',
        'insufficient_funds')
on conflict (stripe_refund_id) do update
  set status = excluded.status,
      amount_cents = excluded.amount_cents,
      failure_reason = excluded.failure_reason;

select is(
  (select count(*)::int from payment_refunds where stripe_refund_id = 're_pr_failed'),
  1,
  'three deliveries of one Stripe Refund leave exactly one row'
);

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select raised_cents::int from fundraiser_totals('9ef00000-0000-0000-0000-0000000000f1')),
  10000,
  'replaying the same refund id does not move the thermometer'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select throws_ok(
  $$ insert into payment_refunds (stripe_refund_id, donation_id, amount_cents, status)
     values ('re_pr_failed', '9ef00000-0000-0000-0000-0000000000d1', 1200, 'failed') $$,
  '23505',
  'duplicate key value violates unique constraint "payment_refunds_stripe_id_idx"',
  'a plain insert of a known Stripe Refund id is refused, so the key is real'
);

-- ── 4. a SUCCEEDED refund is not a reversal ─────────────────────────────────
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

update payment_refunds set status = 'succeeded', failure_reason = null
  where stripe_refund_id = 're_pr_failed';

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select raised_cents::int from fundraiser_totals('9ef00000-0000-0000-0000-0000000000f1')),
  8800,
  'a refund that delivered leaves the money out of the total, where it belongs'
);

-- ── 5. a terminal status latches against an out-of-order delivery ───────────
-- Webhook deliveries are not ordered. A benign `refund.updated` carrying
-- `pending` can arrive after the `refund.failed` that settled the refund, and
-- an unconditional upsert would silently restore the overstatement.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

update payment_refunds set status = 'failed', failure_reason = 'expired_or_canceled_card'
  where stripe_refund_id = 're_pr_failed';

update payment_refunds set status = 'pending', failure_reason = null
  where stripe_refund_id = 're_pr_failed';

select is(
  (select status || '/' || coalesce(failure_reason, '-') from payment_refunds
     where stripe_refund_id = 're_pr_failed'),
  'failed/expired_or_canceled_card',
  'an in-flight status cannot walk a settled refund back, reason included'
);

-- Positive control: the latch holds a TERMINAL status, it does not freeze the
-- row. A refund that is genuinely re-settled still moves.
select lives_ok(
  $$ update payment_refunds set status = 'succeeded'
       where stripe_refund_id = 're_pr_failed' $$,
  'a terminal status can still be replaced by another terminal one'
);
update payment_refunds set status = 'failed', failure_reason = 'insufficient_funds'
  where stripe_refund_id = 're_pr_failed';

-- ── 6. the clamp ────────────────────────────────────────────────────────────
-- A reversal can never exceed what we recorded as refunded in the first place,
-- so a bogus amount widens no total past the donation itself.
update payment_refunds set amount_cents = 999999
  where stripe_refund_id = 're_pr_failed';

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select raised_cents::int from fundraiser_totals('9ef00000-0000-0000-0000-0000000000f1')),
  10000,
  'a reversal larger than the recorded refund is clamped to it, never past the donation'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update payment_refunds set amount_cents = 1200
  where stripe_refund_id = 're_pr_failed';

-- ── 7. one parent ledger, and only a status the CHECK admits ────────────────
select throws_ok(
  $$ insert into payment_refunds (stripe_refund_id, amount_cents, status)
     values ('re_pr_orphan', 500, 'failed') $$,
  '23514',
  'new row for relation "payment_refunds" violates check constraint "payment_refunds_one_ledger_check"',
  'a refund attributable to no money we took cannot be recorded'
);

select throws_ok(
  $$ insert into payment_refunds (stripe_refund_id, donation_id, event_order_id,
                                  amount_cents, status)
     values ('re_pr_both', '9ef00000-0000-0000-0000-0000000000d1',
             '9ef00000-0000-0000-0000-0000000000b1', 500, 'failed') $$,
  '23514',
  'new row for relation "payment_refunds" violates check constraint "payment_refunds_one_ledger_check"',
  'a refund cannot be attributed to both ledgers at once'
);

select throws_ok(
  $$ insert into payment_refunds (stripe_refund_id, donation_id, amount_cents, status)
     values ('re_pr_bogus', '9ef00000-0000-0000-0000-0000000000d1', 500, 'reversed') $$,
  '23514',
  'new row for relation "payment_refunds" violates check constraint "payment_refunds_status_check"',
  'a status outside Stripe''s vocabulary is refused, so the webhook must gate on it'
);

select throws_ok(
  $$ insert into payment_refunds (stripe_refund_id, donation_id, amount_cents, status)
     values ('re_pr_neg', '9ef00000-0000-0000-0000-0000000000d1', -1, 'failed') $$,
  '23514',
  'new row for relation "payment_refunds" violates check constraint "payment_refunds_amount_nonneg_check"',
  'a refund cannot return a negative amount'
);

-- ── 8. the order ledger's arm, which never had a refunded amount at all ─────
select lives_ok(
  $$ insert into payment_refunds (stripe_refund_id, event_order_id, amount_cents,
                                  status, failure_reason)
     values ('re_pr_order', '9ef00000-0000-0000-0000-0000000000b1', 500, 'failed',
             'declined') $$,
  'a failed PARTIAL refund on an event order is recordable — the case event_orders '
  'could not represent at all'
);

-- The operator worklist § 789 could give only the FULL case.
select is(
  (select array_agg(stripe_refund_id order by stripe_refund_id)
     from payment_refunds where status in ('failed', 'canceled')),
  array['re_pr_failed', 're_pr_order'],
  'both ledgers'' failed refunds answer one worklist query'
);

-- ── 9. no client role reads this table, and none writes it ──────────────────
select ok(
  not has_table_privilege('anon', 'public.payment_refunds', 'select')
    and not has_table_privilege('authenticated', 'public.payment_refunds', 'select'),
  'no client role holds SELECT on payment_refunds — the 20270621_001 lockdown '
  'shape, applied at table level because there is no client read path to serve'
);

select ok(
  not has_table_privilege('anon', 'public.payment_refunds', 'insert')
    and not has_table_privilege('authenticated', 'public.payment_refunds', 'update'),
  'no client role holds INSERT or UPDATE on payment_refunds'
);

-- Run as the table OWNER with an `authenticated` role claim: RLS is bypassed,
-- so the row is genuinely visible and the write genuinely reaches it. What
-- refuses is the lock trigger, not an empty result set.
reset role;
set local "request.jwt.claims" = '{"role":"authenticated"}';

select throws_ok(
  $$ update payment_refunds set status = 'succeeded'
       where stripe_refund_id = 're_pr_failed' $$,
  '42501',
  'payment_refunds is service-role-only (the stripe-events webhook is the sole writer)',
  'a non-service-role caller cannot move a refund''s status'
);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select lives_ok(
  $$ update payment_refunds set status = 'canceled'
       where stripe_refund_id = 're_pr_failed' $$,
  'the service role (the stripe-events webhook) can move a refund''s status'
);

-- The privilege the sole writer depends on, STATED rather than inherited.
-- 20270630000001 wrote only `revoke all … from anon, authenticated` and left
-- service_role's DML to Supabase's `alter default privileges`, which is not
-- stable across images: on the workstation CLI's current one the table lands
-- with `service_role=Dxtm` and every assertion above dies at 42501 before it
-- runs. 20270702000002 states the grant, so the two assertions are the pair
-- that has to hold together — the writer keeps everything, the clients keep
-- nothing.
select is(
  (select coalesce(string_agg(v.verb, ', ' order by v.verb), '')
     from (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) v(verb)
    where not has_table_privilege('service_role', 'public.payment_refunds'::regclass, v.verb)),
  '',
  'service_role holds full DML on payment_refunds — the webhook is the sole writer and its privilege is granted, not inherited from an image default');

select is(
  (select coalesce(string_agg(r.role || ' ' || v.verb, ', ' order by r.role, v.verb), '')
     from (values ('anon'::name), ('authenticated'::name)) r(role)
     cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) v(verb)
    where has_table_privilege(r.role, 'public.payment_refunds'::regclass, v.verb)),
  '',
  'and no client role holds any of it — a refund''s amount and failure reason are not a client read path');

select * from finish();
rollback;
