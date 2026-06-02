-- RLS / SECURITY DEFINER hygiene, pass 3 (reviews/audit-rls.md, 2026-05-31).
--
-- Closes the net-new findings from the May 2026 RLS audit that were still
-- open:
--
--   * run_kudos_reject_self read only the legacy single-claim JWT format
--     (request.jwt.claim.role), which modern PostgREST no longer populates,
--     so its service_role bypass was dead. Restore the dual-format read used
--     everywhere since 20260726_001, and pin search_path.
--   * gear_set_updated_at had no pinned search_path (project convention is to
--     pin it on every trigger function).
--   * notify_direct_message / notify_event_cancel / notify_event_rsvp are
--     SECURITY DEFINER trigger functions still EXECUTE-able by anon +
--     authenticated. Trigger firing uses the function owner's rights, not a
--     caller grant, so revoking the RPC surface is pure defence-in-depth —
--     same shape as the auto_tag_default_gear lockdown (20260914_002) and the
--     approve_event_result / join_club_by_token / clone_plan_template revokes.
--   * event_results_redacted: the audit suggested removing security_invoker.
--     That is UNSAFE — the view's row visibility comes from event_results RLS
--     evaluated in the caller's context; with security_invoker off the view
--     would run as owner and bypass RLS, leaking private-event results to
--     anon. The flag is deliberate; documented here and pinned by pgtap.
--   * clone_plan_template fetches the template row before the authorisation
--     check (a standard SECURITY DEFINER manual-RLS-recheck pattern). No
--     bypass exists; documented so a future "return partial data on
--     not-found" refactor doesn't leak a private template's name.
--
-- enroll_club_owner (also flagged) already pins search_path=public in
-- 20260416_001 — that finding was stale; no change needed.

-- run_kudos_reject_self — full body re-emitted (create or replace strips the
-- prior body) with the modern dual-format JWT read + pinned search_path.
create or replace function run_kudos_reject_self()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  -- Service-role bypass — matches the project pattern from
  -- 20260616_001 (rate-limits), 20260709_001 (coach usage), and
  -- 20260718_001 (subscription tier insert guard). Service-role
  -- callers (Edge Functions, migrations, seed setup) are trusted to
  -- plant fixtures + cross-user setup state.
  if v_role = 'service_role' then return NEW; end if;
  -- Defensive null-check on the off chance an RPC fires the trigger
  -- with no auth context. The RLS INSERT policy already blocks
  -- anon client inserts, but a SECURITY DEFINER caller could in
  -- principle reach here with auth.uid() null after a refactor.
  if auth.uid() is null then return NEW; end if;
  if exists (
    select 1 from runs r
    where r.id = NEW.run_id
      and r.user_id = NEW.user_id
  ) then
    raise exception 'self_kudos_not_allowed'
      using errcode = 'check_violation';
  end if;
  return NEW;
end;
$$;

-- gear_set_updated_at — pin search_path (project convention).
create or replace function gear_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$;

-- Trigger functions never need a user-facing RPC grant; trigger firing uses
-- the function owner's rights. Revoke the vestigial EXECUTE grants.
revoke execute on function notify_direct_message() from public, anon, authenticated;
revoke execute on function notify_event_cancel() from public, anon, authenticated;
revoke execute on function notify_event_rsvp() from public, anon, authenticated;

comment on view event_results_redacted is
  'security_invoker=on is DELIBERATE: row visibility is enforced by '
  'event_results RLS evaluated in the caller''s context. Flipping it off '
  'would run the view as owner and bypass RLS, leaking results for '
  'private-club events to anon. Column-level redaction (age_grade_pct, '
  'note, run_id) is via CASE on auth.uid(). Pinned by '
  'event_results_redacted_invoker_test.sql.';

comment on function clone_plan_template(uuid, date) is
  'SECURITY DEFINER: fetches the template row (RLS-bypassed) then manually '
  're-checks authorisation (owner OR club member). The row is fetched before '
  'the check by design — any future change that returns partial data on a '
  'failed check (e.g. an error message embedding tmpl.name) would leak a '
  'private template''s name, so keep the raise paths name-free.';
