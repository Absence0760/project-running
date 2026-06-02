-- Pins the free-text length caps from 20261124_001 (audit-xss L3):
-- club_posts.body <= 4096, events.description <= 2000. The CHECK fires
-- regardless of role, so these run as service_role against the constraint
-- directly (RLS is irrelevant to a CHECK violation).

begin;
select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000ca900001', 'authenticated', 'authenticated', 'cap@hyg.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('ca900000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000ca900001', 'Cap Club', 'cap-club', true);

insert into events (id, club_id, title, starts_at, created_by)
values ('ca900000-0000-0000-0000-00000000e111', 'ca900000-0000-0000-0000-0000000000c1', 'Cap 5k', '2026-06-06 09:00+00', '00000000-0000-0000-0000-0000ca900001');

-- club_posts.body
select lives_ok(
  $$ insert into club_posts (id, club_id, author_id, body)
     values ('ca900000-0000-0000-0000-0000000000b1', 'ca900000-0000-0000-0000-0000000000c1',
             '00000000-0000-0000-0000-0000ca900001', repeat('x', 4096)) $$,
  'a 4096-char club post body is accepted (boundary)');
select throws_ok(
  $$ insert into club_posts (id, club_id, author_id, body)
     values ('ca900000-0000-0000-0000-0000000000b2', 'ca900000-0000-0000-0000-0000000000c1',
             '00000000-0000-0000-0000-0000ca900001', repeat('x', 4097)) $$,
  '23514', NULL,
  'a 4097-char club post body is rejected (check_violation)');

-- events.description
select lives_ok(
  $$ update events set description = repeat('y', 2000)
     where id = 'ca900000-0000-0000-0000-00000000e111' $$,
  'a 2000-char event description is accepted (boundary)');
select throws_ok(
  $$ update events set description = repeat('y', 2001)
     where id = 'ca900000-0000-0000-0000-00000000e111' $$,
  '23514', NULL,
  'a 2001-char event description is rejected (check_violation)');

-- A null description is still allowed.
select lives_ok(
  $$ update events set description = null
     where id = 'ca900000-0000-0000-0000-00000000e111' $$,
  'a null event description is still allowed');

select * from finish();
rollback;
