-- Photos on runs (decisions.md § 36).
--
-- run_photos rows store metadata; the bytes live in the public-read
-- `run-photos` Storage bucket at {owner_id}/{photo_id}.{ext}. RLS on
-- run_photos tracks the parent run via EXISTS — same pattern as
-- run_kudos / run_comments.

-- ─────────────────────── run_photos table ───────────────────────

create table run_photos (
  id            uuid primary key default gen_random_uuid(),
  run_id        uuid references runs(id) on delete cascade not null,
  owner_id      uuid references auth.users(id) on delete cascade not null,
  storage_path  text not null,            -- e.g. {owner_id}/{photo_id}.jpg
  caption       text check (caption is null or length(caption) <= 280),
  position_idx  smallint not null default 0,
  created_at    timestamptz not null default now()
);

create index run_photos_run_id on run_photos (run_id, position_idx, created_at);
create index run_photos_owner on run_photos (owner_id);

alter table run_photos enable row level security;

create policy "photos readable when run is readable"
  on run_photos for select
  using (exists (select 1 from runs where runs.id = run_photos.run_id));

-- The run owner (and only the run owner, in v1) can attach photos. We
-- allow `owner_id <> runs.user_id` in the schema for forward
-- compatibility but enforce equality at write time so club-photo
-- features have to opt in via a future migration.
create policy "run owner attaches photos"
  on run_photos for insert
  with check (
    auth.uid() = owner_id
    and exists (
      select 1 from runs
      where runs.id = run_photos.run_id and runs.user_id = auth.uid()
    )
  );

-- Owner of the photo OR owner of the run can delete (moderation).
create policy "photo owner deletes"
  on run_photos for delete
  using (auth.uid() = owner_id);

create policy "run owner deletes attached photos"
  on run_photos for delete
  using (
    exists (
      select 1 from runs
      where runs.id = run_photos.run_id and runs.user_id = auth.uid()
    )
  );

-- Caption / position can be edited by the photo owner.
create policy "photo owner updates caption"
  on run_photos for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- ─────────────────────── Storage bucket ───────────────────────

-- Public-read bucket so the share page works for anonymous viewers.
-- Per-user folder convention: {auth.uid()}/{photo_id}.{ext}.
insert into storage.buckets (id, name, public)
values ('run-photos', 'run-photos', true)
on conflict (id) do nothing;

create policy "Anyone can read run photo bytes"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'run-photos');

create policy "Users upload to their own folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'run-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users delete their own photos"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'run-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
