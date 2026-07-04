-- Pins migration 20270326_001: search_public_routes' per-sort-mode branches
-- return exactly the ordering the old CASE-wrapped ORDER BY produced —
-- including the nulls-last placement on featured_at, the nulls-last "newest"
-- vs nulls-first unknown-sort split on a null created_at, and the created_at
-- tie-break on equal run_count — plus the row-visibility semantics
-- (is_public, shadow_hidden) and the three partial indexes each branch
-- needs to be index-servable.
--
-- Every reference query below carries the OLD body's literal CASE ORDER BY
-- so a future re-emit of the function can't drift the ordering unnoticed.
-- The fixture tag scopes both sides to these rows only, so seed.sql rows
-- can't introduce cross-query tie ambiguity.

begin;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000326aa', 'authenticated', 'authenticated',
   'owner@sort.local', '', now(), now());

insert into routes
  (id, user_id, name, waypoints, distance_m, is_public, tags,
   run_count, created_at, is_featured, featured_at, shadow_hidden)
values
  ('03260326-0326-0326-0326-0326032603a1', '00000000-0000-0000-0000-0000000326aa',
   'Sort A1', '[]'::jsonb, 5000, true, array['sorttest0326'],
   10, '2026-01-01T00:00:00Z', false, null, false),
  ('03260326-0326-0326-0326-0326032603a2', '00000000-0000-0000-0000-0000000326aa',
   'Sort A2', '[]'::jsonb, 5000, true, array['sorttest0326'],
   10, '2026-02-01T00:00:00Z', true, '2026-01-05T00:00:00Z', false),
  ('03260326-0326-0326-0326-0326032603a3', '00000000-0000-0000-0000-0000000326aa',
   'Sort A3', '[]'::jsonb, 5000, true, array['sorttest0326'],
   5, '2026-03-01T00:00:00Z', true, '2026-01-06T00:00:00Z', false),
  ('03260326-0326-0326-0326-0326032603a4', '00000000-0000-0000-0000-0000000326aa',
   'Sort A4', '[]'::jsonb, 5000, true, array['sorttest0326'],
   0, '2026-04-01T00:00:00Z', false, null, false),
  ('03260326-0326-0326-0326-0326032603a5', '00000000-0000-0000-0000-0000000326aa',
   'Sort A5', '[]'::jsonb, 5000, true, array['sorttest0326'],
   0, null, false, null, false),
  ('03260326-0326-0326-0326-0326032603a6', '00000000-0000-0000-0000-0000000326aa',
   'Sort A6 shadow', '[]'::jsonb, 5000, true, array['sorttest0326'],
   99, '2026-06-01T00:00:00Z', false, null, true),
  ('03260326-0326-0326-0326-0326032603a7', '00000000-0000-0000-0000-0000000326aa',
   'Sort A7 private', '[]'::jsonb, 5000, false, array['sorttest0326'],
   98, '2026-06-02T00:00:00Z', false, null, false);

select results_eq(
  $q$ select id from search_public_routes(
        p_tags => array['sorttest0326'], p_sort => 'popular') $q$,
  $q$ select id from public_routes
      where tags && array['sorttest0326']
      order by
        case when 'popular' = 'popular' then run_count end desc nulls last,
        case when 'popular' = 'featured' then featured_at end desc nulls last,
        case when 'popular' = 'newest' then created_at end desc nulls last,
        created_at desc
      limit 50 offset 0 $q$,
  'popular matches the old CASE ordering');

select results_eq(
  $q$ select id from search_public_routes(
        p_tags => array['sorttest0326'], p_sort => 'featured') $q$,
  $q$ select id from public_routes
      where tags && array['sorttest0326']
      order by
        case when 'featured' = 'popular' then run_count end desc nulls last,
        case when 'featured' = 'featured' then featured_at end desc nulls last,
        case when 'featured' = 'newest' then created_at end desc nulls last,
        created_at desc
      limit 50 offset 0 $q$,
  'featured matches the old CASE ordering');

