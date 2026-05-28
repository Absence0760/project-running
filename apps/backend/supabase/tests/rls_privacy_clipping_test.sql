-- pgtap suite for the privacy-zone clipping primitives:
--
--   - clip_track_for_user(target_user_id, points jsonb) → jsonb
--     SECURITY DEFINER. Reads the target user's zones from their
--     user_settings.prefs.privacy_zones jsonb (which IS owner-only
--     under RLS — see rls_user_settings_test) and returns the
--     clipped points. Zones never leave the database.
--   - privacy_in_any_zone(lat, lng, zones_json) → boolean
--   - privacy_distance_m(lat1, lng1, lat2, lng2) → float (PostGIS)
--
-- A regression in clip_track_for_user is a doxxing vector — every
-- public run + share-link would expose the runner's home address.
-- See decisions §33 for the threat model.

begin;

select plan(19);

-- ── Fixture: one user with privacy zones, one user without ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000c101', 'authenticated', 'authenticated',
   'a@clip.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000c102', 'authenticated', 'authenticated',
   'b@clip.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c101"}';

-- User A's privacy zone: ~150 m radius around (47.37, 8.54). Tight
-- enough that points 200 m east are out of zone.
insert into user_settings (user_id, prefs)
values (
  '00000000-0000-0000-0000-00000000c101',
  jsonb_build_object(
    'privacy_zones', jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150)
    )
  )
);

-- User B has no zone configured (no user_settings row).

-- ── privacy_distance_m + privacy_in_any_zone (helper internals) ──
-- These helpers are no longer granted to anon / authenticated
-- (migration 20260711_001 — the only legitimate caller is
-- clip_track_for_user, which runs SECURITY DEFINER). Tests of the
-- pure-math behaviour run as the test runner (postgres) so they can
-- still validate correctness without re-granting the helpers.
reset role;

-- 1. Same point → ~0 m.
select cmp_ok(
  privacy_distance_m(47.37, 8.54, 47.37, 8.54)::numeric,
  '<', 1::numeric,
  'privacy_distance_m on identical points is < 1 m'
);

-- 2. ~1 km separation. metrePerDegLng at 47.37° ≈ 75356; 0.01° east ≈ 754 m.
select cmp_ok(
  privacy_distance_m(47.37, 8.54, 47.37, 8.55)::numeric,
  '>', 700::numeric,
  'privacy_distance_m on 0.01° east is > 700 m'
);
select cmp_ok(
  privacy_distance_m(47.37, 8.54, 47.37, 8.55)::numeric,
  '<', 800::numeric,
  'privacy_distance_m on 0.01° east is < 800 m'
);

-- ── privacy_in_any_zone ──
-- 3. Centre of the zone is in.
select is(
  privacy_in_any_zone(47.37, 8.54,
    '[{"lat":47.37,"lng":8.54,"radius_m":150}]'::jsonb),
  true,
  'privacy_in_any_zone is true at the zone centre'
);

-- 4. 1 km away is NOT in zone.
select is(
  privacy_in_any_zone(47.37, 8.55,
    '[{"lat":47.37,"lng":8.54,"radius_m":150}]'::jsonb),
  false,
  'privacy_in_any_zone is false 1 km from the zone centre'
);

-- 5. Empty / null zones array → false (no zones, nothing in any).
select is(
  privacy_in_any_zone(47.37, 8.54, '[]'::jsonb),
  false,
  'privacy_in_any_zone with empty zones returns false'
);
select is(
  privacy_in_any_zone(47.37, 8.54, null::jsonb),
  false,
  'privacy_in_any_zone with null zones returns false'
);

-- Re-enter the authenticated context for clip_track_for_user calls.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000c101"}';

-- ── clip_track_for_user ──
-- 6. User without zones → input returned unchanged.
select results_eq(
  $$ select clip_track_for_user(
       '00000000-0000-0000-0000-00000000c102',
       '[{"lat":47.37,"lng":8.54},{"lat":47.37,"lng":8.55}]'::jsonb) $$,
  $$ values ('[{"lat":47.37,"lng":8.54},{"lat":47.37,"lng":8.55}]'::jsonb) $$,
  'clip for a user with no zones returns input unchanged'
);

-- 7. Empty array → empty array.
select is(
  clip_track_for_user('00000000-0000-0000-0000-00000000c101', '[]'::jsonb),
  '[]'::jsonb,
  'clip on an empty input array returns []'
);

-- 8. Null / non-array input → empty array (defensive shape).
select is(
  clip_track_for_user('00000000-0000-0000-0000-00000000c101', null::jsonb),
  '[]'::jsonb,
  'clip on null input returns []'
);
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000c101',
    '{"not":"an array"}'::jsonb),
  '[]'::jsonb,
  'clip on non-array input returns []'
);

-- 9. The CRITICAL test: leading + trailing in-zone points are dropped,
--    out-of-zone middle is preserved. Zone is at (47.37, 8.54). We
--    feed: [in_zone, out_of_zone, out_of_zone, in_zone] and expect
--    only the two middle points back.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000c101',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37,    'lng', 8.5400),  -- in zone
      jsonb_build_object('lat', 47.37,    'lng', 8.5550),  -- 1.1 km east, out
      jsonb_build_object('lat', 47.37,    'lng', 8.5600),  -- 1.5 km east, out
      jsonb_build_object('lat', 47.37005, 'lng', 8.5402)   -- back near home, in zone
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5550),
    jsonb_build_object('lat', 47.37, 'lng', 8.5600)
  ),
  'clip drops leading + trailing in-zone points'
);

