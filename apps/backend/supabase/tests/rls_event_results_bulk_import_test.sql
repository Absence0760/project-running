-- Pins the account-optional bulk-import surface from
-- 20261028_001_event_results_account_optional.sql (persona #43).
--
-- Coverage:
--   1. A club's event-organiser (here the owner) CAN insert a bib-only
--      result (user_id NULL, bib + finisher_name set) on their event —
--      the new organiser INSERT policy.
--   2. The rerank trigger ranks bib-only finishers alongside everyone
--      else (two finishers → ranks 1 and 2 by ascending duration).
--   3. A plain member (not an organiser) CANNOT insert a bib-only row —
--      the organiser policy doesn't admit them and the self-insert
--      policy needs auth.uid() = user_id, which a NULL user_id fails.
--   4. The identity CHECK rejects a row with neither an account nor a
--      bib + name (no anonymous ghost rows).
--   5. The bib UNIQUE constraint rejects a duplicate bib on the same
--      (event, instance) — re-import idempotency arbiter.

begin;

select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000043a1', 'authenticated', 'authenticated',
   'director@evt.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000043a2', 'authenticated', 'authenticated',
   'member@evt.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('43434343-4343-4343-4343-434343434301',
   '00000000-0000-0000-0000-0000000043a1', 'Bib Import Club', 'bib-import-c', true);

-- enroll_club_owner_trigger seeds the owner's club_members row; only the
-- plain member needs an explicit insert.
insert into club_members (club_id, user_id, role, status)
values
  ('43434343-4343-4343-4343-434343434301',
   '00000000-0000-0000-0000-0000000043a2', 'member', 'active');

insert into events (id, club_id, title, starts_at, created_by)
values
  ('43434343-4343-4343-4343-434343434311',
   '43434343-4343-4343-4343-434343434301', 'Charity 10k',
   '2026-06-06 09:00+00', '00000000-0000-0000-0000-0000000043a1');

-- ── Organiser (club owner) bulk-imports two bib-only finishers ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000043a1","role":"authenticated"}';

-- 1. Organiser CAN insert a bib-only result.
do $$
begin
  insert into event_results (event_id, instance_start, bib, finisher_name,
                             duration_s, distance_m)
  values ('43434343-4343-4343-4343-434343434311', '2026-06-06 09:00+00',
          '101', 'Alice Anon', 2400, 10000),
         ('43434343-4343-4343-4343-434343434311', '2026-06-06 09:00+00',
          '102', 'Bob Bibonly', 2700, 10000);
end $$;
select pass('event-organiser can INSERT bib-only results (user_id NULL) on their event');

-- 2. Rerank trigger ranks bib-only finishers by ascending duration.
set local role service_role;
select results_eq(
  $$ select bib, rank from event_results
     where event_id = '43434343-4343-4343-4343-434343434311'
       and instance_start = '2026-06-06 09:00+00'
     order by rank $$,
  $$ values ('101'::text, 1), ('102'::text, 2) $$,
  'bib-only finishers are ranked alongside account finishers (1, 2 by duration)'
);

-- 3. Plain member cannot plant a bib-only result.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000043a2","role":"authenticated"}';
select throws_ok(
  $$ insert into event_results (event_id, instance_start, bib, finisher_name,
                                duration_s, distance_m)
     values ('43434343-4343-4343-4343-434343434311', '2026-06-06 09:00+00',
             '103', 'Mallory', 3000, 10000) $$,
  '42501',
  null,
  'a non-organiser member cannot INSERT a bib-only result'
);

-- 4. Identity CHECK: a row with neither account nor bib+name is rejected.
set local role service_role;
select throws_ok(
  $$ insert into event_results (event_id, instance_start,
                                duration_s, distance_m)
     values ('43434343-4343-4343-4343-434343434311', '2026-06-06 09:00+00',
             1800, 10000) $$,
  '23514',
  null,
  'a row identifying neither an account nor a bib+name is rejected by the identity CHECK'
);

-- 5. bib UNIQUE: duplicate bib on the same (event, instance) is rejected.
select throws_ok(
  $$ insert into event_results (event_id, instance_start, bib, finisher_name,
                                duration_s, distance_m)
     values ('43434343-4343-4343-4343-434343434311', '2026-06-06 09:00+00',
             '101', 'Alice Again', 2500, 10000) $$,
  '23505',
  null,
  'a duplicate bib on the same (event, instance) is rejected by event_results_bib_uniq'
);

select * from finish();

rollback;
