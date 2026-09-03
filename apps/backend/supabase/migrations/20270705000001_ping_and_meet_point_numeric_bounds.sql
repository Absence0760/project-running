-- The two live-tracking ping tables carried no numeric bound of any kind, and
-- an anonymous spectator reads every column of them.
--
-- 20270704000002 closed every EXISTING numeric bound that admitted NaN. It says
-- nothing about a column that was never bounded, and 79 numeric columns in
-- `public` carry no CHECK at all — 31 of them in a type that can hold NaN. This
-- migration takes the eleven whose bad value is visible to someone other than
-- its author; the rest follow in 20270705000002 and 20270705000003.
--
-- ── Measured, not assumed ──────────────────────────────────────────────────
-- From an ordinary account's own session (`set local role authenticated` with
-- its own `request.jwt.claims`), against `live_run_pings_insert_self` as it
-- stands, one statement lands all of it:
--
--   insert into live_run_pings (run_id, user_id, lat, lng, ele, distance_m,
--                               elapsed_s, bpm)
--   values (<own run>, auth.uid(), 'NaN', 'Infinity', 'NaN', 'NaN', -5, -40);
--
-- and `set local role anon` then reads back `(NaN, Infinity, NaN, NaN, -5, -40)`
-- through `live_run_pings_visible_when_run_is`, because the run is public. The
-- write is not a privilege escalation — the runner owns the row — but the
-- READER is every spectator on `/live/[id]`, so a single bad client build (or a
-- deliberate one) breaks the map for an audience rather than for its author.
-- A NaN coordinate does not draw; an Infinity longitude fits the viewport to
-- the whole world. `live_freshness` and `live_motion` both consume the same
-- rows, and `motionFor`'s odometer delta off a NaN distance is NaN.
--
-- The PostGIS derivation already refused the value and said so — inserting the
-- row raises `NOTICE: Coordinate values were coerced into range [-180 -90, 180
-- 90] for GEOGRAPHY`. The geography point was clamped; the two float8 columns
-- the clients actually read kept the garbage. A notice is not a constraint.
--
-- ── The bounds, and why each is the shape it is ────────────────────────────
-- A TWO-SIDED bound excludes NaN and both infinities for free (`NaN <= 90` is
-- false), which is why `route_markers_lat_check` and `route_conditions_lat_check`
-- — the same question already answered twice in this schema — need no NaN term
-- and neither do these. The one-sided `>= 0` shape needs the explicit terms, so
-- the two distances carry them, matching `runs_distance_m_check`.
--
--   lat / lng      -90..90, -180..180. The domain, not a judgement.
--   ele            -500..9000 m. Below the Dead Sea shore (-430) and above
--                  Everest (8849); a wider bound would admit no real run.
--   distance_m     >= 0, explicitly not NaN and not Infinity. No ceiling: it is
--                  a float8 so `numeric(p,s)` cannot refuse an infinity for us,
--                  and a multi-day race has no defensible upper metre.
--   elapsed_s      >= 0. It is the runner's own recording timer.
--   bpm            0..300. 300 is past any measured human heart rate; 0 is
--                  admitted deliberately, because an off-wrist optical sensor
--                  reports it and refusing the row would drop the ping's
--                  POSITION over a heart rate nobody needs.
--
-- `events.meet_lat` / `meet_lng` join them for the same reason one table over:
-- the meeting point of a public club event is rendered to anyone who can see
-- the event, and `events` is small enough that the bound costs nothing.
--
-- ── Online safety (docs/backend/migration_locks.md) ────────────────────────
-- `live_run_pings` and `race_pings` are both in the playbook's high-volume set.
-- Each table's constraints are added in ONE `alter table`, so a table pays a
-- single brief ACCESS EXCLUSIVE for all of its columns rather than one per
-- column, and every add is `NOT VALID` — a metadata flip, no scan. Each
-- validation is a separate statement under SHARE UPDATE EXCLUSIVE, where
-- readers and writers proceed.
--
-- No repair pass, matching 20270704000001 / 20270704000002: a NaN coordinate
-- has no honest replacement. Run these before applying to a populated
-- instance — every one must return 0, or the matching VALIDATE fails:
--
--   select count(*) from live_run_pings
--    where lat not between -90 and 90 or lng not between -180 and 180
--       or (ele is not null and ele not between -500 and 9000)
--       or (distance_m is not null
--           and (distance_m < 0 or distance_m in ('NaN', 'Infinity')))
--       or (elapsed_s is not null and elapsed_s < 0)
--       or (bpm is not null and bpm not between 0 and 300);
--   select count(*) from race_pings
--    where lat not between -90 and 90 or lng not between -180 and 180
--       or (distance_m is not null
--           and (distance_m < 0 or distance_m in ('NaN', 'Infinity')))
--       or (elapsed_s is not null and elapsed_s < 0)
--       or (bpm is not null and bpm not between 0 and 300);
--   select count(*) from events
--    where (meet_lat is not null and meet_lat not between -90 and 90)
--       or (meet_lng is not null and meet_lng not between -180 and 180);
--
-- No column type, nullability or default moves, so neither row-type generator
-- has anything to regenerate.

