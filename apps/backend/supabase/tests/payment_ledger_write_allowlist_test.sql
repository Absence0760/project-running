-- The two money ledgers' write locks, measured as ALLOWLISTS rather than as
-- the column enumerations they used to be (migration 20270702000001).
--
-- `event_orders` is the only payment table carrying a permissive client UPDATE
-- policy — "buyer initiates refund on own paid order" — and 20270408_001
-- grants `authenticated` UPDATE on every one of its columns, so the trigger is
-- the whole of what stands between a buyer and their own money row. Until
-- 20270702000001 that trigger listed fourteen columns plus `status`, and `id`
-- was not among them: a buyer could rewrite the primary key of their own paid
-- order. That is the key `events-checkout` writes into the Stripe session's
-- `metadata.order_id`, that `handleNotPaid` resolves an expiry delivery by, and
-- that `payment_refunds.event_order_id` joins on since 20270630000001.
--
-- Assertion (3) is the one that would have caught it, and assertion (2) is what
-- stops the same omission recurring: the probe list is checked for COVERAGE of
-- the live column set, so a column added to `event_orders` later fails this
-- file until it is probed here too.
--
-- `donations` has no permissive policy at all, so its client rail is RLS and
-- its trigger is the second line. Both are measured, and in the order they
-- actually stand: (7) proves a real `authenticated` session reaches no row,
-- (8)-(9) reach the trigger the way `payment_refund_ledger_test` does — as the
-- table owner carrying an `authenticated` role claim — so a lost RLS policy
-- would not silently leave the ledger writable.

begin;

select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('ba000000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', 'wa-buyer@pay.local', '', now(), now()),
  ('ba000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', 'wa-host@pay.local', '', now(), now());

insert into user_profiles (id, display_name) values
  ('ba000000-0000-0000-0000-0000000000b1', 'Buyer'),
  ('ba000000-0000-0000-0000-0000000000b2', 'Host')
on conflict (id) do nothing;

insert into clubs (id, owner_id, name, slug)
values ('ba000000-0000-0000-0000-0000000000c1', 'ba000000-0000-0000-0000-0000000000b2',
        'Allowlist Studio', 'wa-allowlist-studio');

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values
  ('ba000000-0000-0000-0000-0000000000e1', 'ba000000-0000-0000-0000-0000000000c1',
   'Priced Class', '2027-03-01 18:00+00', 'ba000000-0000-0000-0000-0000000000b2',
   'ba000000-0000-0000-0000-0000000000b2', 'class'),
  ('ba000000-0000-0000-0000-0000000000e2', 'ba000000-0000-0000-0000-0000000000c1',
   'Other Class', '2027-03-08 18:00+00', 'ba000000-0000-0000-0000-0000000000b2',
   'ba000000-0000-0000-0000-0000000000b2', 'class');

insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, currency, platform_fee_cents, status, paid_at)
values ('ba000000-0000-0000-0000-0000000000a1', 'ba000000-0000-0000-0000-0000000000e1',
        '2027-03-01 18:00+00', 'ba000000-0000-0000-0000-0000000000b1',
        'ba000000-0000-0000-0000-0000000000b2', 2500, 'usd', 250, 'paid', now());

-- A donation ledger for the second half of the file.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('ba000000-0000-0000-0000-0000000000ab', 'ba000000-0000-0000-0000-0000000000b2',
        now(), 5000, 1500, 'app', true, '{"activity_type":"run"}');

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('ba000000-0000-0000-0000-0000000000b2', 'acct_test_wa_host', true);

insert into fundraisers (id, owner_user_id, run_id, charity_name, title, goal_cents)
values ('ba000000-0000-0000-0000-0000000000f1', 'ba000000-0000-0000-0000-0000000000b2',
        'ba000000-0000-0000-0000-0000000000ab', 'Charity', 'Allowlist fundraiser', 100000);

insert into donations (id, fundraiser_id, owner_user_id, display_name, message,
                       amount_cents, status, is_anonymous, paid_at)
values ('ba000000-0000-0000-0000-0000000000d1', 'ba000000-0000-0000-0000-0000000000f1',
        'ba000000-0000-0000-0000-0000000000b2', 'Jane D.', 'Go go go!', 2500, 'paid', false, now());

-- ── the buyer's one legitimate write ────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"ba000000-0000-0000-0000-0000000000b1","role":"authenticated"}';

select lives_ok(
  $$ update event_orders set refund_initiated_at = now()
      where id = 'ba000000-0000-0000-0000-0000000000a1' $$,
  'the buyer can still stamp refund_initiated_at on their own paid order');

select isnt(
  (select refund_initiated_at from event_orders where id = 'ba000000-0000-0000-0000-0000000000a1'),
  null,
  'and the stamp landed — the affordance 20270303_001 opened is reachable, so every refusal below is the lock and not a dead write path');

-- ── every other column, probed one at a time ────────────────────────────────
-- Each probe is a value distinct from the fixture's, and type-correct, so the
-- only thing that can refuse it is the write lock. `id` is first because it is
-- the column the pre-20270702000001 enumeration omitted.
create temporary table event_order_probe (col name, assignment text);

