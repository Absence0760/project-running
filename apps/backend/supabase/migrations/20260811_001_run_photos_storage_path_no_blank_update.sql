-- /audit/all Low (storage): the run_photos.storage_path CHECK
-- constraint from 20260622_001 allows the empty-string escape hatch
-- (designed for the mobile two-step insert-then-upload flow) on
-- BOTH inserts AND updates. After the row's storage_path has been
-- set to a real `{owner_id}/{photo_id}.{ext}` path, an owner can
-- still `PATCH /run_photos?id=eq.<photo_id>` with
-- `{ "storage_path": "" }`. The Storage SELECT policy then never
-- matches the metadata row (it joins on
-- `rp.storage_path = storage.objects.name`), so the photo becomes
-- invisible — and the underlying bytes are never cleaned up because
-- the deleteRunPhoto path uses `row.storage_path` to locate the
-- blob, and `storage.remove([''])` is a no-op or errors silently.
--
-- Self-inflicted, not a cross-user exploit. But it's a slow-leak
-- bug for paid clubs (Storage egress / cost) and a footgun the
-- mobile client should not be able to reach by accident.
--
-- BEFORE-UPDATE trigger pattern: reject the transition non-empty
-- → empty. The legitimate placeholder window is INSERT only;
-- after insert sets a real path, the only way to remove the
-- photo is the DELETE path (which clean-removes both the row and
-- the bytes via deleteRunPhoto's storage.remove call).

create or replace function run_photos_block_storage_path_clear()
returns trigger
language plpgsql
as $$
begin
  if old.storage_path is not null
    and old.storage_path <> ''
    and (new.storage_path is null or new.storage_path = '')
  then
    raise exception 'run_photos.storage_path cannot be cleared via UPDATE — use DELETE to remove a photo'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger run_photos_block_storage_path_clear_trigger
  before update on run_photos
  for each row execute function run_photos_block_storage_path_clear();
