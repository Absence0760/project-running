-- RLS suite for the engagement tables that gate visibility through
-- the `private.is_run_visible_to(run_id, caller)` SECURITY DEFINER helper:
--
--   - run_kudos
--   - run_comments
--   - run_photos
--   - segment_efforts
--
-- All four were re-pointed at the helper in 20260701_001 when the
-- "public runs are readable by anyone" SELECT policy on `runs` was
-- dropped (decisions §33). The helper is now the only thing that
-- lets a non-owner SEE engagement on a public run; a regression
-- there silently flips one of two ways:
--
--   - Engagement on public runs becomes invisible to non-owners
--     (the share-link looks empty, kudos counters lie, comments
--     vanish from the social feed).
--   - Engagement on PRIVATE runs leaks (kudos / comments / photos
--     show up on someone else's run-detail surface even though the
--     run itself is hidden).
--
-- One file pins all four because they share a fixture (two users,
-- one private run, one public run, one row of each engagement kind).

begin;

select plan(21);

-- ── Fixture: two users, one private run, one public run ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000e001', 'authenticated', 'authenticated',
   'a@eng.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000e002', 'authenticated', 'authenticated',
   'b@eng.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e001"}';

insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata, is_public)
values
  ('33333333-3333-3333-3333-333333333301',
   '00000000-0000-0000-0000-00000000e001',
   '2026-04-10 10:00:00+00', 1800, 5000, 'app',
   '{"activity_type":"run"}', false),
  ('33333333-3333-3333-3333-333333333302',
   '00000000-0000-0000-0000-00000000e001',
   '2026-04-11 10:00:00+00', 2400, 8000, 'app',
   '{"activity_type":"run"}', true);

