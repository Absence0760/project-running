#!/usr/bin/env node
// Permissive replacements for the relations that filter in their OWN SQL.
//
// The sibling guard's first operator widens row-level security for the span of
// one assertion. That reaches the whole of the mechanism behind a base table
// read - but a `security definer` view and a SECURITY DEFINER function already
// run as their owner, so RLS was never what was hiding anything from them. They
// filter in their own WHERE. Widening RLS leaves their result identical, so
// every refusal assertion that reads only through one would "survive" for a
// reason that says nothing about the assertion.
//
// The operator for that class is a permissive replacement per relation:
// `create or replace` the view or function, inside a savepoint, with the same
// signature and projection and WITHOUT the predicates that decide whether the
// caller may see the rows. The savepoint is rolled back after the assertion,
// so the real definition is restored before the next one runs.
//
// The line every replacement is drawn on, and the reason a false KILL is the
// dangerous direction here:
//
//   Keep every predicate that says WHICH rows the assertion is asking about -
//   the arguments, the join keys, the subject's own identity. Drop every
//   predicate that says WHETHER THE CALLER MAY SEE THEM - ownership, consent,
//   opt-in, blocks, shadow-hiding, the minor floor, `is_*_visible_to`.
//
// Dropping too little leaves the mutation inert, and an inert mutation makes a
// good assertion look vacuous - loud, and safe. Dropping a SUBJECT SELECTOR
// instead reveals rows the assertion never asked about, which makes a VACUOUS
// assertion look good - silent, and the exact false green the guard exists to
// find. So each entry also carries a witness: a subject the real relation
// provably hides, which the replacement must provably reveal. A replacement
// that reveals nothing is reported as an instrument failure rather than
// trusted, because §741's lesson is that a mutation operator is only as honest
// as what it is run against.

// Every entry: `sql` is the replacement, `why` names the access control it
// drops, `subject` names the relation its revealed rows come from, and
// `witness` proves the replacement has teeth. `witness.setup` makes a subject
// the real relation must hide; `witness.probe` counts that subject through the
// relation and must read 0 before the replacement and more than 0 after.

// Restrict a replacement to the rows THIS transaction wrote.
//
// A permissive replacement drops the predicate that decides whether the caller
// may see a row - so it reveals every row in the table, not only the one the
// test filed. Where the assertion's own selector is narrow enough to name the
// test's subject that is the same thing, and where it is not it is emphatically
// not: `gym_exercise_set_history('Bench Press')` normalises the name, and
// seed.sql commits six `Bench press` sets, so the mutation kills that assertion
// whether or not the test inserted anything at all. The kill would then say a
// subject exists in the database rather than that the test built one, which is
// § 741's inversion one remove further out - deterministic here, because the
// seed is committed and reproducible, but still a subject the test did not file.
//
// `xmin` is the handle, and it is sound only when it is pointed at the right
// relation: not the one carrying the access control that was dropped, but the
// one the replacement's rows COME FROM. For `public_run_gear` those are
// different tables - the predicate dropped is a visibility check on `runs`,
// while the rows returned are `run_gear` joined to `gear` - and scoping the
// access-controlled table would restrict nothing the caller ever sees. So each
// entry names its own alias, beside the `why` that names what it drops.
//
// An UPDATE writes a new row version, so a test that establishes its subject by
// mutating a seed row ("make this profile shadow-hidden") is transaction-local
// too. What is left outside is a row the test only ever SELECTed, which is
// exactly the exposure.
//
// § 751 spelled the test `xmin = pg_current_xact_id()::xid` and recorded what
// that misses: pgtap's `lives_ok` and `throws_ok` run their payload in a
// SUBtransaction, so a fixture filed the idiomatic pgtap way carries the
// subtransaction's xid and reads as foreign. It called that the safe direction -
// the mutation goes inert, the assertion survives and the guard reports it by
// name rather than passing it silently - and so it is, but it is still a wrong
// answer, and operator 1's population is full of them: three of
// `public_recaps_rls_test`'s refusals rest on one `lives_ok(... update ...)`.
//
// It also recorded why the exact test was out of reach: `pg_xact_status` is
// superuser-only and these predicates run as `authenticated`. A SECURITY DEFINER
// wrapper owned by `postgres` is the answer to that, and it makes the test exact
// rather than approximate. Given a row the caller can already SEE, an xmin still
// IN PROGRESS can only be this transaction's own - every other in-progress
// transaction's rows are invisible under MVCC - so "visible and in progress" is
// precisely "written here", subtransactions included.
//
// `pg_xact_status` takes an xid8 and `xmin` is a bare 32-bit xid, so the epoch
// has to be put back: `c - c::xid` is the current xid8 less its own low 32 bits.
// Anything this transaction wrote shares that epoch, because a wraparound needs
// 2^32 transactions. The `w >= c` guard is what keeps the reconstruction honest:
// an xid older than ours may be from an earlier epoch and may have had its clog
// truncated, and it is never one of ours, so it is answered without asking.
export const TRANSACTION_LOCAL = 'pgtap_guard_transaction_local';

export const TRANSACTION_LOCAL_SQL = `create function public.${TRANSACTION_LOCAL}(x xid)
 returns boolean language sql stable security definer set search_path to pg_catalog
as $pgtap_guard$
  select w >= c and pg_xact_status(w) = 'in progress'
    from (select pg_current_xact_id() as c) t,
         lateral (select (t.c::text::numeric - t.c::xid::text::numeric
                          + x::text::numeric)::text::xid8 as w) l;
$pgtap_guard$;
`;

/** @param {string} alias */
export const mine = (alias) => `${TRANSACTION_LOCAL}(${alias}.xmin)`;

// The five owner-scoped gym RPCs share one witness, because they read the same
// two tables and their access control is the same `gw.user_id = auth.uid()`.
// It files its own workout and set rather than pointing at the seed's: a
// witness whose subject is committed data proves the replacement reveals the
// database, which is the very thing `mine` exists to stop it doing. The name is
// one no seed row carries, so the probe cannot be answered by anything else.
const GYM_WITNESS_SETUP = `insert into gym_workouts (id, user_id, title, started_at)
   values ('00000000-0000-0000-0000-00000000c001',
           (select id from auth.users order by id limit 1), 'guard witness', now());
 insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
   values ('00000000-0000-0000-0000-00000000c001', 0, 'Pgtap Guard Witness', 5, 60);`;

