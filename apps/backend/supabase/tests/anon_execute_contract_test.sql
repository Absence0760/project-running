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
-- hook, which (6) is here to fail on. The rest of the swept set needs no
-- literal registry here: 264 pgtap files exercise those functions as
-- `authenticated`, so an over-broad revoke fails in the suite that covers the
-- feature rather than in a list that has to be maintained twice.

begin;

select plan(6);

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

-- The cron and job-queue family: withheld from anon AND authenticated by
-- 20270626000001 (and cleanup_stale_rate_limits by 20270625000001), kept for
-- service_role where an operator may invoke it by hand. pg_cron runs them as
-- `postgres` and needs no grant at all.
create temporary table server_only (fn name, keeps_service_role boolean);

insert into server_only (fn, keeps_service_role) values
  ('claim_next_job', true), ('finish_job', true), ('defer_job', true),
  ('find_failed_jobs', true), ('find_stuck_jobs', true),
  ('jobs_failed_summary', true), ('jobs_stuck_summary', true),
  ('cron_schedule_status', true),
  ('cleanup_stale_live_run_pings', true), ('cleanup_stale_race_pings', true),
  ('cleanup_stale_user_coach_usage', true), ('cleanup_stale_rate_limits', true),
  ('cleanup_stale_export_blobs', true),
  ('enqueue_event_reminders', true), ('enqueue_lifecycle_drip', true),
  ('enqueue_weekly_digests', true),
  ('clear_device_token', true), ('clear_push_subscription', true),
  ('cleanup_account_deletion_receipts', false),
  ('auto_hide_target', false), ('enforce_create_rate_limit', false),
  ('_privacy_downsample', false), ('privacy_coarsen_coord', false);

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

select * from finish();
rollback;
