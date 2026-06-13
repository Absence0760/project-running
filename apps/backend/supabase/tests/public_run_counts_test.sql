-- Pins migration 20270118_001 -- public_run_counts(uuid[]) SECURITY DEFINER.
--
-- Counts public runs per user for the People-suggestions surface. Must: count
-- only is_public runs (never private), emit one row per user that has ≥1 public
-- run, and — the correctness point — work for a NON-OWNER caller (base-table
-- RLS dropped the public-anyone SELECT policy in 20260701_001, so a plain query
-- returns 0 for other users; the DEFINER RPC sees the real count).
begin;
select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('bb000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'a@prc.local', '', now(), now()),
  ('bb000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', 'b@prc.local', '', now(), now()),
  ('bb000000-0000-0000-0000-0000000000c3', 'authenticated', 'authenticated', 'viewer@prc.local', '', now(), now());

-- User A: 2 public + 1 private. User B: 0 public + 1 private.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata) values
  ('bb000000-0000-0000-0000-00000000a101', 'bb000000-0000-0000-0000-0000000000a1', now(), 1800, 5000, 'app', true,  '{"activity_type":"run"}'),
  ('bb000000-0000-0000-0000-00000000a102', 'bb000000-0000-0000-0000-0000000000a1', now(), 1200, 3000, 'app', true,  '{"activity_type":"run"}'),
  ('bb000000-0000-0000-0000-00000000a103', 'bb000000-0000-0000-0000-0000000000a1', now(), 1000, 2000, 'app', false, '{"activity_type":"run"}'),
  ('bb000000-0000-0000-0000-00000000b201', 'bb000000-0000-0000-0000-0000000000b2', now(), 1500, 4000, 'app', false, '{"activity_type":"run"}');

-- Call as a NON-OWNER authenticated viewer (the realistic People-search case).
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"bb000000-0000-0000-0000-0000000000c3","role":"authenticated"}';

select is(
  (select public_run_count from public_run_counts(array['bb000000-0000-0000-0000-0000000000a1']::uuid[])),
  2::bigint, 'A has 2 public runs (private one excluded), visible to a non-owner');

select is(
  (select count(*) from public_run_counts(array['bb000000-0000-0000-0000-0000000000b2']::uuid[])),
  0::bigint, 'B has no public runs → no row (private-only is not counted)');

select is(
  (select count(*) from public_run_counts(array[
    'bb000000-0000-0000-0000-0000000000a1',
    'bb000000-0000-0000-0000-0000000000b2']::uuid[])),
  1::bigint, 'one row per user WITH public runs (A only)');

select is(
  (select count(*) from public_run_counts(array[]::uuid[])),
  0::bigint, 'empty input → no rows');

-- A non-owner reading the base table directly gets 0 (the policy 20260701_001
-- dropped) — proving the RPC is what makes the count correct, not RLS.
select is(
  (select count(*) from runs where user_id = 'bb000000-0000-0000-0000-0000000000a1' and is_public = true),
  0::bigint, 'base-table public read is blocked for a non-owner (RPC is required)');

select * from finish();
rollback;
