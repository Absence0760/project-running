-- pgtap for the follow-notification cleanup + coalesce (20270310_001).
--
-- A follow creates one "started following you" notification; unfollowing
-- retracts it while it's still unread; a rapid re-follow doesn't stack a
-- second unread row; and an already-READ follow notification survives the
-- unfollow (a truthful record of something that happened).

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000fb001', 'authenticated', 'authenticated', 'follower@fnc.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000fb002', 'authenticated', 'authenticated', 'followee@fnc.local', '', now(), now());

-- 1. Following creates exactly one unread follow notification for the followee.
insert into user_follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-0000000fb001', '00000000-0000-0000-0000-0000000fb002');
select is(
  (select count(*)::int from notifications
     where user_id = '00000000-0000-0000-0000-0000000fb002'
       and actor_id = '00000000-0000-0000-0000-0000000fb001'
       and kind = 'follow'),
  1,
  'following creates one follow notification'
);

-- 2. Unfollowing retracts the still-unread follow notification.
delete from user_follows
 where follower_id = '00000000-0000-0000-0000-0000000fb001'
   and followee_id = '00000000-0000-0000-0000-0000000fb002';
select is(
  (select count(*)::int from notifications
     where user_id = '00000000-0000-0000-0000-0000000fb002'
       and actor_id = '00000000-0000-0000-0000-0000000fb001'
       and kind = 'follow'),
  0,
  'unfollowing retracts the unread follow notification'
);

-- 3+4. Re-follow twice in a row (unfollowing between) mints exactly ONE unread
--      row, not one per follow — the coalescing INSERT guard.
insert into user_follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-0000000fb001', '00000000-0000-0000-0000-0000000fb002');
delete from user_follows
 where follower_id = '00000000-0000-0000-0000-0000000fb001'
   and followee_id = '00000000-0000-0000-0000-0000000fb002';
insert into user_follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-0000000fb001', '00000000-0000-0000-0000-0000000fb002');
-- (the delete above cleared the first; re-follow makes exactly one)
insert into user_follows (follower_id, followee_id)
values ('00000000-0000-0000-0000-0000000fb002', '00000000-0000-0000-0000-0000000fb001');
-- a distinct pair (reverse direction) is its own notification, untouched
select is(
  (select count(*)::int from notifications
     where user_id = '00000000-0000-0000-0000-0000000fb002'
       and actor_id = '00000000-0000-0000-0000-0000000fb001'
       and kind = 'follow'
       and read_at is null),
  1,
  'churny re-follow leaves exactly one unread follow notification'
);
select is(
  (select count(*)::int from notifications
     where user_id = '00000000-0000-0000-0000-0000000fb001'
       and actor_id = '00000000-0000-0000-0000-0000000fb002'
       and kind = 'follow'),
  1,
  'the reverse-direction follow is a separate, untouched notification'
);

-- 5. A follow notification the user already READ survives an unfollow.
update notifications set read_at = now()
 where user_id = '00000000-0000-0000-0000-0000000fb002'
   and actor_id = '00000000-0000-0000-0000-0000000fb001'
   and kind = 'follow';
delete from user_follows
 where follower_id = '00000000-0000-0000-0000-0000000fb001'
   and followee_id = '00000000-0000-0000-0000-0000000fb002';
select is(
  (select count(*)::int from notifications
     where user_id = '00000000-0000-0000-0000-0000000fb002'
       and actor_id = '00000000-0000-0000-0000-0000000fb001'
       and kind = 'follow'),
  1,
  'an already-read follow notification survives the unfollow'
);

select * from finish();
rollback;
