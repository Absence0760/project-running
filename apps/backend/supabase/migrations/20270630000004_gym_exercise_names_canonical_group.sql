-- The autocomplete datalist groups on the canonical key instead of a bare
-- btrim (decisions § 831).
--
-- `gym_exercise_names` is deliberately case- and spelling-PRESERVING -- it
-- feeds the gym editor's `<input list=datalist>`, not the grouping key -- so
-- § 790 left it alone when it moved the other four RPCs onto
-- `public.normalise_exercise_name`. But preserving the spelling and grouping
-- by the spelling are different things, and it did both. `btrim(text)` with no
-- second argument strips U+0020 and nothing else, so a name pasted with a
-- leading tab is its own group: the lifter is offered `Bench Press` and a
-- second suggestion that looks identical, differs by an invisible character,
-- and inserts a name that keys to the same exercise. Cosmetic rather than a
-- key split -- nothing downstream reads this RPC's output as a key -- but the
-- editor is where the stray character gets typed a second time.
--
-- Grouping moves to the canonical key and the DISPLAY spelling is chosen from
-- the group. The filing proposed picking the most-used spelling "as
-- gym_exercise_records already does with its array_agg(display order by
-- started_at desc, display)". Read, that sibling picks the most RECENT
-- spelling, not the most-used one; the idiom is reused here, the ordering is
-- not. Most-used is the right choice for an autocomplete whose rows are
-- already ordered by use count: the suggestion a lifter accepts then reproduces
-- their own commonest spelling rather than whichever one they typed last. Ties
-- break on most-recent and then on the spelling itself, so the answer is a
-- total order and two calls cannot disagree. That the two RPCs now resolve a
-- display spelling by different rules is filed rather than settled here --
-- unifying them changes a shipped records surface.
--
-- `uses` is the count over the whole group, so the number beside a suggestion
-- is now how often the LIFT was logged rather than how often one spelling of
-- it was. The blank-name filter moves onto the key for the same reason it did
-- in § 790: `btrim(coalesce(name,'')) <> ''` counted a lone tab as an exercise
-- named " ", which both clients drop.
--
-- A group whose only spelling carries edge whitespace still displays it. That
-- is unchanged from before and deliberate: trimming the display would mean a
-- fourth hand-written copy of the whitespace class, which is the defect § 790
-- exists to have removed.
--
-- Lock impact (migration_locks.md): CREATE OR REPLACE FUNCTION locks the
-- pg_proc entry. No table is read or written by this migration.

create or replace function gym_exercise_names()
returns table (
  exercise_name text,
  uses integer
)
language sql
stable
security invoker
set search_path = public
as $$
  with norm as (
    select
      public.normalise_exercise_name(s.exercise_name) as key,
      s.exercise_name as display,
      gw.started_at
    from gym_sets s
    join gym_workouts gw on gw.id = s.workout_id
    where gw.user_id = auth.uid()
      and coalesce(public.normalise_exercise_name(s.exercise_name), '') <> ''
  ),
  spellings as (
    select
      key,
      display,
      count(*)::int as spelling_uses,
      max(started_at) as last_used
    from norm
    group by key, display
  ),
  picked as (
    select
      key,
      (array_agg(display order by spelling_uses desc, last_used desc, display))[1] as display,
      sum(spelling_uses)::int as uses
    from spellings
    group by key
  )
  select p.display, p.uses
  from picked p
  order by p.uses desc, p.display;
$$;

comment on function gym_exercise_names() is
  'Distinct logged exercises for the gym editor autocomplete, one row per canonical grouping key (public.normalise_exercise_name), displayed under the caller''s most-used spelling of it and counted across every spelling. Case and internal spelling are preserved in the display; only the grouping is canonical.';

revoke execute on function gym_exercise_names() from public, anon;
grant  execute on function gym_exercise_names() to authenticated;
