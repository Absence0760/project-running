-- clear_my_unsubscribe_suppression (issue #392): a user re-opting into an
-- engagement stream must be able to lift their OWN user-initiated ('unsubscribe')
-- address block so the next send proceeds — WITHOUT touching a bounce/complaint/
-- manual suppression, and WITHOUT being able to clear another user's block.

begin;

select plan(6);

-- Two users with resolvable addresses (the RPC keys on auth.users.email).
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'alice@suppress.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated',
   'bob@suppress.local', '', now(), now());

-- Alice: a user-initiated unsubscribe (reversible). Bob: also unsubscribed.
-- Plus a bounce suppression on a third address (must never be cleared).
insert into email_suppressions (email, reason) values
  ('alice@suppress.local', 'unsubscribe'),
  ('bob@suppress.local', 'unsubscribe'),
  ('bounced@suppress.local', 'bounce');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

-- 1. Alice re-opts in → the RPC clears exactly one row (her own unsubscribe).
select is(
  (select public.clear_my_unsubscribe_suppression()),
  1,
  'clear_my_unsubscribe_suppression removes the caller''s own unsubscribe row'
);

-- Verify against the table with service_role (the fail-closed RLS hides it from
-- authenticated).
set local role service_role;

-- 2. Alice''s unsubscribe suppression is gone — a send to her would now proceed.
select is(
  (select count(*)::int from email_suppressions where email = 'alice@suppress.local'),
  0,
  'Alice''s unsubscribe suppression is cleared, so a send is no longer hard-blocked'
);

-- 3. Bob''s suppression is untouched — Alice cannot clear another user''s block.
select is(
  (select count(*)::int from email_suppressions where email = 'bob@suppress.local'),
  1,
  'a user cannot clear another user''s suppression'
);

-- 4. The bounce suppression is untouched — only reason=''unsubscribe'' is reversible.
select is(
  (select count(*)::int from email_suppressions where email = 'bounced@suppress.local' and reason = 'bounce'),
  1,
  'a bounce suppression is never cleared by the re-opt-in RPC'
);

-- 5. Idempotent: calling again with nothing left to clear returns 0.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select is(
  (select public.clear_my_unsubscribe_suppression()),
  0,
  'a second call with no remaining unsubscribe row clears nothing'
);

-- 6. A bounce-suppressed reason stays even for the caller''s OWN address: seed a
-- bounce on Alice, re-run, confirm it survives (reason scoping, not address scoping).
set local role service_role;
insert into email_suppressions (email, reason) values ('alice@suppress.local', 'bounce');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select public.clear_my_unsubscribe_suppression();
set local role service_role;
select is(
  (select count(*)::int from email_suppressions where email = 'alice@suppress.local' and reason = 'bounce'),
  1,
  'the caller''s own bounce suppression is left intact by the re-opt-in RPC'
);

select * from finish();
rollback;
