-- Pin the trigram GIN indexes behind every leading-wildcard ILIKE search RPC
-- (20270316_001). Each search function's OR predicate needs EVERY branch's
-- column trgm-indexed or the whole predicate falls back to a seq scan — so this
-- asserts by (table, column, gin_trgm_ops), not by index name, and fails the
-- moment any branch loses its index. Also pins the absence of routes_name_search:
-- a tsvector GIN index cannot serve ILIKE, and its presence reads as "route
-- search is already indexed" to the next person.

begin;

select plan(9);

create or replace function pg_temp.has_trgm_gin_index(
  tbl text, col text
) returns boolean language sql stable as $fn$
  select exists (
    select 1
    from pg_index ix
    join pg_class t on t.oid = ix.indrelid
    join pg_class i on i.oid = ix.indexrelid
    join pg_am am on am.oid = i.relam
    join pg_opclass oc on oc.oid = ix.indclass[0]
    where t.relnamespace = 'public'::regnamespace
      and t.relname = tbl
      and am.amname = 'gin'
      and oc.opcname = 'gin_trgm_ops'
      and (select attname from pg_attribute
           where attrelid = t.oid and attnum = ix.indkey[0]) = col
  );
$fn$;

select ok(
  pg_temp.has_trgm_gin_index('user_profiles', 'display_name'),
  'user_profiles.display_name has a trgm GIN index (search_user_profiles)'
);

select ok(
  pg_temp.has_trgm_gin_index('routes', 'name'),
  'routes.name has a trgm GIN index (search_public_routes)'
);

select ok(
  pg_temp.has_trgm_gin_index('clubs', 'name'),
  'clubs.name has a trgm GIN index (search_clubs)'
);

select ok(
  pg_temp.has_trgm_gin_index('clubs', 'location_label'),
  'clubs.location_label has a trgm GIN index (search_clubs OR branch)'
);

select ok(
  pg_temp.has_trgm_gin_index('challenges', 'title'),
  'challenges.title has a trgm GIN index (browse_public_challenges)'
);

select ok(
  pg_temp.has_trgm_gin_index('challenges', 'description'),
  'challenges.description has a trgm GIN index (browse_public_challenges OR branch)'
);

select ok(
  pg_temp.has_trgm_gin_index('events', 'discipline'),
  'events.discipline has a trgm GIN index (search_public_events)'
);

select ok(
  pg_temp.has_trgm_gin_index('events', 'title'),
  'events.title has a trgm GIN index (search_public_events OR branch)'
);

select ok(
  not exists (
    select 1 from pg_class c
    where c.relname = 'routes_name_search'
      and c.relnamespace = 'public'::regnamespace
  ),
  'dead tsvector index routes_name_search stays dropped (cannot serve ILIKE)'
);

select * from finish();

rollback;
