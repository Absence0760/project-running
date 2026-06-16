-- The public `avatars` bucket (20260927_001) shipped owner INSERT / UPDATE /
-- DELETE policies but NO SELECT policy — the reasoning at the time was that a
-- public bucket serves anonymous DOWNLOADS via the platform public-flag path,
-- so no SELECT policy is needed. That holds for the `/object/public/...`
-- download URL, but NOT for the authenticated Storage `.list()` / `.remove()`
-- operations, which query `storage.objects` under RLS. Without a SELECT policy
-- an owner can neither enumerate nor delete their own avatar objects: `.remove()`
-- silently no-ops (its internal SELECT returns no rows), so a stale avatar
-- lingers world-readable and a same-format re-upload then collides with the
-- existing object (no upsert grant on this bucket).
--
-- Grant owners SELECT on their OWN `{user_id}/` folder so avatar replace +
-- remove work. Public DOWNLOADS still flow through the bucket public flag; this
-- only lets an owner see their own object rows for management, never another
-- user's (the avatar URL itself is already public on the profile page).

create policy "avatars owner can read own objects"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
