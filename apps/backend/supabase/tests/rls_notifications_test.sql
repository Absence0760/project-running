-- RLS suite for `public.notifications`.
--
-- Three policies (no INSERT path — notifications come from triggers
-- on run_kudos / run_comments / user_follows that run as
-- SECURITY DEFINER bypassing RLS):
--   - users read their own notifications (SELECT)
--   - users mark their own notifications read (UPDATE)
--   - users delete their own notifications (DELETE)
--
-- Notifications include who-followed-whom and who-commented-on-what,
-- including comment ids that join back to text content. A leak here
-- exposes social graph + comment context.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000a101', 'authenticated', 'authenticated',
   'a@notif.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000a102', 'authenticated', 'authenticated',
   'b@notif.local', '', now(), now());

-- INSERT must be done as postgres (or via a SECURITY DEFINER trigger);
-- there is no user-facing INSERT policy.
reset role;
insert into notifications (id, user_id, actor_id, kind)
values ('99999999-9999-9999-9999-999999999901',
        '00000000-0000-0000-0000-00000000a101',
        '00000000-0000-0000-0000-00000000a102',
        'follow');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a101"}';

-- 1. Owner can read their notification.
select results_eq(
  $$ select kind from notifications
     where user_id = '00000000-0000-0000-0000-00000000a101' $$,
  $$ values ('follow'::text) $$,
  'owner can read their notifications'
);

-- 2. Non-owner SELECT: ZERO rows.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a102"}';
select is_empty(
  $$ select id from notifications
     where user_id = '00000000-0000-0000-0000-00000000a101' $$,
  'non-owner cannot read another user''s notifications'
);

-- 3. Direct INSERT from authenticated role is rejected (no INSERT policy).
select throws_ok(
  $$ insert into notifications (user_id, actor_id, kind)
     values ('00000000-0000-0000-0000-00000000a102',
             '00000000-0000-0000-0000-00000000a101', 'follow') $$,
  '42501',
  null,
  'authenticated user cannot INSERT into notifications directly'
);

-- 4. Non-owner UPDATE (mark-read) is a no-op.
update notifications set read_at = now()
  where id = '99999999-9999-9999-9999-999999999901';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a101"}';
select is(
  (select read_at from notifications
     where id = '99999999-9999-9999-9999-999999999901'),
  null::timestamptz,
  'non-owner UPDATE on a notification is a no-op'
);

-- 5. Owner UPDATE works (mark-read).
update notifications set read_at = now()
  where id = '99999999-9999-9999-9999-999999999901';
select isnt(
  (select read_at from notifications
     where id = '99999999-9999-9999-9999-999999999901'),
  null::timestamptz,
  'owner can mark their own notification read'
);

-- 6. Non-owner DELETE: no-op.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a102"}';
delete from notifications where id = '99999999-9999-9999-9999-999999999901';
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000a101"}';
select results_eq(
  $$ select count(*)::int from notifications
     where id = '99999999-9999-9999-9999-999999999901' $$,
  $$ values (1) $$,
  'non-owner DELETE on a notification is a no-op'
);

select * from finish();

rollback;
