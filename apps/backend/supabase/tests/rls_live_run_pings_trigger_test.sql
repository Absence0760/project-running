-- Pin the `live_run_pings_drop_in_zone` BEFORE-INSERT trigger from
-- migration 20260618_001_clip_live_run_pings_to_privacy_zones.sql.
--
-- The live spectator surfaces (apps/web `/live/[id]` +
-- `apps/mobile_*/lib/screens/live_spectator_screen.dart`) render
-- realtime pings verbatim — they do NOT have the broadcaster's privacy
-- zones (fetching them client-side would defeat the point). The
-- trigger is therefore the single line of defence between a runner's
-- home/work coordinates and any anonymous spectator on a public live
-- run. If a future migration silently drops, weakens, or renames it,
-- those coordinates start streaming over Realtime.
--
-- This file pins:
--   1. The trigger exists with the expected name + table + timing.
--   2. The function it dispatches to is SECURITY DEFINER (it has to
--      cross the user_settings RLS gate to read the broadcaster's
--      zones).
--   3. Behaviour: with a zone configured, an in-zone ping is dropped;
--      an out-of-zone ping is stored.
--   4. Behaviour: a user without zones has every ping stored
--      (no-op fast-path).

begin;

select plan(7);

-- 1. Trigger exists at the expected name + table.
select has_trigger(
  'public', 'live_run_pings', 'live_run_pings_drop_in_zone_before_insert',
  'live_run_pings_drop_in_zone_before_insert trigger exists on public.live_run_pings'
);

-- 2. Trigger fires BEFORE INSERT (matters: AFTER would not be able to
--    suppress the row, and Realtime would see it).
select is(
  (select tgtype::int & 2 from pg_trigger
   where tgname = 'live_run_pings_drop_in_zone_before_insert'
     and tgrelid = 'public.live_run_pings'::regclass),
  2,
  'trigger fires BEFORE INSERT (tgtype bit 1 set)'
);

-- 3. Function is SECURITY DEFINER. Without this it can't read the
--    broadcaster's user_settings.prefs.privacy_zones (owner-only RLS).
select is(
  (select prosecdef from pg_proc
   where proname = 'live_run_pings_drop_in_zone'
     and pronamespace = 'public'::regnamespace),
  true,
  'live_run_pings_drop_in_zone is SECURITY DEFINER'
);

-- ── Fixtures: one user with zones, one without ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ddd01', 'authenticated', 'authenticated',
   'a@trig.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ddd02', 'authenticated', 'authenticated',
   'b@trig.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ddd01"}';

insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-0000000ddd01',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata, is_public)
values
  ('33333333-3333-3333-3333-333333333301',
   '00000000-0000-0000-0000-0000000ddd01',
   '2026-06-18 10:00:00+00', 1800, 5000, 'app',
   '{"activity_type":"run"}', true);

-- 4. In-zone ping is silently dropped — INSERT succeeds (no error)
--    but the row is not stored.
insert into live_run_pings (run_id, user_id, lat, lng)
values ('33333333-3333-3333-3333-333333333301',
        '00000000-0000-0000-0000-0000000ddd01', 47.37, 8.54);
select results_eq(
  $$ select count(*)::int from live_run_pings
     where run_id = '33333333-3333-3333-3333-333333333301'
       and lat = 47.37 and lng = 8.54 $$,
  $$ values (0) $$,
  'in-zone ping is silently dropped by the trigger (Realtime sees nothing)'
);

-- 5. Out-of-zone ping is stored.
insert into live_run_pings (run_id, user_id, lat, lng)
values ('33333333-3333-3333-3333-333333333301',
        '00000000-0000-0000-0000-0000000ddd01', 47.37, 8.5550);
select results_eq(
  $$ select count(*)::int from live_run_pings
     where run_id = '33333333-3333-3333-3333-333333333301'
       and lng = 8.5550 $$,
  $$ values (1) $$,
  'out-of-zone ping is stored normally'
);

-- ── User without zones: no-op fast-path ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ddd02"}';

insert into runs (id, user_id, started_at, duration_s, distance_m, source, metadata, is_public)
values
  ('33333333-3333-3333-3333-333333333302',
   '00000000-0000-0000-0000-0000000ddd02',
   '2026-06-18 11:00:00+00', 1800, 5000, 'app',
   '{"activity_type":"run"}', true);

-- 6. Pings from a user with no user_settings row are all stored
--    (fast-path: v_zones is null → return new).
insert into live_run_pings (run_id, user_id, lat, lng)
values ('33333333-3333-3333-3333-333333333302',
        '00000000-0000-0000-0000-0000000ddd02', 47.37, 8.54);
insert into live_run_pings (run_id, user_id, lat, lng)
values ('33333333-3333-3333-3333-333333333302',
        '00000000-0000-0000-0000-0000000ddd02', 47.38, 8.55);
select results_eq(
  $$ select count(*)::int from live_run_pings
     where run_id = '33333333-3333-3333-3333-333333333302' $$,
  $$ values (2) $$,
  'user without zones: all pings stored (no-op fast-path)'
);

-- 7. Empty zones array also fast-paths (v_zones is non-null but
--    jsonb_array_length = 0 → return new).
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-0000000ddd02',
  jsonb_build_object('privacy_zones', '[]'::jsonb)
);
insert into live_run_pings (run_id, user_id, lat, lng)
values ('33333333-3333-3333-3333-333333333302',
        '00000000-0000-0000-0000-0000000ddd02', 47.39, 8.56);
select results_eq(
  $$ select count(*)::int from live_run_pings
     where run_id = '33333333-3333-3333-3333-333333333302'
       and lng = 8.56 $$,
  $$ values (1) $$,
  'user with empty zones array: ping stored (fast-path on length=0)'
);

select * from finish();

rollback;
