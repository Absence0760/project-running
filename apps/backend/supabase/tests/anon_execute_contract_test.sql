-- The whole-schema contract behind 20270625000001 and 20270626000001: the set
-- of `public` functions an anonymous caller may execute is a closed list, and
-- everything else is withheld in the form that withholds on every image this
-- schema runs on.
--
-- anon_execute_registry_test.sql pins the RULE (with probe functions, against
-- whichever image is running) and the four functions the first migration
-- withheld. This file pins the SET, for the whole schema, so a function added
-- tomorrow without a revoke fails here rather than shipping open.
--
-- ── Reading it on two images ──
-- A fresh `public` function comes up `proacl` NULL — owner + PUBLIC — on a
-- current workstation CLI, and with an explicit {anon, authenticated,
-- service_role} grant on Supabase Cloud and on CI (`supabase/setup-cli` pinned
-- to 2.84.2). decisions.md 799 has the measurement. That gives the two
-- assertions below different strengths, deliberately:
--
--   * (1) reads `has_function_privilege`, which is the literal truth on each
--     image. On CI -- the image prod resembles -- it catches EVERY newly added
--     function that no migration revoked, because such a function arrives
--     anon-granted by name.
--   * (2) reads the ACL SHAPE instead: `proacl` NULL, a PUBLIC entry, or an
--     anon entry. That is what survives a `drop function` + `create function`,
--     which re-issues whichever default the image has, and it is the half that
--     bites on a workstation.
--
-- Both pass on either image. Neither alone is the contract.
--
-- ── Scope ──
-- `public` only: the CLI exposes `public` and `graphql_public` to PostgREST, so
-- a `private` function is unreachable by an anonymous HTTP caller whatever its
-- ACL, and thirteen of them carry a deliberate anon grant because policies on
-- anon-readable tables name them.
--
-- Trigger-returning functions are excluded from (1) and (2) and the exclusion
-- is itself asserted, in (4): no grant makes one callable -- Postgres refuses
-- with 0A000 before privileges are consulted -- so 67 of them still carry the
-- image default and none of it is reachable.
--
-- Extension-owned functions are excluded too. `global_segments_test` installs
-- pgtap `with schema public`, and postgis or pg_trgm could be relocated there
-- by a future stack change; several hundred extension functions arriving with
-- the image default are the extension's business, not this schema's.
--
-- (5) and (6) are the positive control for the second half of 20270626000001,
-- which withheld `authenticated` as well as anon from the cron and job-queue
-- family. Any signed-up account holds the same create-time grant anon does, so
-- on Cloud a logged-in user could drain the queue; and a sweep that revoked
-- EXECUTE from every role would close that while breaking pg_cron's operator
-- hook, which (6) is here to fail on. The over-revoke direction needs no
-- literal registry: 264 pgtap files exercise those functions as
-- `authenticated`, so an over-broad revoke fails in the suite that covers the
-- feature.
--
-- (7) and (8) close the hole (5) cannot. (5) is exactly as complete as the
-- `server_only` fixture, and the fixture is derived from what the repo SAYS —
-- so a new cron routine whose migration simply forgets `authenticated` is in
-- nobody's list and is asserted by nothing. (7) derives its population from
-- `cron.job` instead: a routine pg_cron runs on a schedule is server-only by
-- construction, because cron executes it as `postgres` and needs no grant, and
-- the requirement cannot be removed without unscheduling the job. (8) is (7)'s
-- own control — the same population read a second, independent way — because a
-- name-matching predicate that quietly matched nothing would leave (7) green
-- over an empty set.

begin;

select plan(8);

-- Every `public` non-trigger function an anonymous caller may execute, and the
-- logged-out surface that needs it.
create temporary table anon_callable (fn name, why text);

