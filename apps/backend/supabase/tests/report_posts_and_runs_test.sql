-- pgtap for reporting club posts + runs (20270115_001). submit_report
-- must accept target_kind in ('club_post','run'), reject reporting your
-- own post/run, and 404 a missing target.

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000e0001', 'authenticated', 'authenticated',
   'owner@e2.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000e0002', 'authenticated', 'authenticated',
   'viewer@e2.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000e0001', 'Owner'),
  ('00000000-0000-0000-0000-0000000e0002', 'Viewer');

-- Owner runs a public club + posts in it; owns a public run.
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values ('77777777-7777-7777-7777-0000000e0001',
   '00000000-0000-0000-0000-0000000e0001',
   'E2 Club', 'e2-club', true, 'open');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000e0001"}';
insert into club_posts (id, club_id, author_id, body)
values ('00000000-0000-0000-0000-0000000eb001',
   '77777777-7777-7777-7777-0000000e0001',
   '00000000-0000-0000-0000-0000000e0001', 'spammy club post');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, metadata, is_public)
values ('00000000-0000-0000-0000-0000000ed001',
   '00000000-0000-0000-0000-0000000e0001', now(), 5000, 1500, 'app',
   '{"activity_type":"run"}'::jsonb, true);

-- ── 1. A viewer can report a club post ───────────────────────────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000e0002"}';
select lives_ok(
  $$ select submit_report('club_post', '00000000-0000-0000-0000-0000000eb001'::uuid, 'spam', null) $$,
  'a viewer can report a club post'
);

-- ── 2. A club_post report row landed ─────────────────────────────
select is(
  (select count(*)::int from reports
     where target_kind = 'club_post'
       and target_id = '00000000-0000-0000-0000-0000000eb001'),
  1,
  'a club_post report row exists'
);

-- ── 3. A viewer can report a run ─────────────────────────────────
select lives_ok(
  $$ select submit_report('run', '00000000-0000-0000-0000-0000000ed001'::uuid, 'inappropriate', null) $$,
  'a viewer can report a run'
);

-- ── 4. A run report row landed ───────────────────────────────────
select is(
  (select count(*)::int from reports
     where target_kind = 'run'
       and target_id = '00000000-0000-0000-0000-0000000ed001'),
  1,
  'a run report row exists'
);

-- ── 5. Post author cannot report their own post (22023) ──────────
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000e0001"}';
select throws_ok(
  $$ select submit_report('club_post', '00000000-0000-0000-0000-0000000eb001'::uuid, 'spam', null) $$,
  '22023',
  null,
  'a user cannot report their own club post'
);

-- ── 6. Run owner cannot report their own run (22023) ─────────────
select throws_ok(
  $$ select submit_report('run', '00000000-0000-0000-0000-0000000ed001'::uuid, 'spam', null) $$,
  '22023',
  null,
  'a user cannot report their own run'
);

-- ── 7. Missing club post 404s (02000) ────────────────────────────
select throws_ok(
  $$ select submit_report('club_post', '00000000-0000-0000-0000-0000000eb999'::uuid, 'spam', null) $$,
  '02000',
  null,
  'reporting a missing club post raises no_data (02000)'
);

-- ── 8. Missing run 404s (02000) ──────────────────────────────────
select throws_ok(
  $$ select submit_report('run', '00000000-0000-0000-0000-0000000ed999'::uuid, 'spam', null) $$,
  '02000',
  null,
  'reporting a missing run raises no_data (02000)'
);

select * from finish();
rollback;
