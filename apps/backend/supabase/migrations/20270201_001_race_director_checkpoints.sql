-- Race-director operations P1 (+ P3 schema): offline aid-station checkpoint
-- check-in feeding live results + cutoff projection. See
-- docs/features/race_director_ops.md.
--
-- Two tables:
--   * event_checkpoints — a race's ordered checkpoints (aid stations / cutoffs),
--     optionally linked to a route_markers row, each with an optional cutoff.
--   * checkpoint_crossings — a runner's in/out stamp at one checkpoint for one
--     event instance, written offline by aid-station volunteers and synced in
--     batches when signal returns.
--
-- Identity mirrors event_results (account-optional, 20261028_001): a crossing
-- names its runner by an account (user_id) OR a bib + runner_name, never fully
-- anonymous. Two NULLs-distinct UNIQUE keys keep one crossing per
-- (event, checkpoint, instance, identity).
--
-- Offline conflict resolution = MERGE in/out (the chosen policy): two
-- volunteers stamping the same runner at the same checkpoint reconcile to ONE
-- crossing with the earliest in_time and latest out_time. This lives in the
-- upsert_checkpoint_crossing RPC (single writer) so two client-minted UUIDs on
-- two phones collapse onto the canonical row. Postgres least()/greatest()
-- ignore NULL inputs, which is exactly the earliest-in / latest-out / fill-the-
-- gap merge.
--
-- P3 weigh-in / medical fields (body_weight_kg / body_weight_pct /
-- medical_hold / medical_note) are Art 9 health data. Per decisions §150 the
-- code path is built now but FAIL-CLOSED: a checkpoint must set
-- requires_weigh_in = true (default false) AND the RPC caller must pass
-- p_health_consent = true for any health field to persist; otherwise they are
-- dropped. The columns are column-SELECT-locked so anon / authenticated cannot
-- read them off the public results surface — organisers read them through
-- fetch_checkpoint_crossings_for_organiser. Production enablement is gated on
-- owner + CISO + counsel sign-off (a deploy checklist item, not missing code).

-- ──────────────────────────────── tables ────────────────────────────────

create table event_checkpoints (
  id                uuid primary key default gen_random_uuid(),
  event_id          uuid not null references events(id) on delete cascade,
  name              text not null check (length(name) between 1 and 120),
  ordinal           integer not null,
  route_marker_id   uuid references route_markers(id) on delete set null,
  position_m        numeric(10, 2),
  cutoff_elapsed_s  integer check (cutoff_elapsed_s is null or cutoff_elapsed_s >= 0),
  cutoff_clock      text check (cutoff_clock is null or cutoff_clock ~ '^[0-2][0-9]:[0-5][0-9]$'),
  requires_weigh_in boolean not null default false,
  created_by        uuid references auth.users not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (event_id, ordinal)
);

create index event_checkpoints_event on event_checkpoints (event_id, ordinal);

comment on column event_checkpoints.requires_weigh_in is
  'When true, this checkpoint collects Art 9 health data (body weight / medical '
  'hold). The fail-closed gate (decisions §150): health fields persist only when '
  'this is true AND the upsert RPC caller passes p_health_consent. Default false.';

create table checkpoint_crossings (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references events(id) on delete cascade,
  checkpoint_id   uuid not null references event_checkpoints(id) on delete cascade,
  instance_start  timestamptz not null,
  user_id         uuid references auth.users on delete set null,
  bib             text,
  runner_name     text,
  in_time         timestamptz,
  out_time        timestamptz,
  -- P3 Art 9 health data — fail-closed (see header + decisions §150).
  body_weight_kg  numeric(5, 2) check (body_weight_kg is null or body_weight_kg between 20 and 400),
  body_weight_pct numeric(5, 2),
  medical_hold    boolean not null default false,
  medical_note    text,
  recorded_by     uuid references auth.users on delete set null,
  recorded_at     timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint checkpoint_crossings_identity_chk
    check (user_id is not null or bib is not null),
  constraint checkpoint_crossings_account_uniq
    unique (event_id, checkpoint_id, instance_start, user_id),
  constraint checkpoint_crossings_bib_uniq
    unique (event_id, checkpoint_id, instance_start, bib)
);

