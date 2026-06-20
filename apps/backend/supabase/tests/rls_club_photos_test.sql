-- RLS + path-guard suite for `public.club_photos` (roadmap backlog row 8 —
-- the deferred club-photo gallery). Migration 20270301_001.
--
-- Policy / guard stack, re-keyed from route_photos to club membership:
--   - SELECT "club photos readable when club is visible" — public club →
--     anyone; private club → owner / active member only. Anon flows
--     through the same gate.
--   - INSERT "club member attaches photos" — caller is the row owner AND an
--     ACTIVE member of the club (any member, not just the owner/admin).
--   - DELETE — photo owner OR club admin (moderation).
--   - UPDATE "club photo owner updates caption" — photo owner only.
--   - storage_path shape CHECK ({owner}/% or '') + no-blank-clear trigger.
--   - thumb_512_path shape CHECK + service-role-only UPDATE trigger.
--   - jobs.kind allowlist accepts 'club_photo_process' (three-file rule).
--
-- Blast radius if regressed: a private club's gallery leaking to anon /
-- non-members; a non-member planting photos on a club they don't belong
-- to; a member or admin unable to moderate; or a cross-user Storage read
-- via a forged path column the SELECT policy would then approve.

begin;

select plan(17);

-- ── Fixture ──
-- owner = club owner; member = active member; admin = active admin;
-- pending = a pending join request; outsider = no membership at all.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000cc001', 'authenticated', 'authenticated',
   'club-owner@photo.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000cc002', 'authenticated', 'authenticated',
   'member@photo.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000cc003', 'authenticated', 'authenticated',
   'admin@photo.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000cc004', 'authenticated', 'authenticated',
   'pending@photo.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000cc005', 'authenticated', 'authenticated',
   'outsider@photo.local', '', now(), now());

-- A public club and a private club, both owned by cc001.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values
  ('11111111-1111-1111-1111-1111000cc001',
   '00000000-0000-0000-0000-0000000cc001', 'Public Club', 'public-club-cc', true, 'open'),
  ('11111111-1111-1111-1111-1111000cc002',
   '00000000-0000-0000-0000-0000000cc001', 'Private Club', 'private-club-cc', false, 'request');

-- The owner (cc001) is auto-enrolled as an ACTIVE 'owner' member of BOTH
-- clubs by the enroll_club_owner trigger (20260416_001), so we only add the
-- additional members on the PRIVATE club: an active member, an active
-- admin, and a pending request.
insert into club_members (club_id, user_id, role, status)
values
  ('11111111-1111-1111-1111-1111000cc002', '00000000-0000-0000-0000-0000000cc002', 'member', 'active'),
  ('11111111-1111-1111-1111-1111000cc002', '00000000-0000-0000-0000-0000000cc003', 'admin', 'active'),
  ('11111111-1111-1111-1111-1111000cc002', '00000000-0000-0000-0000-0000000cc004', 'member', 'pending');

-- ── Owner attaches a photo to the PUBLIC club ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc001","role":"authenticated"}';

-- 1. Owner (auto-enrolled active member) attaches a photo to the public club.
insert into club_photos (id, club_id, owner_id, storage_path, caption, position_idx)
values
  ('33333333-3333-3333-3333-3333000cc001',
   '11111111-1111-1111-1111-1111000cc001',
   '00000000-0000-0000-0000-0000000cc001',
   '00000000-0000-0000-0000-0000000cc001/pub1.jpg',
   'public club photo', 0);
select pass('owner attaches a photo to their public club');

-- 2. Owner attaches a photo to the PRIVATE club too.
insert into club_photos (id, club_id, owner_id, storage_path, caption, position_idx)
values
  ('33333333-3333-3333-3333-3333000cc002',
   '11111111-1111-1111-1111-1111000cc002',
   '00000000-0000-0000-0000-0000000cc001',
   '00000000-0000-0000-0000-0000000cc001/priv1.jpg',
   'private club photo', 0);
select pass('owner attaches a photo to their private club');

-- 3. An ACTIVE MEMBER (not the owner) can contribute to the private club.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc002","role":"authenticated"}';
insert into club_photos (id, club_id, owner_id, storage_path, caption, position_idx)
values
  ('33333333-3333-3333-3333-3333000cc003',
   '11111111-1111-1111-1111-1111000cc002',
   '00000000-0000-0000-0000-0000000cc002',
   '00000000-0000-0000-0000-0000000cc002/priv2.jpg',
   'member contribution', 1);
select pass('active member (non-owner) can attach a photo to the club');

-- 4. A PENDING member cannot contribute (pending grants no write).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc004","role":"authenticated"}';
select throws_ok(
  $$ insert into club_photos (club_id, owner_id, storage_path)
       values ('11111111-1111-1111-1111-1111000cc002',
               '00000000-0000-0000-0000-0000000cc004',
               '00000000-0000-0000-0000-0000000cc004/pending.jpg') $$,
  '42501',
  null,
  'pending member cannot attach a photo'
);

-- 5. An OUTSIDER (no membership) cannot contribute to the private club.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc005","role":"authenticated"}';
select throws_ok(
  $$ insert into club_photos (club_id, owner_id, storage_path)
       values ('11111111-1111-1111-1111-1111000cc002',
               '00000000-0000-0000-0000-0000000cc005',
               '00000000-0000-0000-0000-0000000cc005/outsider.jpg') $$,
  '42501',
  null,
  'non-member cannot attach a photo'
);

