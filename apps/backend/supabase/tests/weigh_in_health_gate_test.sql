-- The SQL half of the Art 9 weigh-in gate (migration 20270201_001,
-- decisions §150) — the half `apps/web/src/lib/runs/weigh_in_flag.ts` and
-- `apps/mobile_android/lib/weigh_in_flag.dart` both call "the client half of a
-- defence-in-depth pair, not the sole guard", and that neither of those
-- suites can see.
--
-- checkpoint_crossings_test already pins the INSERT branch for
-- `body_weight_kg`, all three ways. Two things it does not say, and a
-- fail-closed special-category gate has to say both:
--
--   1. The OTHER three health columns. `body_weight_pct` and `medical_note`
--      fail the same way `body_weight_kg` does, but `medical_hold` is `not
--      null default false`, so its closed-gate answer is `false` rather than
--      NULL — a supplied `true` has to be actively discarded rather than
--      merely not written, and nothing measured that it is.
--
--   2. The MERGE branch. Every fixture in that suite creates a NEW crossing,
--      so the `else cc.<col>` arms of the UPDATE — the ones that decide what a
--      SECOND volunteer's write does to a crossing that already exists — had
--      never run at all. Both directions matter and they fail in opposite
--      ways: a gate-closed merge that WRITES collects health data without
--      consent, and a gate-closed merge that ERASES destroys a reading the
--      runner did consent to. The RPC is the sole writer (there is no
--      INSERT/UPDATE policy on the table), so this branch is the whole of
--      what a re-scan, a correction, or a second aid-station volunteer does.
--
-- Every merge assertion is preceded by one proving the merge actually MERGED
-- — one row, and the out_time the second call carried — because "the health
-- columns did not change" is also what a call that silently inserted a second
-- row, or matched no identity at all, would leave behind.

begin;

select plan(11);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000009e1a1', 'authenticated', 'authenticated',
   'director@wig.local', '', now(), now());

set local role service_role;

insert into clubs (id, owner_id, name, slug, is_public)
values ('09e10101-0101-0101-0101-010101010101',
        '00000000-0000-0000-0000-00000009e1a1', 'Weigh Club', 'wig-club', true);

insert into events (id, club_id, title, starts_at, author_id)
values ('09e10101-0101-0101-0101-010101010111',
        '09e10101-0101-0101-0101-010101010101', 'Canyon 100',
        '2026-06-06 06:00+00', '00000000-0000-0000-0000-00000009e1a1');

-- Three checkpoints: one that does not weigh, one that does, and one created
-- WITHOUT naming `requires_weigh_in` at all — the shape a checkpoint editor
-- that has never heard of the flag produces.
insert into event_checkpoints (id, event_id, name, ordinal, requires_weigh_in, created_by)
values
  ('09e10101-0101-0101-0101-0101010101c1',
   '09e10101-0101-0101-0101-010101010111', 'Aid 1', 1, false,
   '00000000-0000-0000-0000-00000009e1a1'),
  ('09e10101-0101-0101-0101-0101010101c2',
   '09e10101-0101-0101-0101-010101010111', 'Weigh Station', 2, true,
   '00000000-0000-0000-0000-00000009e1a1');

insert into event_checkpoints (id, event_id, name, ordinal, created_by)
values ('09e10101-0101-0101-0101-0101010101c3',
        '09e10101-0101-0101-0101-010101010111', 'Unstated', 3,
        '00000000-0000-0000-0000-00000009e1a1');

select is(
  (select requires_weigh_in from event_checkpoints
    where id = '09e10101-0101-0101-0101-0101010101c3'),
  false,
  'requires_weigh_in defaults to false — a checkpoint that never named the flag does not weigh');

-- ── 1. the INSERT branch, all four health columns ──────────────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-00000009e1a1","role":"authenticated"}';

-- (a) consent WITHOUT requires_weigh_in.
select upsert_checkpoint_crossing(
  '09e10101-0101-0101-0101-010101010111',
  '09e10101-0101-0101-0101-0101010101c1',
  '2026-06-06 06:00+00',
  null, '800', 'Gwen NoWeigh',
  '2026-06-06 10:00+00', null,
  true, 64.5, -3.2, true, 'looked rough at the top');

-- (b) requires_weigh_in WITHOUT consent.
select upsert_checkpoint_crossing(
  '09e10101-0101-0101-0101-010101010111',
  '09e10101-0101-0101-0101-0101010101c2',
  '2026-06-06 06:00+00',
  null, '801', 'Hank NoConsent',
  '2026-06-06 11:00+00', null,
  false, 70.0, -4.1, true, 'declined the weigh-in');

-- (c) both.
select upsert_checkpoint_crossing(
  '09e10101-0101-0101-0101-010101010111',
  '09e10101-0101-0101-0101-0101010101c2',
  '2026-06-06 06:00+00',
  null, '802', 'Ivy Consents',
  '2026-06-06 11:05+00', null,
  true, 58.25, -2.0, true, 'monitor at the next station');

