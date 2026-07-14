-- Pins migration 20270416_001 (RLS initplan wrap). Catch-all over
-- pg_policies: no policy expression may call auth.uid() / auth.jwt() /
-- auth.role() / current_setting() bare — a bare call is re-evaluated per
-- scanned row, where the (select ...) wrap is hoisted into a
-- once-per-statement InitPlan (Supabase performance advisor lint 0003). In
-- deparsed policy text a wrapped call reads 'SELECT auth.uid() AS uid' (or
-- 'SELECT current_setting(...'), so stripping the wrapped forms first
-- leaves only bare calls behind. The failure message names the offenders.

begin;

select plan(1);

select is(
  (select coalesce(
     string_agg(distinct p.schemaname || '.' || p.tablename || ':' || p.policyname, ', '), '')
   from pg_policies p
   where p.schemaname in ('public', 'storage')
     and replace(replace(replace(replace(
           coalesce(p.qual, '') || ' | ' || coalesce(p.with_check, ''),
           'SELECT auth.uid() AS uid', ''),
           'SELECT auth.jwt() AS jwt', ''),
           'SELECT auth.role() AS role', ''),
           'SELECT current_setting(', '')
         ~ 'auth\.(uid|jwt|role)\(\)|current_setting\('),
  '',
  'no RLS policy calls auth.uid()/auth.jwt()/auth.role()/current_setting() '
  'bare — wrap it as (select ...) so it evaluates once per statement, not '
  'per row'
);

select * from finish();
rollback;
