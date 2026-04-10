-- Move GPS tracks from the `runs.track` jsonb column to Supabase Storage.
--
-- Why: a typical 10km run has ~3,300 GPS points, ~265 KB of jsonb. At 10K active
-- users with 200 runs/year that's ~500 GB of database storage. Object storage is
-- ~6x cheaper and doesn't bloat row scans on the dashboard. Compressed JSON
-- (gzip) cuts the per-track size by another 8x.
--
-- This migration:
-- 1. Drops the `track` jsonb column.
-- 2. Adds `track_url text` for the Storage object path.
-- 3. Creates a private `runs` storage bucket.
-- 4. Adds RLS so users can only read/write their own track files.

-- Drop the inline track column. (Local-only repo, no production data to migrate.)
alter table runs drop column track;

-- Add the URL pointer.
alter table runs add column track_url text;

-- Create the bucket. Private — clients access via signed URLs or authenticated
-- requests using their own user_id-prefixed paths.
insert into storage.buckets (id, name, public)
values ('runs', 'runs', false)
on conflict (id) do nothing;

-- RLS for storage.objects on the runs bucket.
-- Convention: paths look like `{user_id}/{run_id}.json.gz`
-- so we use the first path segment to determine ownership.

create policy "Users can read their own run tracks"
on storage.objects for select
to authenticated
using (
  bucket_id = 'runs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can upload their own run tracks"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'runs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can update their own run tracks"
on storage.objects for update
to authenticated
using (
  bucket_id = 'runs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can delete their own run tracks"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'runs'
  and (storage.foldername(name))[1] = auth.uid()::text
);
