-- A `training_plans` template row must never carry the publisher's
-- private fields (migration 20270508_001).
--
-- `vdot` and `current_5k_seconds` are the publisher's fitness numbers;
-- plan-level `notes` is their own free text (training constraints,
-- injury history). Two migration headers claimed these were "stripped on
-- publish", but the strip lived only in the JS/Dart publishers, so a
-- direct REST insert set them and every authenticated reader could
-- SELECT them back off the public library — RLS is row-level, so the
-- "anyone reads public plan templates" branch exposes every column.
--
-- The trigger enforces the invariant at write time on ANY template row,
-- which is what makes the claim true regardless of caller. Non-template
-- plans are untouched: a runner's own plan keeps its vdot and notes.
--
-- Blast radius if this regresses: publishing a plan mails the runner's
-- injury history and fitness proxies to every user browsing the library.

begin;

select plan(9);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000ff01', 'authenticated', 'authenticated',
   'publisher@plan.local', '', now(), now());

-- ── A public-library template strips all three on INSERT ──
insert into training_plans
  (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
   days_per_week, vdot, current_5k_seconds, notes, status,
   is_template, is_public_template, club_id)
values
  ('aaaaaaaa-0000-0000-0000-0000000000f1',
   '00000000-0000-0000-0000-00000000ff01',
   'Public build', 'marathon', 42195, '2026-01-01', '2026-04-01',
   4, 55.3, 1080, 'injury history: stress fracture', 'completed',
   true, true, null);

select is(
  (select vdot from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  null, 'public template: vdot stripped on insert');
select is(
  (select current_5k_seconds from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  null, 'public template: current_5k_seconds stripped on insert');
select is(
  (select notes from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  null, 'public template: notes stripped on insert');

-- ── A later UPDATE cannot smuggle them back in ──
update training_plans
   set vdot = 60.0, current_5k_seconds = 999, notes = 'back door'
 where id = 'aaaaaaaa-0000-0000-0000-0000000000f1';

select is(
  (select vdot from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  null, 'public template: vdot stays stripped after update');
select is(
  (select notes from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000000f1'),
  null, 'public template: notes stays stripped after update');

-- ── A club template (is_template, club_id set) is covered too ──
insert into clubs (id, owner_id, name, slug, is_public, join_policy)
values
  ('77777777-0000-0000-0000-00000000ff01',
   '00000000-0000-0000-0000-00000000ff01',
   'Plan Club', 'plan-club-tp', true, 'open');

insert into training_plans
  (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
   days_per_week, vdot, current_5k_seconds, notes, status,
   is_template, is_public_template, club_id)
values
  ('aaaaaaaa-0000-0000-0000-0000000000f2',
   '00000000-0000-0000-0000-00000000ff01',
   'Club build', 'marathon', 42195, '2026-01-01', '2026-04-01',
   4, 51.1, 1140, 'my knee', 'completed',
   true, false, '77777777-0000-0000-0000-00000000ff01');

select is(
  (select vdot from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000000f2'),
  null, 'club template: vdot stripped');
select is(
  (select notes from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000000f2'),
  null, 'club template: notes stripped');

-- ── A runner's OWN plan keeps everything: this is a template rule, not
--    a blanket one. Nulling these on an ordinary plan would break pace
--    derivation, which reads vdot off the active plan.
insert into training_plans
  (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
   days_per_week, vdot, current_5k_seconds, notes, status,
   is_template, is_public_template, club_id)
values
  ('aaaaaaaa-0000-0000-0000-0000000000f3',
   '00000000-0000-0000-0000-00000000ff01',
   'My plan', 'marathon', 42195, '2026-01-01', '2026-04-01',
   4, 48.2, 1200, 'private note', 'active',
   false, false, null);

select is(
  (select vdot from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000000f3'),
  48.2::numeric(5,2), 'own plan: vdot preserved');
select is(
  (select notes from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000000f3'),
  'private note', 'own plan: notes preserved');

select * from finish();
rollback;
