-- pgtap suite for the social-RLS hardening landed in
-- 20260926_001_social_rls_audit_hardening.sql (audit:rls May 2026).
--
-- Four independent findings, four test groups:
--   1. Direct INSERT into `reports` is blocked (force RPC path).
--   2. `club_members` SELECT hides pending rows from non-admins;
--      admins still see them.
--   3. Anon EXECUTE is revoked on join_club_by_token + clone_plan_template.
--   4. Self-kudos is rejected via the BEFORE INSERT trigger; service-role
--      bypass still works (seed-time fixture planting).

begin;

select plan(17);

-- ─── Fixtures ───────────────────────────────────────────────────────
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000e101', 'authenticated', 'authenticated',
   'admin@social.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000e102', 'authenticated', 'authenticated',
   'pending@social.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000e103', 'authenticated', 'authenticated',
   'stranger@social.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000e104', 'authenticated', 'authenticated',
   'kudoser@social.local', '', now(), now());

-- A public club owned by e101 with e102 as a pending requester.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values (
  '00000000-0000-0000-0000-00000000ec01',
  '00000000-0000-0000-0000-00000000e101',
  'Social Audit Club', 'social-audit-club', true, 'request'
);

-- The clubs INSERT trigger auto-creates the owner's club_members
-- row as ('owner', 'active'), so we only plant the pending requester
-- here.
insert into club_members (club_id, user_id, role, status)
values
  ('00000000-0000-0000-0000-00000000ec01',
   '00000000-0000-0000-0000-00000000e102', 'member', 'pending');

-- ─────────────────────────────────────────────────────────────────────
-- 1. Direct INSERT into `reports` is blocked.
-- ─────────────────────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e101"}';

select throws_ok(
  $$ insert into reports (reporter_id, target_kind, target_id, reason)
     values ('00000000-0000-0000-0000-00000000e101', 'user',
             '00000000-0000-0000-0000-00000000e102', 'spam') $$,
  '42501', null,
  'direct INSERT into reports is rejected by RLS (must go through submit_report RPC)'
);

-- A "reporters read their own reports" check that the SELECT path
-- still works — service_role plants a row, the reporter reads it
-- back.
reset role;
set local "request.jwt.claims" = '{"role":"service_role"}';
insert into reports (reporter_id, target_kind, target_id, reason)
values (
  '00000000-0000-0000-0000-00000000e101', 'user',
  '00000000-0000-0000-0000-00000000e102', 'spam'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e101"}';

select cmp_ok(
  (select count(*) from reports where reporter_id = '00000000-0000-0000-0000-00000000e101')::int,
  '=', 1::int,
  'reporters can still SELECT their own reports after the INSERT policy drop'
);

-- ─────────────────────────────────────────────────────────────────────
-- 2. club_members SELECT — pending row hidden from non-admin observers.
-- ─────────────────────────────────────────────────────────────────────

-- A stranger querying the public club's roster sees only the
-- active owner row — the pending e102 row is hidden.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e103"}';

select cmp_ok(
  (select count(*)::int from club_members
   where club_id = '00000000-0000-0000-0000-00000000ec01'),
  '=', 1::int,
  'stranger sees only active rows in public club roster (pending row hidden)'
);

select cmp_ok(
  (select count(*)::int from club_members
   where club_id = '00000000-0000-0000-0000-00000000ec01'
     and status = 'pending'),
  '=', 0::int,
  'stranger cannot enumerate pending requests by filtering on status'
);

-- The pending requester sees their OWN row (via "users can see
-- their own membership" from 20260417).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e102"}';

select cmp_ok(
  (select count(*)::int from club_members
   where club_id = '00000000-0000-0000-0000-00000000ec01'
     and user_id = '00000000-0000-0000-0000-00000000e102'),
  '=', 1::int,
  'pending requester can still see their own pending row (UI shows "Request pending")'
);

-- The club admin sees the pending row (so they can approve / reject).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e101"}';

select cmp_ok(
  (select count(*)::int from club_members
   where club_id = '00000000-0000-0000-0000-00000000ec01'
     and status = 'pending'),
  '=', 1::int,
  'club admin sees pending requests for their club (approval flow unbroken)'
);

select cmp_ok(
  (select count(*)::int from club_members
   where club_id = '00000000-0000-0000-0000-00000000ec01'),
  '=', 2::int,
  'club admin sees both active owner and pending requester'
);

-- ─────────────────────────────────────────────────────────────────────
-- 3. Anon EXECUTE revoked on the two SECURITY DEFINER RPCs.
-- ─────────────────────────────────────────────────────────────────────
reset role;

select ok(
  not has_function_privilege('anon', 'public.join_club_by_token(text)', 'EXECUTE'),
  'anon must NOT have EXECUTE on join_club_by_token — defence-in-depth '
    'against a future edit that drops the inner auth.uid() check'
);

select ok(
  not has_function_privilege('anon', 'public.clone_plan_template(uuid, date)', 'EXECUTE'),
  'anon must NOT have EXECUTE on clone_plan_template — same lockdown pattern'
);

-- authenticated still has access (legitimate callers).
select ok(
  has_function_privilege('authenticated', 'public.join_club_by_token(text)', 'EXECUTE'),
  'authenticated keeps EXECUTE on join_club_by_token (the legitimate caller)'
);
select ok(
  has_function_privilege('authenticated', 'public.clone_plan_template(uuid, date)', 'EXECUTE'),
  'authenticated keeps EXECUTE on clone_plan_template'
);

select ok(
  not has_function_privilege('anon', 'public.clone_session_template(uuid)', 'EXECUTE'),
  'anon must NOT have EXECUTE on clone_session_template — same lockdown pattern'
);
select ok(
  has_function_privilege('authenticated', 'public.clone_session_template(uuid)', 'EXECUTE'),
  'authenticated keeps EXECUTE on clone_session_template'
);

-- ─────────────────────────────────────────────────────────────────────
-- 4. Self-kudos rejection (trigger).
-- ─────────────────────────────────────────────────────────────────────

-- Plant a public run owned by e104 via service-role.
set local "request.jwt.claims" = '{"role":"service_role"}';
insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public, metadata)
values (
  '00000000-0000-0000-0000-00000000ef01',
  '00000000-0000-0000-0000-00000000e104',
  now(), 600, 5000, 'app', true,
  jsonb_build_object('activity_type', 'run')
);

