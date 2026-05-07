-- /audit/all Medium (public-rows): `race_sessions.started_by` and
-- `race_sessions.auto_approve` are returned to every authenticated
-- user who can see the parent event — including non-members of a
-- public club. The columns are organisational metadata (which admin
-- pressed Start; whether the club uses auto-approve verification),
-- not user PII, but they're not in the documented public-spectator
-- contract.
--
-- The shape of the fix mirrors event_results_redacted (20260805_001
-- + 20260809_001): a `security_invoker = on` view whose row-filter
-- inherits the underlying table's RLS, with the sensitive columns
-- masked behind a `case when is_club_admin(...) then ... else null
-- end` branch. Spectator clients read from the redacted view; admin
-- UI keeps reading the base table where they have row + column
-- access.
--
-- Realtime caveat: the existing realtime subscriptions in
-- `apps/web/src/routes/clubs/[slug]/events/[id]/+page.svelte:342`
-- and `apps/web/src/routes/live/event/[id]/[instance]/+page.svelte:146`
-- subscribe to the BASE `race_sessions` table. Postgres logical
-- replication (which Realtime uses) broadcasts the full row in the
-- WAL payload — column-level grants don't filter realtime. So a
-- non-admin spectator with realtime open would still receive
-- `started_by` + `auto_approve` in the WS payload on row changes.
-- Today no client reads those fields off the realtime event (both
-- subscriptions parse only `status` / `started_at` / `finished_at`
-- to drive the spectator timer + state), so the actual exposure
-- is "an attacker who subscribes + parses raw realtime payloads"
-- — narrower than the REST-scrape route the audit flagged.
--
-- Closing the realtime path completely needs Supabase Realtime RLS
-- (a separate feature) or moving the columns to a sibling table
-- not in `supabase_realtime`. Both are larger surgery than the
-- audit's actual finding warrants, so we close the REST path here
-- and leave the realtime broadcast as a documented Low.

create or replace view race_sessions_redacted as
select
  event_id,
  instance_start,
  status,
  started_at,
  finished_at,
  created_at,
  updated_at,
  case
    when is_club_admin(
      (select club_id from events where id = race_sessions.event_id)
    ) then started_by
    else null
  end as started_by,
  case
    when is_club_admin(
      (select club_id from events where id = race_sessions.event_id)
    ) then auto_approve
    else null
  end as auto_approve
from race_sessions;

alter view race_sessions_redacted set (security_invoker = on);

grant select on race_sessions_redacted to anon, authenticated;

comment on view race_sessions_redacted is
  'Spectator read surface for race_sessions. Masks `started_by` and '
  '`auto_approve` for non-admin viewers. Admin UIs (Race control card '
  'on event_detail_screen / +page.svelte) keep reading the base '
  'race_sessions table for the unredacted columns.';
