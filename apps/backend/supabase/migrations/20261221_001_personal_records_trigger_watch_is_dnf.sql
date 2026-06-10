-- Widen the personal_records UPDATE trigger's column watch-list to
-- include is_dnf and metadata.
--
-- The cache refresher (refresh_personal_records_for_user) filters PR
-- candidates on runs.is_dnf and reads embedded-best metadata keys
-- (fastest_5k_s, …). But the AFTER UPDATE trigger added in
-- 20260508_001 only watches distance_m, duration_s, source, user_id —
-- it predates is_dnf's promotion from a metadata key to a real column
-- (20261207_001).
--
-- So toggling DNF on the web run-detail page — which updates ONLY
-- metadata + is_dnf (apps/web/src/routes/runs/[id]/+page.svelte) —
-- never fires the trigger. A run marked DNF stays in personal_records
-- as the user's PR, and un-marking DNF never adds the run back. The
-- cache stops equalling its authoritative recompute, violating the
-- derived_state.md contract. (The mobile path incidentally includes
-- distance_m/duration_s in its UPDATE SET, so it fires the trigger and
-- masks the bug — the drift is web-only.)
--
-- ALTER TRIGGER can't change the column list, so drop + recreate. The
-- trigger function is unchanged.

drop trigger if exists runs_personal_records_update on runs;

create trigger runs_personal_records_update
  after update of distance_m, duration_s, source, user_id, is_dnf, metadata on runs
  for each row
  execute function trigger_refresh_personal_records();