select results_eq(
  $q$ select id from search_public_routes(
        p_tags => array['sorttest0326'], p_sort => 'newest') $q$,
  $q$ select id from public_routes
      where tags && array['sorttest0326']
      order by
        case when 'newest' = 'popular' then run_count end desc nulls last,
        case when 'newest' = 'featured' then featured_at end desc nulls last,
        case when 'newest' = 'newest' then created_at end desc nulls last,
        created_at desc
      limit 50 offset 0 $q$,
  'newest matches the old CASE ordering');

select results_eq(
  $q$ select id from search_public_routes(
        p_tags => array['sorttest0326'], p_sort => 'bogus') $q$,
  $q$ select id from public_routes
      where tags && array['sorttest0326']
      order by
        case when 'bogus' = 'popular' then run_count end desc nulls last,
        case when 'bogus' = 'featured' then featured_at end desc nulls last,
        case when 'bogus' = 'newest' then created_at end desc nulls last,
        created_at desc
      limit 50 offset 0 $q$,
  'an unrecognised sort matches the old trailing created_at arm');

select results_eq(
  $q$ select id from search_public_routes(
        p_tags => array['sorttest0326'], p_sort => 'popular') $q$,
  array[
    '03260326-0326-0326-0326-0326032603a2',
    '03260326-0326-0326-0326-0326032603a1',
    '03260326-0326-0326-0326-0326032603a3',
    '03260326-0326-0326-0326-0326032603a5',
    '03260326-0326-0326-0326-0326032603a4'
  ]::uuid[],
  'popular: run_count desc, equal counts tie-broken created_at desc (nulls first)');

select results_eq(
  $q$ select id from search_public_routes(
        p_tags => array['sorttest0326'], p_sort => 'featured') $q$,
  array[
    '03260326-0326-0326-0326-0326032603a3',
    '03260326-0326-0326-0326-0326032603a2',
    '03260326-0326-0326-0326-0326032603a5',
    '03260326-0326-0326-0326-0326032603a4',
    '03260326-0326-0326-0326-0326032603a1'
  ]::uuid[],
  'featured: featured_at desc with the non-featured nulls trailing by created_at desc');

select results_eq(
  $q$ select id from search_public_routes(
        p_tags => array['sorttest0326'], p_sort => 'newest') $q$,
  array[
    '03260326-0326-0326-0326-0326032603a4',
    '03260326-0326-0326-0326-0326032603a3',
    '03260326-0326-0326-0326-0326032603a2',
    '03260326-0326-0326-0326-0326032603a1',
    '03260326-0326-0326-0326-0326032603a5'
  ]::uuid[],
  'newest: created_at desc with the null created_at row LAST (old CASE-arm nulls last)');

select results_eq(
  $q$ select id from search_public_routes(
        p_tags => array['sorttest0326'], p_sort => 'popular',
        p_limit => 2, p_offset => 1) $q$,
  array[
    '03260326-0326-0326-0326-0326032603a1',
    '03260326-0326-0326-0326-0326032603a3'
  ]::uuid[],
  'limit/offset still page the branch-ordered result');

select ok(
  not exists (
    select 1 from search_public_routes(p_tags => array['sorttest0326'])
    where id in ('03260326-0326-0326-0326-0326032603a6',
                 '03260326-0326-0326-0326-0326032603a7')
  ),
  'shadow-hidden and private routes stay invisible through every branch');

select ok(
  has_function_privilege(
    'anon',
    'search_public_routes(text,numeric,numeric,text,text[],boolean,text,int,int)',
    'execute'),
  'anon keeps EXECUTE across the re-emit');

select ok(
  exists (select 1 from pg_indexes
          where schemaname = 'public'
            and indexname in ('routes_public_popular_sort',
                              'routes_public_featured_sort',
                              'routes_public_newest_sort')
          having count(*) = 3),
  'the three per-branch partial sort indexes exist');

select ok(
  (select count(*) = 3 from pg_indexes
   where indexname in ('routes_public_popular_sort',
                       'routes_public_featured_sort',
                       'routes_public_newest_sort')
     and indexdef like '%is_public = true%'
     and indexdef like '%shadow_hidden = false%'),
  'each sort index is partial on the public_routes visibility predicate');

select * from finish();

rollback;
