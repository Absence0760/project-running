-- Pin the admin user_id forge guards on routes + training_plans
-- from migration 20260614_001_rls_hardening_pt2.sql.
--
-- Pre-fix: "club admins write club routes" and "club admins write
-- club templates" used `for all using (...)` with no explicit `with
-- check`. Postgres treats USING as the implicit WITH CHECK on
-- INSERT, but neither rule constrained `user_id`. A club admin could
-- INSERT a row attributing it to any user — the documented "uploader"
-- audit trail was forgeable.
--
-- The fix splits each `for all` into a tightened INSERT (adds
-- `user_id = auth.uid()`) and separate UPDATE / DELETE that preserve
-- the relaxed admin rule (admins legitimately need write authority
-- on routes / templates owned by other club members; the audit trail
-- guard is INSERT-side only).
--
-- Coverage:
--   1. Club admin can INSERT a club route attributing it to themselves
--      (positive control — admin authoring works).
--   2. Club admin CANNOT INSERT a club route attributing user_id to
--      another user (the regression fix).
--   3. Club admin can INSERT a club template attributing it to
--      themselves (positive control).
--   4. Club admin CANNOT INSERT a club template attributing user_id
--      to another user (the regression fix).
--   5. Club admin can UPDATE a route owned by another club member —
--      admin write authority is preserved (positive control on the
--      relaxed UPDATE policy).

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000ad01', 'authenticated', 'authenticated',
   'admin@forge.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000ad02', 'authenticated', 'authenticated',
   'member@forge.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('22222222-2222-2222-2222-222222222201',
        '00000000-0000-0000-0000-00000000ad01',
        'Forge Test Club', 'forge-test', true);

-- enroll_club_owner_trigger created the owner row already.
insert into club_members (club_id, user_id, role, status)
values
  ('22222222-2222-2222-2222-222222222201',
   '00000000-0000-0000-0000-00000000ad02', 'member', 'active');

-- Pre-seed a route owned by the member so the admin-UPDATE positive
-- control has a target row.
insert into routes (id, user_id, name, waypoints, distance_m, club_id, is_public)
values ('22222222-2222-2222-2222-222222222211',
        '00000000-0000-0000-0000-00000000ad02',
        'Member route', '[]'::jsonb, 5000.0,
        '22222222-2222-2222-2222-222222222201', false);

-- ── Switch to the admin ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ad01","role":"authenticated"}';

-- 1. Admin INSERTs a club route attributing it to themselves —
--    positive control.
do $$
begin
  insert into routes (user_id, name, waypoints, distance_m, club_id)
  values ('00000000-0000-0000-0000-00000000ad01',
          'Admin self-authored', '[]'::jsonb, 6000.0,
          '22222222-2222-2222-2222-222222222201');
end $$;
select pass('club admin can INSERT a club route attributing it to themselves');

-- 2. Admin attempting to INSERT a club route attributing user_id
--    to a member is rejected (the regression fix).
select throws_ok(
  $$ insert into routes (user_id, name, waypoints, distance_m, club_id)
     values ('00000000-0000-0000-0000-00000000ad02',
             'Forged author', '[]'::jsonb, 7000.0,
             '22222222-2222-2222-2222-222222222201') $$,
  '42501',
  null,
  'club admin cannot INSERT a club route forging user_id to another club member'
);

-- 3. Admin INSERTs a club template attributing it to themselves —
--    positive control.
do $$
begin
  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, start_date, end_date,
    days_per_week, status, is_template, club_id
  ) values (
    '00000000-0000-0000-0000-00000000ad01',
    'Admin self-authored template', 'distance_5k', 5000,
    '2026-06-01', '2026-06-28', 4,
    'completed', true, '22222222-2222-2222-2222-222222222201'
  );
end $$;
select pass('club admin can INSERT a club template attributing it to themselves');

-- 4. Admin attempting to INSERT a club template attributing user_id
--    to a member is rejected (the regression fix).
select throws_ok(
  $$ insert into training_plans (
       user_id, name, goal_event, goal_distance_m, start_date, end_date,
       days_per_week, status, is_template, club_id
     ) values (
       '00000000-0000-0000-0000-00000000ad02',
       'Forged template', 'distance_5k', 5000,
       '2026-06-01', '2026-06-28', 4,
       'completed', true, '22222222-2222-2222-2222-222222222201'
     ) $$,
  '42501',
  null,
  'club admin cannot INSERT a club template forging user_id to another club member'
);

-- 5. Admin CAN UPDATE a route owned by another club member —
--    relaxed UPDATE rule preserved (admins legitimately need write
--    authority on routes owned by others).
do $$
declare
  v_affected integer;
begin
  update routes
     set name = 'Admin-edited member route'
   where id = '22222222-2222-2222-2222-222222222211';
  get diagnostics v_affected = row_count;
  if v_affected <> 1 then
    raise exception 'admin_update_member_route: expected 1 affected, got %', v_affected;
  end if;
end $$;
select pass('club admin can UPDATE a route owned by another club member (admin write authority preserved)');

select * from finish();

rollback;
