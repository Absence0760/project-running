#!/usr/bin/env node
// Permissive replacements for the relations that filter in their OWN SQL.
//
// The sibling guard's first operator drops the session to the BYPASSRLS owner
// for the span of one assertion. That is a complete bypass of row-level
// security and therefore a complete bypass of the mechanism behind a base
// table read - but a `security definer` view and a SECURITY DEFINER function
// already run as their owner, so RLS was never what was hiding anything from
// them. They filter in their own WHERE. Dropping RLS leaves their result
// identical, so every refusal assertion that reads only through one would
// "survive" for a reason that says nothing about the assertion.
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
// drops, and `witness` proves the replacement has teeth. `witness.setup` makes
// a subject the real relation must hide; `witness.probe` counts that subject
// through the relation and must read 0 before the replacement and more than 0
// after.
export const DEFINER_NEUTRALISERS = new Map([
  [
    'public_routes',
    {
      why: 'drops `is_public = true and shadow_hidden = false`; keeps the projection, including the club-visibility mask on club_id',
      sql: `create or replace view public.public_routes as
 select id, user_id, name, distance_m, elevation_m, surface, is_public, slug,
        created_at, updated_at, tags, is_featured, featured_at, run_count,
        case when is_public_club_by_id(club_id) then club_id else null::uuid end as club_id
   from routes r;`,
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
 select id, display_name, avatar_url from user_profiles;`,
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
   from gym_workouts w;`,
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
   join gym_workouts w on w.id = s.workout_id;`,
      witness: {
        setup: `update gym_workouts set is_public = false
                 where id = (select workout_id from gym_sets order by workout_id limit 1);`,
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
  where u.id = p_id;
$neutralised$;`,
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
  order by u.display_name
  limit least(greatest(coalesce(p_limit, 60), 1), 200);
$neutralised$;`,
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
  order by g.kind, g.name;
$neutralised$;`,
      witness: {
        setup: `update runs set is_public = false
                 where id = (select run_id from run_gear order by run_id limit 1);`,
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
  where sc.confirmed_at is null;
$neutralised$;`,
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
  limit least(greatest(coalesce(p_limit, 60), 1), 200);
$neutralised$;`,
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
  order by se.user_id, se.time_seconds asc, se.started_at asc;
$neutralised$;`,
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
  // ── Relations Postgres calls SECURITY INVOKER that still filter for
  // themselves ──
  //
  // The catalogue's `prosecdef` says which privileges a routine runs with, not
  // whether it carries an access predicate. Every RPC below is SECURITY
  // INVOKER, so the owner bypass reaches the RLS on the tables it reads — and
  // is still inert against it, because the refusal is a `= auth.uid()` (or a
  // `shadow_hidden = false`) written into the body. Measured, not assumed: all
  // seven survived the owner bypass on a database where their fixtures exist,
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
  limit p_limit;
$neutralised$;`,
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
      why: 'drops `gw.user_id = auth.uid()`; keeps the blank-name filter and the grouping',
      sql: `create or replace function public.gym_exercise_names()
 returns table(exercise_name text, uses integer)
 language sql stable set search_path to 'public'
as $neutralised$
  select btrim(s.exercise_name), count(*)::int
  from gym_sets s
  join gym_workouts gw on gw.id = s.workout_id
  where btrim(coalesce(s.exercise_name, '')) <> ''
  group by btrim(s.exercise_name)
  order by count(*) desc, btrim(s.exercise_name);
$neutralised$;`,
      witness: {
        setup: `select 1;`,
        probe: `select count(*) from gym_exercise_names();`,
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
  group by regexp_replace(lower(btrim(s.exercise_name)), '\s+', ' ', 'g');
$neutralised$;`,
      witness: {
        setup: `select 1;`,
        probe: `select count(*) from gym_exercise_records();`,
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
      = regexp_replace(lower(btrim(p_name)), '\s+', ' ', 'g');
$neutralised$;`,
      witness: {
        setup: `select 1;`,
        probe: `select count(*) from gym_exercise_set_history(
                  (select s.exercise_name from gym_sets s
                    where s.exercise_name is not null order by s.exercise_name limit 1));`,
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
    );
$neutralised$;`,
      witness: {
        setup: `select 1;`,
        probe: `select count(*) from gym_exercise_set_history_batch(
                  array[(select s.exercise_name from gym_sets s
                          where s.exercise_name is not null order by s.exercise_name limit 1)]);`,
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
    select gw.id, gw.started_at from gym_workouts gw
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
      witness: {
        setup: `select 1;`,
        probe: `select count(*) from gym_workout_summaries();`,
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
      witness: {
        // A streak RPC always returns exactly one row, so a row count would
        // read 1 whether or not anything was revealed. The probe is the value.
        setup: `select 1;`,
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
  limit greatest(0, least(coalesce(p_limit, 24), 100))
  offset greatest(0, coalesce(p_offset, 0));
$neutralised$;`,
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
  limit greatest(1, least(p_limit, 200));
$neutralised$;`,
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
]);
