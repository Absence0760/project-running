-- Pins migration 20270317_001 (Art 9 health-data retention on
-- checkpoint_crossings). The scrub function + cron entry exist, and a manual
-- call nulls the weigh-in / medical fields on crossings recorded more than 90
-- days ago while (a) keeping the in/out split times and (b) leaving fresh
-- crossings untouched.

begin;

select plan(5);

select has_function(
  'private', 'purge_stale_checkpoint_health_data', array[]::text[],
  'private.purge_stale_checkpoint_health_data() exists');

select is(
  (select count(*)::int from cron.job
     where jobname = 'purge-stale-checkpoint-health-data'),
  1,
  'pg_cron entry purge-stale-checkpoint-health-data is registered');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000317a1', 'authenticated', 'authenticated',
   'director@chr.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('03170317-0317-0317-0317-031703170301',
   '00000000-0000-0000-0000-0000000317a1', 'CHR Club', 'chr-club', true);

insert into events (id, club_id, title, starts_at, author_id)
values
  ('03170317-0317-0317-0317-031703170311',
   '03170317-0317-0317-0317-031703170301', 'CHR 100k',
   now() - interval '120 days', '00000000-0000-0000-0000-0000000317a1');

insert into event_checkpoints
  (id, event_id, name, ordinal, requires_weigh_in, created_by)
values
  ('03170317-0317-0317-0317-0317031703c1',
   '03170317-0317-0317-0317-031703170311', 'Weigh-in 1', 1, true,
   '00000000-0000-0000-0000-0000000317a1');

insert into checkpoint_crossings
  (id, event_id, checkpoint_id, instance_start, bib, runner_name,
   in_time, out_time, body_weight_kg, body_weight_pct, medical_hold,
   medical_note, recorded_at)
values
  ('03170317-0317-0317-0317-0317031703d1',
   '03170317-0317-0317-0317-031703170311',
   '03170317-0317-0317-0317-0317031703c1',
   now() - interval '120 days', '101', 'Aged Runner',
   now() - interval '120 days', now() - interval '120 days' + interval '5 minutes',
   72.50, -2.10, true, 'held 10 min for fluids', now() - interval '120 days'),
  ('03170317-0317-0317-0317-0317031703d2',
   '03170317-0317-0317-0317-031703170311',
   '03170317-0317-0317-0317-0317031703c1',
   now() - interval '10 days', '102', 'Fresh Runner',
   now() - interval '10 days', now() - interval '10 days' + interval '5 minutes',
   68.00, -1.30, false, null, now() - interval '10 days');

select private.purge_stale_checkpoint_health_data();

select results_eq(
  $$select body_weight_kg, body_weight_pct, medical_hold, medical_note
      from checkpoint_crossings
      where id = '03170317-0317-0317-0317-0317031703d1'$$,
  $$values (null::numeric(5,2), null::numeric(5,2), false, null::text)$$,
  'the >90-day crossing has its Art 9 health fields scrubbed');

select isnt(
  (select in_time from checkpoint_crossings
     where id = '03170317-0317-0317-0317-0317031703d1'),
  null,
  'the scrub keeps the in/out split times (they are race results)');

select results_eq(
  $$select body_weight_kg, medical_hold
      from checkpoint_crossings
      where id = '03170317-0317-0317-0317-0317031703d2'$$,
  $$values (68.00::numeric(5,2), false)$$,
  'a crossing inside the 90-day window keeps its health fields');

select * from finish();
rollback;
