-- Pins migration 20270201_001 (race-director operations: event_checkpoints +
-- checkpoint_crossings + the two RPCs). The contract:
--
--   1. Writes to checkpoint_crossings are RPC-only. upsert_checkpoint_crossing
--      authorises the caller as an event organiser (owner/admin/event_organiser,
--      status active); a non-organiser authenticated user gets 42501.
--   2. Crossing rows are readable per event-visibility (is_event_visible): a
--      public-club public event's crossings are SELECT-able by anon (non-health
--      columns); flip the club private and anon sees nothing.
--   3. Offline merge dedupe: two upserts for the same (checkpoint, instance, bib)
--      — first stamps in_time, second stamps out_time (and an earlier in_time) —
--      collapse to ONE row with the earliest in_time and the latest out_time.
--   4. Identity rule: an upsert with neither user_id nor bib raises 23514.
--   5. Health column-lock: a direct SELECT of body_weight_kg is denied (42501)
--      to authenticated/anon, while the non-health columns select fine.
--   6. Health fail-closed (decisions §150): the Art 9 health value persists ONLY
--      when the checkpoint requires_weigh_in AND the caller consented; otherwise
--      it is dropped to NULL.
--   7. fetch_checkpoint_crossings_for_organiser returns the health columns for an
--      organiser and raises 42501 for a non-organiser.

begin;

select plan(17);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000201a1', 'authenticated', 'authenticated',
   'director@cp.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000201a2', 'authenticated', 'authenticated',
   'member@cp.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000201a3', 'authenticated', 'authenticated',
   'stranger@cp.local', '', now(), now());

set local role service_role;

-- A public club + public event. enroll_club_owner_trigger seeds the owner's
-- active club_members row; only the plain member needs an explicit insert.
insert into clubs (id, owner_id, name, slug, is_public)
values
  ('01010101-0101-0101-0101-010101010101',
   '00000000-0000-0000-0000-0000000201a1', 'Checkpoint Club', 'cp-club', true);

insert into club_members (club_id, user_id, role, status)
values
  ('01010101-0101-0101-0101-010101010101',
   '00000000-0000-0000-0000-0000000201a2', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id)
values
  ('01010101-0101-0101-0101-010101010111',
   '01010101-0101-0101-0101-010101010101', 'Canyon 50k',
   '2026-06-06 06:00+00', '00000000-0000-0000-0000-0000000201a1');

-- Two checkpoints: a plain aid station and a weigh-in station.
insert into event_checkpoints
  (id, event_id, name, ordinal, requires_weigh_in, created_by)
values
  ('01010101-0101-0101-0101-0101010101c1',
   '01010101-0101-0101-0101-010101010111', 'Aid 1', 1, false,
   '00000000-0000-0000-0000-0000000201a1'),
  ('01010101-0101-0101-0101-0101010101c2',
   '01010101-0101-0101-0101-010101010111', 'Weigh Station', 2, true,
   '00000000-0000-0000-0000-0000000201a1');

-- ============================================================
-- 1. organiser-only writes via the RPC
-- ============================================================
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000201a1","role":"authenticated"}';

select lives_ok(
  $$ select upsert_checkpoint_crossing(
       '01010101-0101-0101-0101-010101010111',
       '01010101-0101-0101-0101-0101010101c1',
       '2026-06-06 06:00+00',
       null, '500', 'Erin Aid',
       '2026-06-06 08:00+00', null) $$,
  'an event organiser can write a crossing via upsert_checkpoint_crossing');

-- A non-organiser authenticated user (plain member) is rejected 42501.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000201a2","role":"authenticated"}';
select throws_ok(
  $$ select upsert_checkpoint_crossing(
       '01010101-0101-0101-0101-010101010111',
       '01010101-0101-0101-0101-0101010101c1',
       '2026-06-06 06:00+00',
       null, '501', 'Mallory', '2026-06-06 08:05+00', null) $$,
  '42501',
  null,
  'a non-organiser member cannot write a crossing (RPC authz)');

