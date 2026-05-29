-- Pins the bib-result claim flow from 20261030_001 (persona #43 follow-up).
-- Organiser-approve trust model: a registered runner requests to claim a
-- bib-only imported result; the event organiser approves, which attaches the
-- account to the row and auto-rejects competing claims.
--
-- Coverage:
--   1. A member can claim a bib-only result on an event they can see.
--   2. The claim_event_result RPC refuses a row that already has an account.
--   3. A claimant who already holds a result for the instance is refused.
--   4. A non-organiser cannot decide a claim.
--   5. Organiser approval attaches the account (event_results.user_id set)
--      and marks the claim approved.
--   6. A competing pending claim on the same row is auto-rejected on approval.

begin;
select plan(7);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000004300c1', 'authenticated', 'authenticated', 'dir@claim.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000004300c2', 'authenticated', 'authenticated', 'alice@claim.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000004300c3', 'authenticated', 'authenticated', 'mallory@claim.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000004300c4', 'authenticated', 'authenticated', 'self@claim.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('43c00000-0000-0000-0000-0000000000c1',
        '00000000-0000-0000-0000-0000004300c1', 'Claim Club', 'claim-club', true);
insert into club_members (club_id, user_id, role, status) values
  ('43c00000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000004300c2', 'member', 'active'),
  ('43c00000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000004300c4', 'member', 'active');

insert into events (id, club_id, title, starts_at, created_by)
values ('43c00000-0000-0000-0000-00000000e111',
        '43c00000-0000-0000-0000-0000000000c1', 'Claim 10k',
        '2026-06-06 09:00+00', '00000000-0000-0000-0000-0000004300c1');

-- A bib-only imported finisher, an account-attributed finisher, and a row
-- the "self" user will already own.
insert into event_results (id, event_id, instance_start, bib, finisher_name, duration_s, distance_m)
values ('e5000000-0000-0000-0000-0000000000b1',
        '43c00000-0000-0000-0000-00000000e111', '2026-06-06 09:00+00',
        '101', 'Alice Anon', 2400, 10000);
insert into event_results (id, event_id, instance_start, user_id, duration_s, distance_m)
values ('e5000000-0000-0000-0000-0000000000b2',
        '43c00000-0000-0000-0000-00000000e111', '2026-06-06 09:00+00',
        '00000000-0000-0000-0000-0000004300c4', 2500, 10000);

-- 2. Cannot claim a row that already has an account.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000004300c2","role":"authenticated"}';
select throws_ok(
  $$ select claim_event_result('e5000000-0000-0000-0000-0000000000b2') $$,
  'This result already belongs to an account',
  'claiming an account-owned result is refused');

-- 3. A user who already has a result for the instance cannot claim a bib row.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000004300c4","role":"authenticated"}';
select throws_ok(
  $$ select claim_event_result('e5000000-0000-0000-0000-0000000000b1') $$,
  'You already have a result for this event',
  'a user who already finished this event cannot claim a bib row');

-- 1. Alice (member, no existing result) can claim the bib-only row.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000004300c2","role":"authenticated"}';
select lives_ok(
  $$ select claim_event_result('e5000000-0000-0000-0000-0000000000b1') $$,
  'a member can claim a bib-only result on a visible event');

-- Mallory also claims the same bib (competing claim).
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000004300c3","role":"authenticated"}';
select lives_ok(
  $$ select claim_event_result('e5000000-0000-0000-0000-0000000000b1') $$,
  'a second user can also claim the same bib (organiser adjudicates)');

-- 4. A non-organiser cannot decide a claim. Mallory tries to self-approve
--    her own (RLS-visible) claim — organiser-gate must still reject her.
select throws_ok(
  $$ select decide_event_result_claim(
       (select id from event_result_claims
        where result_id = 'e5000000-0000-0000-0000-0000000000b1'
          and claimant_id = '00000000-0000-0000-0000-0000004300c3'), true) $$,
  'Not authorised to decide claims for this event',
  'a non-organiser cannot decide a claim (even their own)');

-- 5 + 6. Organiser approves Alice's claim → row attaches to Alice, and
-- Mallory's competing claim is auto-rejected.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000004300c1","role":"authenticated"}';
do $$
declare v_alice uuid;
begin
  select id into v_alice from event_result_claims
    where result_id = 'e5000000-0000-0000-0000-0000000000b1'
      and claimant_id = '00000000-0000-0000-0000-0000004300c2';
  perform decide_event_result_claim(v_alice, true);
end $$;

set local role service_role;
select is(
  (select user_id from event_results where id = 'e5000000-0000-0000-0000-0000000000b1'),
  '00000000-0000-0000-0000-0000004300c2'::uuid,
  'approval attaches the claimant account to the result row');
select is(
  (select status from event_result_claims
   where result_id = 'e5000000-0000-0000-0000-0000000000b1'
     and claimant_id = '00000000-0000-0000-0000-0000004300c3'),
  'rejected',
  'a competing pending claim is auto-rejected on approval');

select * from finish();
rollback;
