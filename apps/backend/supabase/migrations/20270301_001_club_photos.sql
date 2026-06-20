-- Photos on clubs (roadmap backlog row 8, the deferred "club-photo
-- features" half of "Photos on runs and routes"). A club photo gallery so
-- members can attach photos to a club. Mirrors the final hardened state of
-- route_photos (20270114_001) + the run-photo thumbnail worker
-- (photo_process / 20260825_001) in one forward migration, with the
-- visibility/insert/delete gates re-keyed to club membership instead of
-- route ownership:
--
--   * INSERT gated on active club membership (is_club_member) + owner_id =
--     auth.uid() — any member can contribute a photo, not just the owner.
--   * SELECT gated on club visibility: a public club's gallery is readable
--     by anyone; a private club's only by active members / the owner.
--   * DELETE is photo-owner OR club admin (moderation) — a member can
--     remove their own photo; an owner/admin can remove anyone's.
--   * caption UPDATE is photo-owner only.
--   * a PRIVATE `club-photos` Storage bucket (created private from the
--     start, like route-photos — clients read via createSignedUrl) with
--     per-user-folder INSERT/DELETE + a gallery-visibility SELECT gate.
--   * storage_path / thumb_512_path owner-prefix shape CHECKs + the
--     no-blank-clear and service-role-only-thumb UPDATE triggers.
--   * a `club_photo_process` job kind + enqueue triggers (AFTER INSERT and
--     AFTER UPDATE OF storage_path for the mobile insert-then-PATCH path),
--     widening the jobs.kind allowlist. The Go worker's
--     handleClubPhotoProcess re-strips JPEG EXIF (defence in depth — the
--     web + mobile clients already strip client-side) and writes a 512w
--     thumbnail, mirroring handlePhotoProcess against the club-photos
--     bucket + club_photos table.
--
-- Three-file rule (apps/job_worker/CLAUDE.md "Additional job kinds"): the
-- CHECK widen + the Go dispatch case + the pgtap test extension land
-- together so the DB rejects the kind at INSERT (23514) until the handler
-- exists, never silently dropping an enqueue.
--
-- private.is_club_member / private.is_club_admin (moved to the private
-- schema in 20261120_001 so they're not RPC-callable) are SECURITY DEFINER
-- and read 'active' membership only — pending join requests grant no read
-- or write here, the same fail-closed posture every other club surface uses.

-- ─────────────────────── club_photos table ───────────────────────

create table club_photos (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid references clubs(id) on delete cascade not null,
  owner_id        uuid references auth.users(id) on delete cascade not null,
  storage_path    text not null,
  thumb_512_path  text,
  caption         text check (caption is null or length(caption) <= 280),
  position_idx    smallint not null default 0,
  created_at      timestamptz not null default now()
);

create index club_photos_club_id on club_photos (club_id, position_idx, created_at);
create index club_photos_owner on club_photos (owner_id);
create index club_photos_thumb_512_path
  on club_photos (thumb_512_path)
  where thumb_512_path is not null;

alter table club_photos enable row level security;

create policy "club photos readable when club is visible"
  on club_photos for select
  using (
    exists (
      select 1 from clubs
      where clubs.id = club_photos.club_id
        and (
          clubs.is_public = true
          or clubs.owner_id = auth.uid()
          or private.is_club_member(clubs.id)
        )
    )
  );

create policy "club member attaches photos"
  on club_photos for insert
  with check (
    auth.uid() = owner_id
    and private.is_club_member(club_id)
  );

create policy "club photo owner deletes"
  on club_photos for delete
  using (auth.uid() = owner_id);

create policy "club admin deletes any photo"
  on club_photos for delete
  using (private.is_club_admin(club_id));

create policy "club photo owner updates caption"
  on club_photos for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- ─────────────────── storage_path / thumb shape CHECKs ───────────────────
-- Pin both path columns to the owner's prefix so an owner can't rewrite
-- them to point under another user's folder (the SELECT policy below would
-- then approve a cross-user Storage read). Empty string is the legitimate
-- insert-then-upload placeholder window (mobile generates the photo_id
-- server-side, uploads, then PATCHes the real path).

alter table club_photos
  add constraint club_photos_storage_path_shape
  check (
    storage_path = ''
    or storage_path like owner_id::text || '/%'
  );

alter table club_photos
  add constraint club_photos_thumb_512_path_shape
  check (
    thumb_512_path is null
    or thumb_512_path = ''
    or thumb_512_path like owner_id::text || '/%'
  );

-- ─────────────────── block storage_path clear on UPDATE ───────────────────
-- After a real path is set, the only way to remove a photo is DELETE (which
-- clean-sweeps the bytes). Clearing storage_path via UPDATE would orphan
-- the blob and hide the row from the SELECT policy.

create or replace function club_photos_block_storage_path_clear()
returns trigger
language plpgsql
as $$
begin
  if old.storage_path is not null
    and old.storage_path <> ''
    and (new.storage_path is null or new.storage_path = '')
  then
    raise exception 'club_photos.storage_path cannot be cleared via UPDATE — use DELETE to remove a photo'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger club_photos_block_storage_path_clear_trigger
  before update on club_photos
  for each row execute function club_photos_block_storage_path_clear();

-- ─────────────────── block user-side thumb_512_path UPDATE ───────────────────
-- thumb_512_path is service-role only by design (a worker fills it once the
-- thumbnail job runs). Block the authenticated path so a member can't inject
-- a path the SELECT policy then approves.

create or replace function club_photos_block_thumb_path_update()
returns trigger
language plpgsql
as $$
declare
  v_role_legacy text;
  v_claims      text;
  v_role        text;
begin
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
    raise exception 'club_photos.thumb_512_path is service-role only — user-side UPDATE is rejected'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger club_photos_block_thumb_path_update_trigger
  before update on club_photos
  for each row execute function club_photos_block_thumb_path_update();

-- ─────────────────────── Storage bucket ───────────────────────
-- Private bucket. RLS on storage.objects is enforced for every read;
-- clients reach bytes via createSignedUrl. SELECT joins through club_photos
-- → club visibility so a club flipping to private propagates within the
-- signed-URL TTL. file_size_limit + allowed_mime_types match run-photos /
-- route-photos: caps the upload + restricts to image MIME types so a raw
-- client upload can't drop an SVG-XSS or oversized blob into the bucket.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'club-photos', 'club-photos', false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do nothing;

create policy "club-photo bytes visible when club is visible"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'club-photos'
    and exists (
      select 1
      from club_photos cp
      join clubs c on c.id = cp.club_id
      where (
              cp.storage_path = storage.objects.name
              or cp.thumb_512_path = storage.objects.name
            )
        and (
          c.is_public = true
          or c.owner_id = auth.uid()
          or private.is_club_member(c.id)
        )
    )
  );