-- (d) consent at the checkpoint that never named the flag.
select upsert_checkpoint_crossing(
  '09e10101-0101-0101-0101-010101010111',
  '09e10101-0101-0101-0101-0101010101c3',
  '2026-06-06 06:00+00',
  null, '803', 'Jo Unstated',
  '2026-06-06 12:00+00', null,
  true, 61.0, -1.5, true, 'unstated checkpoint');

set local role service_role;

select results_eq(
  $$ select body_weight_kg, body_weight_pct, medical_hold, medical_note
       from checkpoint_crossings where bib = '800' $$,
  $$ values (null::numeric, null::numeric, false, null::text) $$,
  'consent without requires_weigh_in drops every health column, and the '
  'not-null medical_hold lands false rather than the supplied true');

select results_eq(
  $$ select body_weight_kg, body_weight_pct, medical_hold, medical_note
       from checkpoint_crossings where bib = '801' $$,
  $$ values (null::numeric, null::numeric, false, null::text) $$,
  'requires_weigh_in without consent drops every health column');

select results_eq(
  $$ select body_weight_kg, body_weight_pct, medical_hold, medical_note
       from checkpoint_crossings where bib = '802' $$,
  $$ values (58.25::numeric, -2.0::numeric, true, 'monitor at the next station'::text) $$,
  'requires_weigh_in AND consent persists every health column');

select results_eq(
  $$ select body_weight_kg, body_weight_pct, medical_hold, medical_note
       from checkpoint_crossings where bib = '803' $$,
  $$ values (null::numeric, null::numeric, false, null::text) $$,
  'the default is fail-closed in effect, not only in the column: a checkpoint '
  'that never named requires_weigh_in collects nothing even under consent');

-- ── 2. the MERGE branch ────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-00000009e1a1","role":"authenticated"}';

-- (e) a second write onto the gate-closed crossing, this time consenting. The
--     checkpoint still does not weigh, so nothing may be collected.
select upsert_checkpoint_crossing(
  '09e10101-0101-0101-0101-010101010111',
  '09e10101-0101-0101-0101-0101010101c1',
  '2026-06-06 06:00+00',
  null, '800', null,
  null, '2026-06-06 10:20+00',
  true, 63.9, -4.4, true, 'second look');

-- (f) a second write onto the CONSENTED crossing with consent withdrawn — the
--     erase direction. Different values, so an overwrite is distinguishable
--     from a hold.
select upsert_checkpoint_crossing(
  '09e10101-0101-0101-0101-010101010111',
  '09e10101-0101-0101-0101-0101010101c2',
  '2026-06-06 06:00+00',
  null, '802', null,
  null, '2026-06-06 11:30+00',
  false, 99.9, -9.9, false, 'overwritten');

-- (g) a second write onto the no-consent crossing, this time consenting: the
--     gate opens on the merge path too.
select upsert_checkpoint_crossing(
  '09e10101-0101-0101-0101-010101010111',
  '09e10101-0101-0101-0101-0101010101c2',
  '2026-06-06 06:00+00',
  null, '801', null,
  null, '2026-06-06 11:40+00',
  true, 70.0, -4.1, true, 'consented on the way out');

set local role service_role;

select results_eq(
  $$ select count(*)::int, out_time from checkpoint_crossings
      where bib = '800' group by out_time $$,
  $$ values (1, '2026-06-06 10:20+00'::timestamptz) $$,
  'the gate-closed second write MERGED — one row, carrying its out_time');

select results_eq(
  $$ select body_weight_kg, body_weight_pct, medical_hold, medical_note
       from checkpoint_crossings where bib = '800' $$,
  $$ values (null::numeric, null::numeric, false, null::text) $$,
  'a merge under consent onto a checkpoint that does not weigh still collects nothing');

select results_eq(
  $$ select count(*)::int, out_time from checkpoint_crossings
      where bib = '802' group by out_time $$,
  $$ values (1, '2026-06-06 11:30+00'::timestamptz) $$,
  'the consent-withdrawn second write MERGED — one row, carrying its out_time');

select results_eq(
  $$ select body_weight_kg, body_weight_pct, medical_hold, medical_note
       from checkpoint_crossings where bib = '802' $$,
  $$ values (58.25::numeric, -2.0::numeric, true, 'monitor at the next station'::text) $$,
  'a merge without consent neither overwrites nor erases the reading already '
  'taken under it — the else arm holds the stored value, it does not null it');

select results_eq(
  $$ select count(*)::int, out_time from checkpoint_crossings
      where bib = '801' group by out_time $$,
  $$ values (1, '2026-06-06 11:40+00'::timestamptz) $$,
  'the now-consenting second write MERGED — one row, carrying its out_time');

select results_eq(
  $$ select body_weight_kg, body_weight_pct, medical_hold, medical_note
       from checkpoint_crossings where bib = '801' $$,
  $$ values (70.0::numeric, -4.1::numeric, true, 'consented on the way out'::text) $$,
  'the gate opens on the merge path as well as the insert one');

select * from finish();

rollback;
