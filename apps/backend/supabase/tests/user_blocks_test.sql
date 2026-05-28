-- Pins migration 20261012_001 — user_blocks primitive.
-- Persona-hunt Round 3 finding Woman #1.

begin;
select plan(11);

do $$
declare
  v_alice uuid := '88888888-8888-8888-8888-888888aaaaaa';
  v_bob   uuid := '88888888-8888-8888-8888-888888bbbbbb';
  v_carol uuid := '88888888-8888-8888-8888-888888cccccc';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_alice, 'alice@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_bob, 'bob@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_carol, 'carol@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
    values (v_alice, 'Alice', 'km', 'free'),
           (v_bob,   'Bob',   'km', 'free'),
           (v_carol, 'Carol', 'km', 'free')
    on conflict (id) do nothing;
end $$;

-- 1. Alice blocks Bob via the RPC.
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888aaaaaa","role":"authenticated"}';
select lives_ok(
  $$ select block_user('88888888-8888-8888-8888-888888bbbbbb'::uuid) $$,
  'Alice can block Bob via the RPC'
);

-- 2. is_blocked_either_way reports the relationship symmetrically.
select is(
  is_blocked_either_way(
    '88888888-8888-8888-8888-888888aaaaaa'::uuid,
    '88888888-8888-8888-8888-888888bbbbbb'::uuid),
  true,
  'is_blocked_either_way returns true for the blocker→blocked direction'
);
select is(
  is_blocked_either_way(
    '88888888-8888-8888-8888-888888bbbbbb'::uuid,
    '88888888-8888-8888-8888-888888aaaaaa'::uuid),
  true,
  'is_blocked_either_way returns true for the blocked→blocker direction (symmetric)'
);

-- 3. block self is rejected.
select throws_ok(
  $$ select block_user('88888888-8888-8888-8888-888888aaaaaa'::uuid) $$,
  '23514',
  null,
  'block_user rejects self-block'
);

-- 4. Bob cannot read Alice's block row (owner-only RLS).
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888bbbbbb","role":"authenticated"}';
select is(
  (select count(*) from user_blocks
    where blocker_id = '88888888-8888-8888-8888-888888aaaaaa'::uuid),
  0::bigint,
  'Bob cannot see Alice''s block row (one-way visibility — block stays invisible to the blockee)'
);

-- 5. Bob cannot follow Alice (block predicate on user_follows INSERT).
select throws_ok(
  $$ insert into user_follows (follower_id, followee_id)
       values ('88888888-8888-8888-8888-888888bbbbbb'::uuid,
               '88888888-8888-8888-8888-888888aaaaaa'::uuid) $$,
  '42501',
  null,
  'Bob cannot follow Alice when blocked'
);

-- 6. Carol (unblocked) can follow Alice.
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888cccccc","role":"authenticated"}';
select lives_ok(
  $$ insert into user_follows (follower_id, followee_id)
       values ('88888888-8888-8888-8888-888888cccccc'::uuid,
               '88888888-8888-8888-8888-888888aaaaaa'::uuid) $$,
  'Carol (unblocked) can follow Alice'
);

-- 7. Alice unblocks Bob.
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888aaaaaa","role":"authenticated"}';
select lives_ok(
  $$ select unblock_user('88888888-8888-8888-8888-888888bbbbbb'::uuid) $$,
  'Alice can unblock Bob via the RPC'
);

-- 8. is_blocked_either_way returns false after unblock.
select is(
  is_blocked_either_way(
    '88888888-8888-8888-8888-888888aaaaaa'::uuid,
    '88888888-8888-8888-8888-888888bbbbbb'::uuid),
  false,
  'is_blocked_either_way false after unblock'
);

-- 9. public_profile_by_id returns empty for a blocked target.
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888aaaaaa","role":"authenticated"}';
do $$ begin perform block_user('88888888-8888-8888-8888-888888bbbbbb'::uuid); end $$;

select is(
  (select count(*) from public_profile_by_id(
    '88888888-8888-8888-8888-888888bbbbbb'::uuid)),
  0::bigint,
  'public_profile_by_id returns empty for a blocked target'
);

-- 10. Block subsumes unfollow on BOTH sides — Carol's follow of
-- Alice is unaffected, but if Alice follows Carol and then blocks
-- her, the follow goes away.
set local role service_role;
insert into user_follows (follower_id, followee_id)
  values ('88888888-8888-8888-8888-888888aaaaaa'::uuid,
          '88888888-8888-8888-8888-888888cccccc'::uuid);
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"88888888-8888-8888-8888-888888aaaaaa","role":"authenticated"}';
do $$ begin perform block_user('88888888-8888-8888-8888-888888cccccc'::uuid); end $$;
select is(
  (select count(*) from user_follows
    where (follower_id = '88888888-8888-8888-8888-888888aaaaaa'::uuid
           and followee_id = '88888888-8888-8888-8888-888888cccccc'::uuid)
       or (follower_id = '88888888-8888-8888-8888-888888cccccc'::uuid
           and followee_id = '88888888-8888-8888-8888-888888aaaaaa'::uuid)),
  0::bigint,
  'block subsumes unfollow on both sides — pre-existing follow rows are deleted'
);

rollback;
