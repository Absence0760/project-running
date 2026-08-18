-- Pins migration 20270527_002 — search_public_events derives the weekday of a
-- one-off event from the EVENT's timezone, exactly as the sibling p_time filter
-- derives the time of day. The two fixtures straddle UTC so a regression in
-- either direction fails: a 20:00 New York event is Monday in UTC but Sunday
-- locally, and a 06:00 Tokyo event is Sunday in UTC but Monday locally. The
-- last case re-runs the west fixture under a non-UTC session timezone, because
-- the whole bug was that the derivation followed the caller's clock.

begin;
select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaaaaaa-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'byday@disc.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('cccccccc-0000-0000-0000-0000000000e1', 'aaaaaaaa-0000-0000-0000-0000000000e1',
        'Byday Disc Club', 'byday-disc', true);

-- West of UTC: 2099-01-05 01:00Z = 2099-01-04 20:00 America/New_York (Sunday).
-- East of UTC: 2099-01-04 21:00Z = 2099-01-05 06:00 Asia/Tokyo (Monday).
insert into events (id, club_id, author_id, title, category, discipline, starts_at, timezone)
values
  ('eeeeeeee-0000-0000-0000-0000000000b1', 'cccccccc-0000-0000-0000-0000000000e1',
   'aaaaaaaa-0000-0000-0000-0000000000e1', 'Sunday Evening NYC', 'run', null,
   timestamptz '2099-01-05 01:00:00+00', 'America/New_York'),
  ('eeeeeeee-0000-0000-0000-0000000000b2', 'cccccccc-0000-0000-0000-0000000000e1',
   'aaaaaaaa-0000-0000-0000-0000000000e1', 'Monday Morning Tokyo', 'run', null,
   timestamptz '2099-01-04 21:00:00+00', 'Asia/Tokyo');

set local role anon;

select is(
  (select count(*)::int from search_public_events(p_byday := 'SU')
     where id = 'eeeeeeee-0000-0000-0000-0000000000b1'),
  1, 'byday=SU matches a 20:00-local Sunday event west of UTC');

select is(
  (select count(*)::int from search_public_events(p_byday := 'MO')
     where id = 'eeeeeeee-0000-0000-0000-0000000000b1'),
  0, 'byday=MO excludes it — 01:00 Monday UTC is not its local weekday');

select is(
  (select count(*)::int from search_public_events(p_byday := 'MO')
     where id = 'eeeeeeee-0000-0000-0000-0000000000b2'),
  1, 'byday=MO matches a 06:00-local Monday event east of UTC');

select is(
  (select count(*)::int from search_public_events(p_byday := 'SU')
     where id = 'eeeeeeee-0000-0000-0000-0000000000b2'),
  0, 'byday=SU excludes it — 21:00 Sunday UTC is not its local weekday');

set local time zone 'Asia/Tokyo';

select is(
  (select count(*)::int from search_public_events(p_byday := 'SU')
     where id = 'eeeeeeee-0000-0000-0000-0000000000b1'),
  1, 'the weekday follows the event, not the caller''s session timezone');

select * from finish();
rollback;
