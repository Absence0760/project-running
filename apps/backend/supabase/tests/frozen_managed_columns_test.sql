-- The moderation bit, the verified badge, the curation flags, the four derived
-- caches and the three privacy-clipped geometries, each asserted against the
-- write that reached it (migration 20270704000003).
--
-- Every case runs from an ordinary `authenticated` session under the row
-- owner's own JWT — the only privilege any of these exploits needed. Each was
-- measured against the schema before the migration and is written the way it
-- was measured: perform the write the way a client would, then read the column
-- back as a privileged session, because most of these columns are not readable
-- by the client that wrote them.
--
-- The guard DISCARDS rather than refuses, which is why every assertion here is
-- a value comparison rather than a `throws_ok`. That is deliberate on the
-- moderation bit: a 42501 would tell a shadow-hidden account that it is hidden,
-- which is the one thing a shadow hide must not do. It also keeps a caller that
-- hands the table a whole row it read back earlier — `backup.dart`'s restore
-- upserts a `select()`ed route verbatim — working instead of failing every row.
--
-- The half that is easy to get wrong is the OTHER direction, so it is asserted
-- too: the legitimate writers are all SECURITY DEFINER functions called BY an
-- ordinary user's session, so a guard keyed on the JWT role or on
-- `current_setting('role')` would block the moderator while looking correct in
-- every test above. `admin_unhide_target` is exercised here for that reason.

begin;

