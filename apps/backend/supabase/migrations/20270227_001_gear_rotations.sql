-- Gear rotations — named groups a runner cycles a set of shoes (or bikes) through.
--
-- Background. The v1 gear feature (20260827_001) tracks each item on its own,
-- and `is_default` (20260901_001) marks the ONE current pair per kind that
-- auto-tags new runs. What neither captures is a runner's mental grouping: a
-- "Daily trainers" set, a "Race day" set, a "Trail" set. A rotation is a NAMED,
-- MANY-TO-MANY grouping — one shoe can sit in several rotations, a rotation
-- holds several shoes — distinct from `is_default` (single current pair) and
-- complementary to it (a rotation can contain the default plus its siblings).
--
-- Two tables, both owner-scoped exactly like `gear`:
--   `gear_rotations`         — one row per named group (id, owner_id, name).
--   `gear_rotation_members`  — join (rotation_id, gear_id), PK on the pair.
--
-- RLS mirrors `gear` (4 owner-only policies on the rotation) and the run_gear /
-- gear_wear_logs double-gate on the join: a member INSERT must own BOTH the
-- rotation AND the parent gear, so a user can't slip another user's gear into
-- their rotation, nor add gear to a rotation they don't own. There is NO
-- public-visibility path — a rotation is private inventory organisation, never
-- projected onto a public run (unlike `run_gear`).

-- ─────────────────── gear_rotations ───────────────────

create table public.gear_rotations (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid references auth.users(id) on delete cascade not null,
  name        text not null check (length(name) between 1 and 60),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- A runner won't have many rotations; owner_id leads so the owner-scoped read
-- is index-covered, name as a tiebreaker for a stable display order.
create index gear_rotations_owner on public.gear_rotations (owner_id, name);

alter table public.gear_rotations enable row level security;

create policy "owners read their gear rotations"
  on public.gear_rotations for select
  using (owner_id = auth.uid());

create policy "owners insert their gear rotations"
  on public.gear_rotations for insert
  with check (owner_id = auth.uid());

create policy "owners update their gear rotations"
  on public.gear_rotations for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "owners delete their gear rotations"
  on public.gear_rotations for delete
  using (owner_id = auth.uid());

-- Reuse the gear updated_at bump trigger function (20260827_001).
create trigger gear_rotations_updated_at
  before update on public.gear_rotations
  for each row execute function gear_set_updated_at();

-- ─────────────────── gear_rotation_members (join) ───────────────────

create table public.gear_rotation_members (
  rotation_id  uuid references public.gear_rotations(id) on delete cascade not null,
  gear_id      uuid references public.gear(id) on delete cascade not null,
  created_at   timestamptz not null default now(),
  primary key (rotation_id, gear_id)
);

-- Reverse lookup: which rotations contain this gear (for the gear-list grouping).
create index gear_rotation_members_gear on public.gear_rotation_members (gear_id);

alter table public.gear_rotation_members enable row level security;

-- SELECT: the caller must own the parent rotation. Owning the rotation already
-- implies owning the gear (the INSERT gate enforces that), so gating SELECT on
-- the rotation is sufficient and keeps the read index-covered.
create policy "members visible when owner owns the rotation"
  on public.gear_rotation_members for select
  using (
    exists (
      select 1 from public.gear_rotations r
      where r.id = gear_rotation_members.rotation_id and r.owner_id = auth.uid()
    )
  );

-- INSERT requires owning BOTH the rotation AND the gear — the run_gear /
-- gear_wear_logs double-gate. Stops a user from putting another user's gear
-- into their rotation, or adding gear to a rotation they don't own.
create policy "owners add their gear to their rotations"
  on public.gear_rotation_members for insert
  with check (
    exists (
      select 1 from public.gear_rotations r
      where r.id = gear_rotation_members.rotation_id and r.owner_id = auth.uid()
    )
    and exists (
      select 1 from public.gear g
      where g.id = gear_rotation_members.gear_id and g.owner_id = auth.uid()
    )
  );

create policy "owners remove members from their rotations"
  on public.gear_rotation_members for delete
  using (
    exists (
      select 1 from public.gear_rotations r
      where r.id = gear_rotation_members.rotation_id and r.owner_id = auth.uid()
    )
  );