insert into anon_callable (fn, why) values
  ('browse_public_challenges',        'logged-out challenge discovery'),
  ('challenge_leaderboard',           'public challenge board'),
  ('clip_route_for_viewer',           'public route page geometry'),
  ('clubs_in_bbox',                   'logged-out map discovery'),
  ('confirm_safety_contact_by_token', 'a trusted contact confirms from an emailed link with no account'),
  ('discoverable_routes_in_bbox',     'logged-out map discovery'),
  ('event_next_instance_going_counts','public event page'),
  ('fundraiser_anchor_visible',       'public fundraiser page'),
  ('fundraiser_feed',                 'public fundraiser page'),
  ('fundraiser_totals',               'public fundraiser page'),
  ('get_event_meet_point',            'public event page'),
  ('global_segment_effort_ranks',     'public segment board'),
  ('global_segment_leaderboard',      'public segment board'),
  ('heatmap_points_in_bbox',          'logged-out map discovery'),
  ('is_challenge_visible',            'named by two challenge_participants policies `to public`; anon holds SELECT on that table and a policy expression is privilege-checked against the QUERYING role, so withholding turns an anonymous read into 42501'),
  ('is_event_visible',                'named by the checkpoint_crossings, event_checkpoints and event_pricing SELECT policies, all `to public`'),
  ('is_public_club_by_id',            'named by the public_routes view'),
  ('is_public_event_by_id',           'named by the public_runs view'),
  ('is_public_route_by_id',           'named by the public_runs view'),
  ('latest_race_pings',               'logged-out spectator tracker'),
  ('nearby_routes',                   'logged-out route discovery'),
  ('popular_route_tags',              'logged-out route discovery'),
  ('public_profile_by_id',            '/share/profile and the logged-out /live/[id]'),
  ('public_recap_by_id',              '/share/recap'),
  ('public_run_gear',                 'public run page'),
  ('route_conditions_for_viewer',     'public route page'),
  ('route_markers_for_viewer',        'public route page'),
  ('routes_within_box',               'logged-out map discovery'),
  ('run_engagement_counts',           'public run page'),
  ('search_clubs',                    'logged-out search'),
  ('search_public_events',            'logged-out search'),
  ('search_public_routes',            'logged-out search'),
  ('search_race_listings',            'logged-out search'),
  ('segment_effort_ranks',            'public segment board');

-- The routines this repo STATES are withheld from `authenticated` as well as
-- anon — the cron and job-queue family (20270626000001, and
-- cleanup_stale_rate_limits by 20270625000001), the privacy oracles
-- (20270521_001), the derived-cache refreshers, and the secret deleters. Kept
-- for service_role where an operator or an Edge Function invokes it by hand.
-- pg_cron runs its own as `postgres` and needs no grant at all.
--
-- **This list is derived, not hand-kept**, and
-- `apps/backend/scripts/check_server_only_registry.mjs` is what makes that
-- true: it replays every migration and fails the PR when a routine some
-- migration revokes from `authenticated` is missing here, when a row here
-- names a routine no migration revokes, or when `keeps_service_role`
-- disagrees with the grant the migrations state. It was hand-kept until
-- 20270710, and it had drifted — 42 non-trigger `public` routines carried
-- such a revoke and 26 were listed, two of the sixteen missing
-- (`enqueue_safety_overdue_emails`, `sweep_challenge_completions`) sitting in
-- the very cron family this fixture is the positive control for.
--
-- The derivation reads the migration TEXT and the assertions below read the
-- CATALOGUE, which is the whole point: deriving the list from `proacl` would
-- make (5) assert that routines without the privilege do not have the
-- privilege. `keeps_service_role` comes from the same replay rather than from
-- a catalogue reading, because on the CI image every fresh routine arrives
-- with a service_role entry by name and a `true` read off it would say
-- nothing.
create temporary table server_only (fn name, keeps_service_role boolean);

insert into server_only (fn, keeps_service_role) values
  ('_privacy_downsample', false),
  ('auto_hide_target', false),
  ('award_achievements_for_user', false),
  ('claim_next_job', true),
  ('cleanup_account_deletion_receipts', false),
  ('cleanup_stale_export_blobs', true),
  ('cleanup_stale_live_run_pings', true),
  ('cleanup_stale_race_pings', true),
  ('cleanup_stale_rate_limits', true),
  ('cleanup_stale_user_coach_usage', true),
  ('clear_device_token', true),
  ('clear_push_subscription', true),
  ('clip_track_for_user', true),
  ('cron_schedule_status', true),
  ('defer_job', true),
  ('delete_user_integration_secrets', true),
  ('delete_user_provider_secrets', true),
  ('enforce_create_rate_limit', false),
  ('enqueue_data_export', true),
  ('enqueue_event_reminders', true),
  ('enqueue_export_blob_reap', true),
  ('enqueue_lifecycle_drip', true),
  ('enqueue_safety_overdue_emails', false),
  ('enqueue_weekly_digests', true),
  ('expire_stale_export_jobs', true),
  ('find_failed_jobs', true),
  ('find_stuck_jobs', true),
  ('finish_job', true),
  ('jobs_failed_summary', true),
  ('jobs_stuck_summary', true),
  ('notify_data_export_ready', true),
  ('privacy_aware_route_geom', false),
  ('privacy_aware_start_point', false),
  ('privacy_coarsen_coord', false),
  ('privacy_distance_m', false),
  ('privacy_in_any_zone', false),
  ('recompute_event_ranks', false),
  ('refresh_club_member_count', false),
  ('refresh_gym_workout_totals', false),
  ('refresh_route_run_count', false),
  ('sweep_challenge_completions', false),
  ('try_consume_strava_quota', true);

-- (1) The literal reading. On CI this is the contract in full: a function added
-- without a revoke arrives anon-granted by name and lands here.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where p.prorettype <> 'trigger'::regtype
      and has_function_privilege('anon', p.oid, 'EXECUTE')
      and p.proname not in (select fn from anon_callable)
      and not exists (select 1 from pg_depend d
                       where d.classid = 'pg_proc'::regclass and d.objid = p.oid
                         and d.deptype = 'e')),
  '',
  'no public function outside the anon_callable list is executable by anon'
);

