-- Pins migration 20270212_001 (fundraising): a fundraiser may only be opened
-- when its owner has a charges-enabled payout account — trigger-enforced
-- (enforce_fundraiser_requires_charges), not just a hidden UI control. Mirrors
-- the event_pricing requires-charges gate.

begin;
select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('fc000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'fr-owner@fund.local', '', now(), now());

set local role service_role;

-- A public run owned by the fundraiser owner (the anchor).
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('fc000000-0000-0000-0000-0000000000a1',
        'fc000000-0000-0000-0000-000000000001', now(), 5000, 1500, 'app', true,
        '{"activity_type":"run"}');

-- No payout account yet → opening a fundraiser must be rejected by the trigger.
select throws_ok(
  $$ insert into fundraisers (owner_user_id, run_id, charity_name, title, goal_cents)
     values ('fc000000-0000-0000-0000-000000000001',
             'fc000000-0000-0000-0000-0000000000a1', 'Red Cross', 'Run for relief', 50000) $$,
  '23514',
  null,
  'fundraiser insert is rejected when owner has no charges-enabled account'
);

-- A payout account that is NOT charges_enabled → still rejected.
insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('fc000000-0000-0000-0000-000000000001', 'acct_test_fr_owner', false);

select throws_ok(
  $$ insert into fundraisers (owner_user_id, run_id, charity_name, title, goal_cents)
     values ('fc000000-0000-0000-0000-000000000001',
             'fc000000-0000-0000-0000-0000000000a1', 'Red Cross', 'Run for relief', 50000) $$,
  '23514',
  null,
  'fundraiser insert is rejected when owner account is not charges-enabled'
);

-- Flip charges_enabled on → opening the fundraiser now succeeds.
update instructor_payout_accounts set charges_enabled = true
  where user_id = 'fc000000-0000-0000-0000-000000000001';

select lives_ok(
  $$ insert into fundraisers (owner_user_id, run_id, charity_name, title, goal_cents)
     values ('fc000000-0000-0000-0000-000000000001',
             'fc000000-0000-0000-0000-0000000000a1', 'Red Cross', 'Run for relief', 50000) $$,
  'fundraiser insert succeeds once owner is charges-enabled'
);

select * from finish();
rollback;
