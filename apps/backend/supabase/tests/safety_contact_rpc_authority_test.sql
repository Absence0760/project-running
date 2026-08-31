-- Who may act on a safety-contact relationship, and from which side.
--
-- decisions § 720 scoped the owner's list read to `owner_id` and § 726 gave
-- the rows it removed their own "you are a safety contact for" section, whose
-- only action is `set_safety_sms_opt_in`. Both entries turn on the same fact:
-- `safety_contacts` has two legitimate parties with different rights over one
-- row, so RLS cannot be what distinguishes them and each definer RPC carries
-- its own party test. Those tests had no negative coverage — every existing
-- assertion calls each RPC as the party it is meant for.
--
-- The consequential one is the SMS consent. `set_safety_sms_opt_in` matches
-- `contact_user_id = auth.uid()`, so the OWNER cannot arm it; an owner who
-- could would be recording a consent to be texted on behalf of the person who
-- would receive the texts. `decline_safety_contact` matches the caller's own
-- email address, so it is the contact's withdrawal and never the owner's
-- removal — the two paths § 720 established must stay distinct.
--
-- Every refusal here is a `false` return rather than a raise, so each is
-- paired with a re-read proving the row did not move.

begin;
select plan(20);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('5afe0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'sca-owner@safe.local', '', now(), now()),
  ('5afe0000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'sca-contact@safe.local', '', now(), now()),
  ('5afe0000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'sca-stranger@safe.local', '', now(), now()),
  ('5afe0000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'sca-owner2@safe.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit)
values ('5afe0000-0000-0000-0000-000000000001', 'Sca Owner', 'km'),
       ('5afe0000-0000-0000-0000-000000000002', 'Sca Contact', 'km'),
       ('5afe0000-0000-0000-0000-000000000003', 'Sca Stranger', 'km'),
       ('5afe0000-0000-0000-0000-000000000004', 'Sca Owner Two', 'km');

-- Two confirmed relationships naming the same contact, plus one still
-- pending. The insert trigger forces every row unconfirmed, so the confirmed
-- state is stamped directly afterwards the way confirm_safety_contact would.
insert into safety_contacts (id, owner_id, contact_email, contact_phone)
values
  ('5afe0000-0000-0000-0000-0000000000c1', '5afe0000-0000-0000-0000-000000000001',
   'sca-contact@safe.local', '+447700900111'),
  ('5afe0000-0000-0000-0000-0000000000c2', '5afe0000-0000-0000-0000-000000000004',
   'sca-contact@safe.local', '+447700900222'),
  ('5afe0000-0000-0000-0000-0000000000c3', '5afe0000-0000-0000-0000-000000000001',
   'sca-stranger@safe.local', '+447700900333');

update safety_contacts
   set confirmed_at = now(), contact_user_id = '5afe0000-0000-0000-0000-000000000002'
 where id in ('5afe0000-0000-0000-0000-0000000000c1',
              '5afe0000-0000-0000-0000-0000000000c2');

-- c3 names the stranger as its contact_user_id but is never confirmed: the
-- caller is the right person and the relationship is not yet real.
update safety_contacts
   set contact_user_id = '5afe0000-0000-0000-0000-000000000003'
 where id = '5afe0000-0000-0000-0000-0000000000c3';

-- ── the SMS consent belongs to the contact, not to the owner ────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-000000000001","role":"authenticated"}';

select is(
  set_safety_sms_opt_in('5afe0000-0000-0000-0000-0000000000c1', true),
  false,
  'the owner cannot arm the SMS consent on their own relationship'
);

set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  set_safety_sms_opt_in('5afe0000-0000-0000-0000-0000000000c1', true),
  false,
  'a stranger cannot arm the SMS consent on somebody else''s relationship'
);

-- A caller with no resolvable identity: auth.uid() is null, so the match is
-- null-safe-false rather than matching every row with a null contact_user_id.
set local "request.jwt.claims" = '{"role":"authenticated"}';

select is(
  set_safety_sms_opt_in('5afe0000-0000-0000-0000-0000000000c1', true),
  false,
  'an unidentifiable caller cannot arm the SMS consent'
);

reset role;
select is(
  (select sms_opt_in_at from safety_contacts
    where id = '5afe0000-0000-0000-0000-0000000000c1'),
  null::timestamptz,
  'none of the three refused calls stamped the consent'
);

-- The named contact of an UNCONFIRMED relationship is still the right person
-- and still cannot arm it: consent to be texted about a relationship you have
-- not accepted is not a consent.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  set_safety_sms_opt_in('5afe0000-0000-0000-0000-0000000000c3', true),
  false,
  'the named contact of an unconfirmed relationship cannot arm the SMS consent'
);

reset role;
select is(
  (select sms_opt_in_at from safety_contacts
    where id = '5afe0000-0000-0000-0000-0000000000c3'),
  null::timestamptz,
  'the unconfirmed relationship stamped nothing'
);

-- Positive control: the confirmed contact can, and the same call withdraws.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  set_safety_sms_opt_in('5afe0000-0000-0000-0000-0000000000c1', true),
  true,
  'the confirmed contact arms their own SMS consent'
);

