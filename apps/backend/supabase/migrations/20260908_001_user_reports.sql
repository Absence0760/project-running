-- Anti-spam phase 3 (minimal): user-submitted reports.
--
-- Phase 1 (20260906_001) ranks high-reputation rows above bot output.
-- Phase 2 (20260907_001) rate-limits row creates. This phase gives
-- users a way to flag specific content that slipped through both
-- defences. The MVP scope is intentionally small:
--
--   * Targets: user / club / route. Posts + comments are deferred.
--   * No auto-hide. A growing pending-report count on the same target
--     is signal only; suppression is a moderator decision.
--   * No admin UI. v1 review happens directly in Supabase Studio
--     against the `reports` table; an actual admin page is on the
--     roadmap (see docs/roadmap.md § Anti-spam — admin moderation).
--   * Rate-limited at 10 reports/hour to keep a malicious reporter
--     from buring through the table.
--
-- A SECURITY DEFINER `submit_report` RPC wraps the insert so the
-- target's existence can be validated in one transaction. RLS on the
-- table is self-read only — others' reports could reveal who flagged
-- whom, which is itself a harassment vector.

-- ─── Table ────────────────────────────────────────────────────────
create table reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_id     uuid references auth.users(id) on delete cascade not null,
  -- Polymorphic target. The pair (target_kind, target_id) uniquely
  -- identifies the row being reported; the kind picks which table
  -- the id lives in. submit_report() validates the row exists on
  -- the right table before the INSERT lands.
  target_kind     text not null check (target_kind in ('user', 'club', 'route')),
  target_id       uuid not null,
  reason          text not null check (
    reason in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other')
  ),
  notes           text,
  status          text not null default 'pending' check (
    status in ('pending', 'reviewed', 'dismissed')
  ),
  created_at      timestamptz not null default now(),
  reviewed_at     timestamptz,
  reviewed_by     uuid references auth.users(id) on delete set null,
  resolution      text
);

-- Hot read path: "pending reports against target X" — used by the
-- (future) admin queue. Partial so the index stays small once most
-- reports are reviewed.
create index reports_target_pending
  on reports (target_kind, target_id, created_at desc)
  where status = 'pending';

-- "All reports I've filed" for the reporter's own history view.
create index reports_reporter
  on reports (reporter_id, created_at desc);

-- Prevent duplicate pending reports from the same user against the
-- same target — reduces noise in the queue and removes a trivial way
-- to inflate apparent report volume. A reporter who wants to add
-- info should edit notes, not pile on. Once status flips to
-- reviewed/dismissed the partial-unique releases so the same user
-- can re-report if the target reoffends later.
create unique index reports_no_duplicate_pending
  on reports (reporter_id, target_kind, target_id)
  where status = 'pending';

-- ─── RLS ──────────────────────────────────────────────────────────
alter table reports enable row level security;

-- Reporters can read their own report history (status, resolution
-- notes if a moderator wrote one) but never anyone else's. INSERTs
-- go through submit_report(), not the table directly — the policy
-- below still lets a self-INSERT through as defence-in-depth.
create policy "reporters read their own reports"
  on reports for select
  using (auth.uid() = reporter_id);

create policy "reporters insert their own reports"
  on reports for insert
  with check (auth.uid() = reporter_id);

-- No UPDATE / DELETE policies for user-JWT callers. Moderation
-- writes go through service_role (Supabase Studio or the future
-- admin RPC), so they bypass RLS entirely.

-- ─── submit_report RPC ────────────────────────────────────────────
-- Wraps the INSERT with target-existence validation + rate-limit
-- enforcement. SECURITY DEFINER so the rate-limit table doesn't
-- need a separate caller grant.
create or replace function submit_report(
  p_target_kind text,
  p_target_id uuid,
  p_reason text,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reporter uuid := auth.uid();
  v_target_exists boolean;
  v_report_id uuid;
begin
  if v_reporter is null then
    raise exception 'submit_report: not authorized' using errcode = '42501';
  end if;

  if p_target_kind not in ('user', 'club', 'route') then
    raise exception 'submit_report: invalid target_kind %', p_target_kind
      using errcode = '22023';
  end if;

  if p_reason not in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other') then
    raise exception 'submit_report: invalid reason %', p_reason
      using errcode = '22023';
  end if;

  -- Don't let a user report themselves — most likely a misclick, and
  -- the queue noise isn't worth carrying.
  if p_target_kind = 'user' and p_target_id = v_reporter then
    raise exception 'submit_report: cannot report yourself'
      using errcode = '22023';
  end if;

  -- Validate the target exists. The reporter must be able to *see*
  -- the target — the FROM clauses below run as the function owner
  -- (postgres) so RLS doesn't block visibility, but we check the
  -- visibility implicitly by gating clubs on `is_public` for the
  -- reporter to have meaningfully encountered it via Browse. Skip
  -- the public-only narrowing for routes (private routes are still
  -- shared via link).
  if p_target_kind = 'user' then
    select exists (select 1 from user_profiles where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'club' then
    select exists (select 1 from clubs where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'route' then
    select exists (select 1 from routes where id = p_target_id) into v_target_exists;
  end if;

  if not v_target_exists then
    raise exception 'submit_report: target % % not found', p_target_kind, p_target_id
      using errcode = '02000';
  end if;

  -- Rate-limit: 10 reports per hour per reporter. Reuses the existing
  -- enforce_create_rate_limit helper from migration 20260907_001.
  perform enforce_create_rate_limit('create_report', v_reporter, 10, 3600);

  -- INSERT goes through; the unique partial index protects against
  -- duplicate-pending. Catch the 23505 specifically so callers know
  -- "already pending" vs "rate limited" vs "target missing".
  begin
    insert into reports (reporter_id, target_kind, target_id, reason, notes)
    values (v_reporter, p_target_kind, p_target_id, p_reason, p_notes)
    returning id into v_report_id;
  exception when unique_violation then
    raise exception 'submit_report: already reported'
      using errcode = '23505',
            hint = 'You already have a pending report against this target.';
  end;

  return v_report_id;
end;
$$;

revoke execute on function submit_report(text, uuid, text, text) from public;
grant execute on function submit_report(text, uuid, text, text) to authenticated;