-- 6. Forged INSERT under another user's owner_id is rejected.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc002","role":"authenticated"}';
select throws_ok(
  $$ insert into club_photos (club_id, owner_id, storage_path)
       values ('11111111-1111-1111-1111-1111000cc002',
               '00000000-0000-0000-0000-0000000cc001',
               '00000000-0000-0000-0000-0000000cc001/forged.jpg') $$,
  '42501',
  null,
  'cannot INSERT a photo under another user owner_id'
);

-- ── Read visibility ──
-- 7. An outsider can read a photo on the PUBLIC club.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc005","role":"authenticated"}';
select results_eq(
  $$ select caption from club_photos
     where id = '33333333-3333-3333-3333-3333000cc001' $$,
  $$ values ('public club photo'::text) $$,
  'non-member can SELECT a photo on a public club'
);

-- 8. That same outsider CANNOT see any photo on the PRIVATE club.
select is_empty(
  $$ select id from club_photos
     where club_id = '11111111-1111-1111-1111-1111000cc002' $$,
  'non-member cannot SELECT photos on a private club'
);

-- 9. A pending member also cannot see the private club's photos.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc004","role":"authenticated"}';
select is_empty(
  $$ select id from club_photos
     where club_id = '11111111-1111-1111-1111-1111000cc002' $$,
  'pending member cannot SELECT photos on a private club'
);

-- 10. An ACTIVE member CAN see the private club's photos.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc002","role":"authenticated"}';
select results_eq(
  $$ select count(*)::int from club_photos
     where club_id = '11111111-1111-1111-1111-1111000cc002' $$,
  $$ values (2) $$,
  'active member can SELECT photos on a private club'
);

-- ── Delete / moderation ──
-- 11. A non-owner, non-admin member cannot delete another member's photo
--     (cc002 is a plain member; the photo cc002 targets is the owner's).
delete from club_photos where id = '33333333-3333-3333-3333-3333000cc002';
set local role service_role;
reset "request.jwt.claims";
select results_eq(
  $$ select count(*)::int from club_photos
     where id = '33333333-3333-3333-3333-3333000cc002' $$,
  $$ values (1) $$,
  'plain member DELETE of another member photo is a no-op'
);

-- 12. The photo owner CAN delete their own photo.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc002","role":"authenticated"}';
delete from club_photos where id = '33333333-3333-3333-3333-3333000cc003';
set local role service_role;
reset "request.jwt.claims";
select is_empty(
  $$ select id from club_photos
     where id = '33333333-3333-3333-3333-3333000cc003' $$,
  'photo owner can DELETE their own photo'
);

-- 13. A club ADMIN can delete ANYONE'S photo (moderation) — admin cc003
--     deletes the owner's private-club photo.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc003","role":"authenticated"}';
delete from club_photos where id = '33333333-3333-3333-3333-3333000cc002';
set local role service_role;
reset "request.jwt.claims";
select is_empty(
  $$ select id from club_photos
     where id = '33333333-3333-3333-3333-3333000cc002' $$,
  'club admin can DELETE any member photo (moderation)'
);

-- ── Path guards ──
-- 14. storage_path shape CHECK: a path under another user prefix is rejected.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000cc001","role":"authenticated"}';
select throws_ok(
  $$ insert into club_photos (club_id, owner_id, storage_path)
       values ('11111111-1111-1111-1111-1111000cc001',
               '00000000-0000-0000-0000-0000000cc001',
               '00000000-0000-0000-0000-0000000cc002/stolen.jpg') $$,
  '23514',
  null,
  'storage_path that does not start with owner_id is rejected by CHECK'
);

-- 15. no-blank-clear trigger: clearing a real storage_path via UPDATE is
--     rejected (use DELETE to remove a photo).
select throws_ok(
  $$ update club_photos set storage_path = ''
       where id = '33333333-3333-3333-3333-3333000cc001' $$,
  '42501',
  null,
  'clearing storage_path via UPDATE is rejected'
);

-- 16. thumb_512_path is service-role only — an owner UPDATE is rejected.
select throws_ok(
  $$ update club_photos
        set thumb_512_path = '00000000-0000-0000-0000-0000000cc001/pub1_512.jpg'
      where id = '33333333-3333-3333-3333-3333000cc001' $$,
  '42501',
  null,
  'owner UPDATE of thumb_512_path is rejected (service-role only)'
);

-- 17. service_role CAN write thumb_512_path (the worker path) AND the
--     jobs.kind allowlist accepts the new club_photo_process kind.
set local role service_role;
reset "request.jwt.claims";
update club_photos
   set thumb_512_path = '00000000-0000-0000-0000-0000000cc001/pub1_512.jpg'
 where id = '33333333-3333-3333-3333-3333000cc001';
insert into public.jobs (kind, payload)
values ('club_photo_process',
        jsonb_build_object('photo_id', '33333333-3333-3333-3333-3333000cc001',
                           'storage_path', '00000000-0000-0000-0000-0000000cc001/pub1.jpg',
                           'owner_id', '00000000-0000-0000-0000-0000000cc001'));
select pass('service_role writes thumb_512_path + jobs accepts club_photo_process');

select * from finish();

rollback;
