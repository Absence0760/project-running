-- Club-published gym-routine templates — the gym-programming analogue of the
-- session-planner P3 club templates (clone_session_template, 20270104_001) and
-- the training-plan club templates (clone_plan_template). A club-owned routine
-- (gym_routines.club_id set) is the "template"; a member adopts it by cloning
-- the routine + exercises + sets into a new personal routine (author_id =
-- caller, club_id = null).
--
-- This is the LEAK-SAFE subset of gym_programming.md's deferred "public-routine
-- sharing": it deliberately does NOT add a global `is_public` public-read
-- branch — that's the slice the doc held back, because shipping public-read RLS
-- before a browse UI exists lets any authenticated user enumerate every public
-- routine's planned sets via the REST API (a public-rows leak). Club-owned read
-- here is gated on club MEMBERSHIP via private.is_club_member, exactly like
-- club-owned routes (20260520_001) and session plans (20270103_001), so a
-- template is only visible to the club it was published into.

-- ── club_id — makes a routine club-owned ────────────────────────────────────
-- on delete cascade mirrors session_plans.club_id: a club-owned template is
-- club content and goes when the club does. (A purely personal routine has
-- club_id = null and is unaffected.)
alter table public.gym_routines
  add column club_id uuid references public.clubs (id) on delete cascade;

create index gym_routines_club_idx
  on public.gym_routines (club_id, last_modified_at desc)
  where club_id is not null;

-- ── RLS — add club-owned READ + admin-manage branches ───────────────────────
-- Postgres ORs permissive policies, so these are ADDED alongside the existing
-- author-only policies (20270101_001) rather than replacing them — no risk of
-- the bare-body-replacement trap stripping the author policies. Policy
-- expressions qualify the oracle as private.is_club_member / private.is_club_admin
-- because a policy bypasses the caller's search_path (the 20261120_001 lesson).

-- Members of the owning club can READ a club-owned routine (list + preview it
-- on the club Templates tab before adopting).
create policy "gym_routines club members read"
  on public.gym_routines for select
  using (club_id is not null and private.is_club_member(club_id));

-- A club admin can rename or remove (unpublish) a club-owned routine. UPDATE +
-- DELETE only — never INSERT, so the publish path stays the gated DEFINER RPC
-- below and an admin can't inject a row with someone else's author_id.
create policy "gym_routines club admins update"
  on public.gym_routines for update
  using (club_id is not null and private.is_club_admin(club_id))
  with check (club_id is not null and private.is_club_admin(club_id));
create policy "gym_routines club admins delete"
  on public.gym_routines for delete
  using (club_id is not null and private.is_club_admin(club_id));

-- Children inherit the club-member READ visibility (so the Templates tab can
-- show the template's exercises + sets). Writes to children stay author-only +
-- the DEFINER clone/publish RPCs; admin removal cascades from the routine delete.
create policy "gym_routine_exercises club members read"
  on public.gym_routine_exercises for select
  using (exists (
    select 1 from public.gym_routines r
    where r.id = gym_routine_exercises.routine_id
      and r.club_id is not null and private.is_club_member(r.club_id)
  ));

create policy "gym_routine_sets club members read"
  on public.gym_routine_sets for select
  using (exists (
    select 1
    from public.gym_routine_exercises e
    join public.gym_routines r on r.id = e.routine_id
    where e.id = gym_routine_sets.routine_exercise_id
      and r.club_id is not null and private.is_club_member(r.club_id)
  ));

-- ── publish_gym_routine_as_template — author + club-admin gated deep-copy ────
-- Tighter than the session-planner client-side publish (which lets a non-member
-- author set an arbitrary club_id): here the caller MUST be the routine's
-- author AND an admin of the target club, enforced server-side. Deep-copies the
-- routine + exercises + sets into a NEW club-owned routine so the author keeps
-- their personal copy untouched. Returns the new (club-owned) routine id.
create or replace function publish_gym_routine_as_template(
  p_routine_id uuid,
  p_club_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  caller uuid := auth.uid();
  src gym_routines%rowtype;
  new_routine_id uuid;
  new_exercise_id uuid;
  ex_record record;
  set_record record;
begin
  if caller is null then
    raise exception 'publish_gym_routine_as_template: not authenticated';
  end if;

  perform enforce_create_rate_limit('publish_gym_routine_as_template', caller, 20, 3600);

  select * into src from gym_routines where id = p_routine_id;
  if not found then
    raise exception 'publish_gym_routine_as_template: routine not found';
  end if;

  if src.author_id <> caller then
    raise exception 'publish_gym_routine_as_template: only the author may publish routine %', p_routine_id;
  end if;

  if not is_club_admin(p_club_id) then
    raise exception 'publish_gym_routine_as_template: not a club admin of %', p_club_id;
  end if;

  insert into gym_routines (author_id, club_id, title, notes, periodisation, exercise_count)
  values (caller, p_club_id, src.title, src.notes, src.periodisation, src.exercise_count)
  returning id into new_routine_id;

  for ex_record in
    select * from gym_routine_exercises where routine_id = p_routine_id order by position
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

revoke execute on function publish_gym_routine_as_template(uuid, uuid) from public;
grant execute on function publish_gym_routine_as_template(uuid, uuid) to authenticated;

-- ── clone_gym_routine_template — author-or-member adopt into a personal copy ─
-- Mirrors clone_session_template: a member of the owning club (or the author)
-- adopts the template by deep-copying it into a new PERSONAL routine
-- (author_id = caller, club_id = null). A gym routine carries no private
-- fitness data (target loads are the published prescription — the point of the
-- template), so nothing is stripped on clone.
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

  -- Author, or any member of the owning club, may clone. A purely personal
  -- routine (no club_id) is clonable only by its author.
  if tmpl.author_id <> caller
     and not (tmpl.club_id is not null and is_club_member(tmpl.club_id))
  then
    raise exception 'clone_gym_routine_template: not authorised to clone template %', p_template_id;
  end if;

  insert into gym_routines (author_id, club_id, title, notes, periodisation, exercise_count)
  values (caller, null, tmpl.title, tmpl.notes, tmpl.periodisation, tmpl.exercise_count)
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