-- A stranger (not even a member) is likewise rejected 42501.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000201a3","role":"authenticated"}';
select throws_ok(
  $$ select upsert_checkpoint_crossing(
       '01010101-0101-0101-0101-010101010111',
       '01010101-0101-0101-0101-0101010101c1',
       '2026-06-06 06:00+00',
       null, '502', 'Stranger', '2026-06-06 08:10+00', null) $$,
  '42501',
  null,
  'a non-member stranger cannot write a crossing (RPC authz)');

-- ============================================================
-- 2. crossings are readable per event visibility
-- ============================================================
-- anon can read a public-club public event's crossing (non-health columns).
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select count(*)::int from checkpoint_crossings
   where event_id = '01010101-0101-0101-0101-010101010111'),
  1, 'anon reads the public event''s crossings (event-visible)');

-- Flip the club private — anon now sees nothing (event no longer visible).
set local role service_role;
update clubs set is_public = false
  where id = '01010101-0101-0101-0101-010101010101';

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(
  (select count(*)::int from checkpoint_crossings
   where event_id = '01010101-0101-0101-0101-010101010111'),
  0, 'anon cannot read a private club''s event crossings');

-- restore public for the remaining assertions.
set local role service_role;
update clubs set is_public = true
  where id = '01010101-0101-0101-0101-010101010101';

-- ============================================================
-- 3. offline merge dedupe (earliest in / latest out → one row)
-- ============================================================
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000201a1","role":"authenticated"}';

-- First volunteer stamps only the in_time for bib 600.
select upsert_checkpoint_crossing(
  '01010101-0101-0101-0101-010101010111',
  '01010101-0101-0101-0101-0101010101c1',
  '2026-06-06 06:00+00',
  null, '600', 'Frank Merge',
  '2026-06-06 09:00+00', null);

-- Second volunteer (different phone, same runner) stamps only the out_time AND
-- an earlier in_time — the merge takes earliest-in / latest-out.
select upsert_checkpoint_crossing(
  '01010101-0101-0101-0101-010101010111',
  '01010101-0101-0101-0101-0101010101c1',
  '2026-06-06 06:00+00',
  null, '600', 'Frank Merge',
  '2026-06-06 08:55+00', '2026-06-06 09:10+00');

set local role service_role;
select is(
  (select count(*)::int from checkpoint_crossings
   where checkpoint_id = '01010101-0101-0101-0101-0101010101c1' and bib = '600'),
  1, 'two volunteer stamps for the same (checkpoint, instance, bib) collapse to ONE row');

select is(
  (select in_time from checkpoint_crossings
   where checkpoint_id = '01010101-0101-0101-0101-0101010101c1' and bib = '600'),
  '2026-06-06 08:55+00'::timestamptz,
  'the merged crossing keeps the earliest in_time');

select is(
  (select out_time from checkpoint_crossings
   where checkpoint_id = '01010101-0101-0101-0101-0101010101c1' and bib = '600'),
  '2026-06-06 09:10+00'::timestamptz,
  'the merged crossing keeps the latest out_time');

-- ============================================================
-- 4. identity rule: neither user_id nor bib → 23514
-- ============================================================
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000201a1","role":"authenticated"}';
select throws_ok(
  $$ select upsert_checkpoint_crossing(
       '01010101-0101-0101-0101-010101010111',
       '01010101-0101-0101-0101-0101010101c1',
       '2026-06-06 06:00+00',
       null, null, 'Ghost', '2026-06-06 09:30+00', null) $$,
  '23514',
  null,
  'an upsert naming neither a user_id nor a bib is rejected (identity rule)');

