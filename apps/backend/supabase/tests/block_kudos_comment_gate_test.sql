-- Pins 20270204_001 — the block gate on run_kudos / run_comments INSERT
-- actually denies a blocked pair's cross-user engagement.
--
-- Regression: before 20270204_001 the gate's owner subquery
-- (select r.user_id from runs r where r.id = run_id) ran under the
-- INSERTing user's `runs` RLS, which (since 20260701_001 dropped the
-- public-runs SELECT policy on the base table) returns NULL for anyone
-- else's run — so the block predicate was always satisfied and a
-- harassed runner's block never stopped kudos/comment notifications.
-- The fix resolves the owner in a SECURITY DEFINER predicate; these
-- tests fail against the old policy and pass against the fixed one.

begin;
select plan(6);

do $$
declare
  v_alice uuid := '88888888-8888-8888-8888-888888aaaaaa';
  v_bob   uuid := '88888888-8888-8888-8888-888888bbbbbb';
  v_carol uuid := '88888888-8888-8888-8888-888888cccccc';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_alice, 'alice-bkg@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_bob, 'bob-bkg@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_carol, 'carol-bkg@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
    values (v_alice, 'Alice', 'km', 'free'),
           (v_bob,   'Bob',   'km', 'free'),
           (v_carol, 'Carol', 'km', 'free')
    on conflict (id) do nothing;
  -- Bob's + Alice's PUBLIC runs (metadata.activity_type required by the
  -- 20260601_001 CHECK).
  insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
    values ('99999999-9999-9999-9999-999999bbbbbb', v_bob, now(), 5000, 1500, 'app', true,
            '{"activity_type":"run"}'),
           ('99999999-9999-9999-9999-999999aaaaaa', v_alice, now(), 5000, 1500, 'app', true,
            '{"activity_type":"run"}')
    on conflict (id) do nothing;
end $$;

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888aaaaaa","role":"authenticated"}';

-- 1-2. Before any block, Alice can engage with Bob's public run.
select lives_ok(
  $$ insert into run_kudos (user_id, run_id)
       values ('88888888-8888-8888-8888-888888aaaaaa'::uuid,
               '99999999-9999-9999-9999-999999bbbbbb'::uuid) $$,
  'Alice can kudos Bob''s public run before any block'
);
select lives_ok(
  $$ insert into run_comments (run_id, author_id, body)
       values ('99999999-9999-9999-9999-999999bbbbbb'::uuid,
               '88888888-8888-8888-8888-888888aaaaaa'::uuid, 'nice run') $$,
  'Alice can comment on Bob''s public run before any block'
);

-- Clear Alice's pre-block engagement so the post-block retries are fresh
-- INSERTs (not pk-dup 23505 that would mask the 42501 we test for).
set local role service_role;
delete from run_kudos where user_id = '88888888-8888-8888-8888-888888aaaaaa'::uuid;
delete from run_comments where author_id = '88888888-8888-8888-8888-888888aaaaaa'::uuid;

-- Alice blocks Bob.
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888aaaaaa","role":"authenticated"}';
do $$ begin perform block_user('88888888-8888-8888-8888-888888bbbbbb'::uuid); end $$;

-- 3-4. Post-block, Alice (blocker) can no longer kudos / comment Bob's run.
select throws_ok(
  $$ insert into run_kudos (user_id, run_id)
       values ('88888888-8888-8888-8888-888888aaaaaa'::uuid,
               '99999999-9999-9999-9999-999999bbbbbb'::uuid) $$,
  '42501',
  null,
  'blocker''s kudos on the blockee''s run is denied (was the leak)'
);
select throws_ok(
  $$ insert into run_comments (run_id, author_id, body)
       values ('99999999-9999-9999-9999-999999bbbbbb'::uuid,
               '88888888-8888-8888-8888-888888aaaaaa'::uuid, 'post-block') $$,
  '42501',
  null,
  'blocker''s comment on the blockee''s run is denied (was the leak)'
);

-- 5. Symmetric: Bob (the blockee) can't kudos Alice's run either.
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888bbbbbb","role":"authenticated"}';
select throws_ok(
  $$ insert into run_kudos (user_id, run_id)
       values ('88888888-8888-8888-8888-888888bbbbbb'::uuid,
               '99999999-9999-9999-9999-999999aaaaaa'::uuid) $$,
  '42501',
  null,
  'blockee''s kudos on the blocker''s run is denied (symmetric)'
);

-- 6. No collateral: an unrelated user can still kudos Bob's run.
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888cccccc","role":"authenticated"}';
select lives_ok(
  $$ insert into run_kudos (user_id, run_id)
       values ('88888888-8888-8888-8888-888888cccccc'::uuid,
               '99999999-9999-9999-9999-999999bbbbbb'::uuid) $$,
  'an unblocked third party can still kudos Bob''s run (gate is targeted)'
);

rollback;
