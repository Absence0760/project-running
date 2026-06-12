-- Session plans — the yoga/pilates session-content engine, P1 slice of
-- docs/features/session_planner.md.
--
-- A session plan is a reusable, ordered sequence of timed/counted movements
-- (poses, holds, flows, mat/reformer exercises) that an instructor builds once
-- and optionally attaches to a `class`-category event. It is the yoga/pilates
-- analogue of the gym routine engine (gym_programming.md) and mirrors its
-- relational shape (plan -> blocks -> items, expand-once helper, self-hiding).
--
-- P1 scope: build + save + reuse a plan. NO execution / follow-along runner /
-- logging (that's P2). This migration lays the three tables + the optional
-- events.session_plan_id attach point + RLS mirroring club-owned routes
-- (20260520_001): author owns; is_public is world-readable; a club-owned plan
-- is readable by members and writable by club admins.
--
-- Reuses the membership oracles moved to the `private` schema in 20261120_001
-- (private.is_club_member / private.is_club_admin). RLS policies qualify them
-- explicitly because a policy expression bypasses the caller's search_path.

-- ───────────────────────── 1. session_plans ──────────────────────────────────
-- The template head. author_id is the creator (audit + own-row authority).
-- club_id (nullable) mirrors routes.club_id: when set, the plan is club-owned —
-- any club member reads it regardless of is_public, any club admin edits it, and
-- it survives the author leaving the role. est_duration_min is a cached estimate
-- derived from the items (a reps item with no duration contributes 0; see
-- expandSessionSteps); recomputed client-side on save, not trigger-maintained.
create table session_plans (
  id               uuid primary key default gen_random_uuid(),
  author_id        uuid not null references auth.users on delete cascade,
  club_id          uuid references clubs on delete cascade,
  title            text not null,
  discipline       text,
  equipment        text,
  est_duration_min integer,
  is_public        boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index session_plans_author_idx on session_plans (author_id, updated_at desc);
create index session_plans_club_idx on session_plans (club_id, updated_at desc)
  where club_id is not null;
create index session_plans_public_idx on session_plans (updated_at desc)
  where is_public = true;

alter table session_plans enable row level security;

-- Author owns their own plans (read + write). Mirrors "users own their routes".
create policy "authors own their session plans"
  on session_plans for all
  using (auth.uid() = author_id)
  with check (auth.uid() = author_id);

-- A public plan is readable by anyone (incl. anon — discovery in a later slice).
create policy "public session plans are readable"
  on session_plans for select
  using (is_public = true);

-- Club-owned plans: members read, admins write. Mirrors the club-owned-routes
-- pair (20260520_001), using the private-schema oracles (20261120_001).
create policy "club members read club session plans"
  on session_plans for select
  using (club_id is not null and private.is_club_member(club_id));

create policy "club admins write club session plans"
  on session_plans for all
  using (club_id is not null and private.is_club_admin(club_id))
  with check (club_id is not null and private.is_club_admin(club_id));

-- ───────────────────────── 2. session_plan_blocks ────────────────────────────
-- Optional grouping layer (Warm-up / Standing / Floor / Cool-down). A flat plan
-- has no blocks (items carry block_id = null). name nullable so a block can be
-- positional-only. Cascades with the parent plan.
create table session_plan_blocks (
  id        uuid primary key default gen_random_uuid(),
  plan_id   uuid not null references session_plans on delete cascade,
  position  integer not null,
  name      text
);

create index session_plan_blocks_plan_idx on session_plan_blocks (plan_id, position);

alter table session_plan_blocks enable row level security;

-- Blocks inherit the parent plan's visibility. A single combined policy keyed on
-- "can the caller see/own the parent plan" — same predicate the plan's own
-- policies OR together, evaluated through the plan row's RLS.
create policy "session plan blocks inherit plan visibility"
  on session_plan_blocks for all
  using (
    exists (
      select 1 from session_plans p
      where p.id = session_plan_blocks.plan_id
        and (
          p.author_id = auth.uid()
          or p.is_public = true
          or (p.club_id is not null and private.is_club_member(p.club_id))
        )
    )
  )
  with check (
    exists (
      select 1 from session_plans p
      where p.id = session_plan_blocks.plan_id
        and (
          p.author_id = auth.uid()
          or (p.club_id is not null and private.is_club_admin(p.club_id))
        )
    )
  );

-- ───────────────────────── 3. session_plan_items ─────────────────────────────
-- The movements. block_id nullable (flat plan). kind is a narrow union + CHECK
-- (register in check_constraint_unions.mjs as session_plan_items.kind <->
-- SessionItemKind). duration_s for hold/flow; reps for reps; per_side splits
-- into L/R steps at expand time (expandSessionSteps). tempo + cue are free text.
create table session_plan_items (
  id            uuid primary key default gen_random_uuid(),
  plan_id       uuid not null references session_plans on delete cascade,
  block_id      uuid references session_plan_blocks on delete cascade,
  position      integer not null,
  movement_name text not null,
  kind          text not null default 'hold',
  duration_s    integer,
  reps          integer,
  per_side      boolean not null default false,
  tempo         text,
  cue           text
);

-- Separate add constraint (not inline) so the narrow-union parity guard
-- (check_constraint_unions.mjs) finds it, matching the typed-events pattern.
alter table session_plan_items add constraint session_plan_items_kind_check
  check (kind in ('hold', 'reps', 'flow'));

create index session_plan_items_plan_idx on session_plan_items (plan_id, position);
create index session_plan_items_block_idx on session_plan_items (block_id, position)
  where block_id is not null;

alter table session_plan_items enable row level security;

create policy "session plan items inherit plan visibility"
  on session_plan_items for all
  using (
    exists (
      select 1 from session_plans p
      where p.id = session_plan_items.plan_id
        and (
          p.author_id = auth.uid()
          or p.is_public = true
          or (p.club_id is not null and private.is_club_member(p.club_id))
        )
    )
  )
  with check (
    exists (
      select 1 from session_plans p
      where p.id = session_plan_items.plan_id
        and (
          p.author_id = auth.uid()
          or (p.club_id is not null and private.is_club_admin(p.club_id))
        )
    )
  );

-- ───────────────────────── 4. events.session_plan_id ─────────────────────────
-- A class event optionally attaches a full session plan (the rich successor to
-- the lightweight gym_template jsonb hint; both coexist — see session_planner.md
-- § Relationship). Nullable; readable wherever the event is. Only the event
-- organiser may set it: enforced by a BEFORE trigger (RLS WITH CHECK on events
-- already gates organiser writes for the row, but the trigger guarantees the
-- column can't be set by a non-organiser even via a future permissive path, and
-- gives a clear error rather than a silent reject).
alter table events add column session_plan_id uuid references session_plans on delete set null;

create index events_session_plan_idx on events (session_plan_id)
  where session_plan_id is not null;

-- events has a column-level SELECT lockdown (20260818_001 redo): each new
-- client-read column needs an explicit grant (the category / discipline /
-- gym_template precedent). session_plan_id carries no PII (an FK id, NULL for
-- an un-attached class), so the lowest-surface durable fix is the column grant,
-- not an oracle. Row visibility is unchanged — it still flows through the
-- events SELECT RLS policy. UPDATE was never column-narrowed (20260818_001
-- revoked only SELECT), so the organiser write needs no grant here.
grant select (session_plan_id) on events to authenticated, anon;

-- Only an organiser of the event's club may attach/detach a plan. SECURITY
-- DEFINER so the organiser check is reliable regardless of the writer's
-- visibility; search_path includes private for the oracle (the is_event_visible
-- precedent in 20261229_001).
create or replace function enforce_event_session_plan_organiser()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  -- INSERT always fires this trigger (the OF-column clause is ignored on
  -- INSERT); skip when no plan is being attached so a plain event insert is
  -- unaffected. On UPDATE, only guard a genuine change to the attachment.
  if tg_op = 'INSERT' and new.session_plan_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.session_plan_id is not distinct from old.session_plan_id then
    return new;
  end if;

  -- Trusted callers bypass the organiser gate (the lock_event_order_status
  -- pattern): the REST service role, or genuine direct SQL (migrations + seed)
  -- which reach here with an empty role claim AND a privileged session_user.
  -- PostgREST authenticates every end-user request as `authenticator`, so a
  -- user request can never present session_user = postgres.
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;

  if not is_event_organiser(new.club_id) then
    raise exception 'only an event organiser may change the session plan for event %', new.id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger events_session_plan_organiser
  before insert or update of session_plan_id on events
  for each row execute function enforce_event_session_plan_organiser();