export const DEFINER_NEUTRALISERS = new Map([
  [
    'public_routes',
    {
      why: 'drops `is_public = true and shadow_hidden = false`; keeps the projection, including the club-visibility mask on club_id',
      sql: `create or replace view public.public_routes as
 select id, user_id, name, distance_m, elevation_m, surface, is_public, slug,
        created_at, updated_at, tags, is_featured, featured_at, run_count,
        case when is_public_club_by_id(club_id) then club_id else null::uuid end as club_id
   from routes r
  where ${mine('r')};`,
      subject: 'routes r — the route whose publicness was dropped',
      witness: {
        setup: `update routes set is_public = true, shadow_hidden = true
                 where id = (select id from routes order by id limit 1);`,
        probe: `select count(*) from public_routes
                 where id = (select id from routes order by id limit 1);`,
      },
    },
  ],
  [
    'public_profiles',
    {
      why: 'drops `shadow_hidden = false`',
      sql: `create or replace view public.public_profiles as
 select u.id, u.display_name, u.avatar_url from user_profiles u
  where ${mine('u')};`,
      subject: 'user_profiles u',
      witness: {
        setup: `update user_profiles set shadow_hidden = true
                 where id = (select id from user_profiles order by id limit 1);`,
        probe: `select count(*) from public_profiles
                 where id = (select id from user_profiles order by id limit 1);`,
      },
    },
  ],
  [
    'public_gym_workouts',
    {
      why: 'drops `is_public = true`',
      sql: `create or replace view public.public_gym_workouts as
 select id, user_id, started_at, title, duration_s, is_public, set_count, volume_kg, created_at
   from gym_workouts w
  where ${mine('w')};`,
      subject: 'gym_workouts w',
      witness: {
        setup: `update gym_workouts set is_public = false
                 where id = (select id from gym_workouts order by id limit 1);`,
        probe: `select count(*) from public_gym_workouts
                 where id = (select id from gym_workouts order by id limit 1);`,
      },
    },
  ],
  [
    'public_gym_sets',
    {
      why: "drops the parent workout's `is_public = true`; keeps the set→workout join, which is structure rather than access control",
      sql: `create or replace view public.public_gym_sets as
 select s.id, s.workout_id, s.set_index, s.exercise_name, s.reps, s.weight_kg, s.duration_s
   from gym_sets s
   join gym_workouts w on w.id = s.workout_id
  where ${mine('s')};`,
      subject: 'gym_sets s — the rows the view returns, not the parent workout carrying the dropped `is_public`',
      witness: {
        setup: `update gym_workouts set is_public = false
                 where id = (select workout_id from gym_sets order by workout_id limit 1);
                update gym_sets set set_index = set_index
                 where workout_id = (select workout_id from gym_sets order by workout_id limit 1);`,
        probe: `select count(*) from public_gym_sets
                 where workout_id = (select workout_id from gym_sets order by workout_id limit 1);`,
      },
    },
  ],
  [
    'public_profile_by_id',
    {
      why: 'drops `shadow_hidden = false` and the mutual-block check; keeps `u.id = p_id`, which is the subject selector',
      sql: `create or replace function public.public_profile_by_id(p_id uuid)
 returns table(id uuid, display_name text, avatar_url text)
 language sql stable security definer set search_path to 'public'
as $neutralised$
  select u.id, u.display_name, u.avatar_url
  from user_profiles u
  where u.id = p_id
    and ${mine('u')};
$neutralised$;`,
      subject: 'user_profiles u',
      witness: {
        setup: `update user_profiles set shadow_hidden = true
                 where id = (select id from user_profiles order by id limit 1);`,
        probe: `select count(*) from public_profile_by_id(
                  (select id from user_profiles order by id limit 1));`,
      },
    },
  ],
  [
    'search_user_profiles',
    {
      why: 'drops `shadow_hidden = false`, the `discoverable_in_search` opt-out and the under-18 floor; keeps the name/handle match and the limit, which are what the caller asked for',
      sql: `create or replace function public.search_user_profiles(p_query text, p_limit integer default 60)
 returns table(id uuid, display_name text, avatar_url text)
 language sql stable security definer set search_path to 'public'
as $neutralised$
  select u.id, u.display_name, u.avatar_url
  from user_profiles u
  where (
      u.display_name ilike '%' || p_query || '%'
      or (
        u.handle is not null
        and ltrim(p_query, '@') <> ''
        and starts_with(u.handle, lower(ltrim(p_query, '@')))
      )
    )
    and ${mine('u')}
  order by u.display_name
  limit least(greatest(coalesce(p_limit, 60), 1), 200);
$neutralised$;`,
      subject: 'user_profiles u',
      witness: {
        setup: `update user_profiles set shadow_hidden = true
                 where id = (select id from user_profiles
                              where display_name is not null order by id limit 1);`,
        probe: `select count(*) from search_user_profiles(
                  (select display_name from user_profiles
                     where display_name is not null order by id limit 1))
                 where id = (select id from user_profiles
                              where display_name is not null order by id limit 1);`,
      },
    },
  ],
  [
    'public_run_gear',
    {
      why: 'drops `private.is_run_visible_to(p_run_id, auth.uid())`; keeps `rg.run_id = p_run_id` and the gear join',
      sql: `create or replace function public.public_run_gear(p_run_id uuid)
 returns table(id uuid, kind text, name text, brand text, model text)
 language sql stable security definer set search_path to 'public'
as $neutralised$
  select g.id, g.kind, g.name, g.brand, g.model
  from run_gear rg
  join gear g on g.id = rg.gear_id
  where rg.run_id = p_run_id
    and ${mine('rg')}
  order by g.kind, g.name;
$neutralised$;`,
      subject: 'run_gear rg — the link rows the RPC returns; the dropped predicate guards the RUN, which is a different table',
      witness: {
        setup: `update runs set is_public = false
                 where id = (select run_id from run_gear order by run_id limit 1);
                update run_gear set gear_id = gear_id
                 where run_id = (select run_id from run_gear order by run_id limit 1);`,
        probe: `select count(*) from public_run_gear(
                  (select run_id from run_gear order by run_id limit 1));`,
      },
    },
  ],
  [
    'my_pending_safety_requests',
    {
      why: "drops the `lower(contact_email) = lower(me.email)` match against the caller — the whole access control here — and the `auth.users` join that carries it; keeps `confirmed_at is null`, which is what makes a request pending",
      sql: `create or replace function public.my_pending_safety_requests()
 returns table(id uuid, owner_name text, has_phone boolean, created_at timestamptz)
 language sql security definer set search_path to 'public'
as $neutralised$
  select sc.id,
         coalesce(p.display_name, ''),
         sc.contact_phone is not null,
         sc.created_at
  from safety_contacts sc
  left join user_profiles p on p.id = sc.owner_id
  where sc.confirmed_at is null
    and ${mine('sc')};
$neutralised$;`,
      subject: 'safety_contacts sc',
      witness: {
        setup: `insert into safety_contacts (owner_id, contact_email)
                 values ((select id from auth.users order by id limit 1),
                         'pgtap-guard-witness@example.invalid');`,
        probe: `select count(*) from my_pending_safety_requests();`,
      },
    },
  ],
  [
    'discoverable_runners_near',
    {
      why: "drops the caller's own `discoverable_nearby` opt-in, the other runner's two opt-outs, `shadow_hidden`, the under-18 floor and the block check; keeps `discoverable_area is not null` (a runner with no location was never a candidate) and the self-exclusion. The radius goes with the caller's opt-in: an opted-out caller has no `discoverable_area`, so there is no origin left to measure a distance from",
      sql: `create or replace function public.discoverable_runners_near(
   p_radius_m double precision default 25000, p_limit integer default 60)
 returns table(id uuid, display_name text, avatar_url text, bucket integer)
 language sql stable security definer set search_path to 'public', 'extensions'
as $neutralised$
  select u.id, u.display_name, u.avatar_url, 4
  from user_settings s
  join user_profiles u on u.id = s.user_id
  where s.discoverable_area is not null
    and u.id is distinct from auth.uid()
    and ${mine('s')}
  limit least(greatest(coalesce(p_limit, 60), 1), 200);
$neutralised$;`,
      subject: 'user_settings s — a runner with no settings row was never a candidate, so the settings row is what makes one discoverable',
      witness: {
        setup: `insert into user_settings (user_id, prefs, discoverable_area)
                 values ((select id from auth.users order by id limit 1),
                         '{}'::jsonb,
                         extensions.ST_SetSRID(extensions.ST_MakePoint(0, 0), 4326)::geography)
                 on conflict (user_id) do update
                   set discoverable_area = excluded.discoverable_area,
                       prefs = '{}'::jsonb;`,
        probe: `select count(*) from discoverable_runners_near();`,
      },
    },
  ],
  [
    'segment_leaderboard_tiered',
    {
      why: "drops the route-visibility gate, the per-effort `is_run_visible_to`, the block check, the club-membership gate, the shadow-hidden name masking and the `health_data_consent_at` requirement on the age band; keeps the segment id, the gender filter and the age arithmetic itself, which are the query the caller asked for",
      sql: `create or replace function public.segment_leaderboard_tiered(
   p_segment_id uuid, p_gender text default null::text, p_age_band text default null::text,
   p_limit integer default 50, p_club_id uuid default null::uuid)
 returns table(effort_id uuid, user_id uuid, run_id uuid, time_seconds integer,
               started_at timestamptz, display_name text, avatar_url text,
               gender text, age integer)
 language sql stable security definer set search_path to 'public', 'private'
as $neutralised$
  select distinct on (se.user_id)
    se.id, se.user_id, se.run_id, se.time_seconds::integer, se.started_at,
    up.display_name, up.avatar_url, up.gender,
    case when up.date_of_birth is not null
      then extract(year from age(up.date_of_birth))::integer end
  from public.segment_efforts se
  join public.user_profiles up on up.id = se.user_id
  where se.segment_id = p_segment_id
    and (p_gender is null or up.gender = p_gender)
    and (
      p_age_band is null
      or (
        up.date_of_birth is not null
        and extract(year from age(up.date_of_birth))::integer between
              (case when p_age_band = '75+' then 75
                    when p_age_band ~ '^[0-9]+-[0-9]+$'
                      then split_part(p_age_band, '-', 1)::integer end)
          and (case when p_age_band = '75+' then 200
                    when p_age_band ~ '^[0-9]+-[0-9]+$'
                      then split_part(p_age_band, '-', 2)::integer end)
      )
    )
    and ${mine('se')}
  order by se.user_id, se.time_seconds asc, se.started_at asc;
$neutralised$;`,
      subject: 'segment_efforts se',
      witness: {
        setup: `insert into segments (id, route_id, name, start_distance_m, end_distance_m)
                 values ('00000000-0000-0000-0000-0000000f0001',
                         (select id from routes order by id limit 1), 'guard witness', 0, 100);
                update routes set is_public = false
                 where id = (select id from routes order by id limit 1);
                insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
                 values ('00000000-0000-0000-0000-0000000f0001',
                         (select id from runs order by id limit 1),
                         (select user_id from runs order by id limit 1), 100, now());
                select set_config('request.jwt.claims',
                         json_build_object('sub', (select id from auth.users order by id desc limit 1))::text,
                         true);`,
        probe: `select count(*) from segment_leaderboard_tiered(
                  '00000000-0000-0000-0000-0000000f0001'::uuid);`,
      },
    },
  ],
  [
    'global_segment_leaderboard',
    {
      why: "the catalogue twin of `segment_leaderboard_tiered`: drops `gs.is_active`, the per-effort `is_run_visible_to`, the block check, the club-membership gate, the shadow-hidden name masking and the `health_data_consent_at` requirement on the age band; keeps the segment id, the gender filter and the age arithmetic itself, which are the query the caller asked for",
      sql: `create or replace function public.global_segment_leaderboard(
   p_segment_id uuid, p_gender text default null::text, p_age_band text default null::text,
   p_limit integer default 50, p_club_id uuid default null::uuid)
 returns table(effort_id uuid, user_id uuid, run_id uuid, time_seconds integer,
               started_at timestamptz, display_name text, avatar_url text,
               gender text, age integer)
 language sql stable security definer set search_path to 'public', 'private'
as $neutralised$
  select distinct on (se.user_id)
    se.id, se.user_id, se.run_id, se.time_seconds::integer, se.started_at,
    up.display_name, up.avatar_url, up.gender,
    case when up.date_of_birth is not null
      then extract(year from age(up.date_of_birth))::integer end
  from public.global_segment_efforts se
  join public.user_profiles up on up.id = se.user_id
  where se.global_segment_id = p_segment_id
    and (p_gender is null or up.gender = p_gender)
    and (
      p_age_band is null
      or (
        up.date_of_birth is not null
        and extract(year from age(up.date_of_birth))::integer between
              (case when p_age_band = '75+' then 75
                    when p_age_band ~ '^[0-9]+-[0-9]+$'
                      then split_part(p_age_band, '-', 1)::integer end)
          and (case when p_age_band = '75+' then 200
                    when p_age_band ~ '^[0-9]+-[0-9]+$'
                      then split_part(p_age_band, '-', 2)::integer end)
      )
    )
    and ${mine('se')}
  order by se.user_id, se.time_seconds asc, se.started_at asc;
$neutralised$;`,
      subject: 'global_segment_efforts se',
      witness: {
        setup: `insert into global_segments (id, name, waypoints, distance_m, is_active)
                 values ('00000000-0000-0000-0000-0000000f0002', 'guard witness',
                         '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, false);
                insert into global_segment_efforts
                       (global_segment_id, run_id, user_id, time_seconds, started_at)
                 values ('00000000-0000-0000-0000-0000000f0002',
                         (select id from runs order by id limit 1),
                         (select user_id from runs order by id limit 1), 100, now());
                select set_config('request.jwt.claims',
                         json_build_object('sub', (select id from auth.users order by id desc limit 1))::text,
                         true);`,
        probe: `select count(*) from global_segment_leaderboard(
                  '00000000-0000-0000-0000-0000000f0002'::uuid);`,
      },
    },
  ],
  // ── Relations Postgres calls SECURITY INVOKER that still filter for
  // themselves ──
  //
  // The catalogue's `prosecdef` says which privileges a routine runs with, not
  // whether it carries an access predicate. Every RPC below is SECURITY
  // INVOKER, so the first operator reaches the RLS on the tables it reads — and
  // is still inert against it, because the refusal is a `= auth.uid()` (or a
  // `shadow_hidden = false`) written into the body. Measured, not assumed: all
  // seven survived the first operator on a database where their fixtures exist,
  // which is how they were found.
  //
  // One thing a kill over these proves less than it does elsewhere. Where the
  // assertion carries a subject selector of its own — a search string, an
  // exercise name — the row revealed is the subject. Where the caller's own
  // identity IS the only selector ("a stranger sees NONE of the lifter's
  // sets"), a permissive replacement also reveals the seed's rows, so the kill
  // says a subject exists in this transaction rather than that the test built
  // one. Recorded in followups.md rather than papered over.
  [
    'search_clubs',
    {
      why: 'drops `is_public = true and shadow_hidden = false`; keeps the name / location / radius match, which is the search the caller asked for',
      sql: `create or replace function public.search_clubs(
   p_query text default null::text,
   p_center_lng double precision default null::double precision,
   p_center_lat double precision default null::double precision,
   p_radius_m double precision default 80000, p_limit integer default 60)
 returns setof clubs
 language sql stable set search_path to 'public', 'extensions'
as $neutralised$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select c.id, c.owner_id, c.name, c.slug, c.description, c.avatar_url,
         c.location_label, c.is_public, c.created_at, c.updated_at, c.join_policy,
         null::text, c.location_point, c.member_count, c.is_verified,
         c.requires_activity_waiver, c.website_url, c.instagram_url, c.strava_url,
         c.facebook_url, c.shadow_hidden
  from clubs c, center
  where (
      p_query is null
      or c.name ilike '%' || p_query || '%'
      or c.location_label ilike '%' || p_query || '%'
      or (
        center.pt is not null
        and c.location_point is not null
        and ST_DWithin(c.location_point, center.pt, p_radius_m)
      )
    )
    and ${mine('c')}
  limit p_limit;
$neutralised$;`,
      subject: 'clubs c',
      witness: {
        setup: `update clubs set shadow_hidden = true
                 where id = (select id from clubs where is_public order by id limit 1);`,
        probe: `select count(*) from search_clubs(
                  (select name from clubs where is_public order by id limit 1))
                 where id = (select id from clubs where is_public order by id limit 1);`,
      },
    },
  ],
  [
    'gym_exercise_names',
    {
      why: 'drops `gw.user_id = auth.uid()`; keeps the blank-name filter and the canonical-key grouping',
      sql: `create or replace function public.gym_exercise_names()
 returns table(exercise_name text, uses integer)
 language sql stable set search_path to 'public'
as $neutralised$
  with norm as (
    select public.normalise_exercise_name(s.exercise_name) as key,
           s.exercise_name as display,
           gw.started_at
    from gym_sets s
    join gym_workouts gw on gw.id = s.workout_id
    where coalesce(public.normalise_exercise_name(s.exercise_name), '') <> ''
      and ${mine('s')}
  ),
  spellings as (
    select key, display, count(*)::int as spelling_uses, max(started_at) as last_used
    from norm group by key, display
  ),
  picked as (
    select key,
           (array_agg(display order by spelling_uses desc, last_used desc, display))[1] as display,
           sum(spelling_uses)::int as uses
    from spellings group by key
  )
  select p.display, p.uses from picked p order by p.uses desc, p.display;
$neutralised$;`,
      subject: 'gym_sets s',
      witness: {
        setup: GYM_WITNESS_SETUP,
        probe: `select count(*) from gym_exercise_names()
                 where exercise_name = 'Pgtap Guard Witness';`,
      },
    },
  ],
  [
    'gym_exercise_records',
    {
      why: 'drops `gw.user_id = auth.uid()`. The replacement returns one row per exercise with the declared shape rather than re-deriving every best: the assertion counts rows, and a re-derivation would be one more copy of the real aggregation to keep in step',
      sql: `create or replace function public.gym_exercise_records()
 returns table(exercise_name text, heaviest_weight_kg numeric, heaviest_weight_reps integer,
               best_volume_kg numeric, best_est_1rm_kg numeric,
               last_performed_at timestamptz, session_count integer)
 language sql stable set search_path to 'public'
as $neutralised$
  select
    (array_agg(s.exercise_name order by gw.started_at desc))[1],
    max(s.weight_kg),
    max(s.reps),
    max(s.weight_kg * s.reps),
    max(s.weight_kg),
    max(gw.started_at),
    count(distinct s.workout_id)::int
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where btrim(coalesce(s.exercise_name, '')) <> ''
    and ${mine('s')}
  group by regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g');
$neutralised$;`,
      subject: 'gym_sets s',
      witness: {
        setup: GYM_WITNESS_SETUP,
        probe: `select count(*) from gym_exercise_records()
                 where exercise_name = 'Pgtap Guard Witness';`,
      },
    },
  ],
  [
    'gym_exercise_set_history',
    {
      why: 'drops `gw.user_id = auth.uid()`; keeps the normalised exercise-name match, which is the subject the caller named',
      sql: `create or replace function public.gym_exercise_set_history(p_name text)
 returns table(workout_id uuid, started_at timestamptz, exercise_name text, reps integer,
               weight_kg numeric, rpe numeric, duration_s integer, set_type text)
 language sql stable set search_path to 'public'
as $neutralised$
  select s.workout_id, gw.started_at, s.exercise_name, s.reps, s.weight_kg,
         s.rpe, s.duration_s, s.set_type
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g')
      = regexp_replace(lower(btrim(p_name)), '\s+', ' ', 'g')
    and ${mine('s')};
$neutralised$;`,
      subject: 'gym_sets s',
      witness: {
        setup: GYM_WITNESS_SETUP,
        probe: `select count(*) from gym_exercise_set_history('Pgtap Guard Witness');`,
      },
    },
  ],
  [
    'gym_exercise_set_history_batch',
    {
      why: 'drops `gw.user_id = auth.uid()`; keeps the normalised name-array match',
      sql: `create or replace function public.gym_exercise_set_history_batch(p_names text[])
 returns table(normalised_name text, workout_id uuid, started_at timestamptz, exercise_name text,
               reps integer, weight_kg numeric, rpe numeric, duration_s integer, set_type text)
 language sql stable set search_path to 'public'
as $neutralised$
  select regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g'),
         s.workout_id, gw.started_at, s.exercise_name, s.reps, s.weight_kg,
         s.rpe, s.duration_s, s.set_type
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g') in (
      select regexp_replace(lower(btrim(n)), '\s+', ' ', 'g')
      from unnest(coalesce(p_names, '{}'::text[])) as n
      where btrim(coalesce(n, '')) <> ''
    )
    and ${mine('s')};
$neutralised$;`,
      subject: 'gym_sets s',
      witness: {
        setup: GYM_WITNESS_SETUP,
        probe: `select count(*) from gym_exercise_set_history_batch(
                  array['Pgtap Guard Witness']);`,
      },
    },
  ],
  [
    'gym_workout_summaries',
    {
      why: 'drops `gw.user_id = auth.uid()` from the `mine` CTE the whole body hangs off; the listing, the per-workout exercise count and the ordering are left as written',
      sql: `create or replace function public.gym_workout_summaries(p_limit integer default 100)
 returns table(workout_id uuid, exercise_count integer, is_pr boolean)
 language sql stable set search_path to 'public'
as $neutralised$
  with mine as (
    select gw.id, gw.started_at from gym_workouts gw where ${mine('gw')}
  ),
  listed as (
    select m.id, m.started_at from mine m
    order by m.started_at desc, m.id desc
    limit greatest(coalesce(p_limit, 100), 0)
  ),
  norm as (
    select s.workout_id, m.started_at,
           regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g') as key
    from gym_sets s
    join mine m on m.id = s.workout_id
    where btrim(coalesce(s.exercise_name, '')) <> ''
  ),
  counts as (
    select n.workout_id, count(distinct n.key)::int as exercise_count
    from norm n join listed l on l.id = n.workout_id
    group by n.workout_id
  )
  select l.id, coalesce(c.exercise_count, 0), false
  from listed l
  left join counts c on c.workout_id = l.id
  order by l.started_at desc, l.id desc;
$neutralised$;`,
      subject: 'gym_workouts gw — the `mine` CTE the whole body hangs off',
      witness: {
        setup: GYM_WITNESS_SETUP,
        probe: `select count(*) from gym_workout_summaries()
                 where workout_id = '00000000-0000-0000-0000-00000000c001';`,
      },
    },
  ],
  [
    'run_streaks_for_user',
    {
      why: 'drops `r.user_id = auth.uid()`; keeps the timezone bucketing and the optional source filter, both of which are the question the caller asked',
      sql: `create or replace function public.run_streaks_for_user(
   p_tz text default 'UTC'::text, p_source text default null::text)
 returns table(current_streak integer, best_streak integer)
 language sql stable set search_path to 'public'
as $neutralised$
  with days as (
    select distinct (r.started_at at time zone p_tz)::date as d
    from runs r
    where (p_source is null or r.source = p_source)
      and (r.started_at at time zone p_tz)::date <= (now() at time zone p_tz)::date
      and ${mine('r')}
  ),
  islands as (
    select d, d - (row_number() over (order by d))::int as grp from days
  ),
  lens as (
    select count(*)::int as len, max(d) as island_end from islands group by grp
  )
  select
    coalesce((select len from lens
               where island_end >= (now() at time zone p_tz)::date - 1), 0),
    coalesce((select max(len) from lens), 0);
$neutralised$;`,
      subject: 'runs r',
      witness: {
        // A streak RPC always returns exactly one row, so a row count would
        // read 1 whether or not anything was revealed. The probe is the value.
        // The caller is nobody in particular, so the real relation's
        // `user_id = auth.uid()` hides the run the witness just filed.
        setup: `insert into runs (id, user_id, started_at, distance_m, duration_s, source)
                 values ('00000000-0000-0000-0000-00000000c010',
                         (select id from auth.users order by id limit 1),
                         now() - interval '400 days', 1000, 600, 'app');
                select set_config('request.jwt.claims',
                  '{"sub":"00000000-0000-0000-0000-0000000c0ffe"}', true);`,
        probe: `select best_streak from run_streaks_for_user('UTC');`,
      },
    },
  ],
  [
    'browse_public_challenges',
    {
      why: "drops `c.is_public = true`; keeps the still-open-to-join window, the already-joined exclusion and the throwaway suppression, none of which are about permission",
      sql: `create or replace function public.browse_public_challenges(
   p_search text default null::text, p_limit integer default 24, p_offset integer default 0)
 returns table(id uuid, creator_id uuid, club_id uuid, title text, description text,
               metric text, scope text, goal_value numeric, activity_type text,
               starts_at timestamptz, ends_at timestamptz, is_public boolean,
               created_at timestamptz, participant_count integer)
 language sql stable security definer set search_path to 'public'
as $neutralised$
  select c.id, c.creator_id, c.club_id, c.title, c.description, c.metric, c.scope,
         c.goal_value, c.activity_type, c.starts_at, c.ends_at, c.is_public,
         c.created_at, c.participant_count
  from challenges c
  where c.ends_at > now()
    and not exists (
      select 1 from challenge_participants pj
      where pj.challenge_id = c.id and pj.user_id = auth.uid()
    )
    and (
      c.participant_count > 0
      or c.created_at >= now() - interval '7 days'
      or c.creator_id = auth.uid()
    )
    and (
      p_search is null
      or btrim(p_search) = ''
      or c.title ilike '%' || btrim(p_search) || '%'
      or c.description ilike '%' || btrim(p_search) || '%'
    )
    and ${mine('c')}
  limit greatest(0, least(coalesce(p_limit, 24), 100))
  offset greatest(0, coalesce(p_offset, 0));
$neutralised$;`,
      subject: 'challenges c',
      witness: {
        setup: `select set_config('pgtap_guard.witness',
                  (select c.id::text from challenges c
                    where c.is_public = true and c.ends_at > now()
                      and (c.participant_count > 0 or c.created_at >= now() - interval '7 days')
                    order by c.id limit 1), true);
                update challenges set is_public = false
                 where id = current_setting('pgtap_guard.witness')::uuid;`,
        probe: `select count(*) from browse_public_challenges()
                 where id = current_setting('pgtap_guard.witness')::uuid;`,
      },
    },
  ],
  [
    'search_public_events',
    {
      why: "drops `e.is_public = true` and the `clubs.is_public = true` join term — the two predicates that keep a members-only event and a private club's event out of discovery. Every other filter is the search the caller typed and stays, so an assertion about one of THOSE cannot be killed by this replacement",
      sql: `create or replace function public.search_public_events(
   p_query text default null::text, p_category text default null::text,
   p_cadence text default null::text, p_byday text default null::text,
   p_paid text default null::text, p_time text default null::text,
   p_center_lng double precision default null::double precision,
   p_center_lat double precision default null::double precision,
   p_radius_m double precision default 50000, p_limit integer default 60)
 returns table(id uuid, club_id uuid, club_name text, club_slug text, title text,
               category text, discipline text, starts_at timestamptz, timezone text,
               duration_min integer, recurrence_freq text, recurrence_byday text[],
               capacity integer, price_cents integer, currency text, distance_m double precision)
 language sql stable set search_path to 'public', 'extensions'
as $neutralised$
  with center as (
    select case
      when p_center_lng is not null and p_center_lat is not null
      then ST_SetSRID(ST_MakePoint(p_center_lng, p_center_lat), 4326)::geography
    end as pt
  )
  select e.id, e.club_id, c.name, c.slug, e.title, e.category, e.discipline,
         e.starts_at, e.timezone, e.duration_min, e.recurrence_freq, e.recurrence_byday,
         e.capacity, pr.price_cents, pr.currency,
         case when center.pt is not null and c.location_point is not null
           then ST_Distance(c.location_point, center.pt) else null end
  from events e
  join clubs c on c.id = e.club_id
  cross join center
  left join lateral (
    select min(price_cents) as price_cents,
           (array_agg(currency order by price_cents))[1] as currency
    from event_pricing ep
    where ep.event_id = e.id
  ) pr on true
  where (e.recurrence_freq is not null or e.starts_at >= now())
    and (
      p_query is null
      or e.discipline ilike '%' || p_query || '%'
      or e.title ilike '%' || p_query || '%'
    )
    and (p_category is null or e.category = p_category)
    and (
      p_cadence is null
      or (p_cadence = 'one_off' and e.recurrence_freq is null)
      or (p_cadence <> 'one_off' and e.recurrence_freq = p_cadence)
    )
    and (
      p_byday is null
      or (e.recurrence_byday is not null and e.recurrence_byday @> array[p_byday])
      or (
        e.recurrence_freq is null
        and case extract(
                   isodow from e.starts_at at time zone coalesce(e.timezone, 'UTC')
                 )::int
              when 1 then 'MO' when 2 then 'TU' when 3 then 'WE'
              when 4 then 'TH' when 5 then 'FR' when 6 then 'SA'
              when 7 then 'SU' end = p_byday
      )
    )
    and (
      p_paid is null
      or (p_paid = 'paid' and pr.price_cents is not null)
      or (p_paid = 'free' and pr.price_cents is null)
    )
    and (
      p_time is null
      or case
           when extract(hour from e.starts_at at time zone coalesce(e.timezone, 'UTC'))::int
                between 5 and 11 then 'morning'
           when extract(hour from e.starts_at at time zone coalesce(e.timezone, 'UTC'))::int
                between 12 and 16 then 'afternoon'
           else 'evening'
         end = p_time
    )
    and (
      center.pt is null
      or (
        c.location_point is not null
        and ST_DWithin(c.location_point, center.pt, p_radius_m)
      )
    )
    and ${mine('e')}
  limit greatest(1, least(p_limit, 200));
$neutralised$;`,
      subject: 'events e',
      witness: {
        setup: `select set_config('pgtap_guard.witness',
                  (select e.id::text from events e
                     join clubs c on c.id = e.club_id and c.is_public = true
                    where e.is_public = true
                      and (e.recurrence_freq is not null or e.starts_at >= now())
                    order by e.id limit 1), true);
                update events set is_public = false
                 where id = current_setting('pgtap_guard.witness')::uuid;`,
        probe: `select count(*) from search_public_events()
                 where id = current_setting('pgtap_guard.witness')::uuid;`,
      },
    },
  ],
  [
    'public_run_counts',
    {
      why: "drops `r.is_public = true`; keeps the caller's own `user_id = any(p_user_ids)`",
      sql: `create or replace function public.public_run_counts(p_user_ids uuid[])
 returns table(user_id uuid, public_run_count bigint)
 language sql stable security definer set search_path to 'public', 'pg_temp'
as $neutralised$
  select r.user_id, count(*)
  from runs r
  where r.user_id = any(p_user_ids)
    and ${mine('r')}
  group by r.user_id;
$neutralised$;`,
      subject: 'runs r',
      witness: {
        setup: `select set_config('pgtap_guard.witness',
                  (select r.user_id::text from runs r order by r.id limit 1), true);
                update runs set is_public = false
                 where user_id = current_setting('pgtap_guard.witness')::uuid;`,
        probe: `select count(*) from public_run_counts(
                  array[current_setting('pgtap_guard.witness')::uuid]);`,
      },
    },
  ],
  [
    'get_event_meet_point',
    {
      why: 'drops `is_club_member(e.club_id)`; keeps the event id and the both-coordinates-present condition, which is the row existing rather than the caller being allowed it',
      sql: `create or replace function public.get_event_meet_point(p_event_id uuid)
 returns table(meet_lat double precision, meet_lng double precision)
 language sql security definer set search_path to 'public', 'private'
as $neutralised$
  select e.meet_lat, e.meet_lng
  from events e
  where e.id = p_event_id
    and e.meet_lat is not null
    and e.meet_lng is not null
    and ${mine('e')};
$neutralised$;`,
      subject: 'events e',
      witness: {
        setup: `select set_config('pgtap_guard.witness',
                  (select e.id::text from events e order by e.id limit 1), true);
                update events set meet_lat = 51.5, meet_lng = -0.1
                 where id = current_setting('pgtap_guard.witness')::uuid;`,
        probe: `select count(*) from get_event_meet_point(
                  current_setting('pgtap_guard.witness')::uuid);`,
      },
    },
  ],
  [
    'heatmap_points_in_bbox',
    {
      why: "drops `is_public = true`, `shadow_hidden = false` and the `privacy_in_any_zone` clip that is the whole privacy contract of the heatmap; keeps the bounding box, the densification and the point cap, which are the query the caller asked for",
      sql: `create or replace function public.heatmap_points_in_bbox(
   p_min_lng double precision, p_min_lat double precision,
   p_max_lng double precision, p_max_lat double precision,
   p_max_points integer default 5000)
 returns table(lng double precision, lat double precision)
 language sql stable parallel safe security definer set search_path to 'public', 'extensions'
as $neutralised$
  with bbox as (
    select ST_MakeEnvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography as g
  ),
  hit_routes as (
    select r.geom
    from routes r
    cross join bbox
    where r.geom is not null
      and r.geom && bbox.g
      and ${mine('r')}
    limit 200
  ),
  densified as (
    select (ST_DumpPoints(
        ST_LineInterpolatePoints(
          hr.geom::geometry,
          least(1.0, 50.0 / greatest(ST_Length(hr.geom), 50.0))
        )
      )).geom as pt
    from hit_routes hr
  )
  select ST_X(pt), ST_Y(pt) from densified limit p_max_points;
$neutralised$;`,
      subject: 'routes r — the `hit_routes` CTE every emitted point is densified from',
      witness: {
        // Every route owner gets a globe-sized privacy zone, so the real
        // relation clips every point it would otherwise emit — the witness
        // measures the privacy clip itself rather than the is_public term.
        setup: `select set_config('pgtap_guard.minlng', (ST_XMin(g) - 0.01)::text, true),
                       set_config('pgtap_guard.minlat', (ST_YMin(g) - 0.01)::text, true),
                       set_config('pgtap_guard.maxlng', (ST_XMax(g) + 0.01)::text, true),
                       set_config('pgtap_guard.maxlat', (ST_YMax(g) + 0.01)::text, true)
                  from (select ST_Envelope(r.geom::geometry) as g from routes r
                         where r.geom is not null order by r.id limit 1) e;
                insert into user_settings (user_id, prefs)
                select distinct r.user_id,
                       '{"privacy_zones":[{"lat":0,"lng":0,"radius_m":100000000}]}'::jsonb
                  from routes r
                 on conflict (user_id) do update set prefs = excluded.prefs;
                update routes set updated_at = updated_at where geom is not null;`,
        probe: `select count(*) from heatmap_points_in_bbox(
                  current_setting('pgtap_guard.minlng')::double precision,
                  current_setting('pgtap_guard.minlat')::double precision,
                  current_setting('pgtap_guard.maxlng')::double precision,
                  current_setting('pgtap_guard.maxlat')::double precision, 5000);`,
      },
    },
  ],
  [
    'routes_within_box',
    {
      why: "reads `routes` directly instead of the public_routes view, and matches on the raw `geom` instead of `geom_public` — the clipped geometry the privacy zones produce, which is NULL for a route that lies wholly inside one. Keeps the bounding box, the nearest-centre ordering and the result cap",
      sql: `create or replace function public.routes_within_box(
   min_lat double precision, min_lng double precision,
   max_lat double precision, max_lng double precision,
   max_results integer default 50)
 returns setof public_routes
 language sql stable security definer set search_path to 'public', 'extensions'
as $neutralised$
  with box as (
    select ST_SetSRID(ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat), 4326)::geography as g
  ),
  centre as (
    select ST_SetSRID(
      ST_MakePoint((min_lng + max_lng) / 2, (min_lat + max_lat) / 2), 4326)::geography as g
  )
  select r.id, r.user_id, r.name, r.distance_m, r.elevation_m, r.surface, r.is_public,
         r.slug, r.created_at, r.updated_at, r.tags, r.is_featured, r.featured_at,
         r.run_count,
         case when is_public_club_by_id(r.club_id) then r.club_id else null::uuid end
  from routes r, box, centre
  where r.geom is not null
    and ST_Intersects(r.geom, box.g)
    and ${mine('r')}
  order by r.geom <-> centre.g
  limit max_results;
$neutralised$;`,
      subject: 'routes r',
      witness: {
        setup: `select set_config('pgtap_guard.minlng', (ST_XMin(g) - 0.01)::text, true),
                       set_config('pgtap_guard.minlat', (ST_YMin(g) - 0.01)::text, true),
                       set_config('pgtap_guard.maxlng', (ST_XMax(g) + 0.01)::text, true),
                       set_config('pgtap_guard.maxlat', (ST_YMax(g) + 0.01)::text, true)
                  from (select ST_Envelope(r.geom::geometry) as g from routes r
                         where r.geom is not null order by r.id limit 1) e;
                update routes set geom_public = null;`,
        probe: `select count(*) from routes_within_box(
                  current_setting('pgtap_guard.minlat')::double precision,
                  current_setting('pgtap_guard.minlng')::double precision,
                  current_setting('pgtap_guard.maxlat')::double precision,
                  current_setting('pgtap_guard.maxlng')::double precision, 50);`,
      },
    },
  ],
  [
    'coach_roster_summary',
    {
      why: "drops the `mine` gate — `coach_id = auth.uid() and status = 'active'` — which is the entire authorisation of the roster, and the not-authenticated guard above it. The load and plan-completion aggregates are NOT reproduced: every assertion over this RPC is about which athletes appear at all, and a second copy of that arithmetic would be one more thing to keep in step for no measurement gained",
      sql: `create or replace function public.coach_roster_summary()
 returns table(athlete_id uuid, display_name text, avatar_url text, last_run_at timestamptz,
               runs_7d integer, distance_7d_m double precision, load_acute double precision,
               load_chronic double precision, active_plan_id uuid, plan_completion_pct integer)
 language sql stable security definer set search_path to 'public'
as $neutralised$
  select p.id, p.display_name, p.avatar_url, null::timestamptz,
         0, 0::double precision, 0::double precision, 0::double precision,
         null::uuid, 0
  from coach_athletes ca
  join user_profiles p on p.id = ca.athlete_id
  where ${mine('ca')};
$neutralised$;`,
      subject: 'coach_athletes ca — the roster LINK, not the athlete profile it names',
      witness: {
        // The seed already pairs a coach with an athlete and a unique index
        // forbids a second live pair, so the witness demotes the existing link
        // rather than adding one: pending is not active consent, and the real
        // roster is empty for exactly that reason.
        setup: `select set_config('pgtap_guard.witness',
                  (select ca.coach_id::text from coach_athletes ca
                    where ca.athlete_id is not null order by ca.id limit 1), true);
                update coach_athletes set status = 'pending', ended_at = null
                 where athlete_id is not null;
                select set_config('request.jwt.claims',
                  json_build_object('sub', current_setting('pgtap_guard.witness'))::text, true);`,
        probe: `select count(*) from coach_roster_summary();`,
      },
    },
  ],
]);

