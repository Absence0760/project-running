-- Allow runs to be shared publicly via /share/run/{id}.
--
-- Adds is_public to the runs table (same pattern as routes.is_public),
-- a row-level security policy so anonymous viewers can SELECT public runs,
-- and a storage policy so anonymous viewers can download the GPS track for
-- public runs.

-- 1. Add column with a partial index for efficient public-run queries.
alter table runs add column is_public boolean default false;
create index runs_public on runs (is_public, started_at desc) where is_public = true;

-- 2. RLS: anyone can read public runs (no "to authenticated" clause).
create policy "public runs are readable by anyone"
  on runs for select using (is_public = true);

-- 3. Storage: anonymous read access to tracks of public runs.
--    Joins storage.objects → runs via the path convention {user_id}/{run_id}.json.gz
--    to verify the run exists and is_public = true.
create policy "Anyone can read tracks of public runs"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'runs'
    and exists (
      select 1 from runs
      where runs.track_url = name
        and runs.is_public = true
    )
  );
