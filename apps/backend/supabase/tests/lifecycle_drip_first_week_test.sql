-- Pins migration 20270331_001 — the drip_first_week cohort in
-- enqueue_lifecycle_drip(): opted-in users with 1-2 runs total whose most
-- recent run is 2..5 days old get a one-shot "second run makes it a habit"
-- nudge; anyone outside that shape gets nothing, and a completed ('done')
-- job blocks re-enqueue (unlike the window-repeat cohorts).

begin;
select plan(6);

-- Four synthetic users:
--   aaaa — 1 run, 3 days ago, opted in            → enqueued
--   bbbb — 1 run, 1 day ago, opted in             → too fresh, not enqueued
--   cccc — 3 runs, latest 3 days ago, opted in    → too established, not enqueued
--   eeee — 1 run, 3 days ago, NOT opted in        → not enqueued
do $$
declare
  ids uuid[] := array[
    '88888888-8888-8888-8888-88888888aaaa',
    '88888888-8888-8888-8888-88888888bbbb',
    '88888888-8888-8888-8888-88888888cccc',
    '88888888-8888-8888-8888-88888888eeee'
  ];
  i int;
begin
  for i in 1..array_length(ids, 1) loop
    insert into auth.users (id, email, encrypted_password,
                            email_confirmed_at, instance_id, aud, role)
      values (ids[i], 'drip-fw-' || i || '@example.com', '',
              now(), '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated')
      on conflict (id) do nothing;
  end loop;
end $$;

insert into user_settings (user_id, prefs) values
  ('88888888-8888-8888-8888-88888888aaaa', '{"email_lifecycle_drip":"on"}'),
  ('88888888-8888-8888-8888-88888888bbbb', '{"email_lifecycle_drip":"on"}'),
  ('88888888-8888-8888-8888-88888888cccc', '{"email_lifecycle_drip":"on"}'),
  ('88888888-8888-8888-8888-88888888eeee', '{}')
on conflict (user_id) do update set prefs = excluded.prefs;

insert into runs (user_id, started_at, distance_m, duration_s, source) values
  ('88888888-8888-8888-8888-88888888aaaa', now() - interval '3 days', 3000, 1200, 'app'),
  ('88888888-8888-8888-8888-88888888bbbb', now() - interval '1 day',  3000, 1200, 'app'),
  ('88888888-8888-8888-8888-88888888cccc', now() - interval '20 days', 3000, 1200, 'app'),
  ('88888888-8888-8888-8888-88888888cccc', now() - interval '10 days', 3000, 1200, 'app'),
  ('88888888-8888-8888-8888-88888888cccc', now() - interval '3 days',  3000, 1200, 'app'),
  ('88888888-8888-8888-8888-88888888eeee', now() - interval '3 days',  3000, 1200, 'app');

select lives_ok(
  $q$ select enqueue_lifecycle_drip() $q$,
  'enqueue_lifecycle_drip() runs'
);

select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'template' = 'drip_first_week'
     and payload->>'user_id' = '88888888-8888-8888-8888-88888888aaaa'),
  1::bigint,
  '1 run / 3 days ago / opted in -> drip_first_week enqueued'
);

select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'template' = 'drip_first_week'
     and payload->>'user_id' = '88888888-8888-8888-8888-88888888bbbb'),
  0::bigint,
  'latest run only 1 day old -> not enqueued (too fresh)'
);

select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'template' = 'drip_first_week'
     and payload->>'user_id' = '88888888-8888-8888-8888-88888888cccc'),
  0::bigint,
  '3 runs total -> not enqueued (established runner)'
);

select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'template' = 'drip_first_week'
     and payload->>'user_id' = '88888888-8888-8888-8888-88888888eeee'),
  0::bigint,
  'not opted in -> never enqueued'
);

-- One-shot: mark the queued job done, re-run the enqueue — the 'done' row
-- blocks a second drip_first_week for the same user.
update jobs set status = 'done', finished_at = now()
where kind = 'lifecycle_drip'
  and payload->>'template' = 'drip_first_week'
  and payload->>'user_id' = '88888888-8888-8888-8888-88888888aaaa';

select enqueue_lifecycle_drip();

select is(
  (select count(*) from jobs
   where kind = 'lifecycle_drip'
     and payload->>'template' = 'drip_first_week'
     and payload->>'user_id' = '88888888-8888-8888-8888-88888888aaaa'),
  1::bigint,
  'a done drip_first_week blocks re-enqueue (one-shot per user)'
);

select * from finish();
rollback;
