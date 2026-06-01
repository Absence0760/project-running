-- Pins XSS audit H1 + M3 (migration 20261122_001).
--
-- The coach handler writes assistant rows via a service_role client
-- (RLS-bypassing); ordinary authenticated callers must be confined to
-- their own `role = 'user'` turns, and content is capped at 64 KiB.
--
--   1. authenticated CAN insert their own role='user' row.
--   2. authenticated CANNOT insert a role='assistant' row (the H1
--      injection vector) — RLS WITH CHECK rejects it.
--   3. authenticated CANNOT insert a role='user' row for another user.
--   4. The 64 KiB content cap rejects an oversized row.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000a0001', 'authenticated', 'authenticated',
   'a@lockdown.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000a0002', 'authenticated', 'authenticated',
   'b@lockdown.local', '', now(), now());

-- auth.uid() = 0a0001 for these inserts.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000a0001"}';

-- ── 1. own user-role turn is allowed ─────────────────────────────
select lives_ok(
  $$ insert into public.coach_messages (user_id, plan_id, role, content)
       values ('00000000-0000-0000-0000-0000000a0001', null, 'user', 'hello coach') $$,
  'authenticated may insert their own role=user message'
);

-- ── 2. assistant-role injection is rejected (H1) ─────────────────
select throws_ok(
  $$ insert into public.coach_messages (user_id, plan_id, role, content)
       values ('00000000-0000-0000-0000-0000000a0001', null, 'assistant',
               '<img src=x onerror=alert(1)>') $$,
  '42501',
  null,
  'authenticated cannot plant a role=assistant row'
);

-- ── 3. cannot write a user-role turn for someone else ────────────
select throws_ok(
  $$ insert into public.coach_messages (user_id, plan_id, role, content)
       values ('00000000-0000-0000-0000-0000000a0002', null, 'user', 'not mine') $$,
  '42501',
  null,
  'authenticated cannot insert a role=user row for another user'
);

-- ── 4. content length cap (M3) ───────────────────────────────────
select throws_ok(
  format(
    $$ insert into public.coach_messages (user_id, plan_id, role, content)
         values ('00000000-0000-0000-0000-0000000a0001', null, 'user', %L) $$,
    repeat('a', 65537)
  ),
  '23514',
  null,
  'content longer than 64 KiB is rejected by the CHECK constraint'
);

select * from finish();
rollback;