select plan(16);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('f0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'frozen@spam.local', '', now(), now()),
       ('f0000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
        'frozen-admin@spam.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('f0000000-0000-0000-0000-000000000001', 'Frozen'),
       ('f0000000-0000-0000-0000-000000000002', 'Frozen Admin')
on conflict (id) do nothing;

select tests.confirm_consent();

-- The route fixture needs a privacy zone over its head, or `geom_public` is
-- the same line as `geom` and assertion 13 could not tell an unclipped forge
-- from an honest clip that had nothing to remove.
insert into user_settings (user_id, prefs)
values ('f0000000-0000-0000-0000-000000000001',
        jsonb_build_object('privacy_zones', jsonb_build_array(
          jsonb_build_object('lat', 51.5, 'lng', -0.1, 'radius_m', 200))))
on conflict (user_id) do update set prefs = excluded.prefs;

insert into app_admins (user_id)
values ('f0000000-0000-0000-0000-000000000002')
on conflict do nothing;

-- ── the fixtures, built the way a client builds them ────────────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';

insert into clubs (id, owner_id, name, slug, is_public, is_verified, member_count, shadow_hidden)
values ('f0000000-0000-0000-0000-0000000000c1', 'f0000000-0000-0000-0000-000000000001',
        'Frozen Club', 'frozen-club-spam', true, true, 999999, true);

insert into routes (id, user_id, name, waypoints, distance_m, surface, is_public,
                    is_featured, featured_at, run_count, shadow_hidden)
values ('f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-000000000001',
        'Frozen Route',
        '[{"lat":51.5,"lng":-0.1},{"lat":51.51,"lng":-0.11}]'::jsonb,
        5000, 'road', true, true, now(), 4242, true);

insert into gym_workouts (id, user_id, started_at, set_count, volume_kg)
values ('f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-000000000001',
        now(), 999, 999999);

insert into challenges (id, creator_id, title, metric, scope, goal_value,
                        starts_at, ends_at, is_public, participant_count)
values ('f0000000-0000-0000-0000-0000000000f1', 'f0000000-0000-0000-0000-000000000001',
        'Frozen Challenge', 'distance', 'individual', 100000,
        now() - interval '1 day', now() + interval '30 days', true, 999999);

reset role;

-- ── INSERT: the forged value never lands ────────────────────────────────────
select is(
  (select is_verified from clubs where id = 'f0000000-0000-0000-0000-0000000000c1'),
  false,
  'a club created with is_verified => true is not verified — the pre-existing '
  'trigger was BEFORE UPDATE only, so INSERT was the way in'
);
select is(
  (select member_count from clubs where id = 'f0000000-0000-0000-0000-0000000000c1'),
  1,
  'member_count is the authoritative active-member count, not the 999999 asked for'
);
select is(
  (select shadow_hidden from clubs where id = 'f0000000-0000-0000-0000-0000000000c1'),
  false,
  'a club cannot be created pre-cleared of a moderation hide'
);
select is(
  (select is_featured from routes where id = 'f0000000-0000-0000-0000-0000000000d1'),
  false,
  'a route created is_featured is not in the admin-curated lens'
);
select is(
  (select featured_at from routes where id = 'f0000000-0000-0000-0000-0000000000d1'),
  null::timestamptz,
  'and carries no curation stamp'
);
select is(
  (select run_count from routes where id = 'f0000000-0000-0000-0000-0000000000d1'),
  0,
  'run_count is the cache, not the 4242 asked for — the popular discover lens '
  'gates on run_count > 0'
);
select is(
  (select set_count from gym_workouts where id = 'f0000000-0000-0000-0000-0000000000e1'),
  0,
  'set_count is the derived cache over gym_sets, not a client-declared number'
);
select is(
  (select participant_count from challenges where id = 'f0000000-0000-0000-0000-0000000000f1'),
  0,
  'participant_count is the derived cache, and the browse feed ranks on it'
);

-- ── the derivation still runs, so freezing did not break it ────────────────
-- The freeze trigger sorts ahead of routes_geom_trigger by name, so on INSERT
-- it nulls a client-supplied geometry and the derivation then computes the
-- real one. A guard that ran after would leave the route with no line at all.
select isnt(
  (select geom from routes where id = 'f0000000-0000-0000-0000-0000000000d1'),
  null,
  'the route still has its derived geometry — the freeze runs before the '
  'derivation, not instead of it'
);

-- ── UPDATE: the moderation hide holds ───────────────────────────────────────
update user_profiles set shadow_hidden = true
 where id = 'f0000000-0000-0000-0000-000000000001';
update clubs set shadow_hidden = true
 where id = 'f0000000-0000-0000-0000-0000000000c1';
update routes set shadow_hidden = true
 where id = 'f0000000-0000-0000-0000-0000000000d1';

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';
update user_profiles set shadow_hidden = false
 where id = 'f0000000-0000-0000-0000-000000000001';
update clubs set shadow_hidden = false
 where id = 'f0000000-0000-0000-0000-0000000000c1';
update routes set shadow_hidden = false
 where id = 'f0000000-0000-0000-0000-0000000000d1';
update routes set geom_public = geom
 where id = 'f0000000-0000-0000-0000-0000000000d1';
reset role;

select is(
  (select shadow_hidden from user_profiles where id = 'f0000000-0000-0000-0000-000000000001'),
  true,
  'a hidden account cannot unhide itself'
);
select is(
  (select shadow_hidden from clubs where id = 'f0000000-0000-0000-0000-0000000000c1'),
  true,
  'a hidden club cannot be unhidden by its owner'
);
select is(
  (select shadow_hidden from routes where id = 'f0000000-0000-0000-0000-0000000000d1'),
  true,
  'a hidden route cannot be unhidden by its author'
);
-- The positive control: this route's own clip really does remove something,
-- so the inequality below is a refusal rather than a zone that had nothing to
-- take off.
select isnt(
  (select geom_public from routes where id = 'f0000000-0000-0000-0000-0000000000d1'),
  (select geom from routes where id = 'f0000000-0000-0000-0000-0000000000d1'),
  'the privacy-clipped public geometry cannot be overwritten with the raw line, '
  'which anon routes_within_box runs its ST_Intersects against'
);

-- ── DELETE + re-INSERT, the decisions.md 584 round trip ─────────────────────
-- user_profiles is the one table on this list where the client also holds
-- DELETE, so a guard on UPDATE alone would have been reachable in two
-- statements.
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}';
delete from user_profiles where id = 'f0000000-0000-0000-0000-000000000001';
insert into user_profiles (id, display_name, shadow_hidden)
values ('f0000000-0000-0000-0000-000000000001', 'Frozen again', false);
reset role;

select is(
  (select shadow_hidden from user_profiles where id = 'f0000000-0000-0000-0000-000000000001'),
  false,
  'the re-inserted profile is not hidden — a fresh row is not a hidden row, and '
  'this is the residual the moderator has to re-apply'
);

-- ── the machinery is NOT locked out ─────────────────────────────────────────
-- The whole hazard of this guard is over-reach. admin_unhide_target is
-- SECURITY DEFINER and is called BY an ordinary user's session, so its JWT role
-- claim and its `current_setting('role')` both read `authenticated` — the two
-- signals the schema's other column locks key on would each block the
-- moderator here while every assertion above still passed.
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"f0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select ok(
  admin_unhide_target('club', 'f0000000-0000-0000-0000-0000000000c1'),
  'an admin can still unhide through admin_unhide_target'
);
reset role;

select is(
  (select shadow_hidden from clubs where id = 'f0000000-0000-0000-0000-0000000000c1'),
  false,
  'and the club really is unhidden — the guard reads current_user, which '
  'follows the definer switch, not the JWT role, which does not'
);

select * from finish();
rollback;
