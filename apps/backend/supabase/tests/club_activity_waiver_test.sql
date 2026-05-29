-- Pins migration 20261023_001 — club activity-risk waiver columns
-- (parkrun persona #45). clubs.requires_activity_waiver defaults false; a
-- membership can record the acknowledgement timestamp.

begin;
select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'o@waiver.local', '', now(), now()),
  ('aaaaaaaa-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'm@waiver.local', '', now(), now());

-- Club created without specifying the flag — should default false.
insert into clubs (id, owner_id, name, slug)
values ('cccccccc-0000-0000-0000-0000000000d1',
        'aaaaaaaa-0000-0000-0000-0000000000a1', 'Waiver Club', 'waiver-club');

select is(
  (select requires_activity_waiver from clubs
   where id = 'cccccccc-0000-0000-0000-0000000000d1'),
  false,
  'requires_activity_waiver defaults to false');

update clubs set requires_activity_waiver = true
  where id = 'cccccccc-0000-0000-0000-0000000000d1';
select is(
  (select requires_activity_waiver from clubs
   where id = 'cccccccc-0000-0000-0000-0000000000d1'),
  true,
  'an admin can require the activity waiver');

-- A joining member records the acknowledgement timestamp.
insert into club_members (club_id, user_id, role, status, activity_waiver_ack_at)
values ('cccccccc-0000-0000-0000-0000000000d1',
        'aaaaaaaa-0000-0000-0000-0000000000a2', 'member', 'active', now());
select isnt(
  (select activity_waiver_ack_at from club_members
   where club_id = 'cccccccc-0000-0000-0000-0000000000d1'
     and user_id = 'aaaaaaaa-0000-0000-0000-0000000000a2'),
  null,
  'a membership records the activity-waiver acknowledgement timestamp');

select * from finish();
rollback;
