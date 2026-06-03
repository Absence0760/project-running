-- Welcome lifecycle email: signup enqueues it, the log is send-once + private
-- (migration 20261202_001_welcome_email.sql).
--
-- Pins: a new user_profiles row (the once-per-user signup insert) enqueues
-- exactly one `lifecycle_email` job with template 'welcome'; the
-- lifecycle_email_log dedup table enforces send-once per (user, template);
-- and the log is not readable by a normal authenticated user (service-role
-- only).

begin;

select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaae01', 'authenticated', 'authenticated',
        'welcome@wel.local', '', now(), now());

-- The once-per-user signup insert (mirrors confirm_age_and_terms()).
insert into user_profiles (id, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaae01', now(), now(), 'km', 'free');

-- 1. Exactly one welcome job for this user.
select is(
  (select count(*)::int from public.jobs
   where kind = 'lifecycle_email'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaae01'
     and payload->>'template' = 'welcome'),
  1, 'a new user_profiles row enqueues exactly one welcome lifecycle_email job');

-- 2. The send-once log is unique per (user, template).
insert into lifecycle_email_log (user_id, template)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaae01', 'welcome');
select throws_ok(
  $$ insert into lifecycle_email_log (user_id, template)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaae01', 'welcome') $$,
  '23505', null,
  'lifecycle_email_log is send-once per (user, template)');

-- 3. RLS: a normal authenticated user can't read the log.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaae01"}';
select is_empty(
  $$ select 1 from lifecycle_email_log $$,
  'lifecycle_email_log is not readable by an authenticated user (RLS deny-all)');

select * from finish();

rollback;
