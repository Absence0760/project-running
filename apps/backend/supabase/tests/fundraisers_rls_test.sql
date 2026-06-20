-- Pins migration 20270212_001 (fundraising) RLS:
--   * a fundraiser on a PUBLIC anchor (public run / public-club event) is
--     anon-readable (it's a share target);
--   * a fundraiser on a PRIVATE anchor is owner-only — a non-owner (and anon)
--     reads zero rows (fail-closed);
--   * a non-owner cannot insert / close a fundraiser;
--   * an owner cannot anchor a fundraiser to a run they don't own.

begin;
select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('fa000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'fr-owner@rls.local', '', now(), now()),
  ('fa000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'fr-stranger@rls.local', '', now(), now());

set local role service_role;

-- Both have a charges-enabled payout account so the requires-charges trigger
-- passes and the OWNERSHIP gate (RLS) is what's under test on the stranger's
-- attempted insert below — not the charges gate.
insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values
  ('fa000000-0000-0000-0000-000000000001', 'acct_test_rls_owner', true),
  ('fa000000-0000-0000-0000-000000000002', 'acct_test_rls_stranger', true);

-- A PUBLIC run + a PRIVATE run, both owned by the owner.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values
  ('fa000000-0000-0000-0000-0000000000a1',
   'fa000000-0000-0000-0000-000000000001', now(), 5000, 1500, 'app', true,
   '{"activity_type":"run"}'),
  ('fa000000-0000-0000-0000-0000000000a2',
   'fa000000-0000-0000-0000-000000000001', now(), 5000, 1500, 'app', false,
   '{"activity_type":"run"}');

-- A fundraiser on each anchor.
insert into fundraisers (id, owner_user_id, run_id, charity_name, title, goal_cents)
values
  ('fa000000-0000-0000-0000-0000000000f1',
   'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-0000000000a1',
   'Public Charity', 'Public run fundraiser', 100000),
  ('fa000000-0000-0000-0000-0000000000f2',
   'fa000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-0000000000a2',
   'Private Charity', 'Private run fundraiser', 100000);

-- ── anon sees the public-anchor fundraiser, not the private-anchor one ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select is(
  (select count(*)::int from fundraisers where id = 'fa000000-0000-0000-0000-0000000000f1'),
  1,
  'anon can read a fundraiser on a public run'
);

select is(
  (select count(*)::int from fundraisers where id = 'fa000000-0000-0000-0000-0000000000f2'),
  0,
  'anon cannot read a fundraiser on a private run (fail-closed)'
);

-- ── a signed-in stranger: same — public yes, private no ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"fa000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from fundraisers where id = 'fa000000-0000-0000-0000-0000000000f1'),
  1,
  'a signed-in non-owner can read a fundraiser on a public run'
);

select is(
  (select count(*)::int from fundraisers where id = 'fa000000-0000-0000-0000-0000000000f2'),
  0,
  'a signed-in non-owner cannot read a fundraiser on a private run'
);

-- A stranger cannot create a fundraiser on the owner's run (not their anchor).
select throws_ok(
  $$ insert into fundraisers (owner_user_id, run_id, charity_name, title, goal_cents)
     values ('fa000000-0000-0000-0000-000000000002',
             'fa000000-0000-0000-0000-0000000000a1', 'Hijack', 'Not mine', 100000) $$,
  '42501',
  null,
  'a non-owner cannot create a fundraiser on someone else''s run'
);

-- A stranger cannot close (update) the owner's public-anchor fundraiser. No
-- permissive client UPDATE for a non-owner → RLS USING filter hides the row,
-- the update is a no-op (status stays 'open').
update fundraisers set status = 'closed'
  where id = 'fa000000-0000-0000-0000-0000000000f1';

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
select is(
  (select status from fundraisers where id = 'fa000000-0000-0000-0000-0000000000f1'),
  'open',
  'a non-owner cannot close a fundraiser (stays open)'
);

-- ── the owner reads BOTH (own-row branch covers the private anchor) ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"fa000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  (select count(*)::int from fundraisers
     where id in ('fa000000-0000-0000-0000-0000000000f1','fa000000-0000-0000-0000-0000000000f2')),
  2,
  'the owner reads both their public- and private-anchor fundraisers'
);

select * from finish();
rollback;
