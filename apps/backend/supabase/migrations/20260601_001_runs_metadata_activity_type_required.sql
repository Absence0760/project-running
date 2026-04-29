-- Guardrail: every `runs` row must carry `metadata.activity_type`.
--
-- Why: the April 2026 cross-client audit found that Apple Watch
-- payloads were arriving with no activity_type set, which meant runs
-- coming from one platform looked subtly different from another to
-- downstream readers (the dashboard groups by activity_type, the
-- coach prompt asks the model "what kind of activity"). Every writer
-- was patched to set the key (see commits in apps/web,
-- apps/mobile_*/lib, apps/backend/.../parkrun-import,
-- apps/watch_wear, apps/watch_ios). This migration locks in that
-- invariant at the database level so a future writer can't reintroduce
-- the gap silently — postgres rejects the insert with 23514
-- check_violation.
--
-- Two-step rollout, both in this same migration:
-- 1. Backfill existing rows whose metadata is missing the key.
--    metadata is jsonb; coalesce to '{"activity_type": "run"}'
--    when null, otherwise merge in the key when absent. 'run' is
--    the right default — the audit found legacy rows came from the
--    pre-activity_type web manual-entry path, which only ever
--    handled running.
-- 2. Add a CHECK constraint that requires
--    metadata->>'activity_type' to be a non-empty string. NOT NULL
--    on jsonb wouldn't work (the field could exist but be null);
--    using ->> with a length check covers both.
--
-- Reads still tolerate the key being absent (web run-detail page +
-- Dart run_detail_screen.dart both fall back to 'run'), so the
-- backfill is non-disruptive.

-- 1. Backfill.
update runs
set metadata = jsonb_build_object('activity_type', 'run')
where metadata is null;

update runs
set metadata = metadata || jsonb_build_object('activity_type', 'run')
where metadata is not null
  and (metadata->>'activity_type') is null;

-- 2. CHECK constraint. Postgres rejects future writes whose
--    metadata.activity_type is null, missing, or empty.
alter table runs
  add constraint runs_metadata_activity_type_check
    check (
      metadata is not null
      and metadata ? 'activity_type'
      and length(coalesce(metadata->>'activity_type', '')) > 0
    );
