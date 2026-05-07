-- Pin the column-level lockdown on `clubs.invite_token` from migration
-- 20260801_001_clubs_invite_token_lockdown.sql.
--
-- Pre-fix: the "public clubs are readable by anyone" RLS policy was open
-- to anon as well as authenticated, so any anon caller could enumerate
-- every public club's invite token via
--   GET /rest/v1/clubs?is_public=eq.true&select=invite_token
-- and join an invite-only club via `join_club_by_token`, defeating
-- `join_policy = 'invite'`.
--
-- The fix follows the user_profiles column-lockdown shape: revoke
-- table-level SELECT for anon + authenticated, then re-grant SELECT
-- on every column EXCEPT `invite_token`. Admin reads of the token go
-- through `get_club_invite_token(uuid)` SECURITY DEFINER, which gates
-- on `is_club_admin`.
--
-- Coverage:
--   1. Anon SELECT on `clubs.invite_token` raises 42501.
--   2. Authenticated non-admin SELECT on `clubs.invite_token` raises 42501.
--   3. Anon SELECT on safe columns (id, name, slug) still works — the
--      public-club discovery flow isn't broken.
--   4. `get_club_invite_token` returns the token for a club admin.
--   5. `get_club_invite_token` returns NULL for a non-admin (member or
--      stranger) — the RPC fails closed, never the table grant.

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000cc01', 'authenticated', 'authenticated',
   'admin@invite.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000cc02', 'authenticated', 'authenticated',
   'member@invite.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public, join_policy, invite_token)
values ('33333333-3333-3333-3333-333333333301',
        '00000000-0000-0000-0000-00000000cc01',
        'Invite Lockdown Club', 'invite-lockdown', true,
        'invite', 'secret-token-abc123');

-- enroll_club_owner_trigger created the owner row; add the member.
insert into club_members (club_id, user_id, role, status)
values
  ('33333333-3333-3333-3333-333333333301',
   '00000000-0000-0000-0000-00000000cc02', 'member', 'active');

-- ── 1. Anon SELECT on invite_token raises 42501 ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select throws_ok(
  $$ select invite_token from clubs
     where id = '33333333-3333-3333-3333-333333333301' $$,
  '42501',
  null,
  'anon SELECT on clubs.invite_token raises permission denied'
);

-- ── 2. Authenticated non-admin SELECT on invite_token raises 42501 ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc02","role":"authenticated"}';

select throws_ok(
  $$ select invite_token from clubs
     where id = '33333333-3333-3333-3333-333333333301' $$,
  '42501',
  null,
  'authenticated non-admin SELECT on clubs.invite_token raises permission denied'
);

-- ── 3. Anon SELECT on safe columns still works ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select results_eq(
  $$ select name, slug from clubs
     where id = '33333333-3333-3333-3333-333333333301' $$,
  $$ values ('Invite Lockdown Club'::text, 'invite-lockdown'::text) $$,
  'anon SELECT on safe columns (name, slug) still works'
);

-- ── 4. get_club_invite_token returns the token for an admin ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc01","role":"authenticated"}';

select results_eq(
  $$ select get_club_invite_token('33333333-3333-3333-3333-333333333301') $$,
  $$ values ('secret-token-abc123'::text) $$,
  'get_club_invite_token returns the token for a club admin'
);

-- ── 5. get_club_invite_token returns NULL for a non-admin ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000cc02","role":"authenticated"}';

select results_eq(
  $$ select get_club_invite_token('33333333-3333-3333-3333-333333333301') $$,
  $$ values (null::text) $$,
  'get_club_invite_token returns NULL for a non-admin (member-only)'
);

select * from finish();

rollback;
