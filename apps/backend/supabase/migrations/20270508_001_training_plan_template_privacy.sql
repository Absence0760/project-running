-- A template row must not carry the publisher's private fitness fields.
--
-- `20260721_001` and `20270126_001` both describe the publisher's VDOT and
-- 5K time as "stripped on publish", and `20270126_001`'s header goes
-- further: "No runs, PII, or notes-with-PII leak". Nothing enforced any of
-- it. The strip lived only in the JS callers -- `publishPlanToLibrary` and
-- `publishPlanAsTemplate` in apps/web/src/lib/core/data.ts, and the mobile
-- twins in training_service.dart -- so both the read and the write path
-- went around it with one REST call:
--
--   POST /rest/v1/training_plans
--     {"is_template":true,"is_public_template":true,"vdot":55.3,
--      "current_5k_seconds":1080,"notes":"..."}
--   GET  /rest/v1/training_plans?is_public_template=eq.true&select=*
--
-- The SELECT policies ("anyone reads public plan templates",
-- "club members read club templates") are row-level only, and Postgres RLS
-- has no column dimension, so every column of a published row reaches every
-- authenticated reader.
--
-- `notes` was leaking through the SANCTIONED path, not merely a crafted
-- one: both publishers copy `notes: src.notes` from the source plan, and
-- plan-level notes is the runner's own free text -- training constraints,
-- injury history. Publishing a plan mailed it to the library.
--
-- ── Why a trigger, not the redacted-view pattern ──
--
-- `public_runs` / `public_gym_workouts` (20260626_001, 20270313_001) close
-- the same class by making the base table owner-only and routing non-owner
-- reads through a view. That shape does not fit here. Those tables are read
-- directly; a template's weeks and workouts are reached through policies on
-- `plan_weeks` / `plan_workouts` that sub-select `training_plans`, and a
-- policy sub-select is itself RLS-gated. Dropping the two template SELECT
-- branches would therefore blank the library preview and every club
-- template's contents, and restoring them would mean a SECURITY DEFINER
-- visibility helper plus a rewrite of eight dependent policies -- a much
-- wider blast radius than the leak.
--
-- The narrower invariant is also the truer one: a template row is a COPY
-- made for publishing (both publishers insert a sibling and leave the
-- source plan untouched), so these three columns have no reason to hold a
-- value on it at all. Enforcing that at write time fixes the stored data
-- rather than hiding it at read time, which also closes the rows already
-- published -- a view would leave those sitting in the table.
--
-- Consequence worth stating: plan-level `notes` is classified OWNER-ONLY,
-- the same call 20270313_001 made for `gym_workouts.notes`. An
-- author-written blurb describing a published template is a separate
-- feature and wants its own column, not the runner's private field.
-- Per-workout `plan_workouts.notes` is untouched -- that is plan design
-- ("8x400m at 5K pace"), which is the thing being published.

set search_path = public;

create or replace function private.strip_template_private_fields()
returns trigger
language plpgsql
as $$
begin
  if NEW.is_template = true then
    NEW.vdot := null;
    NEW.current_5k_seconds := null;
    NEW.notes := null;
  end if;
  return NEW;
end;
$$;

drop trigger if exists training_plans_strip_template_private_fields on training_plans;
create trigger training_plans_strip_template_private_fields
  before insert or update on training_plans
  for each row execute function private.strip_template_private_fields();

-- Close the rows already published. Templates are a small subset of
-- `training_plans` (one row per publish action), and the predicate is
-- further narrowed to rows that actually carry a value, so this touches
-- few rows and takes only per-row locks -- no table rewrite, no blocking
-- lock on the plans runners are reading.
update training_plans
   set vdot = null,
       current_5k_seconds = null,
       notes = null
 where is_template = true
   and (vdot is not null or current_5k_seconds is not null or notes is not null);