-- (2) The ACL shape, which is what a drop-and-recreate restores and what a
-- `revoke ... from anon` alone leaves behind on a workstation.
select is(
  (select coalesce(string_agg(p.proname || ' (' || coalesce(p.proacl::text, 'proacl is null') || ')', ', ' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where p.prorettype <> 'trigger'::regtype
      and p.proname not in (select fn from anon_callable)
      and not exists (select 1 from pg_depend d
                       where d.classid = 'pg_proc'::regclass and d.objid = p.oid
                         and d.deptype = 'e')
      and (p.proacl is null
           or exists (select 1 from aclexplode(p.proacl) a
                       where a.privilege_type = 'EXECUTE'
                         and (a.grantee = 0 or a.grantee = 'anon'::regrole)))),
  '',
  'no public function outside the list carries a PUBLIC or anon EXECUTE entry'
);

-- (3) The positive control for (1) and (2): revoking anon from everything
-- would satisfy both while 42501-ing every logged-out page in the app.
select is(
  (select coalesce(string_agg(w.fn, ', ' order by w.fn), '')
     from anon_callable w
     join pg_proc p on p.proname = w.fn
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where not has_function_privilege('anon', p.oid, 'EXECUTE')),
  '',
  'every function on the anon_callable list is still executable by anon'
);

-- (4) Why (1) and (2) may skip trigger-returning functions: Postgres refuses
-- the call before privileges are consulted, so the 67 that still carry the
-- image default are unreachable even by the role that holds EXECUTE on them.
-- `clubs_member_count_trigger` is one of those 67, asserted as anon.
set local role anon;
select throws_ok(
  $$select clubs_member_count_trigger()$$,
  '0A000',
  null,
  'a trigger function anon HOLDS execute on is still not callable directly'
);
reset role;

-- (5) The half of 20270626000001 that is not about anon at all.
select is(
  (select coalesce(string_agg(s.fn, ', ' order by s.fn), '')
     from server_only s
     join pg_proc p on p.proname = s.fn
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  '',
  'no cron or job-queue function is executable by a signed-in account'
);

-- (6) And the control on (5): service_role keeps the operator hook.
select is(
  (select coalesce(string_agg(s.fn, ', ' order by s.fn), '')
     from server_only s
     join pg_proc p on p.proname = s.fn
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where s.keeps_service_role
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')),
  '',
  'each server-only function service_role was kept for is still executable by it'
);


-- (7) Every `public` routine pg_cron runs on a schedule is withheld from BOTH
-- client roles. Derived from `cron.job`, which is neither the fixture above nor
-- the ACL being graded: a migration that schedules a routine and forgets the
-- revoke lands here, and the only way to make the requirement go away is to
-- stop scheduling the job.
select is(
  (select coalesce(string_agg(p.proname || ' (' || r.role || ')', ', ' order by p.proname, r.role), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
     cross join (values ('anon'::name), ('authenticated'::name)) r(role)
    where p.prorettype <> 'trigger'::regtype
      and exists (select 1 from cron.job j
                   where j.command ~ ('\m' || p.proname || '\M\s*\('))
      and has_function_privilege(r.role, p.oid, 'EXECUTE')),
  '',
  'no scheduled function is executable by anon or by a signed-in account');

-- (8) The control on (7). Its predicate walks every `public` routine name
-- against every cron command; if that ever matched nothing — a regex flavour
-- change, an empty `cron.job` on some image — (7) would pass over an empty set
-- and report a contract it never checked. This reads the same population from
-- the other end, per JOB rather than per routine: every scheduled command of
-- the form `select <fn>()` naming a `public` routine must be one (7) found.
-- The captured name is lowercased and this reader is case-insensitive where
-- (7)'s `~` is not, deliberately: a command written `SELECT ENQUEUE_...()`
-- names a routine (7) silently skips, and a control that skipped it too would
-- agree with (7) about a function neither of them had looked at.
select is(
  (select coalesce(string_agg(c.fn, ', ' order by c.fn), '')
     from cron.job j
     cross join lateral (select lower((regexp_match(j.command, '^\s*select\s+(?:public\.)?([a-z_0-9]+)\s*\(', 'i'))[1]) as fn) c
    where c.fn is not null
      and exists (select 1 from pg_proc p
                   join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
                  where p.proname = c.fn and p.prorettype <> 'trigger'::regtype)
      and not exists (select 1 from pg_proc p
                       join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
                      where p.proname = c.fn
                        and p.prorettype <> 'trigger'::regtype
                        and exists (select 1 from cron.job k
                                     where k.command ~ ('\m' || p.proname || '\M\s*\(')))),
  '',
  'and the scheduled set (7) reads is the same one the schedule itself names');

select * from finish();
rollback;
