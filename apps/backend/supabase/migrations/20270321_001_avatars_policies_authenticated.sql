-- Scope the avatars owner policies to authenticated (audit/storage
-- 2026-07-03). The four owner policies from 20260927_001 / 20270203_001
-- omitted a `to` clause, so they applied `to public` — fail-closed today
-- (every predicate requires auth.uid(), which is null for anon), but drift
-- from the project's policy shape and one careless predicate edit away from
-- an anon write path. Re-emit all four `to authenticated`; predicates
-- unchanged.

drop policy "avatars owner can upload" on storage.objects;
create policy "avatars owner can upload"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy "avatars owner can update" on storage.objects;
create policy "avatars owner can update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy "avatars owner can delete" on storage.objects;
create policy "avatars owner can delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy "avatars owner can read own objects" on storage.objects;
create policy "avatars owner can read own objects"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
