-- What `public_runs` projects, and the two columns it projects CONDITIONALLY.
--
-- The view is re-emitted in full on every strip migration — twice in two days
-- during the #789 round (20270627000001, 20270628000001) — and each header
-- says only "same column list as the previous". Nothing measured that claim.
-- `rls_public_runs_view_no_track_url_test` pins two column NAMES,
-- `rls_public_runs_view_denylist_test` pins the metadata denylist, and
-- `check_shared_constants.mjs` reads that same denylist out of the migration
-- text — so a re-emit that added `notes`, `title`, `external_id`, `gear_id` or
-- restored the raw `route_id` was caught for exactly two names out of the
-- table.
--
-- The two CASE columns are the sharper half. `route_id` and `event_id` are
-- wrapped in `is_public_route_by_id` / `is_public_event_by_id` so a private
-- route or a private club's event id does not ride out on an anonymously
-- readable run row. seed.sql's own comment block claims to check the event
-- one and does not; `public_helpers_shadow_hidden_test` exercises both helpers
-- as bare functions, never through the view, so dropping the wrapper and
-- selecting `r.event_id` raw passes every shipped assertion.
--
-- Each conditional column is measured on ONE run row, moved between a public
-- and a private anchor, so the null is a withholding rather than a row that
-- never carried the link.

begin;

select plan(8);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('9c000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
        'pv-runner@view.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('9c000000-0000-0000-0000-0000000000a1', 'Runner') on conflict (id) do nothing;

-- A public club and a private one, each with a public event.
insert into clubs (id, owner_id, name, slug, is_public) values
  ('9c000000-0000-0000-0000-0000000000c1', '9c000000-0000-0000-0000-0000000000a1',
   'Open Club', 'pv-open-club', true),
  ('9c000000-0000-0000-0000-0000000000c2', '9c000000-0000-0000-0000-0000000000a1',
   'Closed Club', 'pv-closed-club', false);

insert into events (id, club_id, title, starts_at, author_id, is_public) values
  ('9c000000-0000-0000-0000-0000000000e1', '9c000000-0000-0000-0000-0000000000c1',
   'Open Run', '2027-04-01 09:00+00', '9c000000-0000-0000-0000-0000000000a1', true),
  ('9c000000-0000-0000-0000-0000000000e2', '9c000000-0000-0000-0000-0000000000c2',
   'Members Only', '2027-04-02 09:00+00', '9c000000-0000-0000-0000-0000000000a1', true);

insert into routes (id, user_id, name, waypoints, distance_m, is_public) values
  ('9c000000-0000-0000-0000-0000000000f1', '9c000000-0000-0000-0000-0000000000a1', 'Open Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]', 5000, true),
  ('9c000000-0000-0000-0000-0000000000f2', '9c000000-0000-0000-0000-0000000000a1', 'Private Loop',
   '[{"lat":47.39,"lng":8.56},{"lat":47.40,"lng":8.57}]', 5000, false);

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public,
                  route_id, event_id, metadata)
values ('9c000000-0000-0000-0000-0000000000b1', '9c000000-0000-0000-0000-0000000000a1',
        now(), 5000, 1500, 'app', true,
        '9c000000-0000-0000-0000-0000000000f1', '9c000000-0000-0000-0000-0000000000e1',
        '{"activity_type":"run"}');

set local role anon;

-- (1) The projection, exactly. `columns_are` fails on a missing column as well
-- as an added one, so this is its own positive control: the public-safe
-- columns are asserted present in the same breath as the private ones absent.
select columns_are('public', 'public_runs', array[
  'id', 'user_id', 'started_at', 'duration_s', 'distance_m', 'elevation_gain_m',
  'source', 'activity_type', 'is_dnf', 'is_public', 'created_at', 'route_id',
  'event_id', 'race_listing_id', 'has_track', 'fastest_5k_s', 'fastest_10k_s',
  'fastest_half_marathon_s', 'fastest_marathon_s', 'metadata', 'concluded_at'],
  'public_runs projects exactly the audited column set — a re-emit that carries a new base column through fails here');

-- (2) The run is visible at all. Every null below is measured on THIS row, so
-- a row the view never returned would make all of them vacuous.
select is(
  (select count(*)::int from public_runs where id = '9c000000-0000-0000-0000-0000000000b1'),
  1,
  'the fixture run is readable through public_runs by an anonymous caller');

-- (3) + (4) route_id: a public route's id comes through, a private one's does not.
select is(
  (select route_id from public_runs where id = '9c000000-0000-0000-0000-0000000000b1'),
  '9c000000-0000-0000-0000-0000000000f1'::uuid,
  'public_runs exposes route_id when the route is public');

select is(
  (select event_id from public_runs where id = '9c000000-0000-0000-0000-0000000000b1'),
  '9c000000-0000-0000-0000-0000000000e1'::uuid,
  'public_runs exposes event_id when the joined events club is public');

reset role;
update runs set route_id = '9c000000-0000-0000-0000-0000000000f2',
                event_id = '9c000000-0000-0000-0000-0000000000e2'
 where id = '9c000000-0000-0000-0000-0000000000b1';
set local role anon;

select is(
  (select route_id from public_runs where id = '9c000000-0000-0000-0000-0000000000b1'),
  null::uuid,
  'public_runs nulls route_id when the route is private — the same row that just carried a public one');

select is(
  (select event_id from public_runs where id = '9c000000-0000-0000-0000-0000000000b1'),
  null::uuid,
  'public_runs nulls event_id when the joined events club is private');

-- (5) The shadow-hidden branch of each helper, which is the half a re-emit
-- naming the older `is_route_visible_to` would silently drop.
reset role;
update routes set is_public = true, shadow_hidden = true
 where id = '9c000000-0000-0000-0000-0000000000f2';
update clubs set is_public = true, shadow_hidden = true
 where id = '9c000000-0000-0000-0000-0000000000c2';
set local role anon;

select is(
  (select route_id from public_runs where id = '9c000000-0000-0000-0000-0000000000b1'),
  null::uuid,
  'a shadow-hidden route is not public for this purpose either, though its is_public flag now says true');

select is(
  (select event_id from public_runs where id = '9c000000-0000-0000-0000-0000000000b1'),
  null::uuid,
  'nor is an event whose club is shadow-hidden');

select * from finish();

rollback;
