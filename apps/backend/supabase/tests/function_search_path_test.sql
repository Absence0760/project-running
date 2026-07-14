-- Pins migration 20270415_001 (function search_path pin). Catch-all over
-- pg_proc: EVERY function in the public schema must carry a pinned
-- search_path in proconfig, so a future migration can't ship a function
-- whose unqualified references resolve against the caller's mutable
-- session search_path (Supabase advisor lint 0011). Extension-owned
-- functions are excluded (none live in public today, but an extension
-- update must not fail this suite). The failure message names the
-- offending functions.

begin;

select plan(1);

select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and not exists (
         select 1 from pg_depend d
         where d.objid = p.oid and d.deptype = 'e'
       )
       and not exists (
         select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
         where cfg like 'search_path=%'
       )),
  '',
  'every public-schema function pins search_path — an unpinned function '
  'resolves unqualified references against the caller''s mutable search_path'
);

select * from finish();
rollback;