-- ============================================================
-- 5. health column-lock (Art 9 fields deny-by-default for select)
-- ============================================================
-- A direct table SELECT of a health column is denied for authenticated…
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000201a1","role":"authenticated"}';
select throws_ok(
  $$ select body_weight_kg from checkpoint_crossings
     where checkpoint_id = '01010101-0101-0101-0101-0101010101c1' limit 1 $$,
  '42501',
  null,
  'body_weight_kg is column-locked from authenticated (organiser reads via RPC)');

-- …and for anon.
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$ select body_weight_kg from checkpoint_crossings
     where checkpoint_id = '01010101-0101-0101-0101-0101010101c1' limit 1 $$,
  '42501',
  null,
  'body_weight_kg is column-locked from anon');

-- The non-health columns select fine for anon (public event).
select lives_ok(
  $$ select bib, in_time, out_time from checkpoint_crossings
     where checkpoint_id = '01010101-0101-0101-0101-0101010101c1' limit 1 $$,
  'the non-health columns are SELECT-able (column grant intact)');

-- ============================================================
-- 6. health fail-closed gate (decisions §150)
-- ============================================================
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000201a1","role":"authenticated"}';

-- (a) requires_weigh_in = false + consent = true → health value dropped to NULL.
select upsert_checkpoint_crossing(
  '01010101-0101-0101-0101-010101010111',
  '01010101-0101-0101-0101-0101010101c1',   -- Aid 1 (requires_weigh_in = false)
  '2026-06-06 06:00+00',
  null, '700', 'Gwen NoWeigh',
  '2026-06-06 10:00+00', null,
  true, 64.5);

-- (b) requires_weigh_in = true + consent = false → health value dropped to NULL.
select upsert_checkpoint_crossing(
  '01010101-0101-0101-0101-010101010111',
  '01010101-0101-0101-0101-0101010101c2',   -- Weigh Station (requires_weigh_in = true)
  '2026-06-06 06:00+00',
  null, '701', 'Hank NoConsent',
  '2026-06-06 11:00+00', null,
  false, 70.0);

-- (c) requires_weigh_in = true + consent = true → health value persists.
select upsert_checkpoint_crossing(
  '01010101-0101-0101-0101-010101010111',
  '01010101-0101-0101-0101-0101010101c2',   -- Weigh Station
  '2026-06-06 06:00+00',
  null, '702', 'Ivy Consents',
  '2026-06-06 11:05+00', null,
  true, 58.25);

set local role service_role;
select is(
  (select body_weight_kg from checkpoint_crossings
   where checkpoint_id = '01010101-0101-0101-0101-0101010101c1' and bib = '700'),
  null::numeric,
  'fail-closed: consent without requires_weigh_in drops the health value');

select is(
  (select body_weight_kg from checkpoint_crossings
   where checkpoint_id = '01010101-0101-0101-0101-0101010101c2' and bib = '701'),
  null::numeric,
  'fail-closed: requires_weigh_in without consent drops the health value');

select is(
  (select body_weight_kg from checkpoint_crossings
   where checkpoint_id = '01010101-0101-0101-0101-0101010101c2' and bib = '702'),
  58.25::numeric,
  'fail-closed: requires_weigh_in AND consent persists the health value');

-- ============================================================
-- 7. fetch_checkpoint_crossings_for_organiser
-- ============================================================
-- An organiser reads back the instance's crossings incl. the health columns.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000201a1","role":"authenticated"}';
select is(
  (select body_weight_kg
   from fetch_checkpoint_crossings_for_organiser(
     '01010101-0101-0101-0101-010101010111', '2026-06-06 06:00+00')
   where bib = '702'),
  58.25::numeric,
  'fetch_checkpoint_crossings_for_organiser returns health columns to an organiser');

-- A non-organiser is rejected 42501.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000201a3","role":"authenticated"}';
select throws_ok(
  $$ select * from fetch_checkpoint_crossings_for_organiser(
       '01010101-0101-0101-0101-010101010111', '2026-06-06 06:00+00') $$,
  '42501',
  null,
  'fetch_checkpoint_crossings_for_organiser rejects a non-organiser');

select * from finish();

rollback;
