-- Photos on routes (backlog C1) — the run_photos capability applied to
-- routes. Mirrors the final hardened state of the run_photos migration
-- chain (20260525_001 → 20260916_001) in a single forward migration
-- since route_photos is all-new:
--   * row table + RLS (owner full; public/club-visible SELECT via
--     private.is_route_visible_to)
--   * a PRIVATE `route-photos` Storage bucket + path-guard policies
--     (per-user folder, parent-route-visibility SELECT gate)
--   * storage_path / thumb_512_path shape CHECKs + no-blank-clear and
--     service-role-only-thumb UPDATE triggers
--
-- Differences from run_photos, by design:
--   * The bucket is created PRIVATE from the start (run_photos only
--     flipped private in 20260712_001 after a public-CDN bypass was
--     found). Clients read via createSignedUrl.
--   * Visibility joins through `private.is_route_visible_to(route_id,
--     uid)` (20260819_001) which already covers owner / public / club.
--   * No `photo_process` enqueue trigger: the Go worker has no
--     route-photo handler, and the EXIF strip that justifies the job
--     happens client-side before upload (web data.ts stripExifFromFile,
--     mobile stripJpegExif). thumb_512_path is carried for forward
--     parity but written service-role-only when a worker lands.

-- ─────────────────────── route_photos table ───────────────────────

create table route_photos (
  id              uuid primary key default gen_random_uuid(),
  route_id        uuid references routes(id) on delete cascade not null,
  owner_id        uuid references auth.users(id) on delete cascade not null,
  storage_path    text not null,
  thumb_512_path  text,
  caption         text check (caption is null or length(caption) <= 280),
  position_idx    smallint not null default 0,
  created_at      timestamptz not null default now()
);

create index route_photos_route_id on route_photos (route_id, position_idx, created_at);
create index route_photos_owner on route_photos (owner_id);
create index route_photos_thumb_512_path
  on route_photos (thumb_512_path)
  where thumb_512_path is not null;

alter table route_photos enable row level security;

create policy "photos readable when route is visible"
  on route_photos for select
  using (private.is_route_visible_to(route_photos.route_id, auth.uid()));

create policy "route owner attaches photos"
  on route_photos for insert
  with check (
    auth.uid() = owner_id
    and exists (
      select 1 from routes
      where routes.id = route_photos.route_id and routes.user_id = auth.uid()
    )
  );

create policy "photo owner deletes"
  on route_photos for delete
  using (auth.uid() = owner_id);

create policy "route owner deletes attached photos"
  on route_photos for delete
  using (
    exists (
      select 1 from routes
      where routes.id = route_photos.route_id and routes.user_id = auth.uid()
    )
  );

create policy "photo owner updates caption"
  on route_photos for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- ─────────────────── storage_path / thumb shape CHECKs ───────────────────
-- Pin both path columns to the owner's prefix so an owner can't rewrite
-- them to point under another user's folder (the SELECT policy below
-- would then approve a cross-user Storage read). Empty string is the
-- legitimate insert-then-upload placeholder window (mobile generates the
-- photo_id server-side, uploads, then PATCHes the real path).

alter table route_photos
  add constraint route_photos_storage_path_shape
  check (
    storage_path = ''
    or storage_path like owner_id::text || '/%'
  );

alter table route_photos
  add constraint route_photos_thumb_512_path_shape
  check (
    thumb_512_path is null
    or thumb_512_path = ''
    or thumb_512_path like owner_id::text || '/%'
  );

-- ─────────────────── block storage_path clear on UPDATE ───────────────────
-- After a real path is set, the only way to remove a photo is DELETE
-- (which clean-sweeps the bytes). Clearing storage_path via UPDATE would
-- orphan the blob and hide the row from the SELECT policy.

create or replace function route_photos_block_storage_path_clear()
returns trigger
language plpgsql
as $$
begin
  if old.storage_path is not null
    and old.storage_path <> ''
    and (new.storage_path is null or new.storage_path = '')
  then
    raise exception 'route_photos.storage_path cannot be cleared via UPDATE — use DELETE to remove a photo'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger route_photos_block_storage_path_clear_trigger
  before update on route_photos
  for each row execute function route_photos_block_storage_path_clear();

-- ─────────────────── block user-side thumb_512_path UPDATE ───────────────────
-- thumb_512_path is service-role only by design (a worker fills it once
-- the thumbnail job runs). Block the authenticated path so an owner
-- can't inject a path the SELECT policy then approves.

create or replace function route_photos_block_thumb_path_update()
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
    raise exception 'route_photos.thumb_512_path is service-role only — user-side UPDATE is rejected'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger route_photos_block_thumb_path_update_trigger
  before update on route_photos
  for each row execute function route_photos_block_thumb_path_update();

-- ─────────────────────── Storage bucket ───────────────────────
-- Private bucket. RLS on storage.objects is enforced for every read;
-- clients reach bytes via createSignedUrl. SELECT joins through
-- route_photos → private.is_route_visible_to so a route flipping to
-- private propagates within the signed-URL TTL.

insert into storage.buckets (id, name, public)
values ('route-photos', 'route-photos', false)
on conflict (id) do nothing;

create policy "route-photo bytes visible when parent route is visible"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'route-photos'
    and exists (
      select 1
      from route_photos rp
      where (
              rp.storage_path = storage.objects.name
              or rp.thumb_512_path = storage.objects.name
            )
        and private.is_route_visible_to(rp.route_id, auth.uid())
    )
  );

create policy "Users upload route photos to their own folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'route-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users delete their own route photos"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'route-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