create index checkpoint_crossings_event on checkpoint_crossings (event_id, instance_start);
create index checkpoint_crossings_checkpoint on checkpoint_crossings (checkpoint_id);

comment on column checkpoint_crossings.body_weight_kg is
  'Art 9 health data. Column-SELECT-locked from anon/authenticated; readable '
  'only via fetch_checkpoint_crossings_for_organiser. Written only when the '
  'checkpoint requires_weigh_in AND the RPC caller consented (decisions §150).';

-- ───────────────────────────────── RLS ──────────────────────────────────

alter table event_checkpoints enable row level security;
alter table checkpoint_crossings enable row level security;

-- Checkpoints are non-sensitive race structure: readable by anyone who can see
-- the event (is_event_visible covers public-club / member / owner + the
-- event-level is_public gate, 20270113_001), written by event organisers.
create policy event_checkpoints_select
  on event_checkpoints for select
  using (is_event_visible(event_id));

create policy event_checkpoints_insert_organiser
  on event_checkpoints for insert
  with check (
    exists (
      select 1 from events e
      where e.id = event_checkpoints.event_id
        and private.is_event_organiser(e.club_id)
    )
  );

create policy event_checkpoints_update_organiser
  on event_checkpoints for update
  using (
    exists (
      select 1 from events e
      where e.id = event_checkpoints.event_id
        and private.is_event_organiser(e.club_id)
    )
  );

create policy event_checkpoints_delete_organiser
  on event_checkpoints for delete
  using (
    exists (
      select 1 from events e
      where e.id = event_checkpoints.event_id
        and private.is_event_organiser(e.club_id)
    )
  );

-- Crossings row-visibility = event-visibility, so the public results page can
-- read a public race's splits (account-optional). Health columns are
-- column-locked below; writes are RPC-only (no INSERT/UPDATE/DELETE policy), so
-- the merge logic can never be bypassed by a direct table write.
create policy checkpoint_crossings_select
  on checkpoint_crossings for select
  using (is_event_visible(event_id));

-- Column-SELECT-lock the Art 9 fields. revoke the table default, then grant
-- back only the non-health columns to anon/authenticated. The health columns
-- (body_weight_kg / body_weight_pct / medical_hold / medical_note) and
-- recorded_by are then deny-by-default for these roles; the organiser read
-- path is the SECURITY DEFINER RPC below.
revoke all on checkpoint_crossings from anon, authenticated;
grant select (
  id, event_id, checkpoint_id, instance_start,
  user_id, bib, runner_name, in_time, out_time, recorded_at, updated_at
) on checkpoint_crossings to anon, authenticated;

-- ────────────────────── upsert RPC (single writer) ──────────────────────

-- The ONE writer for checkpoint_crossings. SECURITY DEFINER so it can do the
-- merge across two client-minted UUIDs and bypass the (deliberately absent)
-- direct-write RLS. Authorises the caller as an organiser, enforces the
-- fail-closed health gate, then inserts or merges (earliest in / latest out).
create or replace function upsert_checkpoint_crossing(
  p_event_id        uuid,
  p_checkpoint_id   uuid,
  p_instance_start  timestamptz,
  p_user_id         uuid       default null,
  p_bib             text       default null,
  p_runner_name     text       default null,
  p_in_time         timestamptz default null,
  p_out_time        timestamptz default null,
  p_health_consent  boolean    default false,
  p_body_weight_kg  numeric    default null,
  p_body_weight_pct numeric    default null,
  p_medical_hold    boolean    default null,
  p_medical_note    text       default null
)
returns checkpoint_crossings
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_club              uuid;
  v_requires_weigh_in boolean;
  v_allow_health      boolean;
  v_existing          checkpoint_crossings;
  v_result            checkpoint_crossings;
