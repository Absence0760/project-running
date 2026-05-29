-- Pins migration 20261026_001 — direct-message RLS + notification
-- (very-social persona #55). Asserts the follow-graph gate, the block
-- override, recipient read access + mark-read, and the 'message'
-- notification.

begin;
select plan(6);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('99999999-9999-9999-9999-99990000d5a1', 'a-55@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99990000d5b2', 'b-55@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99990000d5c3', 'c-55@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99990000d5d4', 'd-55@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- A follows B (one-way is enough). A and D follow each other, but D
-- blocks A. C has no relationship with A.
insert into user_follows (follower_id, followee_id) values
  ('99999999-9999-9999-9999-99990000d5a1', '99999999-9999-9999-9999-99990000d5b2'),
  ('99999999-9999-9999-9999-99990000d5a1', '99999999-9999-9999-9999-99990000d5d4'),
  ('99999999-9999-9999-9999-99990000d5d4', '99999999-9999-9999-9999-99990000d5a1');
insert into user_blocks (blocker_id, blocked_id) values
  ('99999999-9999-9999-9999-99990000d5d4', '99999999-9999-9999-9999-99990000d5a1');

set local role authenticated;

-- ── A → B: allowed (A follows B) ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99990000d5a1","role":"authenticated"}';
select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body)
    values ('11111111-0000-0000-0000-0000000000d5',
            '99999999-9999-9999-9999-99990000d5a1',
            '99999999-9999-9999-9999-99990000d5b2', 'hey')$$,
  'a follow-graph member can send a DM');

-- ── A → C: blocked (no follow relationship) ──
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('99999999-9999-9999-9999-99990000d5a1',
            '99999999-9999-9999-9999-99990000d5c3', 'cold dm')$$,
  '42501',
  null,
  'a cold stranger (no follow) cannot DM');

-- ── A → D: blocked (D blocked A, even though they follow) ──
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('99999999-9999-9999-9999-99990000d5a1',
            '99999999-9999-9999-9999-99990000d5d4', 'blocked dm')$$,
  '42501',
  null,
  'a block overrides the follow relationship');

-- ── B reads + marks read ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-99990000d5b2","role":"authenticated"}';
select is(
  (select count(*)::int from direct_messages
   where id = '11111111-0000-0000-0000-0000000000d5'),
  1,
  'the recipient can read the message');

update direct_messages set read_at = now()
  where id = '11111111-0000-0000-0000-0000000000d5';
select isnt(
  (select read_at from direct_messages where id = '11111111-0000-0000-0000-0000000000d5'),
  null,
  'the recipient can mark the message read');

-- ── notification fired to B ──
set local role postgres;
select is(
  (select count(*)::int from notifications
   where kind = 'message'
     and user_id = '99999999-9999-9999-9999-99990000d5b2'
     and actor_id = '99999999-9999-9999-9999-99990000d5a1'),
  1,
  'the first DM of a burst notifies the recipient');

select * from finish();
rollback;
