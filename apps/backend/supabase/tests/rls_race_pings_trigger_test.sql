-- Pin the `race_pings_drop_in_zone` BEFORE-INSERT trigger from
-- migration 20260704_001_clip_race_pings_to_privacy_zones.sql.
--
-- The race spectator surfaces (`apps/web/src/routes/live/event/[id]/[instance]/+page.svelte`
-- + the mobile `race_controller.dart` ping client) render `race_pings`
-- verbatim — they do NOT have the broadcaster's privacy zones
-- (fetching them client-side would defeat the point). This trigger
-- is therefore the single line of defence between a runner's
-- home/work coordinates and any anonymous spectator on a public-club
-- race. If a future migration silently drops, weakens, or renames
-- it, those coordinates start streaming over the leaderboard /
-- spectator feed.
--
-- This file pins:
--   1. The trigger exists with the expected name + table + timing.
--   2. The function is SECURITY DEFINER (it has to cross the
--      user_settings RLS gate to read the broadcaster's zones).
--   3. Behaviour: with a zone configured, an in-zone ping is dropped;
--      an out-of-zone ping is stored.
--   4. Behaviour: a user without zones has every ping stored
--      (no-op fast-path).

begin;

select plan(7);

-- 1. Trigger exists at the expected name + table.
select has_trigger(
  'public', 'race_pings', 'race_pings_drop_in_zone_before_insert',
  'race_pings_drop_in_zone_before_insert trigger exists on public.race_pings'
);

-- 2. Trigger fires BEFORE INSERT.
select is(
  (select tgtype::int & 2 from pg_trigger
   where tgname = 'race_pings_drop_in_zone_before_insert'
     and tgrelid = 'public.race_pings'::regclass),
  2,
  'race trigger fires BEFORE INSERT (tgtype bit 1 set)'
);

-- 3. Function is SECURITY DEFINER.
select is(
  (select prosecdef from pg_proc
   where proname = 'race_pings_drop_in_zone'
     and pronamespace = 'public'::regnamespace),
  true,
  'race_pings_drop_in_zone is SECURITY DEFINER'
);

-- ── Fixtures: club admin + race participant ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000eee01', 'authenticated', 'authenticated',
   'admin@racetrig.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000eee02', 'authenticated', 'authenticated',
   'runner@racetrig.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000eee01"}';

-- Public-club fixtures the race-trigger test depends on.
insert into clubs (id, owner_id, name, slug, is_public)
values ('44444444-4444-4444-4444-444444444401',
        '00000000-0000-0000-0000-0000000eee01',
        'Race Trigger Test Club', 'race-trig-test', true);

insert into events (id, club_id, title, starts_at, created_by)
values ('44444444-4444-4444-4444-444444444402',
        '44444444-4444-4444-4444-444444444401',
        'Race Trigger Test', now(),
        '00000000-0000-0000-0000-0000000eee01');

insert into race_sessions (event_id, instance_start, status, started_at)
values ('44444444-4444-4444-4444-444444444402',
        '2026-07-04 10:00:00+00', 'running', now());

-- Participant has a privacy zone configured.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000eee02"}';
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-0000000eee02',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

-- 4. In-zone ping is silently dropped.
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values ('44444444-4444-4444-4444-444444444402',
        '2026-07-04 10:00:00+00',
        '00000000-0000-0000-0000-0000000eee02',
        now(), 47.37, 8.54);
select results_eq(
  $$ select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000eee02'
       and lat = 47.37 and lng = 8.54 $$,
  $$ values (0) $$,
  'in-zone race ping is silently dropped (spectator feed sees nothing)'
);

-- 5. Out-of-zone ping is stored.
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values ('44444444-4444-4444-4444-444444444402',
        '2026-07-04 10:00:00+00',
        '00000000-0000-0000-0000-0000000eee02',
        now(), 47.37, 8.5550);
select results_eq(
  $$ select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000eee02'
       and lng = 8.5550 $$,
  $$ values (1) $$,
  'out-of-zone race ping is stored normally'
);

-- ── Admin (no privacy zone) ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000eee01"}';

-- 6. Admin without zones: all pings stored (no-op fast-path).
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values ('44444444-4444-4444-4444-444444444402',
        '2026-07-04 10:00:00+00',
        '00000000-0000-0000-0000-0000000eee01',
        now(), 47.37, 8.54);
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values ('44444444-4444-4444-4444-444444444402',
        '2026-07-04 10:00:00+00',
        '00000000-0000-0000-0000-0000000eee01',
        now(), 47.38, 8.55);
select results_eq(
  $$ select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000eee01' $$,
  $$ values (2) $$,
  'user without zones: all race pings stored (no-op fast-path)'
);

-- 7. Empty zones array also fast-paths.
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-0000000eee01',
  jsonb_build_object('privacy_zones', '[]'::jsonb)
);
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values ('44444444-4444-4444-4444-444444444402',
        '2026-07-04 10:00:00+00',
        '00000000-0000-0000-0000-0000000eee01',
        now(), 47.39, 8.56);
select results_eq(
  $$ select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000eee01'
       and lng = 8.56 $$,
  $$ values (1) $$,
  'user with empty zones array: race ping stored (fast-path on length=0)'
);

select * from finish();

rollback;
