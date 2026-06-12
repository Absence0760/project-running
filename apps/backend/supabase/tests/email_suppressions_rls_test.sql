-- email_suppressions is worker/service-role-only (bounces, complaints, the
-- unsubscribe endpoint). RLS is fail-closed: no policy, so a regular
-- authenticated user can neither read nor write it. service_role bypasses RLS
-- and remains the sole reader/writer.

begin;

select plan(3);

-- Seeded as the test superuser (RLS does not apply before `set role`).
insert into email_suppressions (email, reason) values ('blocked@suppress.local', 'bounce');

-- 1. weekly_digest is an accepted jobs.kind (the digest scheduler enqueues it).
select lives_ok(
  $$ insert into jobs (kind, payload) values ('weekly_digest', '{}'::jsonb) $$,
  'weekly_digest is an accepted jobs.kind'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000000e1"}';

-- 2. An authenticated user cannot READ the suppression list (fail-closed RLS).
select is(
  (select count(*)::int from email_suppressions),
  0,
  'authenticated user cannot read email_suppressions (no SELECT policy)'
);

-- 3. An authenticated user cannot WRITE it either.
select throws_ok(
  $$ insert into email_suppressions (email, reason) values ('x@y.local', 'manual') $$,
  '42501', null,
  'authenticated user cannot insert into email_suppressions'
);

select * from finish();
rollback;
