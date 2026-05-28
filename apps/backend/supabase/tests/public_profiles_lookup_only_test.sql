-- Pins migration 20261011_001 — anon can no longer SELECT * from
-- public_profiles in bulk; only the SECURITY DEFINER lookup RPC
-- works. Persona-hunt Round 3 finding Privacy-Conscious #1.

begin;
select plan(3);

-- Seed two synthetic users so the test can verify enumeration is
-- blocked (a successful enumeration would return both).
do $$
declare
  v_a uuid := '99999999-9999-9999-9999-9999ddddaa01';
  v_b uuid := '99999999-9999-9999-9999-9999ddddaa02';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_a, 'pp-a@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_b, 'pp-b@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
    values (v_a, 'User A', 'km', 'free')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
    values (v_b, 'User B', 'km', 'free')
    on conflict (id) do nothing;
end $$;

-- Switch to anon role to verify the enumeration block.
set local role = 'anon';

-- 1. Bulk SELECT on the view from anon must fail (privilege denied)
--    or return zero rows — the revoke makes this an "insufficient
--    privilege" error.
select throws_ok(
  $$select id from public_profiles$$,
  '42501',
  null,
  'anon SELECT on public_profiles is revoked'
);

-- 2. The lookup RPC works for a known uuid.
select is(
  (select display_name from public_profile_by_id(
    '99999999-9999-9999-9999-9999ddddaa01'::uuid)),
  'User A',
  'public_profile_by_id returns the row for a known uuid'
);

-- 3. RPC with an unknown uuid returns no row (not an error).
select is(
  (select count(*) from public_profile_by_id(
    '99999999-9999-9999-9999-9999ddddaa99'::uuid)),
  0::bigint,
  'public_profile_by_id with unknown uuid returns empty'
);

reset role;
rollback;
