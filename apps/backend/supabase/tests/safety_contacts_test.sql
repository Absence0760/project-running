-- Safety-contact finish alerts (migration 20261218_001_safety_contacts.sql).
--
-- Pins: owner-scoped RLS + the no-owner-UPDATE rule, the force-unconfirmed
-- insert guard, the confirm-email enqueue, the in-app + token confirm RPCs,
-- the email-only-matching pending lookup, and the finish-alert trigger
-- (fires for a CONFIRMED contact regardless of is_public, skips unconfirmed
-- contacts + bulk-import-old runs).

begin;

select plan(16);

-- Actors. owner runs; contact_a is an app user who'll confirm in-app;
-- stranger owns an unrelated list.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01', 'authenticated', 'authenticated', 'owner@safe.local',    '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c02', 'authenticated', 'authenticated', 'contacta@safe.local',  '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c03', 'authenticated', 'authenticated', 'stranger@safe.local',  '', now(), now());

insert into user_profiles (id, display_name, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01', 'Ada Owner', now(), now(), 'km', 'free');

-- ─────────── owner add (RLS insert) + confirm-email enqueue ───────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01"}';

-- Owner adds an app-user contact. Try to preset confirmed_at — the
-- BEFORE INSERT guard must force it back to unconfirmed.
insert into safety_contacts (owner_id, contact_email, confirmed_at, contact_user_id)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01', 'contacta@safe.local', now(),
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c02');

select is(
  (select count(*)::int from safety_contacts
   where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01'
     and confirmed_at is null and contact_user_id is null),
  1, 'INSERT is forced unconfirmed even when the client presets opt-in');

reset role;

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'confirm'
     and payload->>'contact_email' = 'contacta@safe.local'
     and payload->>'owner_name' = 'Ada Owner'),
  1, 'adding a contact enqueues exactly one safety_email confirm job carrying owner name + token');

select isnt(
  (select payload->>'confirm_token' from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'confirm' limit 1),
  null, 'the confirm job carries a confirm_token');

-- ─────────── unique (owner, lower(email)) ───────────

select throws_ok(
  $$ insert into safety_contacts (owner_id, contact_email)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01', 'ContactA@safe.local') $$,
  '23505', null, 'the same address (case-insensitive) cannot be added twice by one owner');

-- ─────────── not-self CHECK ───────────

select throws_ok(
  $$ update safety_contacts
       set contact_user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01'
     where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01' $$,
  '23514', null, 'a contact cannot be linked to the owner themselves');

-- ─────────── RLS: owner isolation + no owner UPDATE ───────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c03"}';
select is_empty(
  $$ select 1 from safety_contacts where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01' $$,
  'a stranger cannot read another owner''s safety contacts');
reset role;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01"}';
-- No owner UPDATE policy: the row isn't visible for update, so this affects
-- 0 rows (and cannot self-confirm).
update safety_contacts set confirmed_at = now()
  where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01';
reset role;
select is(
  (select count(*)::int from safety_contacts
   where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01' and confirmed_at is not null),
  0, 'an owner cannot self-confirm a contact via UPDATE (no owner UPDATE policy)');

-- ─────────── in-app confirm path (contact_a) ───────────

-- The contact sees the pending request addressed to their account email.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c02"}';
select is(
  (select count(*)::int from my_pending_safety_requests()),
  1, 'a contact sees the pending request addressed to their account email');
select is(
  (select owner_name from my_pending_safety_requests() limit 1),
  'Ada Owner', 'the pending request carries the owner display name');

-- A stranger whose email matches nothing sees nothing.
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c03"}';
select is_empty(
  $$ select 1 from my_pending_safety_requests() $$,
  'a user with no matching contact_email sees no pending requests');

-- Contact confirms. The pending row isn't directly SELECT-able by the
-- contact (by design) — the id comes from the definer pending-lookup.
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c02"}';
select is(
  confirm_safety_contact((select id from my_pending_safety_requests() limit 1)),
  true, 'the contact confirms their own pending request');
reset role;

select is(
  (select count(*)::int from safety_contacts
   where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01'
     and confirmed_at is not null
     and contact_user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c02'),
  1, 'confirming sets confirmed_at and links the contact''s account');

-- ─────────── finish-alert trigger (private run, confirmed contact) ───────────

insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb5c01',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01', now(), 1800, 5000, 'app', false);

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'finish'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb5c01'),
  1, 'a PRIVATE run finish enqueues a safety_email finish job for the confirmed contact');

-- ─────────── bulk-import guard: an old run does not alert ───────────

insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb5c02',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c01', now() - interval '3 days', 1800, 5000, 'app', false);

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'finish'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb5c02'),
  0, 'a run older than 24h (bulk import) does not enqueue a finish alert');

-- ─────────── unconfirmed contact gets no alert ───────────

-- stranger as owner adds an unconfirmed contact, then finishes a run.
insert into safety_contacts (owner_id, contact_email)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c03', 'pending@safe.local');
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb5c03',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c03', now(), 1800, 5000, 'app', true);
select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'finish'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb5c03'),
  0, 'a finish with only an UNCONFIRMED contact enqueues no alert');

-- ─────────── email-link (token) confirm for an external contact ───────────

select is(
  (select confirm_safety_contact_by_token(confirm_token) from safety_contacts
   where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5c03'),
  true, 'an external contact confirms via the unguessable email-link token');

select * from finish();

rollback;
