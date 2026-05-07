-- Pin the no-blank-update trigger on run_photos.storage_path from
-- migration 20260811_001_run_photos_storage_path_no_blank_update.sql.
--
-- Pre-fix: the storage_path CHECK from 20260622_001 allowed the
-- empty-string escape hatch on BOTH insert and update. After the
-- row was set to a real `{owner}/{photo}.{ext}` path, the owner
-- could PATCH it back to `''`, leaving an orphan metadata row +
-- unreclaimable Storage bytes. Self-inflicted but a slow leak.
--
-- The trigger blocks the transition `non-empty → empty` on UPDATE.
-- INSERT with `''` (the legitimate two-step mobile placeholder)
-- still works; the legitimate update path (placeholder → real
-- path) still works.
--
-- Coverage:
--   1. INSERT with '' placeholder succeeds (mobile two-step flow).
--   2. UPDATE from '' to a real path succeeds (the second step).
--   3. UPDATE from a real path back to '' is rejected (the bug).
--   4. UPDATE that keeps the same real path (e.g. caption edit)
--      succeeds — the trigger only fires on transitions to empty.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000bb', 'authenticated', 'authenticated',
   'photo@local', '', now(), now());

set local role service_role;

-- Seed a run owned by the user so run_photos.run_id has a target.
insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values ('77777777-7777-7777-7777-777777777777',
        '00000000-0000-0000-0000-0000000000bb',
        '2026-04-01T08:00:00Z',
        5000.0, 1500, 'app', false,
        '{"activity_type":"run"}'::jsonb);

-- 1. INSERT with empty-string placeholder still works.
do $$
begin
  insert into run_photos (id, run_id, owner_id, storage_path)
  values ('77777777-7777-7777-7777-7777777777aa',
          '77777777-7777-7777-7777-777777777777',
          '00000000-0000-0000-0000-0000000000bb',
          '');
end $$;
select pass('INSERT with empty-string placeholder succeeds (mobile two-step flow)');

-- 2. UPDATE from '' to a real path succeeds (the upload-completion step).
do $$
begin
  update run_photos
     set storage_path = '00000000-0000-0000-0000-0000000000bb/aa.jpg'
   where id = '77777777-7777-7777-7777-7777777777aa';
end $$;
select pass('UPDATE empty-string → real path succeeds (placeholder upgrade)');

-- 3. UPDATE from real path back to '' is rejected by the trigger.
select throws_ok(
  $$ update run_photos
       set storage_path = ''
     where id = '77777777-7777-7777-7777-7777777777aa' $$,
  '42501',
  null,
  'UPDATE real path → empty-string is rejected — owner must DELETE instead'
);

-- 4. UPDATE that preserves the real path (e.g. caption edit) still works.
do $$
begin
  update run_photos
     set caption = 'edited caption'
   where id = '77777777-7777-7777-7777-7777777777aa';
end $$;
select pass('UPDATE that keeps the same path succeeds (caption / position edits)');

select * from finish();

rollback;
