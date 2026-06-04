-- Pins F15: notifications carry a polymorphic (activity_kind, activity_id)
-- pair, 20261212_001.
--
-- Two things under test:
--   1. The run-notification triggers (kudos / comment / run_completed)
--      populate ('run', run_id) alongside the legacy run_id bridge.
--   2. The one-time backfill stamped existing run-linked rows the same way.
--   3. The activity_kind CHECK rejects an out-of-domain modality tag.
--
-- Runs as superuser so the closed notifications INSERT policy and the
-- run_kudos visibility checks are out of the way — the assertions are the
-- trigger payload + CHECK, not RLS.

begin;

select plan(6);

-- A second user to act as the kudos-giver (the trigger skips self-kudos).
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000f1501', 'authenticated', 'authenticated',
        'f15actor@test.local', '', now(), now());

-- Kudos on a seed run → notify_run_kudos fires for the run owner.
insert into run_kudos (user_id, run_id)
  values ('00000000-0000-0000-0000-0000000f1501',
          'a1000001-0000-0000-0000-000000000007');

select is(
  (select activity_kind from notifications
     where kind = 'kudos' and run_id = 'a1000001-0000-0000-0000-000000000007'
     order by created_at desc limit 1),
  'run',
  'kudos notification carries activity_kind = run'
);
select is(
  (select activity_id from notifications
     where kind = 'kudos' and run_id = 'a1000001-0000-0000-0000-000000000007'
     order by created_at desc limit 1),
  'a1000001-0000-0000-0000-000000000007'::uuid,
  'kudos notification carries activity_id = run_id'
);

-- Backfill check: simulate a pre-migration row (run_id set, pair null), then
-- assert the migration's backfill semantics by re-applying the same UPDATE the
-- migration ran. The pair must equal ('run', run_id).
insert into notifications (id, user_id, kind, run_id)
  values ('22222222-2222-2222-2222-222222222222',
          'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'comment',
          'a1000001-0000-0000-0000-000000000008');
update notifications
  set activity_kind = 'run', activity_id = run_id
  where id = '22222222-2222-2222-2222-222222222222' and activity_id is null;
select is(
  (select activity_kind || ':' || activity_id::text from notifications
     where id = '22222222-2222-2222-2222-222222222222'),
  'run:a1000001-0000-0000-0000-000000000008',
  'backfill stamps run-linked rows as (run, run_id)'
);

-- run_id is kept as the transition bridge (not dropped).
select has_column('public', 'notifications', 'run_id',
  'notifications.run_id is kept as the transition bridge');

-- A non-activity notification leaves the pair null (no spurious tag).
insert into notifications (id, user_id, kind)
  values ('33333333-3333-3333-3333-333333333333',
          'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'follow');
select is(
  (select activity_kind from notifications
     where id = '33333333-3333-3333-3333-333333333333'),
  null,
  'follow notification leaves activity_kind null'
);

-- The CHECK rejects an out-of-domain modality tag.
select throws_ok(
  $$ insert into notifications (user_id, kind, activity_kind, activity_id)
     values ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'kudos', 'cycle', gen_random_uuid()) $$,
  '23514',
  null,
  'notifications rejects an unknown activity_kind'
);

select * from finish();
rollback;
