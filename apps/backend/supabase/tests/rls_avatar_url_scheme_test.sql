-- Pin the avatar_url scheme CHECK constraints from migration
-- 20260808_001_avatar_url_scheme_check.sql.
--
-- Pre-fix: `user_profiles.avatar_url` and `clubs.avatar_url` were
-- unconstrained `text`. Today every render path uses them as
-- `<img src={avatar_url}>` (modern browsers refuse `javascript:` in
-- img-src), but a future surface that renders the same value in an
-- `<a href>` context would be immediately exploitable for stored
-- XSS via `javascript:alert(...)`. CHECK enforces `https?:` at the
-- DB layer regardless of which renderer ships next.
--
-- Coverage:
--   1. user_profiles INSERT with javascript: scheme is rejected.
--   2. user_profiles INSERT with valid https: scheme succeeds.
--   3. user_profiles UPDATE flipping a row to javascript: is rejected.
--   4. clubs INSERT with javascript: scheme is rejected.
--   5. NULL avatar_url is allowed (the column is optional).

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'av1@local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated',
   'av2@local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000000a3', 'authenticated', 'authenticated',
   'av3@local', '', now(), now());

set local role service_role;

-- 1. javascript: scheme rejected on user_profiles INSERT.
select throws_ok(
  $$ insert into user_profiles (id, display_name, avatar_url)
     values ('00000000-0000-0000-0000-0000000000a1',
             'Av1', 'javascript:alert(1)') $$,
  '23514',
  null,
  'user_profiles.avatar_url rejects javascript: scheme'
);

-- 2. https: scheme on user_profiles INSERT succeeds.
do $$
begin
  insert into user_profiles (id, display_name, avatar_url)
  values ('00000000-0000-0000-0000-0000000000a2',
          'Av2', 'https://avatar.example.com/me.png');
end $$;
select pass('user_profiles.avatar_url accepts https: scheme');

-- 3. UPDATE flipping to javascript: is rejected.
select throws_ok(
  $$ update user_profiles
       set avatar_url = 'javascript:alert(1)'
     where id = '00000000-0000-0000-0000-0000000000a2' $$,
  '23514',
  null,
  'user_profiles.avatar_url UPDATE rejects javascript: scheme'
);

-- 4. clubs INSERT with javascript: rejected.
select throws_ok(
  $$ insert into clubs (id, owner_id, name, slug, is_public, avatar_url)
     values ('66666666-6666-6666-6666-666666666601',
             '00000000-0000-0000-0000-0000000000a2',
             'Bad Avatar Club', 'bad-avatar-club', true,
             'javascript:alert(1)') $$,
  '23514',
  null,
  'clubs.avatar_url rejects javascript: scheme'
);

-- 5. NULL avatar_url is allowed (optional column).
do $$
begin
  insert into user_profiles (id, display_name, avatar_url)
  values ('00000000-0000-0000-0000-0000000000a3',
          'Av3', null);
end $$;
select pass('user_profiles.avatar_url allows NULL');

select * from finish();

rollback;