-- 10. Mid-track in-zone points (a loop home) are PRESERVED — the clipper
--     only walks from each end, it doesn't punch holes in the middle.
--     This is the "casual privacy" call from §33: protect the
--     start/end address, accept that a loop-home shape leaks.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000c101',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37,    'lng', 8.5400),  -- in zone, leading → drop
      jsonb_build_object('lat', 47.37,    'lng', 8.5550),  -- out
      jsonb_build_object('lat', 47.37005, 'lng', 8.5401),  -- in zone, mid → KEEP
      jsonb_build_object('lat', 47.37,    'lng', 8.5550),  -- out
      jsonb_build_object('lat', 47.37,    'lng', 8.5402)   -- in zone, trailing → drop
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37,    'lng', 8.5550),
    jsonb_build_object('lat', 47.37005, 'lng', 8.5401),
    jsonb_build_object('lat', 47.37,    'lng', 8.5550)
  ),
  'clip preserves mid-track in-zone points (loop-home pattern)'
);

-- 11. Track that's entirely in-zone collapses to empty (the clipper
--     walks from both ends and meets in the middle).
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000c101',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37,    'lng', 8.5400),
      jsonb_build_object('lat', 47.37005, 'lng', 8.5401),
      jsonb_build_object('lat', 47.37,    'lng', 8.5402)
    )
  ),
  '[]'::jsonb,
  'clip on an entirely-in-zone track returns []'
);

-- 12. Track that never touches the zone is returned unchanged.
select is(
  clip_track_for_user(
    '00000000-0000-0000-0000-00000000c101',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5550),
      jsonb_build_object('lat', 47.37, 'lng', 8.5600)
    )
  ),
  jsonb_build_array(
    jsonb_build_object('lat', 47.37, 'lng', 8.5550),
    jsonb_build_object('lat', 47.37, 'lng', 8.5600)
  ),
  'clip on a track that never touches the zone returns input unchanged'
);

-- 13. Persona-hunt Round 3 finding Ultra #5: oversize inputs no
--     longer raise. The clipper now downsamples > 50k inputs via
--     even-stride sampling (preserving endpoints) and then runs
--     the zone-clip pass over the downsampled array. Asserts the
--     call succeeds (no exception) on a 60001-point input.
do $$
declare
  big jsonb;
  out_count int;
begin
  select jsonb_agg(jsonb_build_object('lat', 47.37, 'lng', 8.5550))
    into big
    from generate_series(1, 60001);
  -- A bare call that doesn't raise — the actual count assertion
  -- happens in the next pgtap test below.
  perform clip_track_for_user('00000000-0000-0000-0000-00000000c101', big);
end;
$$;
select pass('clip_track_for_user no longer rejects > 50000-point input — it downsamples');

-- 14. Downsampled output is bounded at ≤ ~50k points. The +1
--     headroom accounts for the explicit "pin the last element"
--     branch when stride doesn't land on (len - 1).
select cmp_ok(
  (
    select jsonb_array_length(
      clip_track_for_user(
        '00000000-0000-0000-0000-00000000c101',
        (select jsonb_agg(jsonb_build_object('lat', 47.37, 'lng', 8.5550))
           from generate_series(1, 60001))
      )
    )
  ),
  '<=', 50001,
  'clip_track_for_user output is ≤ 50001 points for a 60001-point input'
);

-- 15. Endpoint preservation — the persona's stated correctness
--     criterion. After downsampling, the first and last samples of
--     the OUT-OF-ZONE input must still appear in the output. We
--     build an input where positions 0 and N-1 are uniquely
--     identifiable (slightly different lng) so we can assert their
--     survival without ambiguity.
do $$
declare
  big jsonb;
  out_arr jsonb;
  first_in jsonb;
  last_in jsonb;
  first_out jsonb;
  last_out jsonb;
begin
  -- Build a 60001-element array of out-of-zone points where each
  -- carries an ordinal so we can spot the endpoints.
  select jsonb_agg(
    jsonb_build_object(
      'lat', 47.37,
      'lng', 8.55 + (i::float / 60001) * 0.01
    ) order by i
  ) into big
  from generate_series(0, 60000) as i;

  first_in := big -> 0;
  last_in := big -> 60000;
  out_arr := clip_track_for_user('00000000-0000-0000-0000-00000000c101', big);
  first_out := out_arr -> 0;
  last_out := out_arr -> (jsonb_array_length(out_arr) - 1);

  if first_in is distinct from first_out then
    raise exception 'first endpoint changed: in=% out=%', first_in, first_out;
  end if;
  if last_in is distinct from last_out then
    raise exception 'last endpoint changed: in=% out=%', last_in, last_out;
  end if;
end;
$$;
select pass('clip_track_for_user preserves first + last endpoints when downsampling');

-- 14. The most important wire-leak guard: the SECURITY DEFINER context
--     bypasses RLS on user_settings to read zones. Verify that zones
--     themselves never appear in the function's output. The output is
--     a plain jsonb array of {lat, lng} — never an object containing
--     'privacy_zones' or 'radius_m'.
select is(
  (clip_track_for_user(
    '00000000-0000-0000-0000-00000000c101',
    jsonb_build_array(
      jsonb_build_object('lat', 47.37, 'lng', 8.5550)
    )
  )::text ~ '(radius_m|privacy_zones)'),
  false,
  'clip_track_for_user output never leaks zone metadata'
);

select * from finish();

rollback;
