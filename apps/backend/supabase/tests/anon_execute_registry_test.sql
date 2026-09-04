-- Class guard for EXECUTE on `public` functions: the rule that makes a
-- withholding statement portable, and the four withholdings that depend on it.
--
-- Every function in `public` is owned by `postgres`, and what a fresh one's ACL
-- says depends on the Postgres image the schema is running on:
--
--   * Supabase Cloud, and CI (`supabase/setup-cli` pinned to 2.84.2), carry an
--     `alter default privileges` for `postgres` granting EXECUTE to anon,
--     authenticated and service_role. A function arrives with those three BY
--     NAME, and `revoke ... from public` removes nothing.
--   * The workstation's current CLI (2.109.1) ships an image whose `postgres`
--     default ACL is `{postgres=X/postgres}`; a fresh function comes up with
--     `proacl` NULL — Postgres's built-in owner+PUBLIC default — so there
--     `revoke ... from public` withholds and `revoke ... from anon` does not.
--
-- Two shipped suites are the evidence: `coach_roster_summary_test` expects an
-- anon caller to reach the body of a function revoked only `from public` and be
-- refused BY THE BODY, and `donations_status_lock_test` calls `fundraiser_totals`
-- as service_role, which no migration granted. Both pass on CI and fail here.
--
-- So neither single-grantee revoke is portable and only naming BOTH is.
-- Assertions (4)-(6) pin that rule against whichever image is running, so an
-- image change is a loud failure here rather than a silent re-reading of every
-- `revoke` in the tree. Assertions (1)-(3) pin the four withholdings
-- 20270625000001 made, in a form that survives either image.
--
-- Assertions (7)-(8) are the same registry read the other way round: the
-- routines a named role must be able to CALL, whose grant is therefore the
-- migration's job to state rather than the image's to supply. Note what (7)-(8)
-- can and cannot see: on an image whose default privileges hand out EXECUTE by
-- name they hold whether or not a migration said anything, so it is the
-- workstation image — where `proacl` is exactly `{postgres}` plus what was
-- stated — that makes them bite.
--
-- So the `stated` table below is a THIRD RAIL, not a local fixture:
-- `apps/backend/scripts/check_stated_function_grants.mjs` parses these same
-- rows out of this file and replays the migration TEXT to prove each grant is
-- stated, which bites on every image and needs no database at all. Editing a
-- row here changes what that guard demands, and the guard refuses outright
-- rather than passing if it cannot parse a row.
--
-- What is NOT here is deliberate. The guard DERIVES the far larger part of the
-- obligation from the call sites — every RPC name the web, Lambda, api_client
-- and mobile trees call must carry a stated `authenticated` grant, and every
-- one the Edge Functions and the Go worker call must carry a stated
-- `service_role` one — so a routine with an app caller needs no row. This table
-- carries only the pairs no source tree names: `fundraiser_totals`, whose
-- service_role caller is a pgtap file, and `host_can_take_payment`, which the
-- guard would derive anyway and which is registered because the round that
-- granted it wanted the reason recorded beside the other.

begin;

select plan(9);

create temporary table withheld (fn name, args text, kept name, why text);

insert into withheld (fn, args, kept, why) values
  ('enqueue_run_rematch',        'uuid',                            'authenticated',
   '20260612_001 wrote `revoke ... from anon` alone under "Authed users only"; on an image where the grant arrives via PUBLIC that statement withholds nothing'),
  ('segment_leaderboard_tiered', 'uuid, text, text, integer, uuid', 'authenticated',
   '20260830_001 dropped the anon grant as an audit fix; 20261022_001 changed the signature, and drop-and-recreate reset the ACL to the image default'),
  ('cleanup_stale_rate_limits',  '',                                'service_role',
   'SECURITY DEFINER, body is an unqualified DELETE on rate_limits — an anonymous call cleared every stale rate-limit window'),
  ('refresh_gym_workout_totals', 'uuid',                            null,
   'SECURITY DEFINER write to gym_workouts for any workout id; its only caller is the definer trigger gym_sets_maintain_totals, which evaluates it as the owner');

-- (1) anon cannot execute any of them. The plain reading of the contract.
select is(
  (select coalesce(string_agg(w.fn, ', ' order by w.fn), '')
     from withheld w
     join pg_proc p on p.proname = w.fn
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where has_function_privilege('anon', p.oid, 'EXECUTE')),
  '',
  'anon cannot execute any function 20270625000001 withheld'
);

-- (2) And the ACL carries neither a PUBLIC entry nor an anon entry — which is
-- the assertion that survives a drop-and-recreate. A recreate hands the
-- function back the image default: a PUBLIC grant on one image, an explicit
-- anon grant on the other. Testing only (1) would catch the second and not the
-- first on the image where `proacl` comes back NULL.
select is(
  (select coalesce(string_agg(w.fn || ' (' || coalesce(p.proacl::text, 'proacl is null — the built-in owner+PUBLIC default') || ')', ', ' order by w.fn), '')
     from withheld w
     join pg_proc p on p.proname = w.fn
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where p.proacl is null
       or exists (select 1 from aclexplode(p.proacl) a
                   where a.privilege_type = 'EXECUTE'
                     and (a.grantee = 0 or a.grantee = 'anon'::regrole))),
  '',
  'no withheld function carries a PUBLIC or anon EXECUTE entry — a later '
  'drop-and-recreate would restore one and fail here'
);

