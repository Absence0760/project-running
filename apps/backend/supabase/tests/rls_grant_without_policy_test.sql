-- Backstop for the intentional anon/authenticated DML grant matrix
-- (migration 20270408_001). That migration hands broad table-level
-- INSERT/UPDATE/DELETE to anon/authenticated on many tables (app_admins,
-- achievements, account_deletion_receipts, challenge_badges,
-- personal_records, public_recaps, runs, …). This is INERT today because
-- every one of those tables also enables RLS with only auth.uid()-scoped
-- permissive policies — Postgres denies all rows when no permissive
-- policy is satisfiable for the role, so the grant reaches nothing.
--
-- The grant matrix is deliberate (it mirrors Supabase's default posture
-- and is the source of truth that restores prod after default-privileges
-- drift — see the migration header). So the invariant here is NOT "no
-- table has a DML grant without a policy" (that intentional state would
-- fail today). It is the load-bearing safety-net check: no table that
-- carries an anon/authenticated DML grant may also carry a permissive
-- RLS policy that is TRIVIALLY SATISFIABLE for that role. A future
-- `create policy … to anon using (true)` (or `with check (true)`, or a
-- `for all … using (true)`) added to a granted table would immediately
-- turn the standing grant live and make those rows anon-writable /
-- anon-readable. This test fails the moment such a policy lands.
--
-- Detecting "satisfiable for anon" in full generality is undecidable in
-- SQL, so this uses the tractable, high-value heuristic the audit calls
-- for: flag a policy whose governing predicate is the literal `true`.
-- Empirically (verified against this Postgres) the predicate NULL is the
-- OPPOSITE of dangerous — a USING/WITH-CHECK that is absent denies all
-- rows (a SELECT/DELETE policy with no USING returns zero rows; an INSERT
-- policy with no WITH CHECK rejects every insert) — so only the literal
-- `true` is flagged, never NULL. The write side coalesces WITH CHECK onto
-- USING to mirror Postgres's own default (a `for all … using (true)` has
-- a NULL with_check but still authorises inserts via the USING).
--
-- Current policies are all (select auth.uid())-scoped, so the offender
-- list is empty today; it becomes non-empty on the regression above.

begin;

select plan(1);

select is(
  (select coalesce(string_agg(
            g.tablename || '.' || p.policyname || ' (' || p.cmd || '/' || g.role || ')',
            ', ' order by g.tablename, p.policyname, g.role), '')
   from (
     -- (table, role) pairs where an app role holds a real DML grant — the
     -- standing safety net whose only remaining gate is RLS satisfiability.
     select c.oid as reloid, c.relname as tablename, r.role
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
       cross join (values ('anon'::name), ('authenticated'::name)) r(role)
      where c.relkind = 'r'
        and c.relrowsecurity
        and (has_table_privilege(r.role, c.oid, 'INSERT')
          or has_table_privilege(r.role, c.oid, 'UPDATE')
          or has_table_privilege(r.role, c.oid, 'DELETE'))
   ) g
   join (
     select p.tablename, p.policyname, p.cmd, p.qual, p.with_check,
            unnest(case when 'public' = any(p.roles)
                        then array['anon','authenticated']::name[]
                        else p.roles end) as role
       from pg_policies p
      where p.schemaname = 'public'
        and p.permissive = 'PERMISSIVE'
   ) p
     on p.tablename = g.tablename and p.role = g.role
   -- Trivially-true on either the USING side (row reachability for
   -- SELECT/UPDATE/DELETE) or the write side (coalesce WITH CHECK onto
   -- USING for INSERT/UPDATE/ALL). Parens + case are normalised away.
   where lower(btrim(btrim(p.qual), '()')) = 'true'
      or lower(btrim(btrim(coalesce(p.with_check, p.qual)), '()')) = 'true'),
  '',
  'no table carrying an anon/authenticated DML grant has a permissive RLS '
  'policy with a trivially-true (literal `true`) USING/WITH CHECK — such a '
  'policy would turn the standing grant live and make the table '
  'anon-writable; scope every policy to (select auth.uid()) instead'
);

select * from finish();
rollback;