insert into event_order_probe (col, assignment) values
  ('id',                         $$ id = 'ba000000-0000-0000-0000-0000000000a9' $$),
  ('event_id',                   $$ event_id = 'ba000000-0000-0000-0000-0000000000e2' $$),
  ('instance_start',             $$ instance_start = '2027-03-08 18:00+00' $$),
  ('buyer_user_id',              $$ buyer_user_id = 'ba000000-0000-0000-0000-0000000000b2' $$),
  ('host_user_id',               $$ host_user_id = 'ba000000-0000-0000-0000-0000000000b1' $$),
  ('stripe_checkout_session_id', $$ stripe_checkout_session_id = 'cs_forged' $$),
  ('stripe_payment_intent_id',   $$ stripe_payment_intent_id = 'pi_forged' $$),
  ('amount_cents',               $$ amount_cents = 1 $$),
  ('currency',                   $$ currency = 'eur' $$),
  ('platform_fee_cents',         $$ platform_fee_cents = 0 $$),
  ('status',                     $$ status = 'refunded' $$),
  ('created_at',                 $$ created_at = '2020-01-01 00:00+00' $$),
  ('paid_at',                    $$ paid_at = '2020-01-01 00:00+00' $$),
  ('refunded_at',                $$ refunded_at = now() $$),
  ('reserved_until',             $$ reserved_until = now() $$);

-- (2) Coverage. The defect was an enumeration that went stale, so the probe
-- list is measured against the live column set rather than trusted: a column
-- added to event_orders later fails HERE until it is probed above.
select is(
  (select coalesce(string_agg(a.attname, ', ' order by a.attname), '')
     from pg_attribute a
    where a.attrelid = 'public.event_orders'::regclass
      and a.attnum > 0 and not a.attisdropped
      and a.attname <> 'refund_initiated_at'
      and a.attname not in (select col from event_order_probe)),
  '',
  'every event_orders column except the buyer refund stamp is probed below');

create temporary table event_order_probe_result (col name, written boolean);

do $probe$
declare r record;
begin
  -- `id` is probed LAST and deliberately so: every probe selects the row by
  -- its id, so a successful id rewrite would leave every later probe matching
  -- no row -- which raises nothing and would score as WRITTEN. Running it last
  -- keeps each verdict exact. (Measured: without this the pre-fix run reports
  -- nine writable columns where only one is.)
  for r in select col, assignment from event_order_probe
            order by (col = 'id'), col loop
    begin
      execute format('update event_orders set %s where id = %L',
                     r.assignment, 'ba000000-0000-0000-0000-0000000000a1');
      insert into event_order_probe_result values (r.col, true);
    exception when insufficient_privilege then
      insert into event_order_probe_result values (r.col, false);
    end;
  end loop;
end
$probe$;

-- (3) The lock itself. `id` failing here is the defect 20270702000001 closed.
select is(
  (select coalesce(string_agg(col, ', ' order by col), '')
     from event_order_probe_result where written),
  '',
  'the buyer cannot change any event_orders column but the refund stamp — including id, which the enumeration this replaced omitted');

-- (4) And the probes really ran: an empty result table would satisfy (3) too.
select is(
  (select count(*)::int from event_order_probe_result),
  (select count(*)::int from event_order_probe),
  'every probe was executed — an unrun probe set would satisfy the assertion above for free');

-- (5) The row is untouched: a refusal that had already written something and
-- then rolled back only its own statement would still be a leak.
select results_eq(
  $$ select amount_cents, platform_fee_cents, status, currency, buyer_user_id
       from event_orders where id = 'ba000000-0000-0000-0000-0000000000a1' $$,
  $$ values (2500, 250, 'paid', 'usd', 'ba000000-0000-0000-0000-0000000000b1'::uuid) $$,
  'the order still carries the figures the webhook wrote');

-- (6) The webhook is unaffected — the same writes the buyer was refused.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select lives_ok(
  $$ update event_orders
        set status = 'refunded', refunded_at = now(), amount_cents = 2500
      where id = 'ba000000-0000-0000-0000-0000000000a1' $$,
  'the service role still moves status, refunded_at and amount together — the lock is about the caller, not the columns');

-- ── donations: RLS first, then the trigger ──────────────────────────────────
-- (7) The first rail. `donations` carries no permissive policy, so a real
-- signed-in session matches no row at all.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"ba000000-0000-0000-0000-0000000000b1","role":"authenticated"}';

update donations set message = 'edited by the donor'
 where id = 'ba000000-0000-0000-0000-0000000000d1';
delete from donations where id = 'ba000000-0000-0000-0000-0000000000d1';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select results_eq(
  $$ select count(*)::int, max(message) from donations
      where id = 'ba000000-0000-0000-0000-0000000000d1' $$,
  $$ values (1, 'Go go go!') $$,
  'a signed-in client neither edits nor deletes a donation — no permissive policy exists to match the row');

-- (8) The second rail, reached the way payment_refund_ledger_test reaches it:
-- as the table owner (RLS bypassed) carrying an `authenticated` role claim, so
-- the trigger is what answers. Before 20270702000001 the trigger checked only
-- `status` and `refunded_cents`, and this write went through.
reset role;
set local "request.jwt.claims" = '{"role":"authenticated"}';

select throws_ok(
  $$ update donations set amount_cents = 1
      where id = 'ba000000-0000-0000-0000-0000000000d1' $$,
  '42501',
  null,
  'the donation ledger refuses a non-service-role amount change even with RLS out of the way');

select throws_ok(
  $$ update donations set client_request_id = gen_random_uuid()
      where id = 'ba000000-0000-0000-0000-0000000000d1' $$,
  '42501',
  null,
  'and refuses a client re-keying the checkout idempotency handle');

-- (9) The webhook writes the same columns — the positive control that (8) is
-- the caller check and not a broken statement.
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select lives_ok(
  $$ update donations set amount_cents = 3000, client_request_id = gen_random_uuid()
      where id = 'ba000000-0000-0000-0000-0000000000d1' $$,
  'the donation webhook writes both columns unchallenged');

select * from finish();

rollback;