-- e104 attempts to give themselves kudos via the authenticated path
-- — must be rejected by the trigger with 'self_kudos_not_allowed'.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e104"}';

select throws_ok(
  $$ insert into run_kudos (run_id, user_id)
     values ('00000000-0000-0000-0000-00000000ef01',
             '00000000-0000-0000-0000-00000000e104') $$,
  '23514', 'self_kudos_not_allowed',
  'authenticated owner cannot give themselves kudos (trigger rejects)'
);

-- Cross-user kudos still works.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e103"}';

select lives_ok(
  $$ insert into run_kudos (run_id, user_id)
     values ('00000000-0000-0000-0000-00000000ef01',
             '00000000-0000-0000-0000-00000000e103') $$,
  'cross-user kudos still works after the self-kudos trigger lands'
);

-- Service-role bypass — seed-time fixture planting must still work.
-- (The wire-leak regression suite in seed.sql plants a "user kudos
-- their own run" row to verify visibility helpers; that path must
-- not be broken by the trigger.)
reset role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select lives_ok(
  $$ insert into run_kudos (run_id, user_id)
     values ('00000000-0000-0000-0000-00000000ef01',
             '00000000-0000-0000-0000-00000000e104') $$,
  'service-role self-kudos insert bypasses the trigger (seed setup path)'
);

-- ─────────────────────────────────────────────────────────────────────
-- 5. clone_plan_template rate-limit (audit followup, 20260927_001).
-- ─────────────────────────────────────────────────────────────────────
-- The RPC body now calls enforce_create_rate_limit('clone_plan_template',
-- caller, 20, 3600). Pin via pg_proc source inspection — a future
-- edit that drops the perform line silently re-opens the loop-clone
-- abuse surface.
select ok(
  exists (
    select 1 from pg_proc
     where proname = 'clone_plan_template'
       and pronamespace = 'public'::regnamespace
       and prosrc ilike '%enforce_create_rate_limit(''clone_plan_template''%'
  ),
  'clone_plan_template body MUST call enforce_create_rate_limit('
  '''clone_plan_template'', ...) — without it, a club member can '
  'loop-clone every public template UUID and bulk-create rows '
  'under their account (audit:rls May 2026 deferred Low fix).'
);

select * from finish();
rollback;
