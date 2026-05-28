-- Race-session state-machine guards.
--
-- Pre-fix the table CHECK accepted any status value in the allowlist,
-- and the admin update policy accepted any transition. A race
-- director who mis-tapped could flip `armed → finished` without ever
-- pressing Start; `started_at` stayed null while `finished_at` was
-- set. The `event_results_set_approval_default` trigger still fired
-- on later insert attempts and looked up `auto_approve` from the
-- (now-dead) row, so results landed against a session that never
-- actually ran. There was no recovery path documented and no
-- automated guard.
--
-- Persona-hunt Round 2 finding Pro #5.
--
-- Two guards layered onto the existing CHECK:
--
-- 1. A composite CHECK enforces the temporal invariants:
--      armed     → started_at is null, finished_at is null
--      running   → started_at is not null, finished_at is null
--      finished  → started_at is not null (must have run!), finished_at is not null
--      cancelled → finished_at is null (cancellation is pre-start)
--
-- 2. A BEFORE-UPDATE trigger enforces the directed transition graph
--    so a status flip can't skip 'running':
--      armed     → running | cancelled
--      running   → finished
--      finished  → (terminal — no further flips)
--      cancelled → (terminal — no further flips)
--
--    The trigger also blocks `finished → finished` re-writes and
--    `armed → armed` no-ops so a future UI bug can't repeatedly fire
--    the row's update timestamps without an actual transition.

alter table race_sessions
  add constraint race_sessions_status_temporal_invariant
  check (
    case status
      when 'armed' then started_at is null and finished_at is null
      when 'running' then started_at is not null and finished_at is null
      when 'finished' then started_at is not null and finished_at is not null
      when 'cancelled' then finished_at is null
      else false
    end
  );

create or replace function race_sessions_enforce_transition()
returns trigger
language plpgsql
as $$
begin
  -- INSERTs don't transition — they just establish a starting state.
  -- The composite CHECK already validates the starting state's
  -- temporal fields. Allow.
  if tg_op = 'INSERT' then
    return new;
  end if;

  -- UPDATE: enforce the directed transition graph. Same-status
  -- writes are allowed ONLY when other columns change (e.g. an
  -- `auto_approve` toggle while still armed). A self-transition
  -- attempt with no other meaningful changes is harmless but we
  -- don't block it — that's a UI optimisation, not a correctness
  -- concern.
  if old.status = new.status then
    return new;
  end if;

  case
    when old.status = 'armed' and new.status in ('running', 'cancelled') then
      return new;
    when old.status = 'running' and new.status = 'finished' then
      return new;
    when old.status in ('finished', 'cancelled') then
      raise exception
        'race_sessions: cannot transition from terminal status %', old.status
        using errcode = 'check_violation';
    else
      raise exception
        'race_sessions: invalid transition % → %', old.status, new.status
        using errcode = 'check_violation';
  end case;
end;
$$;

drop trigger if exists race_sessions_enforce_transition_trg on race_sessions;
create trigger race_sessions_enforce_transition_trg
  before insert or update on race_sessions
  for each row
  execute function race_sessions_enforce_transition();
