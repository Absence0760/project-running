-- Transactional subscription emails: the AFTER UPDATE trigger on
-- user_profiles enqueues pro_welcome on a purchase and payment_failed on a
-- billing issue, recurs on re-subscribe, and stays quiet on renewal / clear
-- (migration 20261203_001_subscription_emails.sql).
--
-- Runs as the default pgtap role (session_user=postgres, no JWT role), which
-- the lock_subscription_columns guard (20261112_001) treats as trusted
-- direct SQL — so these UPDATEs are allowed, same as the RevenueCat webhook's
-- service-role writes.

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01', 'authenticated', 'authenticated',
        'sub@sub.local', '', now(), now());
insert into user_profiles (id, age_confirmed_at, terms_accepted_at, preferred_unit, subscription_tier)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01', now(), now(), 'km', 'free');

-- 1. free → pro enqueues a pro_welcome.
update user_profiles set subscription_tier = 'pro'
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01';
select is(
  (select count(*)::int from jobs
   where kind = 'lifecycle_email'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01'
     and payload->>'template' = 'pro_welcome'),
  1, 'free → pro enqueues a pro_welcome');

-- 2. Renewal (pro → pro, no transition) does NOT re-enqueue.
update user_profiles set subscription_tier = 'pro'
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01';
select is(
  (select count(*)::int from jobs
   where kind = 'lifecycle_email'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01'
     and payload->>'template' = 'pro_welcome'),
  1, 'renewal (pro → pro) does not re-enqueue pro_welcome');

-- 3. billing_issue_at null → non-null enqueues a payment_failed.
update user_profiles set billing_issue_at = now()
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01';
select is(
  (select count(*)::int from jobs
   where kind = 'lifecycle_email'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01'
     and payload->>'template' = 'payment_failed'),
  1, 'a new billing issue enqueues a payment_failed');

-- 4. Clearing billing_issue_at (resolved on next renewal) does NOT enqueue.
update user_profiles set billing_issue_at = null
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01';
select is(
  (select count(*)::int from jobs
   where kind = 'lifecycle_email'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01'
     and payload->>'template' = 'payment_failed'),
  1, 'clearing billing_issue_at does not enqueue another payment_failed');

-- 5. Downgrade then re-subscribe enqueues a SECOND pro_welcome (recurring —
--    not deduped by the once-per-user log).
update user_profiles set subscription_tier = 'free'
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01';
update user_profiles set subscription_tier = 'pro'
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01';
select is(
  (select count(*)::int from jobs
   where kind = 'lifecycle_email'
     and payload->>'user_id' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabe01'
     and payload->>'template' = 'pro_welcome'),
  2, 're-subscribe enqueues a second pro_welcome (recurring transactional)');

select * from finish();

rollback;
