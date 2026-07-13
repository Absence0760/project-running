-- SMS escalation channel + per-run "not back by X" override
-- (migration 20270410_001, docs/features/safety.md).
--
-- Pins: the per-run expected_return_at override branch of the overdue scan
-- (fires without the universal pref), the additive safety_sms leg (only for a
-- confirmed contact with a stored phone AND an SMS opt-in — email always
-- accompanies it), the SMS opt-in double-consent (armed only with a phone on
-- file, owner cannot self-set), set_run_expected_return owner+stub gating, the
-- E.164 phone CHECK, and public_runs stripping expected_return_at.

begin;

select plan(16);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501', 'authenticated', 'authenticated', 'runner@sms.local',   '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7502', 'authenticated', 'authenticated', 'contact@sms.local',  '', now(), now()),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7503', 'authenticated', 'authenticated', 'other@sms.local',    '', now(), now());

insert into user_profiles (id, display_name, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501', 'Sam SMS', now(), now(), 'km', 'free');

-- ─────────── E.164 CHECK ───────────

select throws_ok(
  $$insert into safety_contacts (owner_id, contact_email, contact_phone)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501', 'bad@sms.local', '07700 900123')$$,
  '23514',
  null,
  'a non-E.164 phone is rejected by the CHECK');

-- Owner adds a contact WITH a phone. The force-unconfirmed trigger nulls
-- confirmed_at / contact_user_id / sms_opt_in_at regardless of input.
insert into safety_contacts (owner_id, contact_email, contact_phone, confirmed_at, sms_opt_in_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501', 'contact@sms.local', '+447700900123', now(), now());

select is(
  (select sms_opt_in_at is null and confirmed_at is null
   from safety_contacts where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501'),
  true, 'insert cannot preset confirmed_at or sms_opt_in_at (defense in depth)');

-- ─────────── contact confirms WITH SMS opt-in ───────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7502"}';
select is(
  (select has_phone from my_pending_safety_requests() limit 1),
  true, 'the pending request surfaces has_phone so the confirm UI can offer SMS');
select is(
  confirm_safety_contact((select id from my_pending_safety_requests() limit 1), true),
  true, 'the contact confirms and opts into SMS in one call');
reset role;

select isnt(
  (select sms_opt_in_at from safety_contacts
   where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501'),
  null, 'confirming with p_sms_opt_in and a phone on file arms sms_opt_in_at');

-- ─────────── overdue scan: per-run override fires WITHOUT the universal pref ───────────

-- No user_settings row at all for this runner: only the per-run override can
-- make them overdue.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7501', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501',
        now() - interval '20 minutes', 0, 0, 'app', 'run', true,
        jsonb_build_object('activity_type', 'run', 'in_progress', true,
                           'expected_return_at', to_char(now() - interval '2 minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')));

delete from public.jobs;
select public.enqueue_safety_overdue_emails();

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'overdue'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7501'),
  1, 'a passed per-run expected_return_at fires the overdue email with no universal pref');

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_sms' and payload->>'template' = 'overdue'
     and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7501'
     and payload->>'contact_phone' = '+447700900123'),
  1, 'an SMS-opted confirmed contact with a phone gets an additive safety_sms job');

select isnt(
  (select metadata->>'safety_escalated_at' from runs
   where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7501'),
  null, 'the per-run override match is stamped once');

-- A future expected_return_at does not fire.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7502', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501',
        now() - interval '5 minutes', 0, 0, 'app', 'run', true,
        jsonb_build_object('activity_type', 'run', 'in_progress', true,
                           'expected_return_at', to_char(now() + interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SSOF')));
select public.enqueue_safety_overdue_emails();
select is(
  (select count(*)::int from public.jobs
   where payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7502'),
  0, 'a still-in-the-future expected_return_at does not fire');

-- ─────────── SMS leg is additive, never gating: contact without phone/opt-in gets email only ───────────

insert into safety_contacts (owner_id, contact_email)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501', 'other@sms.local');
update safety_contacts set confirmed_at = now(), contact_user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7503'
  where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501' and contact_email = 'other@sms.local';

insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7503', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501',
        now() - interval '20 minutes', 0, 0, 'app', 'run', true,
        jsonb_build_object('activity_type', 'run', 'in_progress', true,
                           'expected_return_at', to_char(now() - interval '2 minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF')));
delete from public.jobs;
select public.enqueue_safety_overdue_emails();

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7503'),
  2, 'both confirmed contacts get the email (the guaranteed floor)');

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_sms' and payload->>'run_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7503'),
  1, 'only the SMS-opted contact with a phone gets an SMS — the email-only contact does not');

-- ─────────── set_safety_sms_opt_in toggles off ───────────

-- Resolve the row id as superuser: the RPC is SECURITY DEFINER, so the
-- caller never needs a direct SELECT grant on safety_contacts.
select id as sms_row from safety_contacts
  where contact_user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7502' \gset

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7502"}';
select is(
  set_safety_sms_opt_in(:'sms_row', false),
  true, 'a linked contact can withdraw SMS consent');
reset role;

select is(
  (select sms_opt_in_at from safety_contacts
   where contact_user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7502'),
  null, 'withdrawing SMS consent clears sms_opt_in_at');

-- ─────────── set_run_expected_return: owner + in-progress only ───────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7501"}';
select is(
  set_run_expected_return('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7502', now() + interval '30 minutes'),
  true, 'the owner can set an expected-return on their own in-progress run');

-- A non-owner cannot.
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa7503"}';
select is(
  set_run_expected_return('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7502', now() + interval '30 minutes'),
  false, 'a non-owner cannot set an expected-return on someone else''s run');
reset role;

-- ─────────── public_runs strips expected_return_at ───────────

select is(
  (select metadata ? 'expected_return_at' from public_runs
   where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb7502'),
  false, 'public_runs never exposes the owner-private expected_return_at');

select * from finish();
rollback;
