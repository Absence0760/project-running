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
--
-- Extended for decisions § 763 (migration 20270616_001), which column-scoped
-- this table's INSERT grant to (user_id, plan_id, role, content) and revoked
-- `anon`'s leftover table-level UPDATE. Before it, the WITH CHECK confined a
-- client to its own `role = 'user'` turn — so assistant forgery was already
-- blocked — while the client still chose the row's own `id` and its
-- `created_at`, against a lockdown whose stated purpose (20260518_001) is the
-- auditability of the conversation log. And `anon` held a privilege
-- `authenticated` did not, which is the divergence § 759 refused to accept on
-- the read side; it was inert only because the owner policy reads
-- `auth.uid() = user_id` and anon's is null, which is RLS covering for a
-- grant.
--
--   5-7.  A client cannot supply `id` or `created_at`, and a legitimate
--         insert still lands with server-assigned values.
--   8-10. The UPDATE carve-out is exactly (archived_at, reaction): a client
--         may archive and react on its own row and may not rewrite `content`.
--   11.   `anon` holds no UPDATE, so the refusal is at the grant rather than
--         at the policy.

begin;

select plan(11);

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

-- ── 5-7. the insert carve-out is four columns, not the whole row ─
select throws_ok(
  $$ insert into public.coach_messages (id, user_id, plan_id, role, content)
       values ('00000000-0000-0000-0000-0000000a00f1',
               '00000000-0000-0000-0000-0000000a0001', null, 'user', 'chosen id') $$,
  '42501',
  null,
  'a client cannot choose a coach_messages row id'
);

select throws_ok(
  $$ insert into public.coach_messages (user_id, plan_id, role, content, created_at)
       values ('00000000-0000-0000-0000-0000000a0001', null, 'user', 'backdated',
               '2020-01-01T00:00:00Z') $$,
  '42501',
  null,
  'a client cannot backdate a coach_messages turn'
);

insert into public.coach_messages (user_id, plan_id, role, content)
values ('00000000-0000-0000-0000-0000000a0001', null, 'user', 'server stamped');

select is(
  (select count(*)::int from public.coach_messages
    where user_id = '00000000-0000-0000-0000-0000000a0001'
      and content = 'server stamped'
      and id is not null
      and created_at > now() - interval '1 minute'),
  1,
  'a legitimate turn still lands with a server-assigned id and timestamp'
);

-- ── 8-10. the update carve-out is exactly (archived_at, reaction) ─
select lives_ok(
  $$ update public.coach_messages set archived_at = now(), reaction = 'up'
      where user_id = '00000000-0000-0000-0000-0000000a0001'
        and content = 'server stamped' $$,
  'the owner may archive and react on their own turn'
);

select throws_ok(
  $$ update public.coach_messages set content = 'rewritten'
      where user_id = '00000000-0000-0000-0000-0000000a0001'
        and content = 'server stamped' $$,
  '42501',
  null,
  'the owner cannot rewrite the content of a logged turn'
);

select throws_ok(
  $$ update public.coach_messages set role = 'assistant'
      where user_id = '00000000-0000-0000-0000-0000000a0001'
        and content = 'server stamped' $$,
  '42501',
  null,
  'the owner cannot promote their own turn to an assistant turn'
);

-- ── 11. anon holds no UPDATE at all ──────────────────────────────
-- 20260518_001 revoked the table grant from `authenticated` only, and
-- 20270408_001 version-controlled the leftover. The refusal must be the
-- grant's, not the policy's: RLS covering for a privilege is what § 759
-- refused to accept on the read side.
set local role anon;
set local "request.jwt.claims" = '';
select throws_ok(
  $$ update public.coach_messages set archived_at = now() $$,
  '42501',
  null,
  'anon holds no UPDATE on coach_messages — refused at the grant, not the policy'
);

select * from finish();
rollback;
