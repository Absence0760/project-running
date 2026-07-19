-- user_profiles.display_name rejects control characters (migration
-- 20270423_001, issue #375). display_name flows into the Subject of the
-- safety-contact emails the app relays to third parties; a CR/LF in the name
-- is an SMTP/MIME header injection. The Go mailer strips control chars by
-- construction; this CHECK is the write-boundary second layer. Proves a plain
-- name is accepted, a newline/carriage-return is rejected with 23514, and NULL
-- stays allowed.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-000037500001', 'authenticated', 'authenticated',
        'a@375.local', '', now(), now());

-- A plain display_name is accepted.
select lives_ok($$
  insert into user_profiles (id, display_name)
  values ('00000000-0000-0000-0000-000037500001', 'Ada Lovelace')
$$, 'a plain display_name is accepted');

-- A newline (the header-injection payload) is rejected (23514 check_violation).
select throws_ok($$
  update user_profiles set display_name = E'Ada\nBcc: evil@example.com'
  where id = '00000000-0000-0000-0000-000037500001'
$$, '23514', null, 'a display_name containing a newline is rejected');

-- A carriage return is rejected too.
select throws_ok($$
  update user_profiles set display_name = E'Ada\rBcc: evil@example.com'
  where id = '00000000-0000-0000-0000-000037500001'
$$, '23514', null, 'a display_name containing a carriage return is rejected');

-- NULL stays allowed — display_name is optional.
select lives_ok($$
  update user_profiles set display_name = null
  where id = '00000000-0000-0000-0000-000037500001'
$$, 'a NULL display_name is accepted');

select * from finish();

rollback;
