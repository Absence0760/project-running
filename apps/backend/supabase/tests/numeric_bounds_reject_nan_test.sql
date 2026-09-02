-- A catch-all: every single-column numeric CHECK in the public schema is
-- EVALUATED against NaN, and against Infinity where the column's own type can
-- hold one.
--
-- `'NaN'::numeric >= 0` is TRUE, and so is the float8 form — Postgres orders
-- NaN above every real value rather than making a comparison with it unknown.
-- A one-sided bound written as `col >= 0` therefore says nothing about NaN,
-- which is how 26 constraints across eleven tables came to admit one
-- (migration 20270704000002). A two-sided bound is immune for free, because
-- its upper edge is the half NaN fails.
--
-- This test does not read the SQL and agree that it looks right. It pulls each
-- constraint's own `pg_get_expr` body out of the catalogue, substitutes the
-- column for the literal, and executes it — so a bound added tomorrow in the
-- one-sided shape fails here rather than joining the list quietly, and a bound
-- whose wording nobody anticipated is still measured by what it DOES.
--
-- Two rules, because an expression is only evaluable when every column it
-- names is substituted:
--
--   1. Every SINGLE-column numeric CHECK must reject NaN (and Infinity where
--      the type admits one). That is the evaluable set.
--   2. Every numeric column that appears in a MULTI-column CHECK must also
--      carry a single-column CHECK, so rule 1 reaches it — or be named in
--      MULTI_COLUMN_EXEMPT below with the reason its bound cannot be written
--      one column at a time. `segments.end_distance_m` failed this rule before
--      20270704000002: `end > start` and `end - start >= 100` are both TRUE
--      for a NaN end against a real start, so the pair constraints did not
--      stand in for a bound of its own.
--
-- Scope, stated so it is not over-read: this asks whether a bound that EXISTS
-- actually bounds. It says nothing about the numeric columns in the schema
-- that carry no CHECK at all — that is a separate, per-column question about
-- what each one's honest range is, filed in followups.md.

begin;

select plan(6);

-- ── the sweep, as a function so the operator can be validated with it ───────
-- `pg_temp` keeps it out of the catalogue every other suite reads.
create function pg_temp.sweep_numeric_bounds()
returns table (tbl text, conname text, attname text, typ text,
               def text, admits_nan boolean, admits_inf boolean)
language plpgsql as $fn$
declare
  r record;
  res boolean;
  cast_suffix text;
  inf_reachable boolean;
begin
  for r in
    select c.conrelid::regclass::text as tbl, c.conname, a.attname,
           format_type(a.atttypid, a.atttypmod) as typ,
           pg_get_expr(c.conbin, c.conrelid) as def
    from pg_constraint c
    join pg_attribute a
      on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
    where c.contype = 'c'
      and c.connamespace = 'public'::regnamespace
      and array_length(c.conkey, 1) = 1
      and a.atttypid in ('numeric'::regtype, 'float8'::regtype, 'float4'::regtype)
  loop
    tbl := r.tbl; conname := r.conname; attname := r.attname;
    typ := r.typ; def := r.def;
    cast_suffix := case when r.typ like 'double%' then '::float8'
                        when r.typ like 'real%' then '::float4'
                        else '::numeric' end;
    -- The typmod decides whether an infinity is reachable at all: a
    -- numeric(p, s) refuses one with a 22003 field overflow before any CHECK
    -- is consulted, so a term excluding it there would be dead code.
    inf_reachable := (r.typ = 'numeric' or r.typ like 'double%' or r.typ like 'real%');
    begin
      execute format('select (%s)',
        regexp_replace(r.def, '\m' || r.attname || '\M',
                       quote_literal('NaN') || cast_suffix, 'g')) into res;
      admits_nan := coalesce(res, true);
    exception when others then
      -- An expression the substitution cannot evaluate is not evidence of
      -- safety. Record it as an admission so it has to be looked at.
      admits_nan := true;
    end;
    admits_inf := false;
    if inf_reachable then
      begin
        execute format('select (%s)',
          regexp_replace(r.def, '\m' || r.attname || '\M',
                         quote_literal('Infinity') || cast_suffix, 'g')) into res;
        admits_inf := coalesce(res, true);
      exception when others then
        admits_inf := true;
      end;
    end if;
    return next;
  end loop;
end $fn$;

-- ── operator validation: the sweep must be able to say "admits" ─────────────
-- A sweep that reported nothing would satisfy every emptiness assertion below
-- for free. Plant a constraint of exactly the shape this test exists to catch
-- and require the sweep to name it, before asking it about the real schema.
-- The table lives inside the test's own transaction and rolls back with it.
create table public.nan_bound_probe (v numeric check (v >= 0));

select is(
  (select string_agg(tbl || '.' || attname, ',')
     from pg_temp.sweep_numeric_bounds()
    where tbl = 'nan_bound_probe' and admits_nan and admits_inf),
  'nan_bound_probe.v',
  'the sweep names a bare `>= 0` numeric bound as admitting NaN and Infinity'
);

drop table public.nan_bound_probe;

create temporary table numeric_bound_results as
  select * from pg_temp.sweep_numeric_bounds();

-- ── population floors ───────────────────────────────────────────────────────
select cmp_ok(
  (select count(*)::int from numeric_bound_results), '>=', 40,
  'the sweep evaluated the single-column numeric CHECK constraints it audits'
);
select cmp_ok(
  (select count(distinct tbl)::int from numeric_bound_results), '>=', 12,
  'and they span the tables that carry numeric bounds, not one'
);

-- ── rule 1: no single-column numeric bound admits a non-finite value ────────
select is(
  (select coalesce(string_agg(tbl || '.' || attname || ' (' || conname || ')', ', '
                              order by tbl, attname), '')
     from numeric_bound_results where admits_nan),
  '',
  'no single-column numeric CHECK in the public schema admits NaN'
);

select is(
  (select coalesce(string_agg(tbl || '.' || attname || ' (' || conname || ')', ', '
                              order by tbl, attname), '')
     from numeric_bound_results where admits_inf),
  '',
  'no single-column numeric CHECK on an infinity-capable column admits Infinity'
);

-- ── rule 2: a multi-column bound does not stand in for a single-column one ──
select is(
  (select coalesce(string_agg(tbl || '.' || attname, ', ' order by tbl, attname), '')
     from (
       select distinct c.conrelid::regclass::text as tbl, a.attname
       from pg_constraint c
       join pg_attribute a
         on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
       where c.contype = 'c'
         and c.connamespace = 'public'::regnamespace
         and array_length(c.conkey, 1) > 1
         and a.atttypid in ('numeric'::regtype, 'float8'::regtype, 'float4'::regtype)
         and not exists (
           select 1
           from pg_constraint s
           join pg_attribute sa
             on sa.attrelid = s.conrelid and sa.attnum = any (s.conkey)
           where s.contype = 'c'
             and s.conrelid = c.conrelid
             and array_length(s.conkey, 1) = 1
             and sa.attname = a.attname
         )
         -- MULTI_COLUMN_EXEMPT. challenges.goal_value's bound is inherently
         -- window-relative (a streak_days goal is graded against the length of
         -- its own window), so it cannot be written one column at a time. Its
         -- finiteness terms are asserted directly, by value, in
         -- challenge_goal_check_test.sql.
         and not (c.conrelid = 'public.challenges'::regclass and a.attname = 'goal_value')
     ) q),
  '',
  'every numeric column in a multi-column CHECK also carries a single-column one'
);

select * from finish();
rollback;