begin
  -- authz: the caller must be an organiser of the checkpoint's event.
  select e.club_id into v_club from events e where e.id = p_event_id;
  if v_club is null then
    raise exception 'event not found' using errcode = '42704';
  end if;
  if not is_event_organiser(v_club) then
    raise exception 'not an event organiser' using errcode = '42501';
  end if;

  -- the checkpoint must belong to the event.
  select requires_weigh_in into v_requires_weigh_in
  from event_checkpoints
  where id = p_checkpoint_id and event_id = p_event_id;
  if not found then
    raise exception 'checkpoint not in event' using errcode = '23503';
  end if;

  if p_user_id is null and p_bib is null then
    raise exception 'crossing needs a user_id or a bib' using errcode = '23514';
  end if;

  -- fail-closed health gate (decisions §150).
  v_allow_health := coalesce(v_requires_weigh_in, false)
                and coalesce(p_health_consent, false);

  -- find an existing crossing for this (checkpoint, instance, identity).
  select * into v_existing
  from checkpoint_crossings cc
  where cc.checkpoint_id = p_checkpoint_id
    and cc.instance_start = p_instance_start
    and (
      (p_user_id is not null and cc.user_id = p_user_id)
      or (p_user_id is null and p_bib is not null and cc.bib = p_bib)
    )
  limit 1;

  if v_existing.id is null then
    insert into checkpoint_crossings (
      event_id, checkpoint_id, instance_start, user_id, bib, runner_name,
      in_time, out_time, recorded_by,
      body_weight_kg, body_weight_pct, medical_hold, medical_note
    ) values (
      p_event_id, p_checkpoint_id, p_instance_start, p_user_id, p_bib, p_runner_name,
      p_in_time, p_out_time, auth.uid(),
      case when v_allow_health then p_body_weight_kg end,
      case when v_allow_health then p_body_weight_pct end,
      case when v_allow_health then coalesce(p_medical_hold, false) else false end,
      case when v_allow_health then p_medical_note end
    )
    returning * into v_result;
  else
    -- merge in/out: least()/greatest() ignore NULLs, so this is earliest-in,
    -- latest-out, and fills whichever field the other volunteer left blank.
    update checkpoint_crossings cc set
      in_time         = least(cc.in_time, p_in_time),
      out_time        = greatest(cc.out_time, p_out_time),
      runner_name     = coalesce(cc.runner_name, p_runner_name),
      recorded_by     = coalesce(auth.uid(), cc.recorded_by),
      body_weight_kg  = case when v_allow_health then coalesce(p_body_weight_kg, cc.body_weight_kg) else cc.body_weight_kg end,
      body_weight_pct = case when v_allow_health then coalesce(p_body_weight_pct, cc.body_weight_pct) else cc.body_weight_pct end,
      medical_hold    = case when v_allow_health then coalesce(p_medical_hold, cc.medical_hold) else cc.medical_hold end,
      medical_note    = case when v_allow_health then coalesce(p_medical_note, cc.medical_note) else cc.medical_note end,
      updated_at      = now()
    where cc.id = v_existing.id
    returning * into v_result;
  end if;

  return v_result;
end;
$$;

revoke all on function upsert_checkpoint_crossing(
  uuid, uuid, timestamptz, uuid, text, text, timestamptz, timestamptz,
  boolean, numeric, numeric, boolean, text
) from public, anon;
grant execute on function upsert_checkpoint_crossing(
  uuid, uuid, timestamptz, uuid, text, text, timestamptz, timestamptz,
  boolean, numeric, numeric, boolean, text
) to authenticated;

-- ─────────────── organiser read (incl. Art 9 health columns) ───────────────

-- The organiser dashboard read path: returns every crossing for an event
-- instance INCLUDING the column-locked health fields. SECURITY DEFINER, gated
-- on is_event_organiser, so health data only reaches a race official.
create or replace function fetch_checkpoint_crossings_for_organiser(
  p_event_id       uuid,
  p_instance_start timestamptz
)
returns setof checkpoint_crossings
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_club uuid;
begin
  select e.club_id into v_club from events e where e.id = p_event_id;
  if v_club is null then
    raise exception 'event not found' using errcode = '42704';
  end if;
  if not is_event_organiser(v_club) then
    raise exception 'not an event organiser' using errcode = '42501';
  end if;

  return query
    select * from checkpoint_crossings cc
    where cc.event_id = p_event_id
      and cc.instance_start = p_instance_start
    order by cc.checkpoint_id, cc.in_time;
end;
$$;

revoke all on function fetch_checkpoint_crossings_for_organiser(uuid, timestamptz)
  from public, anon;
grant execute on function fetch_checkpoint_crossings_for_organiser(uuid, timestamptz)
  to authenticated;
