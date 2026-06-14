-- Scheme CHECK on the club link columns (migration 20270131_001).
-- A stored non-http(s) URL (javascript:/data:) must be rejected at the DB so
-- it can never reach a rendered anchor — the last line of XSS defence behind
-- client-side validation + rel="noopener noreferrer".

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000dd001', 'authenticated', 'authenticated',
        'club-owner@links.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000dd001","role":"authenticated"}';

-- 1. https website is accepted.
insert into clubs (id, owner_id, name, slug, website_url)
values ('11111111-1111-1111-1111-1111000dd001',
        '00000000-0000-0000-0000-0000000dd001', 'Linked Club', 'linked-club-dd1',
        'https://example.com');
select pass('https website_url is accepted');

-- 2. http instagram is accepted (and a null link is fine).
update clubs set instagram_url = 'http://instagram.com/club'
  where id = '11111111-1111-1111-1111-1111000dd001';
select pass('http instagram_url is accepted');

-- 3. A javascript: scheme is rejected by the CHECK.
select throws_ok(
  $$ update clubs set website_url = 'javascript:alert(1)'
       where id = '11111111-1111-1111-1111-1111000dd001' $$,
  '23514',
  null,
  'javascript: website_url is rejected by the scheme CHECK'
);

-- 4. A data: scheme on a social link is rejected too.
select throws_ok(
  $$ update clubs set facebook_url = 'data:text/html,<script>1</script>'
       where id = '11111111-1111-1111-1111-1111000dd001' $$,
  '23514',
  null,
  'data: facebook_url is rejected by the scheme CHECK'
);

select * from finish();

rollback;
