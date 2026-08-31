-- The exercise grouping key's CASE-folding half stops being the database's
-- opinion (decisions § 830).
--
-- § 790 made the WHITESPACE half provider-independent by naming code points
-- and left this filed: the derivation still opened with a bare `lower()`,
-- whose answer is the collation of its argument. Measured on PG 17.6 over
-- every one of the 1,112,063 assignable code points, calling `lower()` under
-- each collation the stack carries:
--
--   * ICU `en-US` vs libc `en_US.utf8` differ at exactly ONE code point,
--     U+0130 (LATIN CAPITAL LETTER I WITH DOT ABOVE): ICU folds it to
--     `i` + U+0307, libc to a bare `i`.
--   * ICU `en-US` vs ICU `tr-TR` differ at TWO, and one of them is ASCII:
--     `lower('I')` is U+0131 under a Turkish database, so every exercise name
--     carrying a capital I -- "Incline Press" -- would key differently.
--   * ICU `en-US` vs ICU `lt-LT` differ at three (U+00CC, U+00CD, U+0128).
--   * The `C` and `C.utf8` collations fold ASCII and nothing else: 1,406 code
--     points that fold under every other collation are left alone.
--   * Context matters too, which a per-code-point sweep cannot see: ICU
--     applies Unicode's Final_Sigma rule and libc does not, so `lower('ΟΔΟΣ')`
--     ends in U+03C2 on one provider and U+03C3 on the other.
--
-- Naming a case-mapping table the way § 790 named the whitespace class was
-- measured and rejected: `translate()` over the 1,488 code points carrying a
-- non-identity simple lowercase mapping costs 60 us per call against 0.34 us
-- for `lower()` (200,000 calls: 12.0 s against 0.068 s), and the four RPCs
-- re-derive the key once per `gym_sets` row -- ~1.9 s of pure folding on a
-- 15,000-set history, paid hardest by the non-ASCII names the table exists to
-- protect. That cost is only removable by persisting the key on `gym_sets` so
-- nothing re-derives it at read time, which is a change to the shape of the
-- highest-volume gym table and a slice of its own. Filed, not done here.
--
-- Pinning the collation costs nothing and closes the whole of the filed
-- defect. `und-x-icu` is the ICU root locale, present on every ICU-enabled
-- server and carrying no language tailoring by definition, and an explicit
-- COLLATE outranks the argument's own. Re-measured under all six collations
-- above, across every code point and across a 10,031-string context corpus
-- (each cased code point alone, ASCII-flanked, doubled, and followed by a
-- combining acute): zero disagreement, where the old derivation disagreed on
-- 14 / 24 / 10 / 9,849 of those strings under tr-TR / lt-LT / libc / C. Cost:
-- 0.47 us per call against 0.34 us, and unchanged for non-ASCII input.
--
-- What remains, and is filed rather than hidden: the ICU VERSION linked into
-- the server, and the two clients' own case tables, which are neither ICU nor
-- each other. Dart's `toLowerCase()` is Unicode SIMPLE case mapping from an
-- older table and JS's is full mapping from a newer one; measured, they
-- disagree at 466 code points. The two folds named below are the ones
-- reachable in a Latin or Greek exercise name, and naming them puts all three
-- rails on one answer:
--
--   * U+0130 folds to a bare `i` BEFORE the lowercase. That is its Unicode
--     SIMPLE lowercase mapping and what Dart and libc already return, and it
--     is the only 1:many unconditional lowercase mapping in Unicode, so
--     removing it leaves every remaining fold 1:1. Without it a mobile-written
--     `exercise_key` for a name containing U+0130 VIOLATES the CHECK § 790
--     added -- 23514, measured rather than reasoned about.
--   * U+03C2 (final sigma) folds to U+03C3 AFTER. That collapses Final_Sigma
--     in both directions: ICU and JS produce the final form contextually,
--     libc and Dart never do, and a Greek lifter's all-caps spelling would
--     otherwise never meet their lower-case one.
--
-- Lock impact (migration_locks.md): CREATE OR REPLACE FUNCTION locks the
-- pg_proc entry only. The two backfills are batched by primary key behind a
-- predicate matching only rows that already disagree. The CHECK constraints
-- are DROPPED and re-added NOT VALID (both metadata-only, ACCESS EXCLUSIVE for
-- the catalogue update alone) and then VALIDATEd under SHARE UPDATE EXCLUSIVE.
-- Re-adding is what re-proves them: the constraint EXPRESSION is unchanged, so
-- Postgres leaves `convalidated` true when the function underneath it moves,
-- and every stored row would then carry an unverified claim.