create policy "Users upload club photos to their own folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'club-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users delete their own club photos"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'club-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ─────────────────── widen jobs.kind allowlist ───────────────────
-- Full re-statement at the chain end (the pattern docs in 20261211_001).

alter table public.jobs drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push', 'lifecycle_drip', 'club_photo_process'
    )
  );

-- ─────────────────── enqueue trigger on club_photos ───────────────────
-- The web path uploads the object first, then inserts the row with the
-- final storage_path — so AFTER INSERT enqueues directly. The mobile path
-- inserts a placeholder row (empty storage_path), uploads, then PATCHes the
-- real path — so the placeholder insert is skipped here and caught by the
-- AFTER UPDATE trigger below when the path fills in.

create or replace function enqueue_club_photo_process_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.storage_path is null or NEW.storage_path = '' then
    return NEW;
  end if;

  insert into public.jobs (kind, payload)
  values (
    'club_photo_process',
    jsonb_build_object(
      'photo_id', NEW.id::text,
      'storage_path', NEW.storage_path,
      'owner_id', NEW.owner_id::text
    )
  );
  return NEW;
end;
$$;

revoke execute on function enqueue_club_photo_process_job() from public;

create trigger club_photos_enqueue_process
  after insert on public.club_photos
  for each row execute function enqueue_club_photo_process_job();

-- ─────────────────── enqueue on placeholder → real-path UPDATE ───────────────────
-- Fires only when storage_path transitions from empty to a real value —
-- never on a caption edit or the service-role thumb PATCH.

create or replace function enqueue_club_photo_process_job_on_path_fill()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (old.storage_path is null or old.storage_path = '')
    and new.storage_path is not null
    and new.storage_path <> ''
  then
    insert into public.jobs (kind, payload)
    values (
      'club_photo_process',
      jsonb_build_object(
        'photo_id', NEW.id::text,
        'storage_path', NEW.storage_path,
        'owner_id', NEW.owner_id::text
      )
    );
  end if;
  return NEW;
end;
$$;

revoke execute on function enqueue_club_photo_process_job_on_path_fill() from public;

create trigger club_photos_enqueue_process_on_path_fill
  after update of storage_path on public.club_photos
  for each row execute function enqueue_club_photo_process_job_on_path_fill();
