-- Pin the `race_pings_drop_in_zone` BEFORE-INSERT trigger from
-- migration 20260704_001_clip_race_pings_to_privacy_zones.sql, as
-- amended by 20270309_001_race_pings_coarse_carveout.sql.
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
-- The privacy-vs-safety carve-out (20270309_001): an in-zone ping is no
-- longer dropped outright. The precise lat/lng is never stored, but the
-- SINGLE most-recent in-zone ping per runner-per-race-instance is
-- RETAINED coarsened to a ~2-dp (~1.1 km) grid and flagged
-- `coarse = true`, so a runner who collapses inside their own zone still
-- leaves a last-seen cell on the leaderboard for a race director / SAR
-- without broadcasting their exact home point.
--
-- This file pins:
--   1. The trigger exists with the expected name + table + timing.
--   2. The function is SECURITY DEFINER (it has to cross the
--      user_settings RLS gate to read the broadcaster's zones).
--   3. Behaviour (carve-out): an in-zone ping never stores its precise
--      coordinates, but a single coarse `coarse = true` last-seen point
--      is retained and advances to the newest in-zone stop; an
--      out-of-zone ping is stored precise + uncoarsened.
--   4. Behaviour: a user without zones has every ping stored
--      (no-op fast-path).

begin;

select plan(9);

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

insert into events (id, club_id, title, starts_at, author_id)
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

-- 4a. In-zone ping: the PRECISE coordinates are never stored. The ping
--     lands at (47.3707, 8.5409) — ~103 m from the zone centre (47.37,
--     8.54), inside the 150 m radius — and the carve-out coarsens it
--     before insert, so the exact point must not survive on the feed.
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values ('44444444-4444-4444-4444-444444444402',
        '2026-07-04 10:00:00+00',
        '00000000-0000-0000-0000-0000000eee02',
        now(), 47.3707, 8.5409);
select results_eq(
  $$ select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000eee02'
       and lat = 47.3707 and lng = 8.5409 $$,
  $$ values (0) $$,
  'in-zone race ping never stores its precise coordinates (spectator feed sees no exact point)'
);

-- 4b. A single coarse last-seen IS retained, rounded to ~2-dp (47.37,
--     8.54) and flagged coarse = true — the safety last-seen cell.
select results_eq(
  $$ select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000eee02'
       and coarse = true and lat = 47.37 and lng = 8.54 $$,
  $$ values (1) $$,
  'in-zone race ping retained as a single coarse (~2-dp) last-seen point'
);

-- 4c. A second in-zone ping advances the last-seen point but does NOT
--     accumulate — at most one coarse row per runner-per-race-instance.
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values ('44444444-4444-4444-4444-444444444402',
        '2026-07-04 10:00:00+00',
        '00000000-0000-0000-0000-0000000eee02',
        now(), 47.3694, 8.5413);
select results_eq(
  $$ select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000eee02'
       and coarse = true $$,
  $$ values (1) $$,
  'a later in-zone race ping replaces the prior coarse last-seen (at most one per runner)'
);

-- 5. Out-of-zone ping is stored precise + uncoarsened.
insert into race_pings (event_id, instance_start, user_id, at, lat, lng)
values ('44444444-4444-4444-4444-444444444402',
        '2026-07-04 10:00:00+00',
        '00000000-0000-0000-0000-0000000eee02',
        now(), 47.37, 8.5550);
select results_eq(
  $$ select count(*)::int from race_pings
     where user_id = '00000000-0000-0000-0000-0000000eee02'
       and lng = 8.5550 and coarse = false $$,
  $$ values (1) $$,
  'out-of-zone race ping is stored normally (precise, not coarsened)'
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
