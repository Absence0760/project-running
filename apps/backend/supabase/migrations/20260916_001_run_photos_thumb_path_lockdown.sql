-- audit/storage (May 2026) found that the `thumb_512_path` column added
-- in 20260826_001 had no path-shape CHECK and was writable by the row
-- owner via the broad "photo owner updates caption" UPDATE policy.
--
-- Combined with the SELECT policy added in the same migration —
-- "rp.storage_path = name OR rp.thumb_512_path = name" — an
-- authenticated user can PATCH their own run_photos row, setting
-- thumb_512_path to a path under another user's prefix; the read
-- policy then approves a Storage SELECT on that path. Cross-user
-- read of arbitrary objects in the run-photos bucket.
--
-- Fix:
-- 1. CHECK constraint mirroring run_photos_storage_path_shape
--    (20260622_001) so the column can't reference an alien prefix.
--    thumb_512_path is nullable so NULL passes too.
-- 2. BEFORE UPDATE trigger that blocks any user-side change to
--    thumb_512_path. The thumbnail is service-role-only by design
--    (the worker writes it after the original upload completes);
--    no user-driven path should ever touch this column.

-- ─────────────────── path-shape CHECK ───────────────────

-- not valid: there may be in-flight rows from local test fixtures
-- that don't satisfy the constraint; the audit fix lands cleanly
-- without a rewrite of historical data. Then validate.
alter table public.run_photos
  add constraint run_photos_thumb_512_path_shape
  check (
    thumb_512_path is null
    or thumb_512_path = ''
    or thumb_512_path like owner_id::text || '/%'
  ) not valid;

alter table public.run_photos
  validate constraint run_photos_thumb_512_path_shape;

-- ─────────────────── block user-side UPDATE ───────────────────

create or replace function run_photos_block_thumb_path_update()
returns trigger
language plpgsql
as $$
declare
  v_role_legacy text;
  v_claims      text;
  v_role        text;
begin
  -- service_role bypasses RLS but ALSO runs triggers. Distinguish:
  -- when the worker writes the thumb (service-role auth), the JWT
  -- claim role is 'service_role'. For owner-side UPDATEs the role
  -- is 'authenticated' (and auth.uid() is the owner). Block only
  -- the authenticated path. When neither JWT claim shape is set
  -- (server-side maintenance, no API gateway), the current session
  -- user is read instead (postgres / service_role get a free pass).
  v_role_legacy := current_setting('request.jwt.claim.role', true);
  v_claims := current_setting('request.jwt.claims', true);
  v_role := coalesce(
    nullif(v_role_legacy, ''),
    case
      when v_claims is null or v_claims = '' then null
      else nullif(v_claims::jsonb ->> 'role', '')
    end,
    current_user
  );
  if v_role in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if new.thumb_512_path is distinct from old.thumb_512_path then
    raise exception 'run_photos.thumb_512_path is service-role only — '
                    'user-side UPDATE is rejected (audit/storage)'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger run_photos_block_thumb_path_update_trigger
  before update on public.run_photos
  for each row execute function run_photos_block_thumb_path_update();
