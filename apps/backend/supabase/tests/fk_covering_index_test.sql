-- Pins migration 20270417_001 (FK covering indexes). Catch-all over
-- pg_constraint: every foreign key on a public-schema table must have an
-- index whose leading columns cover the FK columns (Supabase performance
-- advisor lint 0001) — without one, deleting/updating a referenced parent
-- row seq-scans the child table, which the delete-account cascade pays on
-- every child of auth.users. The failure message names the offenders.

begin;

select plan(1);

select is(
  (select coalesce(string_agg(
     c.conrelid::regclass || '(' || (
       select string_agg(a.attname, ',' order by x.n)
       from unnest(c.conkey) with ordinality x(attnum, n)
       join pg_attribute a on a.attrelid = c.conrelid and a.attnum = x.attnum
     ) || ')', ', ' order by c.conrelid::regclass::text), '')
   from pg_constraint c
   join pg_class t on t.oid = c.conrelid
   join pg_namespace n on n.oid = t.relnamespace
   where c.contype = 'f' and n.nspname = 'public'
     and not exists (
       select 1 from pg_index i
       where i.indrelid = c.conrelid
         and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] = c.conkey
     )),
  '',
  'every public-schema foreign key has a covering index — an unindexed FK '
  'seq-scans the child table on every parent delete/update'
);

select * from finish();
rollback;
