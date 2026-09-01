-- No view or materialized view in `public` hands a client a write verb.
--
-- Every grant registry in this suite filters `relkind in ('r','p')` — the
-- write lockdown registry, the read lockdown registry, and the role-grant
-- matrix all do — so a view is outside all three by construction. That would
-- be harmless if a view were read-only, and it is not: a single-FROM
-- no-aggregate view is AUTO-UPDATABLE, and nine of the twelve views here are
-- deliberately NOT `security_invoker` (20260626_001 states the choice for
-- `public_runs`), so they execute as their owner — `postgres`, which has
-- BYPASSRLS. An INSERT/UPDATE/DELETE grant reaching `anon` on `public_runs`
-- therefore writes into `runs` past every policy on it.
--
-- The `revoke all ... grant select` pair each strip migration re-emits
-- (20270627000001:89, 20270628000001:89) is what keeps that from happening,
-- and re-emitting it by hand on every re-creation is exactly the shape that
-- goes wrong once. `activities_view_windowed_test` pins one verb on one view;
-- this is the class.

begin;

select plan(4);

-- (1) The population is real. An empty view set would satisfy (3) for free,
-- and this suite's registries have shipped that failure before.
select cmp_ok(
  (select count(*)::int from pg_class c
     join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where c.relkind in ('v', 'm')),
  '>=', 12,
  'the public schema still carries the view set this guard is about');

-- (2) Positive control: the client roles really do read through these views,
-- so an empty write set below is a withholding rather than a role that holds
-- nothing anywhere. Every view named here is a client read path.
select is(
  (select coalesce(string_agg(t.name || ' (' || t.role || ')', ', ' order by t.name, t.role), '')
     from (values
             ('public_runs', 'anon'), ('public_runs', 'authenticated'),
             ('public_routes', 'anon'), ('public_routes', 'authenticated'),
             ('public_profiles', 'authenticated'), ('activities', 'authenticated')
          ) t(name, role)
    where not has_table_privilege(t.role::name, ('public.' || t.name)::regclass, 'SELECT')),
  '',
  'anon and authenticated still read the public views — the write set below is a withholding, not an empty grant table');

-- (3) The class itself.
select is(
  (select coalesce(string_agg(c.relname || ' (' || r.role || ', ' || v.verb || ')',
                              ', ' order by c.relname, r.role, v.verb), '')
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
     cross join (values ('anon'::name), ('authenticated'::name)) r(role)
     cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES')) v(verb)
    where c.relkind in ('v', 'm')
      and has_table_privilege(r.role, c.oid, v.verb)),
  '',
  'no client role holds a write verb on any public view — an auto-updatable owner-executing view writes into its base table past RLS');

-- (4) The reason (3) matters is that most of these views run as their owner
-- rather than as the caller. If that ever stops being true the risk model has
-- changed and this file should be re-read, so it is measured rather than
-- assumed.
select cmp_ok(
  (select count(*)::int from pg_class c
     join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where c.relkind in ('v', 'm')
      and not coalesce(array_to_string(c.reloptions, ',') like '%security_invoker=%', false)),
  '>=', 1,
  'at least one public view still executes as its owner rather than as the caller');

select * from finish();

rollback;
