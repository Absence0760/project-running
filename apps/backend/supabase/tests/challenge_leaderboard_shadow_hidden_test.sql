-- Pins migration 20270524_001 on `challenge_leaderboard`: the third SECURITY
-- DEFINER board that joined `user_profiles` and so bypassed the
-- "authenticated read profiles except shadow-hidden" policy (20270329_001).
--
--   1. A shadow-hidden participant's display name is withheld from others.
--   2. Their ROW and their rank survive — dropping them would restate every
--      other participant's position, and the ranking is over runs the viewer
--      is already entitled to see.
--   3. They still see their own name.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000fc001', 'authenticated', 'authenticated',
   'hidden@chlb.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fc002', 'authenticated', 'authenticated',
   'visible@chlb.local', '', now(), now());

insert into user_profiles (id, display_name, shadow_hidden)
values
  ('00000000-0000-0000-0000-0000000fc001', 'Hidden Runner', true),
  ('00000000-0000-0000-0000-0000000fc002', 'Visible Runner', false);

select tests.confirm_consent();

insert into challenges (id, creator_id, title, metric, scope, goal_value,
                        starts_at, ends_at, is_public)
values ('cbcbcbcb-0000-0000-0000-0000000000c1',
        '00000000-0000-0000-0000-0000000fc002', 'Backstop Challenge',
        'distance', 'individual', 50000,
        now() - interval '2 days', now() + interval '5 days', true);

set local role authenticated;

-- The hidden runner leads the board on distance.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fc001"}';
insert into challenge_participants (challenge_id, user_id)
values ('cbcbcbcb-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000fc001');
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888fc01', '00000000-0000-0000-0000-0000000fc001',
        now() - interval '1 day', 20000, 6000, 'app', '{"activity_type":"run"}'::jsonb, true);

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fc002"}';
insert into challenge_participants (challenge_id, user_id)
values ('cbcbcbcb-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000fc002');
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('88888888-8888-8888-8888-88888888fc02', '00000000-0000-0000-0000-0000000fc002',
        now() - interval '1 day', 10000, 3000, 'app', '{"activity_type":"run"}'::jsonb, true);

-- ── Read as the visible participant ──
select is(
  (select count(*)::int from challenge_leaderboard('cbcbcbcb-0000-0000-0000-0000000000c1'::uuid)),
  2,
  'both participants remain on the board'
);

select results_eq(
  $$ select user_id::text, display_name, value, rank
       from challenge_leaderboard('cbcbcbcb-0000-0000-0000-0000000000c1'::uuid) $$,
  $$ values
       ('00000000-0000-0000-0000-0000000fc001', null::text, 20000::numeric, 1::bigint),
       ('00000000-0000-0000-0000-0000000fc002', 'Visible Runner', 10000::numeric, 2::bigint)
  $$,
  'a shadow-hidden participant keeps their value and rank but loses their name'
);

select is(
  (select rank from challenge_leaderboard('cbcbcbcb-0000-0000-0000-0000000000c1'::uuid)
     where user_id = '00000000-0000-0000-0000-0000000fc002'),
  2::bigint,
  'the visible participant''s rank is not restated by the redaction'
);

-- ── The hidden participant still sees their own name ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000fc001"}';

select is(
  (select display_name from challenge_leaderboard('cbcbcbcb-0000-0000-0000-0000000000c1'::uuid)
     where user_id = '00000000-0000-0000-0000-0000000fc001'),
  'Hidden Runner',
  'a shadow-hidden participant still sees their own name'
);

select * from finish();
rollback;