alter table live_run_pings
  add constraint live_run_pings_lat_check
    check (lat >= -90 and lat <= 90) not valid,
  add constraint live_run_pings_lng_check
    check (lng >= -180 and lng <= 180) not valid,
  add constraint live_run_pings_ele_check
    check (ele is null or (ele >= -500 and ele <= 9000)) not valid,
  add constraint live_run_pings_distance_m_check
    check (distance_m is null
           or (distance_m >= 0
               and distance_m <> 'NaN'::float8
               and distance_m <> 'Infinity'::float8)) not valid,
  add constraint live_run_pings_elapsed_s_check
    check (elapsed_s is null or elapsed_s >= 0) not valid,
  add constraint live_run_pings_bpm_check
    check (bpm is null or (bpm >= 0 and bpm <= 300)) not valid;

alter table live_run_pings validate constraint live_run_pings_lat_check;
alter table live_run_pings validate constraint live_run_pings_lng_check;
alter table live_run_pings validate constraint live_run_pings_ele_check;
alter table live_run_pings validate constraint live_run_pings_distance_m_check;
alter table live_run_pings validate constraint live_run_pings_elapsed_s_check;
alter table live_run_pings validate constraint live_run_pings_bpm_check;

alter table race_pings
  add constraint race_pings_lat_check
    check (lat >= -90 and lat <= 90) not valid,
  add constraint race_pings_lng_check
    check (lng >= -180 and lng <= 180) not valid,
  add constraint race_pings_distance_m_check
    check (distance_m is null
           or (distance_m >= 0
               and distance_m <> 'NaN'::float8
               and distance_m <> 'Infinity'::float8)) not valid,
  add constraint race_pings_elapsed_s_check
    check (elapsed_s is null or elapsed_s >= 0) not valid,
  add constraint race_pings_bpm_check
    check (bpm is null or (bpm >= 0 and bpm <= 300)) not valid;

alter table race_pings validate constraint race_pings_lat_check;
alter table race_pings validate constraint race_pings_lng_check;
alter table race_pings validate constraint race_pings_distance_m_check;
alter table race_pings validate constraint race_pings_elapsed_s_check;
alter table race_pings validate constraint race_pings_bpm_check;

alter table events
  add constraint events_meet_lat_check
    check (meet_lat is null or (meet_lat >= -90 and meet_lat <= 90)) not valid,
  add constraint events_meet_lng_check
    check (meet_lng is null or (meet_lng >= -180 and meet_lng <= 180)) not valid;

alter table events validate constraint events_meet_lat_check;
alter table events validate constraint events_meet_lng_check;
