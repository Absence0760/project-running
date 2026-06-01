-- pgtap for reporting comments (20261117_001). submit_report must accept
-- target_kind='comment', reject a self-authored comment, and 404 a missing one.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c0001', 'authenticated', 'authenticated',
   'runner@cmt.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c0002', 'authenticated', 'authenticated',
   'commenter@cmt.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000c0001', 'Runner'),
  ('00000000-0000-0000-0000-0000000c0002', 'Commenter');

-- Runner owns a public run; Commenter leaves a comment on it.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0001"}';
insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('00000000-0000-0000-0000-00000000d001',
   '00000000-0000-0000-0000-0000000c0001', now(), 5000, 1500, 'app', '{"activity_type":"run"}'::jsonb, true);

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0002"}';
insert into run_comments (id, run_id, author_id, body)
values ('00000000-0000-0000-0000-0000000ab001',
   '00000000-0000-0000-0000-00000000d001',
   '00000000-0000-0000-0000-0000000c0002', 'rude comment');

-- 1. The run owner can report the comment.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0001"}';
select lives_ok(
  $$ select submit_report('comment', '00000000-0000-0000-0000-0000000ab001'::uuid, 'harassment', null) $$,
  'run owner can report a comment'
);

-- 2. A report row landed with target_kind=comment.
select is(
  (select count(*)::int from reports
     where target_kind = 'comment'
       and target_id = '00000000-0000-0000-0000-0000000ab001'),
  1,
  'a comment report row exists'
);

-- 3. The comment author cannot report their own comment (22023).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0002"}';
select throws_ok(
  $$ select submit_report('comment', '00000000-0000-0000-0000-0000000ab001'::uuid, 'spam', null) $$,
  '22023',
  null,
  'a user cannot report their own comment'
);

-- 4. Reporting a non-existent comment 404s (02000).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c0001"}';
select throws_ok(
  $$ select submit_report('comment', '00000000-0000-0000-0000-0000000ab999'::uuid, 'spam', null) $$,
  '02000',
  null,
  'reporting a missing comment raises no_data (02000)'
);

select * from finish();
rollback;
