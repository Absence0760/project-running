-- Pins migration 20261220_001 — search_clubs must project the FULL clubs
-- rowtype. The function `returns setof clubs` with an explicit column list
-- (it can't `select c.*` because invite_token is grant-redacted). When
-- 20261023_001 added clubs.requires_activity_waiver, the function was left
-- one column short and threw 42P13 ("Final statement returns too few
-- columns") at call time. This pins both the no-throw and the new column's
-- value so the next clubs column-add that forgets the function fails the
-- cheap pgtap job instead of only the api_client integration suite.

begin;
select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'sc@search.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public, requires_activity_waiver)
values ('cccccccc-0000-0000-0000-0000000000e1',
        'aaaaaaaa-0000-0000-0000-0000000000c1', 'Search Club', 'search-club', true, true);

-- Call as the owner so RLS visibility is unambiguous — the 42P13 the test
-- guards against is a function-body type mismatch, independent of the caller.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated"}';

select lives_ok(
  $$ select * from search_clubs(null) $$,
  'search_clubs executes without a return-type mismatch (42P13)');

select is(
  (select count(*)::int from search_clubs(null)
   where id = 'cccccccc-0000-0000-0000-0000000000e1'),
  1,
  'search_clubs returns the public club');

select is(
  (select requires_activity_waiver from search_clubs(null)
   where id = 'cccccccc-0000-0000-0000-0000000000e1'),
  true,
  'search_clubs projects clubs.requires_activity_waiver (added by 20261023_001)');

select * from finish();
rollback;
