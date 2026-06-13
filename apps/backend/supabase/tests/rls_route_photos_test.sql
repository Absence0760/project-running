-- RLS + path-guard suite for `public.route_photos` (backlog C1 — the
-- run_photos capability applied to routes). Migration 20270114_001.
--
-- Policy / guard stack mirrored from the run_photos chain:
--   - SELECT "photos readable when route is visible" — gated by
--     private.is_route_visible_to(route_id, auth.uid()) (own / public /
--     club-member). Anon flows through the same helper.
--   - INSERT "route owner attaches photos" — caller is the row owner AND
--     owns the parent route.
--   - DELETE — photo owner OR route owner.
--   - UPDATE "photo owner updates caption" — owner only.
--   - storage_path shape CHECK ({owner}/% or '') + no-blank-clear trigger.
--   - thumb_512_path shape CHECK + service-role-only UPDATE trigger.
--
-- Blast radius if regressed: a private route's photos leaking to anon /
-- non-members; a forged INSERT planting photos on a route the caller
-- doesn't own; or a cross-user Storage read via a forged path column
-- the SELECT policy would then approve.

begin;

select plan(13);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000bb001', 'authenticated', 'authenticated',
   'route-owner@photo.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000bb002', 'authenticated', 'authenticated',
   'other@photo.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000bb001","role":"authenticated"}';

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('22222222-2222-2222-2222-2222000bb001',
   '00000000-0000-0000-0000-0000000bb001',
   'Public Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   5000, true),
  ('22222222-2222-2222-2222-2222000bb002',
   '00000000-0000-0000-0000-0000000bb001',
   'Private Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
   5000, false);

-- 1. Owner attaches a photo to their public route.
insert into route_photos (id, route_id, owner_id, storage_path, caption, position_idx)
values
  ('33333333-3333-3333-3333-3333000bb001',
   '22222222-2222-2222-2222-2222000bb001',
   '00000000-0000-0000-0000-0000000bb001',
   '00000000-0000-0000-0000-0000000bb001/photo1.jpg',
   'on the public loop', 0);
select pass('owner attaches a photo to their own public route');

-- 2. Owner attaches a photo to their private route too.
insert into route_photos (id, route_id, owner_id, storage_path, caption, position_idx)
values
  ('33333333-3333-3333-3333-3333000bb002',
   '22222222-2222-2222-2222-2222000bb002',
   '00000000-0000-0000-0000-0000000bb001',
   '00000000-0000-0000-0000-0000000bb001/photo2.jpg',
   'on the private loop', 0);
select pass('owner attaches a photo to their own private route');

-- 3. Owner can read their own photo.
select results_eq(
  $$ select caption from route_photos
     where id = '33333333-3333-3333-3333-3333000bb001' $$,
  $$ values ('on the public loop'::text) $$,
  'owner can SELECT their own photo'
);

-- 4. A different signed-in user can read the photo on the PUBLIC route.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000bb002","role":"authenticated"}';
select results_eq(
  $$ select caption from route_photos
     where id = '33333333-3333-3333-3333-3333000bb001' $$,
  $$ values ('on the public loop'::text) $$,
  'non-owner can SELECT a photo on a public route'
);

-- 5. That same user CANNOT see the photo on the PRIVATE route.
select is_empty(
  $$ select id from route_photos
     where id = '33333333-3333-3333-3333-3333000bb002' $$,
  'non-owner cannot SELECT a photo on a private route'
);

-- 6. Forged INSERT under another user's owner_id is rejected.
select throws_ok(
  $$ insert into route_photos (route_id, owner_id, storage_path)
       values ('22222222-2222-2222-2222-2222000bb001',
               '00000000-0000-0000-0000-0000000bb001',
               '00000000-0000-0000-0000-0000000bb001/forged.jpg') $$,
  '42501',
  null,
  'cannot INSERT a photo under another user owner_id'
);

-- 7. INSERT against a route the caller does NOT own is rejected, even
--    with the caller's own owner_id (the route is public, so the
--    visibility helper would pass — the INSERT policy is stricter).
select throws_ok(
  $$ insert into route_photos (route_id, owner_id, storage_path)
       values ('22222222-2222-2222-2222-2222000bb001',
               '00000000-0000-0000-0000-0000000bb002',
               '00000000-0000-0000-0000-0000000bb002/notmine.jpg') $$,
  '42501',
  null,
  'cannot attach a photo to a route the caller does not own'
);

-- 8. Non-owner DELETE on the public-route photo is a silent no-op
--    (caller is neither photo owner nor route owner).
delete from route_photos where id = '33333333-3333-3333-3333-3333000bb001';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000bb001","role":"authenticated"}';
select results_eq(
  $$ select count(*)::int from route_photos
     where id = '33333333-3333-3333-3333-3333000bb001' $$,
  $$ values (1) $$,
  'non-owner DELETE on a photo is a no-op'
);

-- 9. storage_path shape CHECK: a path under another user prefix is rejected.
select throws_ok(
  $$ insert into route_photos (route_id, owner_id, storage_path)
       values ('22222222-2222-2222-2222-2222000bb001',
               '00000000-0000-0000-0000-0000000bb001',
               '00000000-0000-0000-0000-0000000bb002/stolen.jpg') $$,
  '23514',
  null,
  'storage_path that does not start with owner_id is rejected by CHECK'
);

-- 10. no-blank-clear trigger: once a real path is set, an UPDATE that
--     clears it is rejected (use DELETE to remove a photo).
select throws_ok(
  $$ update route_photos set storage_path = ''
       where id = '33333333-3333-3333-3333-3333000bb001' $$,
  '42501',
  null,
  'clearing storage_path via UPDATE is rejected'
);

-- 11. thumb_512_path shape CHECK: an alien-prefix thumb is rejected.
select throws_ok(
  $$ update route_photos
        set thumb_512_path = '00000000-0000-0000-0000-0000000bb002/stolen_512.jpg'
      where id = '33333333-3333-3333-3333-3333000bb001' $$,
  '42501',
  null,
  'owner UPDATE of thumb_512_path is rejected (service-role only)'
);

-- 12. service_role CAN write thumb_512_path (worker path).
set local role service_role;
reset "request.jwt.claims";
update route_photos
   set thumb_512_path = '00000000-0000-0000-0000-0000000bb001/photo1_512.jpg'
 where id = '33333333-3333-3333-3333-3333000bb001';
select pass('service_role can UPDATE thumb_512_path (worker path)');

-- 13. Anon cannot read a photo on a private route.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select id from route_photos
     where id = '33333333-3333-3333-3333-3333000bb002' $$,
  'anon cannot SELECT a photo on a private route'
);

select * from finish();

rollback;
