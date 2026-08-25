-- Pins migration 20270606_001 on the two segment boards: an age band is an
-- Art 9 *use* of the date of birth, so it goes behind health_data_consent_at.
--
-- decisions § 718 open item 2, closed as § 727. `user_profiles.date_of_birth`
-- is the **age record** — child protection, no consent term, which is why
-- 20270605_001 stopped withdraw_health_data_consent() erasing it (§ 721). But
-- deriving an age from it is a health inference, and both boards banded on
-- `extract(year from age(up.date_of_birth))` while checking nothing. This is
-- the server half of the rule the health_consent parity pair carries on the
-- clients (§ 722).
--
--   1. A runner WITH the Art 9 stamp is banded, on both boards.
--   2. A runner with a date but NO stamp falls out of the age tier entirely —
--      not into a wrong one — which is exactly what the adjacent
--      `date_of_birth is not null` branch already does for a runner with no
--      date at all. The two are pinned as indistinguishable.
--   3. The consent term gates the age TIER, not the athlete: an unconsented
--      runner is untouched on the unfiltered all-comers board.
--   4. The caller's own `age` echo carries the same term, because the
--      DERIVATION is the processing — `healthUseDob` returns null for
--      `consent_withheld` on the runner's own row too.
--   5. The gender tier is unaffected and gains no term of its own: `gender` is
--      only ever populated under consent, so it was already correct.
--
-- Reads as authenticated callers via `set local "request.jwt.claims"`.
-- No service-role bypass.

begin;

select plan(10);

-- ── Fixture: an owner plus three athletes born on the same day ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ac001', 'authenticated', 'authenticated',
   'owner@agc.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ac002', 'authenticated', 'authenticated',
   'consented@agc.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ac003', 'authenticated', 'authenticated',
   'withheld@agc.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ac004', 'authenticated', 'authenticated',
   'nodate@agc.local', '', now(), now());

-- ac002 and ac003 are the same age and the same gender; the ONLY thing that
-- differs is the Art 9 stamp. ac004 carries no date at all and is the control
-- the withheld runner must be indistinguishable from. The stamp is written
-- directly because `tests.confirm_consent()` stamps the Art 8 age-confirmation
-- columns, which are a different gate on a different lawful basis.
insert into user_profiles (id, display_name, gender, date_of_birth, health_data_consent_at)
values
  ('00000000-0000-0000-0000-0000000ac001', 'Route Owner', 'male', null, null),
  ('00000000-0000-0000-0000-0000000ac002', 'Consented Forty', 'male',
   (now() - interval '41 years')::date, now()),
  ('00000000-0000-0000-0000-0000000ac003', 'Withheld Forty', 'male',
   (now() - interval '41 years')::date, null),
  ('00000000-0000-0000-0000-0000000ac004', 'No Date At All', 'male', null, null);

select tests.confirm_consent();

-- The catalogue is curated, so `global_segments` carries no authenticated
-- INSERT policy — it is seeded before the role switch, as the sibling suites do.
insert into global_segments (id, name, waypoints, distance_m, is_active)
values ('a9a9a9a9-0000-0000-0000-0000000000c1', 'Consent Climb',
        '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, true);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac001"}';
insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values ('66666666-6666-6666-6666-66666666ac01',
        '00000000-0000-0000-0000-0000000ac001', 'Consent Loop',
        '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]', 10000, true);

insert into segments (id, route_id, name, start_distance_m, end_distance_m, author_id)
values ('77777777-7777-7777-7777-77777777ac01',
        '66666666-6666-6666-6666-66666666ac01', 'Consent Sprint', 500, 1500,
        '00000000-0000-0000-0000-0000000ac001');

-- Each athlete plants one effort on each board. Times are distinct so the
-- ordering is deterministic.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac002"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ac02', '00000000-0000-0000-0000-0000000ac002',
        now(), 10000, 1800, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('77777777-7777-7777-7777-77777777ac01', '88888888-8888-8888-8888-88888888ac02',
        '00000000-0000-0000-0000-0000000ac002', 100, now() - interval '3 hours');
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('a9a9a9a9-0000-0000-0000-0000000000c1', '88888888-8888-8888-8888-88888888ac02',
        '00000000-0000-0000-0000-0000000ac002', 100, now() - interval '3 hours');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac003"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ac03', '00000000-0000-0000-0000-0000000ac003',
        now(), 10000, 1810, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('77777777-7777-7777-7777-77777777ac01', '88888888-8888-8888-8888-88888888ac03',
        '00000000-0000-0000-0000-0000000ac003', 110, now() - interval '2 hours');
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('a9a9a9a9-0000-0000-0000-0000000000c1', '88888888-8888-8888-8888-88888888ac03',
        '00000000-0000-0000-0000-0000000ac003', 110, now() - interval '2 hours');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac004"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888ac04', '00000000-0000-0000-0000-0000000ac004',
        now(), 10000, 1820, 'app', '{"activity_type":"run"}'::jsonb, true);
insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('77777777-7777-7777-7777-77777777ac01', '88888888-8888-8888-8888-88888888ac04',
        '00000000-0000-0000-0000-0000000ac004', 120, now() - interval '1 hour');
insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values ('a9a9a9a9-0000-0000-0000-0000000000c1', '88888888-8888-8888-8888-88888888ac04',
        '00000000-0000-0000-0000-0000000ac004', 120, now() - interval '1 hour');

-- ── Cohort reads as the route owner, who holds no effort of their own ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac001"}';

-- 1. The headline: two athletes are 41, one consented. Only the consented one
--    is in the 40-44 tier. Pre-fix this returned both.
select results_eq(
  $$ select user_id::text from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-77777777ac01'::uuid, null, '40-44', 50) $$,
  $$ values ('00000000-0000-0000-0000-0000000ac002') $$,
  'route board: only the runner with the Art 9 stamp is banded by age'
);

-- 2. The unconsented runner falls out of the tier the same way a runner with
--    no date at all does — not into a neighbouring band. Nothing in the age
--    dimension can distinguish them, which is the consistency claim the
--    migration makes about the adjacent `date_of_birth is not null` branch.
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777ac01'::uuid, null, '40-44', 50)
   where user_id in ('00000000-0000-0000-0000-0000000ac003',
                     '00000000-0000-0000-0000-0000000ac004')),
  0,
  'route board: a withheld date and no date are both absent from the band'
);

-- 3. No age band the runner could fall into contains them, so this is not a
--    band-edge artefact.
select is(
  (select count(*)::int from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777ac01'::uuid, null, '35-39', 50))
  + (select count(*)::int from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-77777777ac01'::uuid, null, '45-49', 50)),
  0,
  'route board: the withheld runner is in no neighbouring band either'
);

-- 4. The consent term gates the age TIER, not the athlete. All three keep
--    their place on the unfiltered all-comers board — spending a privacy gate
--    on a competitive ranking that never needed the age would be the wrong
--    kind of narrowing.
select results_eq(
  $$ select user_id::text from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-77777777ac01'::uuid, null, null, 50) $$,
  $$ values
       ('00000000-0000-0000-0000-0000000ac002'),
       ('00000000-0000-0000-0000-0000000ac003'),
       ('00000000-0000-0000-0000-0000000ac004')
  $$,
  'route board: the unfiltered board is untouched by the consent term'
);

-- 5. The gender tier gains no term of its own and must not change: `gender` is
--    only ever populated under consent, so it was already correct. A fix that
--    widened the gate to every demographic column would surface here.
select results_eq(
  $$ select user_id::text from segment_leaderboard_tiered(
       '77777777-7777-7777-7777-77777777ac01'::uuid, 'male', null, 50) $$,
  $$ values
       ('00000000-0000-0000-0000-0000000ac002'),
       ('00000000-0000-0000-0000-0000000ac003'),
       ('00000000-0000-0000-0000-0000000ac004')
  $$,
  'route board: the gender tier is unaffected by the age consent term'
);

-- ── The caller's own age echo carries the same term ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac002"}';
select cmp_ok(
  (select age from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777ac01'::uuid, null, null, 50)
   where user_id = '00000000-0000-0000-0000-0000000ac002'),
  '>=', 41,
  'route board: a consented caller still sees their own age'
);

-- 6. The withheld caller gets null — the derivation is the processing, so
--    consent is what authorises it even about oneself. This is the same
--    answer `healthUseDob` gives for `consent_withheld` on the client.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac003"}';
select is(
  (select age from segment_leaderboard_tiered(
     '77777777-7777-7777-7777-77777777ac01'::uuid, null, null, 50)
   where user_id = '00000000-0000-0000-0000-0000000ac003'),
  null::integer,
  'route board: a withheld caller gets no age echo about themselves'
);

-- ── The catalogue board carries the identical rule ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac001"}';

select results_eq(
  $$ select user_id::text from global_segment_leaderboard(
       'a9a9a9a9-0000-0000-0000-0000000000c1'::uuid, null, '40-44', 50) $$,
  $$ values ('00000000-0000-0000-0000-0000000ac002') $$,
  'catalogue board: only the runner with the Art 9 stamp is banded by age'
);

select results_eq(
  $$ select user_id::text from global_segment_leaderboard(
       'a9a9a9a9-0000-0000-0000-0000000000c1'::uuid, null, null, 50) $$,
  $$ values
       ('00000000-0000-0000-0000-0000000ac002'),
       ('00000000-0000-0000-0000-0000000ac003'),
       ('00000000-0000-0000-0000-0000000ac004')
  $$,
  'catalogue board: the unfiltered board is untouched by the consent term'
);

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac003"}';
select is(
  (select age from global_segment_leaderboard(
     'a9a9a9a9-0000-0000-0000-0000000000c1'::uuid, null, null, 50)
   where user_id = '00000000-0000-0000-0000-0000000ac003'),
  null::integer,
  'catalogue board: a withheld caller gets no age echo about themselves'
);

select * from finish();
rollback;
