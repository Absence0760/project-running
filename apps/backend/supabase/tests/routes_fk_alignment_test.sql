-- Pins migration 20270322_001 (db-design alignment): the duplicate
-- training_plans_active index is gone (the partial UNIQUE
-- training_plans_one_active serves those lookups), and the two outlier FKs
-- referencing routes(id) carry their intended ON DELETE behaviour — a deleted
-- route detaches from runs (SET NULL) and takes its reviews with it (CASCADE)
-- instead of blocking the delete with 23503.

begin;

select plan(6);

select is(
  (select count(*)::int from pg_indexes
     where tablename = 'training_plans' and indexname = 'training_plans_active'),
  0,
  'the duplicate training_plans_active index is dropped');

select is(
  (select indexdef ilike '%unique%' from pg_indexes
     where tablename = 'training_plans' and indexname = 'training_plans_one_active'),
  true,
  'training_plans_one_active survives as the partial unique index');

select is(
  (select confdeltype from pg_constraint where conname = 'runs_route_id_fkey'),
  'n',
  'runs.route_id is ON DELETE SET NULL');

select is(
  (select confdeltype from pg_constraint where conname = 'route_reviews_route_id_fkey'),
  'c',
  'route_reviews.route_id is ON DELETE CASCADE');

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000322a1', 'authenticated', 'authenticated',
   'runner@fka.local', '', now(), now());

insert into routes (id, user_id, name, waypoints, distance_m)
values
  ('03220322-0322-0322-0322-0322032203a1'::uuid,
   '00000000-0000-0000-0000-0000000322a1', 'FKA Route', '[]'::jsonb, 5000);

insert into runs (id, user_id, route_id, started_at, distance_m, duration_s, source, metadata)
values
  ('03220322-0322-0322-0322-0322032203b1'::uuid,
   '00000000-0000-0000-0000-0000000322a1',
   '03220322-0322-0322-0322-0322032203a1',
   now() - interval '1 day', 5000, 1500, 'app', '{"activity_type":"run"}');

delete from routes where id = '03220322-0322-0322-0322-0322032203a1';

select is(
  (select count(*)::int from runs
     where id = '03220322-0322-0322-0322-0322032203b1'),
  1,
  'deleting a route keeps the linked run');

select is(
  (select route_id from runs
     where id = '03220322-0322-0322-0322-0322032203b1'),
  null,
  'the surviving run''s route_id is nulled');

select * from finish();
rollback;
