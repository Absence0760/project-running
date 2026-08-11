-- Pins migration 20270517_001 (event_pricing gets ONE non-partial arbiter):
--   * an organiser can upsert a SERIES price (instance_start IS NULL) twice —
--     the second call updates in place instead of raising 42P10 or inserting a
--     duplicate series row.
--   * the same for a PER-INSTANCE override, without disturbing the series row.
--
-- The `on conflict (event_id, instance_start)` clause below is exactly what
-- PostgREST emits for `setEventPricing`'s upsert. Against the two PARTIAL
-- unique indexes this table shipped with, BOTH branches raised 42P10 ("there is
-- no unique or exclusion constraint matching the ON CONFLICT specification"),
-- because Postgres will only infer a partial index as an arbiter when the
-- statement carries a matching WHERE clause and PostgREST never emits one. A
-- price could therefore never be attached to an event and the paid-registration
-- rail was unreachable — with no test exercising the ON CONFLICT path, nothing
-- caught it. This suite is that test: it runs as the organiser (the real
-- caller), not the service role, so the RLS write policy is in the path too.

begin;
select plan(9);

-- ── Fixtures: host (also club owner) with a charges-enabled payout account ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaa2222-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'ep-host@evt.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb2222-0000-0000-0000-000000000001',
        'aaaa2222-0000-0000-0000-000000000001', 'Vinyasa Studio', 'ep-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values ('cccc2222-0000-0000-0000-000000000001',
        'bbbb2222-0000-0000-0000-000000000001', 'Vinyasa Flow',
        '2026-07-01 18:00+00', 'aaaa2222-0000-0000-0000-000000000001',
        'aaaa2222-0000-0000-0000-000000000001', 'class');

-- The pricing trigger requires the host to be able to take payment.
insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('aaaa2222-0000-0000-0000-000000000001', 'acct_ep_host', true);

-- ── The organiser is the caller from here down ──
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"aaaa2222-0000-0000-0000-000000000001","role":"authenticated"}';

-- ── Series price: insert, then re-price ─────────────────────────────────────
select lives_ok(
  $$ insert into event_pricing (event_id, instance_start, price_cents, currency,
                                modality, refund_policy, sales_close_offset_minutes,
                                platform_fee_bps)
     values ('cccc2222-0000-0000-0000-000000000001', null, 2200, 'usd',
             'in_person', 'full_until_24h', 0, 0)
     on conflict (event_id, instance_start) do update
       set price_cents = excluded.price_cents,
           refund_policy = excluded.refund_policy $$,
  'series price upserts (insert branch) — the arbiter is inferable'
);

select lives_ok(
  $$ insert into event_pricing (event_id, instance_start, price_cents, currency,
                                modality, refund_policy, sales_close_offset_minutes,
                                platform_fee_bps)
     values ('cccc2222-0000-0000-0000-000000000001', null, 3300, 'usd',
             'in_person', 'no_refund', 0, 0)
     on conflict (event_id, instance_start) do update
       set price_cents = excluded.price_cents,
           refund_policy = excluded.refund_policy $$,
  're-pricing the series upserts (update branch) — this raised 42P10 before'
);

select is(
  (select count(*)::int from event_pricing
    where event_id = 'cccc2222-0000-0000-0000-000000000001'
      and instance_start is null),
  1,
  're-pricing the series updates the one row rather than adding a second'
);

select is(
  (select price_cents from event_pricing
    where event_id = 'cccc2222-0000-0000-0000-000000000001'
      and instance_start is null),
  3300,
  'the series row carries the re-priced amount'
);

select is(
  (select refund_policy from event_pricing
    where event_id = 'cccc2222-0000-0000-0000-000000000001'
      and instance_start is null),
  'no_refund',
  'every column in the DO UPDATE set is applied, not just the price'
);

-- ── Per-instance override: insert, then re-price ────────────────────────────
select lives_ok(
  $$ insert into event_pricing (event_id, instance_start, price_cents, currency,
                                modality, refund_policy, sales_close_offset_minutes,
                                platform_fee_bps)
     values ('cccc2222-0000-0000-0000-000000000001', '2026-07-08 18:00+00', 4400,
             'usd', 'in_person', 'full_until_24h', 0, 0)
     on conflict (event_id, instance_start) do update
       set price_cents = excluded.price_cents $$,
  'per-instance override upserts (insert branch)'
);

select lives_ok(
  $$ insert into event_pricing (event_id, instance_start, price_cents, currency,
                                modality, refund_policy, sales_close_offset_minutes,
                                platform_fee_bps)
     values ('cccc2222-0000-0000-0000-000000000001', '2026-07-08 18:00+00', 5500,
             'usd', 'in_person', 'full_until_24h', 0, 0)
     on conflict (event_id, instance_start) do update
       set price_cents = excluded.price_cents $$,
  're-pricing one instance upserts (update branch)'
);

select is(
  (select price_cents from event_pricing
    where event_id = 'cccc2222-0000-0000-0000-000000000001'
      and instance_start = '2026-07-08 18:00+00'),
  5500,
  'the per-instance row carries the re-priced amount'
);

-- The whole point of the two-index shape the single arbiter replaces: a series
-- row and an instance override coexist. Collapsing them would silently discard
-- one of the host's prices.
select is(
  (select count(*)::int from event_pricing
    where event_id = 'cccc2222-0000-0000-0000-000000000001'),
  2,
  'series row and per-instance override coexist — 2 rows, not 1'
);

select * from finish();
rollback;
