-- Fix: gear chips never rendered on the public run-share page for non-owners.
--
-- Two compounding bugs, both dating to the 20260827_001 gear migration which
-- landed AFTER 20260701_001 dropped the public-run SELECT policy on the base
-- `runs` table (public reads moved to security-definer helpers + the
-- public_runs view):
--
--   1. The run_gear SELECT policy wrapped is_run_visible_to in an
--      `exists (select 1 from runs r where ...)`. That inner select is
--      evaluated under the CALLER's RLS on `runs`, which no longer exposes
--      public runs to non-owners, so the wrapper returned no row and the
--      definer helper was never reached. The sibling social tables
--      (run_kudos / run_comments / ...) call is_run_visible_to DIRECTLY; bring
--      run_gear in line.
--
--   2. Even with the link visible, fetching the gear details means joining to
--      the `gear` table, whose SELECT policy is owner-only — so a non-owner
--      (incl. anon on a public share) reads the run_gear link but a NULL gear
--      row, and the chip renders nothing. Row-level security can't expose just
--      the public columns (name/brand/model) while hiding the private ones
--      (notes/target_distance_m/retired_at). A SECURITY DEFINER function that
--      projects only the public columns for gear on a visible run is the
--      leak-free way to drive the public chip.

-- (1) Direct definer call, matching the sibling social-table policies.
drop policy "run_gear visible when parent run is visible" on public.run_gear;

create policy "run_gear visible when parent run is visible"
  on public.run_gear for select
  using (private.is_run_visible_to(run_gear.run_id, auth.uid()));

-- (2) Public projection for the share-page chip. Returns ONLY the public gear
-- columns, and only for a run the caller can see. Owner-management reads
-- (fetchMyGear / the picker) keep going through the owner-only `gear` policy;
-- this function is exclusively the read path for "what gear did this run use".
create or replace function public.public_run_gear(p_run_id uuid)
returns table (id uuid, kind text, name text, brand text, model text)
language sql
stable
security definer
set search_path = public
as $$
  select g.id, g.kind, g.name, g.brand, g.model
  from run_gear rg
  join gear g on g.id = rg.gear_id
  where rg.run_id = p_run_id
    and private.is_run_visible_to(p_run_id, auth.uid())
  order by g.kind, g.name
$$;

grant execute on function public.public_run_gear(uuid) to anon, authenticated;
