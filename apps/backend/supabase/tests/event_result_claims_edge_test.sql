-- Edge cases for the bib-result claim flow (20261030_001, persona #43)
-- kept separate from event_result_claims_test.sql so each scenario has
-- clean fixtures rather than threading off the happy-path mutations.
--
-- Coverage:
--   1. Re-requesting after a rejection re-opens the claim to 'pending'.
--   2. A user who can't see the event (private club, non-member) is refused.
--   3. Approval is refused if the claimant has recorded their own result for
--      the instance since claiming (the approve-time re-check — guards the
--      claim-then-self-submit race).

begin;
select plan(3);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000043ed01', 'authenticated', 'authenticated', 'dir@edge.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000043ed02', 'authenticated', 'authenticated', 'claimant@edge.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000043ed03', 'authenticated', 'authenticated', 'outsider@edge.local', '', now(), now());

set local role service_role;

-- A PRIVATE club + event + bib-only result.
insert into clubs (id, owner_id, name, slug, is_public)
values ('43ed0000-0000-0000-0000-0000000000c1',
        '00000000-0000-0000-0000-00000043ed01', 'Edge Club', 'edge-club', false);
insert into club_members (club_id, user_id, role, status) values
  ('43ed0000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000043ed02', 'member', 'active');

insert into events (id, club_id, title, starts_at, author_id)
values ('43ed0000-0000-0000-0000-00000000e111',
        '43ed0000-0000-0000-0000-0000000000c1', 'Edge 10k',
        '2026-06-06 09:00+00', '00000000-0000-0000-0000-00000043ed01');

insert into event_results (id, event_id, instance_start, bib, finisher_name, duration_s, distance_m)
values ('ed000000-0000-0000-0000-0000000000b1',
        '43ed0000-0000-0000-0000-00000000e111', '2026-06-06 09:00+00',
        '201', 'Edge Anon', 2400, 10000);

-- ── 1. Re-open after reject ──
-- Member claims, organiser rejects, member re-claims → pending again.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000043ed02","role":"authenticated"}';
select claim_event_result('ed000000-0000-0000-0000-0000000000b1');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000043ed01","role":"authenticated"}';
do $$
declare v_id uuid;
begin
  select id into v_id from event_result_claims
    where result_id = 'ed000000-0000-0000-0000-0000000000b1'
      and claimant_id = '00000000-0000-0000-0000-00000043ed02';
  perform decide_event_result_claim(v_id, false);
end $$;

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000043ed02","role":"authenticated"}';
select claim_event_result('ed000000-0000-0000-0000-0000000000b1');

set local role service_role;
select is(
  (select status from event_result_claims
   where result_id = 'ed000000-0000-0000-0000-0000000000b1'
     and claimant_id = '00000000-0000-0000-0000-00000043ed02'),
  'pending',
  're-requesting after a rejection re-opens the claim to pending');

-- ── 2. Outsider (not a member of the private club) cannot claim ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000043ed03","role":"authenticated"}';
select throws_ok(
  $$ select claim_event_result('ed000000-0000-0000-0000-0000000000b1') $$,
  'Not authorised to claim this result',
  'a non-member cannot claim a result on a private club event they cannot see');

-- ── 3. Approve-time guard: claimant self-submits after claiming ──
-- Insert a claim directly (service role) for the claimant, then give them
-- their own result for the instance, then have the organiser try to approve.
set local role service_role;
insert into event_results (id, event_id, instance_start, user_id, duration_s, distance_m)
values ('ed000000-0000-0000-0000-0000000000b2',
        '43ed0000-0000-0000-0000-00000000e111', '2026-06-06 09:00+00',
        '00000000-0000-0000-0000-00000043ed02', 2500, 10000);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000043ed01","role":"authenticated"}';
select throws_ok(
  $$ select decide_event_result_claim(
       (select id from event_result_claims
        where result_id = 'ed000000-0000-0000-0000-0000000000b1'
          and claimant_id = '00000000-0000-0000-0000-00000043ed02'), true) $$,
  'The claimant already has a result for this event',
  'approval is refused when the claimant has since recorded their own result');

select * from finish();
rollback;
