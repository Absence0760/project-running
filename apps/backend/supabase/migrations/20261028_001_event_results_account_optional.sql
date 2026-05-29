-- Persona #43 (event-organiser): bulk-import chip-timing results.
--
-- A chip-timing CSV is keyed on BIB + printed name + time, for finishers
-- who mostly have NO account. `event_results` was built entirely around
-- account holders: `user_id` was NOT NULL, FK to auth.users, and part of
-- the primary key, and INSERT RLS was self-only. None of that lets an
-- organiser write a row for a bib-only finisher.
--
-- This migration makes the table account-OPTIONAL while keeping every
-- existing invariant for account rows:
--
--   * A surrogate `id` PK replaces (event_id, instance_start, user_id) —
--     a nullable user_id can't sit in a PK.
--   * `user_id` becomes nullable; `bib` + `finisher_name` carry the
--     identity of a non-account finisher.
--   * Two plain UNIQUE constraints (NOT partial) preserve the old
--     one-result-per-(account|bib)-per-instance rule. SQL treats NULLs as
--     distinct, so account rows (bib NULL) never collide on the bib
--     constraint and bib rows (user_id NULL) never collide on the account
--     constraint. Keeping them non-partial means PostgREST `onConflict`
--     can still use them as upsert arbiters (the self-submit path upserts
--     on (event_id, instance_start, user_id); the bulk-import path upserts
--     on (event_id, instance_start, bib)).
--   * A CHECK forces every row to identify its finisher by an account OR
--     a bib+name — no fully-anonymous ghost rows.
--   * An additive INSERT policy lets a club's event-organiser (owner /
--     admin / event_organiser) write rows on events they run. The
--     existing self-insert policy is untouched; Postgres OR's them, so an
--     account holder still posts their own time and an organiser can bulk
--     import. A non-organiser still can't forge a result (the pinned
--     20260613_001 test).
--
-- The rerank trigger already ranks every finished row in an
-- (event_id, instance_start) group by ascending duration, so bib-only
-- finishers land on the leaderboard with no trigger change.

alter table event_results drop constraint event_results_pkey;

alter table event_results
  add column id uuid not null default gen_random_uuid();

alter table event_results add primary key (id);

alter table event_results alter column user_id drop not null;

alter table event_results
  add column bib text,
  add column finisher_name text;

alter table event_results
  add constraint event_results_account_uniq
  unique (event_id, instance_start, user_id);

alter table event_results
  add constraint event_results_bib_uniq
  unique (event_id, instance_start, bib);

alter table event_results
  add constraint event_results_identity_chk
  check (user_id is not null or (bib is not null and finisher_name is not null));

-- Organiser INSERT path for bulk import. Additive to event_results_insert_self
-- (20260613_001) — both are permissive, so OR semantics apply. is_event_organiser
-- covers owner / admin / event_organiser and inherently implies the caller can
-- see the event, so no extra visibility clause is needed.
create policy event_results_insert_organiser
  on event_results for insert
  with check (
    exists (
      select 1 from events e
      where e.id = event_results.event_id
        and is_event_organiser(e.club_id)
    )
  );

-- Expose bib + finisher_name on the leaderboard read surface so the client
-- can render a name for bib-only rows (user_id NULL). These are public race
-- data (a bib number is worn visibly; the finisher name is printed in
-- official results), so they are NOT redacted. run_id / age_grade_pct / note
-- stay owner-only via the auth.uid() case branches — rebuilt verbatim from
-- 20260809_001, the live body, per the "create or replace strips prior fixes"
-- rule.
drop view if exists event_results_redacted;

create view event_results_redacted as
select
  event_id,
  instance_start,
  user_id,
  bib,
  finisher_name,
  duration_s,
  distance_m,
  rank,
  finisher_status,
  case
    when user_id = auth.uid() then age_grade_pct
    else null
  end as age_grade_pct,
  case
    when user_id = auth.uid() then note
    else null
  end as note,
  created_at,
  updated_at,
  organiser_approved,
  case
    when user_id = auth.uid() then run_id
    else null
  end as run_id
from event_results;

alter view event_results_redacted set (security_invoker = on);

grant select on event_results_redacted to anon, authenticated;