create or replace function public.normalise_exercise_name(p_name text)
returns text
language sql
immutable
parallel safe
returns null on null input
set search_path = ''
as $$
  select btrim(
    regexp_replace(
      translate(
        lower(translate(p_name, U&'\0130', U&'\0069') collate "und-x-icu"),
        U&'\03C2', U&'\03C3'
      ),
      '[\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+',
      ' ',
      'g'
    ),
    ' '
  );
$$;

comment on function public.normalise_exercise_name(text) is
  'The exercise grouping key: U+0130 folded to i, lower-cased under the pinned ICU root collation, final sigma folded to sigma, every run of whitespace collapsed to one space, trimmed. Neither half depends on the database locale provider -- the whitespace class is written by code point and the case fold names its collation. Must stay identical to normaliseExerciseName in apps/web/src/lib/gym/gym_prs.ts and apps/mobile_android/lib/gym_prs.dart; scripts/check_shared_constants.mjs compares the three.';

-- Unchanged from 20270623000001 and restated because a later DROP would reset
-- the ACL: the grant list is decided by who WRITES the two keyed tables, since
-- a CHECK naming a function ACL-checks it against the INSERTING role. `anon`
-- has to be revoked BY NAME -- Supabase's default privileges hand every new
-- function an EXPLICIT anon grant that `from public` does not reach (§ 790).
revoke execute on function public.normalise_exercise_name(text) from public, anon;
grant  execute on function public.normalise_exercise_name(text) to authenticated;
grant  execute on function public.normalise_exercise_name(text) to service_role;

-- ── Re-canonicalise the two persisted keys ──────────────────────────────────
-- A key written by a conforming client moves only for a name carrying U+0130
-- or U+03C2, and on a database whose collation was already ICU root-equivalent
-- nothing else moves at all. Measured on the local stack: 0 of 47 stored rows
-- (4 gym_routine_exercises + 43 exercises) differ under either derivation. The
-- pass runs anyway for the reason § 790 gave -- "every client build that ever
-- wrote a row conformed" is a claim about history a migration cannot verify.
do $$
declare
  batch_size constant integer := 1000;
  touched integer;
begin
  loop
    with candidates as (
      select id
      from public.gym_routine_exercises
      where exercise_key is distinct from public.normalise_exercise_name(exercise_name)
        and coalesce(public.normalise_exercise_name(exercise_name), '') <> ''
      order by id
      limit batch_size
    )
    update public.gym_routine_exercises t
    set exercise_key = public.normalise_exercise_name(t.exercise_name)
    from candidates c
    where t.id = c.id;
    get diagnostics touched = row_count;
    exit when touched = 0;
  end loop;

  loop
    with candidates as (
      select id
      from public.exercises
      where name_key is distinct from public.normalise_exercise_name(name)
        and coalesce(public.normalise_exercise_name(name), '') <> ''
      order by id
      limit batch_size
    )
    update public.exercises t
    set name_key = public.normalise_exercise_name(t.name)
    from candidates c
    where t.id = c.id;
    get diagnostics touched = row_count;
    exit when touched = 0;
  end loop;
end;
$$;

alter table public.gym_routine_exercises
  drop constraint gym_routine_exercises_exercise_key_canonical;

alter table public.exercises
  drop constraint exercises_name_key_canonical;

alter table public.gym_routine_exercises
  add constraint gym_routine_exercises_exercise_key_canonical
  check (exercise_key = public.normalise_exercise_name(exercise_name))
  not valid;

alter table public.exercises
  add constraint exercises_name_key_canonical
  check (name_key = public.normalise_exercise_name(name))
  not valid;

alter table public.gym_routine_exercises
  validate constraint gym_routine_exercises_exercise_key_canonical;

alter table public.exercises
  validate constraint exercises_name_key_canonical;
