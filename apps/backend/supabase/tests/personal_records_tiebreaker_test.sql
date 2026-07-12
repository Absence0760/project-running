-- Pins migration 20270405_001 — deterministic PR selection on tied times
-- (bughunt #4). Before the fix, `refresh_personal_records_for_user` ranked
-- candidates with `order by duration_s asc` only, so two efforts sharing the
-- exact same `duration_s` broke the tie arbitrarily and the credited
-- `run_id` / `achieved_at` could flip between rebuilds. The tiebreaker is
-- `order by duration_s asc, achieved_at asc, run_id asc` — earliest effort,
-- then lowest run_id — so the SAME physical run wins every refresh.

begin;
select plan(5);

do $$
declare
  v_user uuid := '77777777-7777-7777-7777-777777777aaa';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_user, 'pr-tiebreak@example.com', '',
            now(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated')
    on conflict (id) do nothing;
end $$;

-- Two 5k runs at the IDENTICAL time (1200 s) but different start dates.
-- The earlier `achieved_at` (run …01, May 1) must win over the later one
-- (run …02, May 8) — and win every rebuild.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values
  ('77777777-7777-7777-7777-777777770001',
   '77777777-7777-7777-7777-777777777aaa',
   '2026-05-01 09:00:00+00', 5000, 1200, 'app', '{"activity_type":"run"}'),
  ('77777777-7777-7777-7777-777777770002',
   '77777777-7777-7777-7777-777777777aaa',
   '2026-05-08 09:00:00+00', 5000, 1200, 'app', '{"activity_type":"run"}');

-- Two 10k runs at the identical time (2400 s) AND the identical start
-- instant, differing only by run_id. The lower run_id (…03 < …04) must win,
-- exercising the final `run_id asc` rung of the tiebreaker.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata)
values
  ('77777777-7777-7777-7777-777777770004',
   '77777777-7777-7777-7777-777777777aaa',
   '2026-06-01 09:00:00+00', 10000, 2400, 'app', '{"activity_type":"run"}'),
  ('77777777-7777-7777-7777-777777770003',
   '77777777-7777-7777-7777-777777777aaa',
   '2026-06-01 09:00:00+00', 10000, 2400, 'app', '{"activity_type":"run"}');

do $$
begin
  perform refresh_personal_records_for_user(
    '77777777-7777-7777-7777-777777777aaa'::uuid
  );
end $$;

select is(
  (select run_id from personal_records
   where user_id = '77777777-7777-7777-7777-777777777aaa' and distance = '5k'),
  '77777777-7777-7777-7777-777777770001'::uuid,
  'tied 5k time: earliest achieved_at wins'
);

select is(
  (select run_id from personal_records
   where user_id = '77777777-7777-7777-7777-777777777aaa' and distance = '10k'),
  '77777777-7777-7777-7777-777777770003'::uuid,
  'tied 10k time + tied achieved_at: lowest run_id wins'
);

-- Determinism: capture each bucket's winner, refresh several more times, and
-- assert the credited run never moves. Under the old arbitrary tiebreak this
-- could flip on any rebuild.
do $$
declare
  v_5k_first  uuid;
  v_10k_first uuid;
  i int;
begin
  select run_id into v_5k_first from personal_records
    where user_id = '77777777-7777-7777-7777-777777777aaa' and distance = '5k';
  select run_id into v_10k_first from personal_records
    where user_id = '77777777-7777-7777-7777-777777777aaa' and distance = '10k';

  for i in 1..5 loop
    perform refresh_personal_records_for_user(
      '77777777-7777-7777-7777-777777777aaa'::uuid
    );
  end loop;

  create temporary table _tiebreak_check on commit drop as
  select
    v_5k_first  as prev_5k,
    v_10k_first as prev_10k,
    (select run_id from personal_records
       where user_id = '77777777-7777-7777-7777-777777777aaa' and distance = '5k')  as now_5k,
    (select run_id from personal_records
       where user_id = '77777777-7777-7777-7777-777777777aaa' and distance = '10k') as now_10k;
end $$;

select is(
  (select now_5k from _tiebreak_check),
  (select prev_5k from _tiebreak_check),
  '5k PB run_id is stable across repeated refreshes'
);

select is(
  (select now_10k from _tiebreak_check),
  (select prev_10k from _tiebreak_check),
  '10k PB run_id is stable across repeated refreshes'
);

-- Exactly one row per tied bucket — the tiebreaker collapses to a single
-- winner, it doesn't emit both tied runs.
select is(
  (select count(*) from personal_records
   where user_id = '77777777-7777-7777-7777-777777777aaa'),
  2::bigint,
  'two tied buckets collapse to exactly two PR rows'
);

select * from finish();
rollback;
