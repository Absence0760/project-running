-- RLS suite for `public.coach_messages`.
--
-- Owner-only across SELECT / INSERT / UPDATE / DELETE. Holds the AI
-- Coach conversation history — every user message + every model
-- response. Beyond personal-content sensitivity, content can include
-- training plans, injury notes, and goals; cross-user reads would be
-- a serious privacy regression.

begin;

select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000c0ac01', 'authenticated', 'authenticated',
   'a@coach.local', '', now(), now()),
  ('00000000-0000-0000-0000-000000c0ac02', 'authenticated', 'authenticated',
   'b@coach.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000c0ac01"}';

insert into coach_messages (id, user_id, role, content)
values
  ('cccccccc-cccc-cccc-cccc-cccccccccc01',
   '00000000-0000-0000-0000-000000c0ac01', 'user', 'I have a knee niggle.'),
  ('cccccccc-cccc-cccc-cccc-cccccccccc02',
   '00000000-0000-0000-0000-000000c0ac01', 'assistant', 'Take 2 days off.');

-- 1. Owner can read their own conversation.
select results_eq(
  $$ select content from coach_messages
     where user_id = '00000000-0000-0000-0000-000000c0ac01'
     order by created_at $$,
  $$ values ('I have a knee niggle.'::text), ('Take 2 days off.'::text) $$,
  'owner can read their full coach conversation'
);

-- 2. Non-owner SELECT: ZERO rows.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000c0ac02"}';
select is_empty(
  $$ select content from coach_messages
     where user_id = '00000000-0000-0000-0000-000000c0ac01' $$,
  'non-owner cannot read another user''s coach conversation'
);

-- 3. Forged INSERT (under another user_id) rejected.
select throws_ok(
  $$ insert into coach_messages (user_id, role, content)
     values ('00000000-0000-0000-0000-000000c0ac01', 'assistant', 'forged') $$,
  '42501',
  null,
  'cannot INSERT a coach_messages row under another user_id'
);

-- 4. Non-owner UPDATE: no-op (RLS hides rows from the UPDATE target).
update coach_messages set reaction = 'up'
  where id = 'cccccccc-cccc-cccc-cccc-cccccccccc02';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000c0ac01"}';
select is(
  (select reaction from coach_messages
     where id = 'cccccccc-cccc-cccc-cccc-cccccccccc02'),
  null::text,
  'non-owner UPDATE on another user''s coach message is a no-op'
);

-- 5. Non-owner DELETE: no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000c0ac02"}';
delete from coach_messages
  where user_id = '00000000-0000-0000-0000-000000c0ac01';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000c0ac01"}';
select results_eq(
  $$ select count(*)::int from coach_messages
     where user_id = '00000000-0000-0000-0000-000000c0ac01' $$,
  $$ values (2) $$,
  'non-owner DELETE on another user''s coach messages is a no-op'
);

-- 6. Owner UPDATE works (reactions, archived_at).
update coach_messages set reaction = 'up'
  where id = 'cccccccc-cccc-cccc-cccc-cccccccccc02';
select is(
  (select reaction from coach_messages
     where id = 'cccccccc-cccc-cccc-cccc-cccccccccc02'),
  'up',
  'owner UPDATE works on their own coach message'
);

-- 7. Anon cannot SELECT.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select 1 from coach_messages
     where user_id = '00000000-0000-0000-0000-000000c0ac01' $$,
  'anon cannot read coach_messages'
);

select * from finish();

rollback;
