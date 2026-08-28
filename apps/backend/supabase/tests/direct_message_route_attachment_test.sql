-- Pins migration 20270619_001 — the typed route attachment on direct_messages
-- (route_direct_share.md v2).
--
-- The load-bearing claim is the INSERT gate: a sender may attach only a route
-- they can see. Without it the rail accepts any uuid, and "the recipient's read
-- is clipped anyway" is a reason the card does not leak, not a reason the write
-- should be unconstrained.

begin;
select plan(6);

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('99999999-9999-9999-9999-999900072a01', 'a-772@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-999900072b02', 'b-772@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-999900072c03', 'c-772@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- A and B follow each other, so the follow-graph half of the policy is
-- satisfied throughout and every refusal below is the attachment clause's.
insert into user_follows (follower_id, followee_id) values
  ('99999999-9999-9999-9999-999900072a01', '99999999-9999-9999-9999-999900072b02'),
  ('99999999-9999-9999-9999-999900072b02', '99999999-9999-9999-9999-999900072a01');

-- A owns one route; C owns one public and one private route.
insert into routes (id, user_id, name, waypoints, distance_m, is_public) values
  ('77777777-0000-0000-0000-000000000a01', '99999999-9999-9999-9999-999900072a01',
   'A own route', '[{"lat":1,"lng":1},{"lat":2,"lng":2}]'::jsonb, 5000, false),
  ('77777777-0000-0000-0000-000000000c01', '99999999-9999-9999-9999-999900072c03',
   'C public route', '[{"lat":1,"lng":1},{"lat":2,"lng":2}]'::jsonb, 6000, true),
  ('77777777-0000-0000-0000-000000000c02', '99999999-9999-9999-9999-999900072c03',
   'C private route', '[{"lat":1,"lng":1},{"lat":2,"lng":2}]'::jsonb, 7000, false);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-999900072a01","role":"authenticated"}';

-- ── A attaches their OWN route ──
select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body, route_id)
    values ('22222222-0000-0000-0000-000000000a01',
            '99999999-9999-9999-9999-999900072a01',
            '99999999-9999-9999-9999-999900072b02',
            'https://example.test/share/route/77777777-0000-0000-0000-000000000a01',
            '77777777-0000-0000-0000-000000000a01')$$,
  'a sender can attach a route they own');

-- ── A attaches a PUBLIC route owned by C ──
-- The affordance is gated on `is_public || isOwner`, so a non-owner sending an
-- already-public route is a shipped path, not a hypothetical.
select lives_ok(
  $$insert into direct_messages (id, sender_id, recipient_id, body, route_id)
    values ('22222222-0000-0000-0000-000000000a02',
            '99999999-9999-9999-9999-999900072a01',
            '99999999-9999-9999-9999-999900072b02',
            'https://example.test/share/route/77777777-0000-0000-0000-000000000c01',
            '77777777-0000-0000-0000-000000000c01')$$,
  'a sender can attach a public route they do not own');

-- ── A attaches a PRIVATE route owned by C ──
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, route_id)
    values ('99999999-9999-9999-9999-999900072a01',
            '99999999-9999-9999-9999-999900072b02',
            'planted',
            '77777777-0000-0000-0000-000000000c02')$$,
  '42501',
  null,
  'a sender cannot attach a route they cannot see');

-- ── A plain message still sends ──
select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('99999999-9999-9999-9999-999900072a01',
            '99999999-9999-9999-9999-999900072b02',
            'no attachment here')$$,
  'the attachment clause does not disturb an ordinary message');

-- ── The recipient reads the attachment ──
set local "request.jwt.claims" = '{"sub":"99999999-9999-9999-9999-999900072b02","role":"authenticated"}';
select is(
  (select route_id from direct_messages
   where id = '22222222-0000-0000-0000-000000000a01'),
  '77777777-0000-0000-0000-000000000a01'::uuid,
  'the recipient reads the route reference off their own message row');

-- ── Deleting the route keeps the message ──
reset role;
delete from routes where id = '77777777-0000-0000-0000-000000000a01';
select is(
  (select coalesce(route_id::text, 'null') || '|' || body
   from direct_messages where id = '22222222-0000-0000-0000-000000000a01'),
  'null|https://example.test/share/route/77777777-0000-0000-0000-000000000a01',
  'deleting the route nulls the reference and leaves the message intact');

select * from finish();
rollback;
