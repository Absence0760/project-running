-- Admin moderation surface for user reports (the `reports` table from
-- 20260908_001). Until now moderation was manual in Supabase Studio
-- against the table. This adds:
--
--   * an `app_admins` allow-list table (grant/revoke an admin by id),
--   * a `private.is_admin(uid)` oracle mirroring the membership-oracle
--     pattern (20261120_001) — lives in `private` so PostgREST does not
--     expose it as an anon-callable RPC,
--   * SECURITY DEFINER RPCs that drive the /admin/reports queue, each
--     HARD-DENYING a non-admin caller before touching report data, and
--   * a cheap `am_i_admin()` RPC the web client uses purely to pick the
--     page chrome (the real authorization boundary is the per-RPC admin
--     gate, since the web app is a statically-prerendered SPA where
--     client-side route gating is not a security control).
--
-- Triage-only for v1: an admin marks a target's pending reports
-- reviewed/dismissed with a resolution note. There is no takedown /
-- content-hide action — suppression stays a separate, deliberate step
-- (the original report MVP note already flagged auto-hide as
-- out-of-scope), so this migration does not flip any visibility flag.

-- ─── app_admins allow-list ────────────────────────────────────────
create table app_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  -- Who granted the admin (null for a bootstrap/seed grant). Self-FK to
  -- auth.users, not app_admins, so revoking the granter doesn't cascade
  -- away the grantee.
  granted_by uuid references auth.users(id) on delete set null
);

-- RLS: the table is its own admin oracle's backing store, so reads go
-- through SECURITY DEFINER (private.is_admin / am_i_admin) which own the
-- table as the definer. No user-JWT policy is created, so under RLS a
-- normal caller sees zero rows and cannot write — default-deny. Grants
-- to add/remove an admin happen via service_role (Studio) or seed.sql.
alter table app_admins enable row level security;

-- ─── is_admin oracle (private schema) ─────────────────────────────
-- SECURITY DEFINER so it can read app_admins under RLS; search_path
-- pinned; in `private` so it is not a PostgREST RPC oracle. Mirrors the
-- club/event membership oracles moved in 20261120_001.
create schema if not exists private;
grant usage on schema private to anon, authenticated, service_role;

create or replace function private.is_admin(uid uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (select 1 from app_admins where user_id = uid);
$$;

revoke execute on function private.is_admin(uuid) from public;
grant execute on function private.is_admin(uuid)
  to anon, authenticated, service_role;

-- ─── am_i_admin: cheap chrome gate for the web client ─────────────
-- The ONLY admin function exposed in `public` (PostgREST-callable). It
-- discloses nothing an authenticated caller can't already infer about
-- *themselves*, and the report RPCs below do the real gating.
create or replace function am_i_admin()
returns boolean
language sql
security definer
set search_path = public, private
as $$
  select coalesce(private.is_admin(auth.uid()), false);
$$;

revoke execute on function am_i_admin() from public;
grant execute on function am_i_admin() to authenticated;

-- ─── fetch_pending_reports: the queue ─────────────────────────────
-- One row per reported target with pending reports, newest-active
-- first. Drives the triage list without N round-trips.
create or replace function fetch_pending_reports()
returns table (
  target_kind     text,
  target_id       uuid,
  report_count    bigint,
  reporter_count  bigint,
  reasons         jsonb,
  latest_at       timestamptz
)
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'fetch_pending_reports: not authorized'
      using errcode = '42501';
  end if;

  return query
    with pending as (
      select r.target_kind as tk, r.target_id as tid,
             r.reporter_id as rid, r.reason as rsn, r.created_at as cat
      from reports r
      where r.status = 'pending'
    ),
    by_reason as (
      select g.tk, g.tid, jsonb_object_agg(g.rsn, g.n) as reasons
      from (
        select p.tk, p.tid, p.rsn, count(*) as n
        from pending p
        group by p.tk, p.tid, p.rsn
      ) g
      group by g.tk, g.tid
    )
    select
      p.tk,
      p.tid,
      count(*)                      as report_count,
      count(distinct p.rid)         as reporter_count,
      br.reasons,
      max(p.cat)                    as latest_at
    from pending p
    join by_reason br on br.tk = p.tk and br.tid = p.tid
    group by p.tk, p.tid, br.reasons
    order by max(p.cat) desc;
end;
$$;

revoke execute on function fetch_pending_reports() from public;
grant execute on function fetch_pending_reports() to authenticated;

-- ─── fetch_reports_for_target: the detail panel ───────────────────
-- Every report (any status) against one target, newest first.
create or replace function fetch_reports_for_target(
  p_target_kind text,
  p_target_id   uuid
)
returns table (
  id           uuid,
  reporter_id  uuid,
  reason       text,
  notes        text,
  status       text,
  created_at   timestamptz,
  reviewed_at  timestamptz,
  reviewed_by  uuid,
  resolution   text
)
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'fetch_reports_for_target: not authorized'
      using errcode = '42501';
  end if;

  return query
    select r.id, r.reporter_id, r.reason, r.notes, r.status,
           r.created_at, r.reviewed_at, r.reviewed_by, r.resolution
    from reports r
    where r.target_kind = p_target_kind
      and r.target_id = p_target_id
    order by r.created_at desc;
end;
$$;

revoke execute on function fetch_reports_for_target(text, uuid) from public;
grant execute on function fetch_reports_for_target(text, uuid) to authenticated;

-- ─── resolve_target_reports: the triage action ────────────────────
-- Mark all pending reports on one target reviewed/dismissed, stamping
-- reviewer + time + a resolution note. Returns the number of rows
-- resolved so the client can confirm.
create or replace function resolve_target_reports(
  p_target_kind text,
  p_target_id   uuid,
  p_status      text,
  p_resolution  text default null
)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_admin uuid := auth.uid();
  v_count integer;
begin
  if not private.is_admin(v_admin) then
    raise exception 'resolve_target_reports: not authorized'
      using errcode = '42501';
  end if;

  if p_status not in ('reviewed', 'dismissed') then
    raise exception 'resolve_target_reports: invalid status %', p_status
      using errcode = '22023';
  end if;

  update reports
    set status      = p_status,
        resolution  = p_resolution,
        reviewed_by = v_admin,
        reviewed_at = now()
  where target_kind = p_target_kind
    and target_id = p_target_id
    and status = 'pending';

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function resolve_target_reports(text, uuid, text, text) from public;
grant execute on function resolve_target_reports(text, uuid, text, text) to authenticated;
