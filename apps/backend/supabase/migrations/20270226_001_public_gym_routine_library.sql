-- Public gym-routine library — anyone-can-adopt. This ships the slice the
-- gym-programming v1 RLS deliberately held back (gym_programming.md § "No global
-- is_public column in v1" + migration 20270101_001): publish a personal routine
-- as a public template, and let any authenticated user preview + clone it into
-- their own library. It is the gym-routine analogue of the public PLAN library
-- (clone_public_plan, 20270126_001) and is orthogonal to the club-scoped
-- templates (20270109_001): a club template has club_id set + is_public_template
-- false; a public template has club_id null + is_public_template true. The two
-- visibility branches OR together in RLS and never overlap (CHECK below).
--
-- Why this is safe to add now (the v1 deferral is satisfied): the leak the v1
-- note guarded against was shipping public-read RLS BEFORE a browse UI existed,
-- so any authenticated user could enumerate every public routine's planned sets
-- via the REST API with no surface that intended it. This migration ships the
-- read branch IN THE SAME change as the /gym/routines/library browse UI (web)
-- and the mobile twin, so the exposure is intended, not an accident. A gym
-- routine carries no private fitness data — its target loads ARE the published
-- prescription (the point of a template) — so nothing is stripped on publish or
-- clone, unlike the plan library which strips the publisher's vdot.

-- ── is_public_template — makes a personal routine a public template ─────────
alter table public.gym_routines
  add column is_public_template boolean not null default false;

-- A public template is publisher-owned, never club-owned: the two visibility
-- branches stay strictly separable (mirrors training_plans' public-vs-club
-- separation). A club template is adopted via clone_gym_routine_template's
-- member gate; a public template via its is_public_template gate.
alter table public.gym_routines
  add constraint gym_routines_public_not_club
  check (is_public_template = false or club_id is null);

-- Browse index: the library lists public templates newest-first.
create index gym_routines_public_library_idx
  on public.gym_routines (last_modified_at desc)
  where is_public_template = true;

-- ── RLS — add public READ branches ──────────────────────────────────────────
-- Postgres OR-combines permissive policies of the same command, so these
-- ADD a public-read branch alongside the existing author-only (20270101_001)
-- and club-member (20270109_001) policies. Gated on authenticated — the
-- library is a signed-in surface (mirrors the public-plan-library policy and
-- the user_profiles public-read policy) — so a public template is previewable
-- + cloneable by any signed-in user while non-public routines stay private.

create policy "gym_routines public templates read"
  on public.gym_routines for select
  using (is_public_template = true and auth.role() = 'authenticated');

create policy "gym_routine_exercises public templates read"
  on public.gym_routine_exercises for select
  using (
    auth.role() = 'authenticated'
    and exists (
      select 1 from public.gym_routines r
      where r.id = gym_routine_exercises.routine_id
        and r.is_public_template = true
    )
  );

create policy "gym_routine_sets public templates read"
  on public.gym_routine_sets for select
  using (
    auth.role() = 'authenticated'
    and exists (
      select 1
      from public.gym_routine_exercises e
      join public.gym_routines r on r.id = e.routine_id
      where e.id = gym_routine_sets.routine_exercise_id
        and r.is_public_template = true
    )
  );

-- ── clone_gym_routine_template — add the public-template branch ──────────────
-- Bare-body create-or-replace: this re-emits the COMPLETE 20270109_001 body
-- (the not-authenticated guard, rate limit, not-found check, author-or-member
-- gate, and the exercise+set deep-copy) and ADDS a third authorisation branch
-- so a public template is also clonable by any signed-in caller. Re-reading the
-- latest body first (the create-or-replace-strips-prior-fixes lesson). The copy
-- is identical — a clone is always a personal, club-less, NON-public routine.
create or replace function clone_gym_routine_template(p_template_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
  tmpl gym_routines%rowtype;
  new_routine_id uuid;
  new_exercise_id uuid;
  ex_record record;
  set_record record;
begin
  if caller is null then
    raise exception 'clone_gym_routine_template: not authenticated';
  end if;

  perform enforce_create_rate_limit('clone_gym_routine_template', caller, 20, 3600);

  select * into tmpl from gym_routines where id = p_template_id;
  if not found then
    raise exception 'clone_gym_routine_template: template not found';
  end if;

  -- Three authorisation branches OR together:
  --   1. the author (clone your own routine),
  --   2. a member of the owning club (club template), or
  --   3. any signed-in caller when the routine is a public template.
  -- A purely personal routine (no club_id, not public) is clonable only by its
  -- author.
  if tmpl.author_id <> caller
     and not (tmpl.club_id is not null and is_club_member(tmpl.club_id))
     and not tmpl.is_public_template
  then
    raise exception 'clone_gym_routine_template: not authorised to clone template %', p_template_id;
  end if;

  insert into gym_routines (author_id, club_id, is_public_template, title, notes, periodisation, exercise_count)
  values (caller, null, false, tmpl.title, tmpl.notes, tmpl.periodisation, tmpl.exercise_count)
  returning id into new_routine_id;

  for ex_record in
    select * from gym_routine_exercises where routine_id = p_template_id order by position
  loop
    insert into gym_routine_exercises (
      routine_id, exercise_name, exercise_key, position, superset_group, superset_order,
      modality, progression, progression_params, notes
    )
    values (
      new_routine_id, ex_record.exercise_name, ex_record.exercise_key, ex_record.position,
      ex_record.superset_group, ex_record.superset_order, ex_record.modality,
      ex_record.progression, ex_record.progression_params, ex_record.notes
    )
    returning id into new_exercise_id;

    for set_record in
      select * from gym_routine_sets where routine_exercise_id = ex_record.id order by set_index
    loop
      insert into gym_routine_sets (
        routine_exercise_id, set_index, set_type, target_reps_min, target_reps_max,
        target_weight_kg, target_percent_1rm, target_rpe, rest_s, tempo,
        target_duration_s, target_distance_m
      )
      values (
        new_exercise_id, set_record.set_index, set_record.set_type, set_record.target_reps_min,
        set_record.target_reps_max, set_record.target_weight_kg, set_record.target_percent_1rm,
        set_record.target_rpe, set_record.rest_s, set_record.tempo,
        set_record.target_duration_s, set_record.target_distance_m
      );
    end loop;
  end loop;

  return new_routine_id;
end;
$$;

revoke execute on function clone_gym_routine_template(uuid) from public;
grant execute on function clone_gym_routine_template(uuid) to authenticated;

-- ── set_gym_routine_public — owner publish / unpublish toggle ───────────────
-- Publishing a personal routine to the public library is just flipping the flag
-- on the routine the caller already owns (the routine IS the template — no
-- deep-copy, unlike the plan library which copies into a separate template
-- row). The existing author-update RLS would already permit this flip, but a
-- dedicated RPC keeps the toggle explicit + auditable, enforces author-only +
-- not-club-owned in one place, and gives the clients a single call instead of a
-- bare column write through PostgREST. SECURITY DEFINER + the author check is
-- the access gate; the not-club-owned guard mirrors the CHECK so an admin can't
-- route a club template into the public library through this path.
create or replace function set_gym_routine_public(
  p_routine_id uuid,
  p_public boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  src gym_routines%rowtype;
begin
  if caller is null then
    raise exception 'set_gym_routine_public: not authenticated';
  end if;

  select * into src from gym_routines where id = p_routine_id;
  if not found then
    raise exception 'set_gym_routine_public: routine not found';
  end if;

  if src.author_id <> caller then
    raise exception 'set_gym_routine_public: only the author may publish routine %', p_routine_id;
  end if;

  if p_public and src.club_id is not null then
    raise exception 'set_gym_routine_public: a club-owned routine cannot be a public template';
  end if;

  update gym_routines
  set is_public_template = p_public,
      last_modified_at = now()
  where id = p_routine_id;
end;
$$;

revoke execute on function set_gym_routine_public(uuid, boolean) from public;
grant execute on function set_gym_routine_public(uuid, boolean) to authenticated;
