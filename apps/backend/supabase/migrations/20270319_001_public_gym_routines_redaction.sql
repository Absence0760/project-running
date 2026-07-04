-- Redact external_id / last_modified_at from the public gym-routine library
-- surface (audit/public-rows 2026-07-03; source 20270226_001).
--
-- The "gym_routines public templates read" RLS branch opened the WHOLE row to
-- any signed-in user, so GET /rest/v1/gym_routines?is_public_template=eq.true
-- leaked, alongside the intended template fields:
--
--   * external_id      — the per-user import/dedup crosswalk. Same class of
--                        leak 20270313_001 closed on gym_workouts.
--   * last_modified_at — the offline-sync clock; keeps ticking on the
--                        author's private edits after publish, so it leaks
--                        edit cadence. Classified owner-only for gym_workouts
--                        and runs; same here.
--
-- Same medicine as 20270313_001: the base-table public branch is dropped and
-- non-author reads go through a redacted view that projects only the
-- template-safe columns. The exercises/sets child policies referenced the
-- parent row via a plain EXISTS subquery, which the parent's RLS would now
-- hide from a non-author — so they move onto a SECURITY DEFINER oracle
-- (private.is_public_gym_routine, the is_public_route_by_id pattern) that
-- answers the is-this-template-public question without exposing the row.
-- clone_gym_routine_template / set_gym_routine_public are SECURITY DEFINER
-- and unaffected.
--
-- The library stays a signed-in surface: the view is granted to authenticated
-- only, and browse ordering moves from last_modified_at (now redacted) to
-- created_at, with the partial browse index re-pointed to match.

create or replace function private.is_public_gym_routine(p_routine_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_public_template from gym_routines where id = p_routine_id),
    false
  );
$$;

revoke all on function private.is_public_gym_routine(uuid) from public, anon;
grant execute on function private.is_public_gym_routine(uuid) to authenticated;

drop policy "gym_routines public templates read" on public.gym_routines;

drop policy "gym_routine_exercises public templates read" on public.gym_routine_exercises;
create policy "gym_routine_exercises public templates read"
  on public.gym_routine_exercises for select
  using (
    auth.role() = 'authenticated'
    and private.is_public_gym_routine(routine_id)
  );

drop policy "gym_routine_sets public templates read" on public.gym_routine_sets;
create policy "gym_routine_sets public templates read"
  on public.gym_routine_sets for select
  using (
    auth.role() = 'authenticated'
    and exists (
      select 1 from public.gym_routine_exercises e
      where e.id = gym_routine_sets.routine_exercise_id
        and private.is_public_gym_routine(e.routine_id)
    )
  );

create view public.public_gym_routines as
select
  r.id,
  r.author_id,
  r.club_id,
  r.is_public_template,
  r.title,
  r.notes,
  r.periodisation,
  r.exercise_count,
  r.created_at
from public.gym_routines r
where r.is_public_template = true;

grant select on public.public_gym_routines to authenticated;

drop index gym_routines_public_library_idx;
create index gym_routines_public_library_idx
  on public.gym_routines (created_at desc)
  where is_public_template = true;
