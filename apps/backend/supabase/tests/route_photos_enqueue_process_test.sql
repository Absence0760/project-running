-- Enqueue-trigger suite for the route-photo server-side processing job
-- (migration 20270224_001_route_photo_thumbnails.sql). The AFTER INSERT
-- trigger on route_photos enqueues one `route_photo_process` job per
-- uploaded photo (web path: insert with the final path). The mobile path
-- inserts a placeholder empty path, uploads, then PATCHes the real path —
-- so the placeholder insert must NOT enqueue, and the AFTER UPDATE OF
-- storage_path trigger must enqueue when the path fills in.
--
-- public.jobs is RLS deny-all to authenticated callers (only service_role
-- and the SECURITY DEFINER enqueue functions write/read it), so the photo
-- INSERT/UPDATE runs as authenticated (the real client role) while the
-- job-count assertions read jobs as service_role.
--
-- Blast radius if regressed: route photos uploaded but never EXIF-stripped
-- server-side / never thumbnailed (the deferred half of roadmap row 8), or
-- a duplicate job per upload (extra Storage churn).

begin;

select plan(6);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000cc001', 'authenticated', 'authenticated',
   'route-enqueue@photo.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc001","role":"authenticated"}';

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('22222222-2222-2222-2222-2222000cc001',
   '00000000-0000-0000-0000-0000000cc001',
   'Enqueue Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   5000, true);

-- INSERT with a real storage_path (web path) — should enqueue one job.
insert into route_photos (id, route_id, owner_id, storage_path, position_idx)
values
  ('33333333-3333-3333-3333-3333000cc001',
   '22222222-2222-2222-2222-2222000cc001',
   '00000000-0000-0000-0000-0000000cc001',
   '00000000-0000-0000-0000-0000000cc001/web_photo.jpg', 0);

-- INSERT with an empty placeholder path (mobile path) — should NOT enqueue.
insert into route_photos (id, route_id, owner_id, storage_path, position_idx)
values
  ('33333333-3333-3333-3333-3333000cc002',
   '22222222-2222-2222-2222-2222000cc001',
   '00000000-0000-0000-0000-0000000cc001',
   '', 1);

-- Read jobs as service_role (RLS deny-all to authenticated).
set local role service_role;
reset "request.jwt.claims";

-- 1. INSERT with a real storage_path enqueued exactly one job.
select results_eq(
  $$ select count(*)::int from public.jobs
     where kind = 'route_photo_process'
       and payload->>'photo_id' = '33333333-3333-3333-3333-3333000cc001' $$,
  $$ values (1) $$,
  'INSERT with a real path enqueues one route_photo_process job'
);

-- 2. The enqueued payload carries the path + owner the worker needs.
select results_eq(
  $$ select payload->>'storage_path', payload->>'owner_id'
       from public.jobs
      where kind = 'route_photo_process'
        and payload->>'photo_id' = '33333333-3333-3333-3333-3333000cc001' $$,
  $$ values ('00000000-0000-0000-0000-0000000cc001/web_photo.jpg',
             '00000000-0000-0000-0000-0000000cc001') $$,
  'enqueued payload carries storage_path + owner_id'
);

-- 3. INSERT with an empty placeholder path did NOT enqueue.
select is_empty(
  $$ select id from public.jobs
     where kind = 'route_photo_process'
       and payload->>'photo_id' = '33333333-3333-3333-3333-3333000cc002' $$,
  'INSERT with a placeholder empty path does not enqueue'
);

-- PATCH the placeholder to a real path (mobile upload complete) as authenticated.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc001","role":"authenticated"}';
update route_photos
   set storage_path = '00000000-0000-0000-0000-0000000cc001/mobile_photo.jpg'
 where id = '33333333-3333-3333-3333-3333000cc002';

-- A caption-only UPDATE on an already-pathed row must NOT re-enqueue.
update route_photos
   set caption = 'a caption edit'
 where id = '33333333-3333-3333-3333-3333000cc001';

set local role service_role;
reset "request.jwt.claims";

-- 4. UPDATE filling the path enqueued one job.
select results_eq(
  $$ select count(*)::int from public.jobs
     where kind = 'route_photo_process'
       and payload->>'photo_id' = '33333333-3333-3333-3333-3333000cc002' $$,
  $$ values (1) $$,
  'UPDATE filling the path enqueues one route_photo_process job'
);

-- 5. The caption-only UPDATE did not re-enqueue (still one job for cc001).
select results_eq(
  $$ select count(*)::int from public.jobs
     where kind = 'route_photo_process'
       and payload->>'photo_id' = '33333333-3333-3333-3333-3333000cc001' $$,
  $$ values (1) $$,
  'a caption-only UPDATE does not re-enqueue'
);

-- 6. The service-role thumb_512_path PATCH must not re-enqueue (the worker's
--    own write must not loop back into a fresh job).
update route_photos
   set thumb_512_path = '00000000-0000-0000-0000-0000000cc001/web_photo_512.jpg'
 where id = '33333333-3333-3333-3333-3333000cc001';

select results_eq(
  $$ select count(*)::int from public.jobs
     where kind = 'route_photo_process'
       and payload->>'photo_id' = '33333333-3333-3333-3333-3333000cc001' $$,
  $$ values (1) $$,
  'the service-role thumb_512_path PATCH does not re-enqueue'
);

select * from finish();

rollback;
