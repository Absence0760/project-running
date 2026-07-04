-- Pins migration 20270324_001 (view write lockdown). Two layers:
--
--   1. A catch-all over information_schema: NO view in the public schema may
--      grant anon/authenticated anything beyond SELECT. Supabase's default
--      privileges hand out full table privileges on CREATE, and a simple
--      view is auto-updatable with writes authorised as the VIEW OWNER
--      (postgres, bypassing RLS) — so a future view created without the
--      revoke-then-grant reset fails HERE instead of shipping writable.
--   2. A functional probe on the shape that was exploitable: an anon insert
--      through public_race_listings is denied.

begin;

select plan(3);

select is(
  (select count(*)::int
     from information_schema.role_table_grants g
     join information_schema.views v
       on v.table_schema = g.table_schema and v.table_name = g.table_name
     where g.table_schema = 'public'
       and g.grantee in ('anon', 'authenticated')
       and g.privilege_type <> 'SELECT'),
  0,
  'no public-schema view grants anon/authenticated anything beyond SELECT — '
  'writes through an auto-updatable view run as the view owner and bypass RLS'
);

set local role anon;
set local "request.jwt.claims" = '{}';

select throws_ok(
  $$ insert into public_race_listings (provider, name, race_date)
     values ('manual', 'Forged Via View', current_date + 1) $$,
  '42501',
  null,
  'anon cannot INSERT through public_race_listings'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ insert into public_gym_workouts (id, user_id, started_at, is_public)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', now(), true) $$,
  '42501',
  null,
  'authenticated cannot INSERT through public_gym_workouts'
);

select * from finish();
rollback;
