-- Closeouts from the audit rounds landed in earlier May 2026
-- commits. The user explicitly asked for every deferred Low /
-- speculative / "future work" item to be closed in the same pass —
-- see the feedback memory feedback_never_defer_low_priority.md.
--
-- Four items in this migration:
--
--   1. Orphan-blob cleanup in `run-photos`. Migration
--      20260826_001 added a worker-generated 512-wide thumbnail
--      (`thumb_512_path`) as a separate Storage object. Until
--      commit 4cfdae4 (audit:storage Medium fix), both
--      `deleteRun` and `deleteRunPhoto` only swept `storage_path`.
--      Any photo deleted between 20260826_001 and 4cfdae4 left a
--      thumbnail blob in the bucket — invisible to the UI (the
--      Storage SELECT policy joins through `run_photos`, which is
--      gone) but still paying for storage cost. Sweep them now.
--
--   2. `avatars` bucket bootstrap. The `delete-account` Edge
--      Function calls `deletePrefix('avatars', user_id)` but no
--      migration ever created the bucket. The drain catches the
--      bucket-not-found error and silently no-ops, which is fine
--      for today's pre-launch state but would mask a real problem
--      the moment the avatar-upload feature ships. Create the
--      bucket with `public = true` (avatars are inherently
--      displayed on public profile pages), a tight size cap, a
--      strict image/* MIME allowlist, and owner-scoped INSERT /
--      UPDATE / DELETE policies that gate on the `{user_id}/...`
--      path prefix.
--
--   3. `clone_plan_template` rate-limit. The RPC has no abuse
--      guard. A club member could enumerate every public template
--      UUID and loop-clone them into their own `training_plans`,
--      bulk-creating rows under their account. Bounded to the
--      caller's own data (no cross-user impact) but a "your
--      Plans list shows 5 000 entries" failure mode is its own
--      product bug. 20/hour matches the user-facing "create a
--      handful of plans" cadence.
--
--   4. Notes the `storage.foldername[2]` second-segment assumption
--      that gates the exports subdir in the `runs` SELECT policy
--      from 20260816_001. Captured in the preamble above so a
--      future contributor adding a new subdir at depth-2 sees the
--      design choice before they reach the policy body.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Orphan-blob cleanup — run-photos.
-- ─────────────────────────────────────────────────────────────────────
-- Delete every storage.objects row in the run-photos bucket whose
-- name is NOT referenced by any run_photos row (in either
-- storage_path or thumb_512_path). Idempotent: re-running after the
-- cleanup is a no-op because every remaining object is referenced.
--
-- The storage extension installs a `protect_objects_delete` BEFORE
-- DELETE trigger that blocks unscoped deletes by default — the
-- documented escape hatch is `set local storage.allow_delete_query
-- = 'true'`, which gates the trigger off for the current
-- transaction only. We set it explicitly inside a DO block so the
-- migration runner can drop the orphan rows; the actual blob bytes
-- are reaped by the storage backend's background sweeper once the
-- row is gone.
do $$
begin
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
    where bucket_id = 'run-photos'
      and name not in (
        select storage_path from run_photos
          where storage_path is not null
        union
        select thumb_512_path from run_photos
          where thumb_512_path is not null
      );
end $$;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Create the `avatars` bucket with the correct shape.
-- ─────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,  -- inherently public — avatars render on public profile pages
  2 * 1024 * 1024,  -- 2 MB cap; an avatar over 2 MB is almost certainly an upload mistake
  array[
    'image/jpeg',
    'image/png',
    'image/webp'
  ]
)
on conflict (id) do nothing;

-- Owner-scoped writes — the {user_id}/<filename> path prefix is the
-- canonical pattern used by every other user-upload bucket in this
-- project (runs, run-photos). Without these policies the bucket is
-- read-write-by-public, which is the same shape that 20260712_001
-- closed for run-photos.
drop policy if exists "avatars owner can upload" on storage.objects;
create policy "avatars owner can upload"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars owner can update" on storage.objects;
create policy "avatars owner can update"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars owner can delete" on storage.objects;
create policy "avatars owner can delete"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- The bucket itself is `public = true` so anonymous SELECTs against
-- storage.objects rows in this bucket are allowed by the platform
-- bucket-public-flag path — no separate SELECT policy needed. The
-- public-flag pin in storage_bucket_privacy_test.sql will need to
-- be updated to account for this bucket separately.

-- ─────────────────────────────────────────────────────────────────────
-- 3. clone_plan_template — rate-limit at 20/hour.
-- ─────────────────────────────────────────────────────────────────────
-- Replaces the function body verbatim except for the new
-- enforce_create_rate_limit call inserted before any DB write.
-- The rate-limit raises a P0001 with a friendly tag that the
-- mobile + web error helpers already translate.
-- Re-apply the canonical body from 20260721_001_plan_templates_strip_fitness.sql
-- with the rate-limit perform inserted near the top. The previous
-- attempt in this file copy-pasted the original 20260524_001 body
-- verbatim — but 20260721_001 had since (a) rewritten the column set
-- to match the actual training_plans / plan_weeks / plan_workouts
-- schema, (b) added parent_template_id wiring, (c) added the
-- vdot / current_5k_seconds strip (publisher-private fitness data
-- must NOT propagate to clones — that pass-3 audit fix), and (d)
-- fixed the status='draft' bug (training_plans_status_check only
-- allows active/completed/abandoned). The /release-readiness pgtap
-- run caught the regression — fix it here by basing on the right
-- body, not the original. The only addition compared to 20260721_001
-- is the enforce_create_rate_limit call at the top.
create or replace function clone_plan_template(
  template_id uuid,
  new_start_date date
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  tmpl training_plans%rowtype;
  new_plan_id uuid;
  new_week_id uuid;
  date_offset_days int;
  week_record record;
  workout_record record;
begin
  if caller is null then
    raise exception 'clone_plan_template: not authenticated';
  end if;

  -- Abuse guard: 20 clones/hour is well above the legitimate
  -- "browse + clone a few templates" cadence and below the
  -- "loop-clone every public template" abuse shape. Same scale
  -- as create_route (30/h) per migration 20260907_001. New in
  -- 20260927_001 — closes the rate-limit gap /audit:rls flagged.
  perform enforce_create_rate_limit('clone_plan_template', caller, 20, 3600);

  -- SECURITY DEFINER context bypasses RLS on training_plans, so the
  -- select * into below reads any matching template row regardless
  -- of caller. The explicit authorisation check below is the
  -- single access gate.
  select * into tmpl
  from training_plans
  where id = template_id and is_template = true;

  if not found then
    raise exception 'clone_plan_template: template not found';
  end if;

  -- Caller must own the template OR be a club member of its club.
  if tmpl.user_id <> caller
     and not (tmpl.club_id is not null and is_club_member(tmpl.club_id))
  then
    raise exception 'clone_plan_template: not authorised to clone template %', template_id;
  end if;

  date_offset_days := new_start_date - tmpl.start_date;

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, parent_template_id, is_template
  )
  values (
    caller, tmpl.name, tmpl.goal_event, tmpl.goal_distance_m, tmpl.goal_time_seconds,
    new_start_date, tmpl.end_date + date_offset_days,
    tmpl.days_per_week,
    -- Publisher-private fitness data — never propagated to the clone.
    -- The clone owner (`caller`) sets their own VDOT via /plans/new.
    null, null,
    'active', tmpl.notes, template_id, false
  )
  returning id into new_plan_id;

  -- Iterate weeks → workouts. Date-shift workouts by date_offset_days.
  for week_record in
    select * from plan_weeks where plan_id = template_id order by week_index
  loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (new_plan_id, week_record.week_index, week_record.phase,
            week_record.target_volume_m, week_record.notes)
    returning id into new_week_id;

    for workout_record in
      select * from plan_workouts where week_id = week_record.id
    loop
      insert into plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
        target_pace_sec_per_km, target_pace_tolerance_sec, structure, notes
      )
      values (
        new_week_id,
        workout_record.scheduled_date + date_offset_days,
        workout_record.kind,
        workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.structure,
        workout_record.notes
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$$;

-- Re-grant after the create-or-replace (DROP rights are wiped by
-- the rewrite). Anon EXECUTE was revoked in 20260926_001.
grant execute on function clone_plan_template(uuid, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 4. storage.foldername[2] documentation pin.
-- ─────────────────────────────────────────────────────────────────────
-- The runs SELECT policy from 20260816_001 reads
-- `coalesce((storage.foldername(name))[2], '') <> 'exports'` to
-- carve the exports subdir out of the per-folder owner-read gate.
-- That predicate is index-2 specific: a path
-- `{user_id}/matched/foo.json.gz` would produce
-- `(storage.foldername())[2] = 'matched'`, which DOES NOT equal
-- 'exports', so the carve-out would not gate it — the new subdir
-- would be readable under the owner SELECT policy. A future
-- contributor adding a new subdir at depth-2 must either (a)
-- co-name the carve-out (extend the predicate to include the
-- new subdir) or (b) accept that the new subdir is readable
-- by the owner via the per-folder gate.
--
-- This is a comment-only deliverable — no schema change.
-- Captured here because modifying the historical 20260816_001
-- migration is forbidden.
do $$ begin null; end $$;