reset role;
select isnt(
  (select sms_opt_in_at from safety_contacts
    where id = '5afe0000-0000-0000-0000-0000000000c1'),
  null::timestamptz,
  'the contact''s opt-in stamped the consent'
);

select is(
  (select sms_opt_in_at from safety_contacts
    where id = '5afe0000-0000-0000-0000-0000000000c2'),
  null::timestamptz,
  'arming one relationship did not arm the contact''s other one'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  set_safety_sms_opt_in('5afe0000-0000-0000-0000-0000000000c1', false),
  true,
  'the contact withdraws their own SMS consent'
);

reset role;
select is(
  (select sms_opt_in_at from safety_contacts
    where id = '5afe0000-0000-0000-0000-0000000000c1'),
  null::timestamptz,
  'the withdrawal cleared the stamp'
);

-- An id nobody holds is a false, not a raise and not a silent true.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  set_safety_sms_opt_in('5afe0000-0000-0000-0000-0000000000cf', true),
  false,
  'an unknown relationship id reports no row updated'
);

-- ── the contact-of read is scoped, and it is the caller''s whole side ───────
select is(
  (select count(*)::int from safety_contacts where contact_user_id = auth.uid()),
  2,
  'the contact-of read returns both relationships this caller confirmed'
);

-- Asked WITHOUT the client's own scope, so the zero is RLS's answer and not
-- the query's: neither permissive SELECT policy names this caller on c3.
-- refusal: the linked-contact SELECT policy admits only rows naming the caller
select is(
  (select count(*)::int from safety_contacts
    where id = '5afe0000-0000-0000-0000-0000000000c3'),
  0,
  'the contact never sees a relationship naming somebody else as the contact'
);

-- ── withdrawal is decline, and decline is the contact''s verb ───────────────
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-000000000001","role":"authenticated"}';

select is(
  decline_safety_contact('5afe0000-0000-0000-0000-0000000000c1'),
  false,
  'the owner cannot decline their own relationship (removal is the owner''s verb)'
);

set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-000000000003","role":"authenticated"}';

-- A different row from the owner's attempt above, so the two refusals are
-- measured independently rather than the second finding the first's work done.
select is(
  decline_safety_contact('5afe0000-0000-0000-0000-0000000000c2'),
  false,
  'a stranger cannot decline somebody else''s relationship'
);

reset role;
select is(
  (select count(*)::int from safety_contacts
    where id in ('5afe0000-0000-0000-0000-0000000000c1',
                 '5afe0000-0000-0000-0000-0000000000c2')),
  2,
  'neither refused decline removed a relationship'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"5afe0000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  decline_safety_contact('5afe0000-0000-0000-0000-0000000000c1'),
  true,
  'the contact declines the relationship they are named in'
);

reset role;
select is(
  (select count(*)::int from safety_contacts
    where id = '5afe0000-0000-0000-0000-0000000000c1'),
  0,
  'the contact''s decline removed the relationship'
);

select is(
  (select count(*)::int from safety_contacts
    where id = '5afe0000-0000-0000-0000-0000000000c2'),
  1,
  'declining one relationship left the contact''s other one standing'
);

select * from finish();
rollback;