-- (3) The positive control for (1) and (2). Without it, revoking EXECUTE from
-- every role would score as a clean pass while breaking the operator hook, the
-- leaderboard and the cron sweep.
select is(
  (select coalesce(string_agg(w.fn || ' (' || w.kept || ')', ', ' order by w.fn), '')
     from withheld w
     join pg_proc p on p.proname = w.fn
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where w.kept is not null
      and not has_function_privilege(w.kept, p.oid, 'EXECUTE')),
  '',
  'each withheld function is still executable by the role it was kept for'
);

-- (4)-(6) The rule itself, against this image. `zz_pub` is withheld from PUBLIC
-- only, `zz_anon` from anon only, `zz_both` from both.
create function public.zz_grant_probe_pub() returns integer language sql immutable as $p$ select 1 $p$;
create function public.zz_grant_probe_anon() returns integer language sql immutable as $p$ select 1 $p$;
create function public.zz_grant_probe_both() returns integer language sql immutable as $p$ select 1 $p$;

select ok(
  has_function_privilege('anon', 'public.zz_grant_probe_both()', 'EXECUTE'),
  'a function created in `public` is anon-EXECUTE-able before any grant '
  'statement — which is why withholding one is the migration''s job'
);

revoke execute on function public.zz_grant_probe_pub() from public;
revoke execute on function public.zz_grant_probe_anon() from anon;

select ok(
  has_function_privilege('anon', 'public.zz_grant_probe_pub()', 'EXECUTE')
  or has_function_privilege('anon', 'public.zz_grant_probe_anon()', 'EXECUTE'),
  'at least one single-grantee revoke leaves anon holding EXECUTE — which one '
  'depends on the image, so neither `from public` nor `from anon` alone is a '
  'withholding this schema may rely on'
);

revoke execute on function public.zz_grant_probe_both() from public, anon;

select ok(
  not has_function_privilege('anon', 'public.zz_grant_probe_both()', 'EXECUTE'),
  'naming both PUBLIC and anon withholds the function on either image — the '
  'house form, and the form 20270625000001 uses'
);

-- (7)-(8) The mirror of (1)-(3): the routines a named role must be able to
-- call, registered so the grant is the repo's statement and not the image's
-- default. Its sibling `fundraiser_feed` is deliberately absent — see
-- 20270707000001 for why it is not granted service_role for symmetry, and
-- check_stated_function_grants.mjs for what now catches the day it acquires a
-- server-side caller.
create temporary table stated (fn name, args text, caller name, why text);

insert into stated (fn, args, caller, why) values
  ('fundraiser_totals', 'uuid', 'service_role',
   '20270213_001 revoked from public and granted anon + authenticated only, so on an image whose default ACL is {postgres} the thermometer read is refused to the role that writes the ledger; donations_status_lock_test reads it as service_role'),
  ('host_can_take_payment', 'uuid', 'service_role',
   '20261229_001 granted authenticated only; donations-checkout and events-checkout both call it on a service-role client to decide whether a host may take payment at all, so on an image whose default ACL is {postgres} every checkout refuses a host who can. Granted by 20270708000001');

select is(
  (select coalesce(string_agg(t.fn || ' (' || t.caller || ')', ', ' order by t.fn), '')
     from stated t
     join pg_proc p on p.proname = t.fn
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where pg_catalog.oidvectortypes(p.proargtypes) = t.args
      and not has_function_privilege(t.caller, p.oid, 'EXECUTE')),
  '',
  'each registered routine is executable by the role that calls it'
);

-- (8) And by a grant naming that role, not through PUBLIC and not through a
-- NULL proacl. This is what separates a stated grant from an inherited one on
-- the image that can tell them apart.
select is(
  (select coalesce(string_agg(t.fn || ' (' || coalesce(p.proacl::text, 'proacl is null') || ')', ', ' order by t.fn), '')
     from stated t
     join pg_proc p on p.proname = t.fn
     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where pg_catalog.oidvectortypes(p.proargtypes) = t.args
      and (p.proacl is null
           or not exists (select 1 from aclexplode(p.proacl) a
                           where a.privilege_type = 'EXECUTE'
                             and a.grantee = t.caller::regrole))),
  '',
  'each registered routine carries an EXECUTE entry naming that role, so the '
  'grant survives an image whose default privileges supply nothing'
);

-- (9) The control for (7) and (8), and the reason this file plans nine.
-- Both are aggregates over the join, so a row that matches NO routine is
-- reported as no failure rather than as a row that could not be checked -- the
-- shape decisions § 741 names. That is not hypothetical: the join was written
-- `pg_get_function_identity_arguments(p.oid) = t.args`, which renders a named
-- parameter as `p_fundraiser_id uuid` against a registry that says `uuid`, so
-- it matched nothing on EITHER image and (7)-(8) asserted over an empty set
-- from the day they were added. `oidvectortypes` renders the type list alone,
-- which is what the registry carries and what a `grant execute on function
-- f(uuid)` statement names.
select is(
  (select coalesce(string_agg(t.fn || '(' || t.args || ')', ', ' order by t.fn), '')
     from stated t
    where (select count(*)
             from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
            where p.proname = t.fn
              and pg_catalog.oidvectortypes(p.proargtypes) = t.args) <> 1),
  '',
  'each registered routine resolves to exactly one function in public, so '
  '(7) and (8) are asserting about something'
);

select * from finish();
rollback;
