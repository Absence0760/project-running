-- Off-route → auto-notify-contact escalation (migration 20270414_001,
-- docs/features/safety.md).
--
-- Pins the escalate_run_off_route(p_run_id) RPC: fires an off_route email per
-- confirmed contact (+ additive SMS for an opted-in phone) for the OWNER's
-- in-progress broadcast run, sharing the once-per-run safety_escalated_at
-- stamp; fail-closed on a missing opt-in pref / no confirmed contact / a
-- non-owner caller / a saved run / an already-stamped run.

begin;

select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01', 'authenticated', 'authenticated', 'runner@ofr.local',  '', now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccc02', 'authenticated', 'authenticated', 'contact@ofr.local', '', now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccc03', 'authenticated', 'authenticated', 'other@ofr.local',   '', now(), now());

insert into user_profiles (id, display_name, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
values ('cccccccc-cccc-cccc-cccc-cccccccccc01', 'Ola Offroute', now(), now(), 'km', 'free');

-- Runner opted into off-route alerts + one confirmed contact with SMS opt-in.
insert into user_settings (user_id, prefs)
values ('cccccccc-cccc-cccc-cccc-cccccccccc01', '{"safety_off_route_alerts": true}');

insert into safety_contacts (owner_id, contact_email, contact_phone)
values ('cccccccc-cccc-cccc-cccc-cccccccccc01', 'contact@ofr.local', '+447700900123');
update safety_contacts
  set confirmed_at = now(),
      contact_user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc02',
      sms_opt_in_at = now()
  where owner_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01';

-- The active broadcast stub + a recent ping (the runner is being tracked).
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('dddddddd-dddd-dddd-dddd-dddddddddd01', 'cccccccc-cccc-cccc-cccc-cccccccccc01',
        now() - interval '25 minutes', 0, 0, 'app', 'run', true, '{"activity_type": "run", "in_progress": true}');
insert into live_run_pings (run_id, user_id, at, lat, lng)
values ('dddddddd-dddd-dddd-dddd-dddddddddd01', 'cccccccc-cccc-cccc-cccc-cccccccccc01',
        now() - interval '2 minutes', 51.5, -0.12);

delete from public.jobs;

-- ─────────── a non-owner caller escalates nothing ───────────

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccc03","role":"authenticated"}';

select is(
  public.escalate_run_off_route('dddddddd-dddd-dddd-dddd-dddddddddd01'),
  false, 'a non-owner call does not escalate');
select is(
  (select count(*)::int from public.jobs where payload->>'template' = 'off_route'),
  0, 'a non-owner call enqueues no off_route jobs');

-- ─────────── the owner escalates: email + SMS, once, stamped ───────────

set local "request.jwt.claims" = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccc01","role":"authenticated"}';

select is(
  public.escalate_run_off_route('dddddddd-dddd-dddd-dddd-dddddddddd01'),
  true, 'the owner escalates their own in-progress broadcast run');

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_email' and payload->>'template' = 'off_route'
     and payload->>'contact_email' = 'contact@ofr.local'
     and payload->>'run_id' = 'dddddddd-dddd-dddd-dddd-dddddddddd01'
     and payload->>'owner_name' = 'Ola Offroute'
     and payload ? 'last_seen_at'),
  1, 'one off_route email per confirmed contact, carrying last_seen_at');

select is(
  (select count(*)::int from public.jobs
   where kind = 'safety_sms' and payload->>'template' = 'off_route'
     and payload->>'contact_phone' = '+447700900123'),
  1, 'one additive off_route SMS for the opted-in phone');

select isnt(
  (select metadata->>'safety_escalated_at' from runs
   where id = 'dddddddd-dddd-dddd-dddd-dddddddddd01'),
  null, 'the escalated run is stamped safety_escalated_at');

-- Second call: already stamped → no-op, no second job.
select is(
  public.escalate_run_off_route('dddddddd-dddd-dddd-dddd-dddddddddd01'),
  false, 'a second call on an already-escalated run no-ops');
select is(
  (select count(*)::int from public.jobs where payload->>'template' = 'off_route'),
  2, 'no duplicate off_route jobs on a re-call (1 email + 1 sms)');

-- ─────────── fail-closed: opt-out pref → never escalates ───────────

delete from public.jobs;
update user_settings set prefs = '{"safety_off_route_alerts": false}'
  where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('dddddddd-dddd-dddd-dddd-dddddddddd02', 'cccccccc-cccc-cccc-cccc-cccccccccc01',
        now() - interval '10 minutes', 0, 0, 'app', 'run', true, '{"activity_type": "run", "in_progress": true}');

select is(
  public.escalate_run_off_route('dddddddd-dddd-dddd-dddd-dddddddddd02'),
  false, 'no safety_off_route_alerts opt-in means no escalation (fail-closed)');

-- ─────────── fail-closed: no confirmed contact → never escalates ───────────

update user_settings set prefs = '{"safety_off_route_alerts": true}'
  where user_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01';
update safety_contacts set confirmed_at = null
  where owner_id = 'cccccccc-cccc-cccc-cccc-cccccccccc01';

select is(
  public.escalate_run_off_route('dddddddd-dddd-dddd-dddd-dddddddddd02'),
  false, 'no confirmed contact means no escalation (fail-closed)');

select * from finish();
rollback;