// Definer relations a zero-or-empty assertion reads and that deliberately have
// NO permissive replacement, because none of their assertions is a refusal.
//
// Registering one costs a copy of a definition to keep in step with the schema,
// and buys a measurement only where an empty result is a claim about access
// control. All three of these are outside that, for three different reasons,
// and each was checked rather than assumed - the operator was pointed at it and
// the verdict it would produce is recorded beside it. The list is CLOSED: the
// validation phase re-derives the same set from the suite and fails if another
// relation joins it, so the next assertion written over an unmeasured definer
// relation is a decision someone makes on purpose rather than a chore the guard
// hands them at merge time.
export const UNREGISTERED_DEFINER_RELATIONS = [
  {
    relation: 'fetch_pending_reports',
    assertion: 'resolved target is gone from the queue',
    reason:
      "the claim is that resolving a report takes it OUT of the moderation queue, which is the RPC's `status = 'pending'` filter - a subject selector, not access control. A replacement may only drop the admin gate, so the resolved report stays absent and the assertion would survive: an EXPECTED_SURVIVORS entry bought with a second copy of the queue query",
  },
  {
    relation: 'challenge_leaderboard',
    assertion: 'activity_type=run filter excludes a walk (value 0)',
    reason:
      'the expectation is a zero VALUE rather than an emptiness - a leaderboard metric that summed nothing - and a widening mutation moves a value, so a kill would say the mutation changed an answer rather than that access control was hiding a row. Same class as the two assertions § 745 left outside the vocabulary',
  },
  {
    relation: 'find_backlogged_jobs',
    assertion:
      'a job scheduled into the future is not backlogged -- the clock is scheduled_at, not created_at',
    reason:
      "the function carries no access-control filter to drop. It is a definer only so the ten-minute alert cron reads `jobs` without a policy, and its whole WHERE is `status = 'queued'` plus an age threshold - two subject selectors, the same shape as `fetch_pending_reports` above. Its three zero-count assertions each claim a predicate rather than a visibility: that the age is measured off `scheduled_at` and not `created_at` (or `defer_job`'s backing-off retries would read as a stalled queue), and that a running and a failed job belong to the stuck and failed alerts instead. Emptiness is not what any of them turns on either - assertions (1) and (2) in the same transaction are `results_eq` positives naming the rows the function DOES return, so a function that had gone silent would fail there first",
  },
];