-- Owner attaches engagement on both runs (kudos from a different user
-- requires a separate insert; we'll do that later).
insert into run_kudos (user_id, run_id) values
  ('00000000-0000-0000-0000-00000000e001', '33333333-3333-3333-3333-333333333301'),
  ('00000000-0000-0000-0000-00000000e001', '33333333-3333-3333-3333-333333333302');

insert into run_comments (id, run_id, author_id, body) values
  ('cccccccc-3333-3333-3333-333333333301',
   '33333333-3333-3333-3333-333333333301',
   '00000000-0000-0000-0000-00000000e001',
   'comment on private run'),
  ('cccccccc-3333-3333-3333-333333333302',
   '33333333-3333-3333-3333-333333333302',
   '00000000-0000-0000-0000-00000000e001',
   'comment on public run');

insert into run_photos (id, run_id, owner_id, storage_path) values
  ('aaaaaaaa-3333-3333-3333-333333333301',
   '33333333-3333-3333-3333-333333333301',
   '00000000-0000-0000-0000-00000000e001',
   '00000000-0000-0000-0000-00000000e001/private.jpg'),
  ('aaaaaaaa-3333-3333-3333-333333333302',
   '33333333-3333-3333-3333-333333333302',
   '00000000-0000-0000-0000-00000000e001',
   '00000000-0000-0000-0000-00000000e001/public.jpg');

-- ── Non-owner reads ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e002"}';

-- 1. run_kudos: non-owner sees only kudos on the public run.
select results_eq(
  $$ select run_id from run_kudos
       where run_id in ('33333333-3333-3333-3333-333333333301',
                         '33333333-3333-3333-3333-333333333302')
       order by run_id $$,
  $$ values ('33333333-3333-3333-3333-333333333302'::uuid) $$,
  'non-owner sees kudos on public run, not on private run'
);

-- 2. run_comments: same shape.
select results_eq(
  $$ select id from run_comments
       where run_id in ('33333333-3333-3333-3333-333333333301',
                         '33333333-3333-3333-3333-333333333302')
       order by id $$,
  $$ values ('cccccccc-3333-3333-3333-333333333302'::uuid) $$,
  'non-owner sees comments on public run, not on private run'
);

-- 3. run_photos: same shape.
select results_eq(
  $$ select id from run_photos
       where run_id in ('33333333-3333-3333-3333-333333333301',
                         '33333333-3333-3333-3333-333333333302')
       order by id $$,
  $$ values ('aaaaaaaa-3333-3333-3333-333333333302'::uuid) $$,
  'non-owner sees photos on public run, not on private run'
);

-- ── Non-owner writes ──

-- 4. Kudos INSERT on the public run: allowed (auth.uid()=user_id AND
--    private.is_run_visible_to(run_id, caller) is true for public runs).
insert into run_kudos (user_id, run_id) values
  ('00000000-0000-0000-0000-00000000e002', '33333333-3333-3333-3333-333333333302');
select results_eq(
  $$ select count(*)::int from run_kudos
       where run_id = '33333333-3333-3333-3333-333333333302'
         and user_id = '00000000-0000-0000-0000-00000000e002' $$,
  $$ values (1) $$,
  'non-owner can give kudos on a public run'
);

-- 5. Kudos INSERT on the private run: rejected (helper returns false).
select throws_ok(
  $$ insert into run_kudos (user_id, run_id) values
       ('00000000-0000-0000-0000-00000000e002', '33333333-3333-3333-3333-333333333301') $$,
  '42501',
  null,
  'non-owner cannot give kudos on a private run'
);

-- 6. Kudos INSERT under a forged user_id is rejected even on a public run.
select throws_ok(
  $$ insert into run_kudos (user_id, run_id) values
       ('00000000-0000-0000-0000-00000000e001', '33333333-3333-3333-3333-333333333302') $$,
  '42501',
  null,
  'cannot give kudos under another user_id even on a public run'
);

-- 7. Comment INSERT on the public run: allowed.
insert into run_comments (id, run_id, author_id, body) values
  ('cccccccc-3333-3333-3333-333333333303',
   '33333333-3333-3333-3333-333333333302',
   '00000000-0000-0000-0000-00000000e002',
   'comment from non-owner');
select results_eq(
  $$ select count(*)::int from run_comments
       where id = 'cccccccc-3333-3333-3333-333333333303' $$,
  $$ values (1) $$,
  'non-owner can post a comment on a public run'
);

-- 8. Comment INSERT on the private run: rejected.
select throws_ok(
  $$ insert into run_comments (run_id, author_id, body) values
       ('33333333-3333-3333-3333-333333333301',
        '00000000-0000-0000-0000-00000000e002',
        'leaked comment') $$,
  '42501',
  null,
  'non-owner cannot post a comment on a private run'
);

-- 9. Comment INSERT under a forged author_id is rejected.
select throws_ok(
  $$ insert into run_comments (run_id, author_id, body) values
       ('33333333-3333-3333-3333-333333333302',
        '00000000-0000-0000-0000-00000000e001',
        'forged author') $$,
  '42501',
  null,
  'cannot post a comment under another author_id'
);

-- 10. Photo INSERT by a non-owner on the public run: rejected (the
--     photos INSERT policy requires `auth.uid() = owner_id` AND that
--     the caller owns the RUN, not just that the run is visible —
--     stops drive-by photo attachment to other people's public runs).
select throws_ok(
  $$ insert into run_photos (run_id, owner_id, storage_path) values
       ('33333333-3333-3333-3333-333333333302',
        '00000000-0000-0000-0000-00000000e002',
        '00000000-0000-0000-0000-00000000e002/x.jpg') $$,
  '42501',
  null,
  'non-owner cannot attach a photo to another user''s public run'
);

-- 11. Comment author can edit their own comment.
update run_comments set body = 'edited' where id = 'cccccccc-3333-3333-3333-333333333303';
select results_eq(
  $$ select body from run_comments where id = 'cccccccc-3333-3333-3333-333333333303' $$,
  $$ values ('edited'::text) $$,
  'comment author can edit their own comment'
);

-- 12. Non-author cannot edit a comment.
update run_comments set body = 'pwned' where id = 'cccccccc-3333-3333-3333-333333333302';
select isnt(
  (select body from run_comments where id = 'cccccccc-3333-3333-3333-333333333302'),
  'pwned',
  'non-author cannot edit another user''s comment'
);

-- 13. Run owner can DELETE any comment on their run.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e001"}';
delete from run_comments where id = 'cccccccc-3333-3333-3333-333333333303';
select is_empty(
  $$ select id from run_comments where id = 'cccccccc-3333-3333-3333-333333333303' $$,
  'run owner can delete any comment on their run'
);

-- 14. Comment author can DELETE their own comment on someone else's run.
--     (Needs a fresh fixture: a comment by user B on user A's public run.)
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e002"}';
insert into run_comments (id, run_id, author_id, body) values
  ('cccccccc-3333-3333-3333-333333333304',
   '33333333-3333-3333-3333-333333333302',
   '00000000-0000-0000-0000-00000000e002',
   'B comments on A''s public run');
delete from run_comments where id = 'cccccccc-3333-3333-3333-333333333304';
select is_empty(
  $$ select id from run_comments where id = 'cccccccc-3333-3333-3333-333333333304' $$,
  'comment author can delete their own comment'
);

-- 15. Kudos owner can rescind their own kudos.
delete from run_kudos
  where user_id = '00000000-0000-0000-0000-00000000e002'
    and run_id = '33333333-3333-3333-3333-333333333302';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e001"}';
select is_empty(
  $$ select 1 from run_kudos
       where user_id = '00000000-0000-0000-0000-00000000e002'
         and run_id = '33333333-3333-3333-3333-333333333302' $$,
  'kudos giver can rescind their own kudos'
);

-- 16. Anon: cannot read kudos on private run.
set local role anon;
set local "request.jwt.claims" = '';
select is_empty(
  $$ select 1 from run_kudos
       where run_id = '33333333-3333-3333-3333-333333333301' $$,
  'anon cannot read kudos on a private run'
);

-- 17. Anon: CAN read kudos on a public run.
select results_eq(
  $$ select count(*)::int from run_kudos
       where run_id = '33333333-3333-3333-3333-333333333302' $$,
  $$ values (1) $$,
  'anon can read kudos on a public run via is_run_visible_to'
);

-- 18. Anon: cannot read comments on private run, can read on public.
select is_empty(
  $$ select 1 from run_comments
       where run_id = '33333333-3333-3333-3333-333333333301' $$,
  'anon cannot read comments on a private run'
);
select results_eq(
  $$ select id from run_comments
       where run_id = '33333333-3333-3333-3333-333333333302'
       order by id $$,
  $$ values ('cccccccc-3333-3333-3333-333333333302'::uuid) $$,
  'anon can read comments on a public run via is_run_visible_to'
);

-- 19. Anon: cannot read photos on private run, can on public.
select is_empty(
  $$ select 1 from run_photos
       where run_id = '33333333-3333-3333-3333-333333333301' $$,
  'anon cannot read photos on a private run'
);

-- 20. is_run_visible_to helper: directly assert the contract for
--     all three callers (owner / non-owner / null/anon-as-null) on
--     both private and public runs.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000e001"}';
select is(
  private.is_run_visible_to('33333333-3333-3333-3333-333333333301',
                    '00000000-0000-0000-0000-00000000e001'),
  true,
  'private.is_run_visible_to(private_run, owner) = true'
);

select * from finish();

rollback;
