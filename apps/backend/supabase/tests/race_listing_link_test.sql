-- runs.race_listing_id FK + public_runs projection (migration 20270214_001).
-- A matched/imported race result links its run back to the public calendar
-- entry. race_listing_id is non-sensitive (it points only at a PUBLIC listing),
-- so it PASSES THROUGH public_runs — while the owner-only race metadata keys
-- (race_name/bib/chip_time/gun_time/age_group_place/age_group/overall_place)
-- stay stripped. Deleting a listing nulls the link (on delete set null), never
-- the run.

begin;

select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000ddd01', 'authenticated', 'authenticated',
        'racer@link.local', '', now(), now());

set local role service_role;

insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified)
values ('22222222-2222-2222-2222-2222000ddd01', 'runsignup', 'rs-7001',
        'Richmond Half Marathon', current_date - 7, 21097, true);

-- A public race-source run carrying the owner-only race metadata + the link.
insert into runs (
  id, user_id, started_at, duration_s, distance_m, source, is_public,
  activity_type, race_listing_id, metadata
) values (
  'cccccccc-cccc-cccc-cccc-cccc000ddd01',
  '00000000-0000-0000-0000-0000000ddd01',
  (current_date - 7)::timestamptz + interval '9 hours', 6443, 21097, 'race', true,
  'run',
  '22222222-2222-2222-2222-2222000ddd01',
  jsonb_build_object(
    'activity_type', 'run',
    'race_name', 'Richmond Half Marathon', 'bib', '1234',
    'chip_time', '1:47:23', 'gun_time', '1:48:01',
    'overall_place', 142, 'age_group_place', 12, 'age_group', 'M35-39'
  )
);

-- ── Anon view of the public run ────────────────────────────────────────────
set local role anon;
set local "request.jwt.claims" = '';

-- 1. race_listing_id is exposed (it links to a public calendar entry).
select results_eq(
  $$ select race_listing_id from public_runs
     where id = 'cccccccc-cccc-cccc-cccc-cccc000ddd01' $$,
  $$ values ('22222222-2222-2222-2222-2222000ddd01'::uuid) $$,
  'public_runs exposes race_listing_id (links to a public listing)'
);

-- 2. The owner-only race metadata keys are all stripped from the view.
do $$
declare
  meta jsonb;
  bad text[] := array[]::text[];
  k text;
  owner_only text[] := array[
    'race_name', 'bib', 'chip_time', 'gun_time',
    'overall_place', 'age_group_place', 'age_group'
  ];
begin
  select metadata into meta from public_runs
   where id = 'cccccccc-cccc-cccc-cccc-cccc000ddd01';
  foreach k in array owner_only loop
    if meta ? k then bad := array_append(bad, k); end if;
  end loop;
  if array_length(bad, 1) is not null then
    raise exception 'race metadata leaked through public_runs: %',
      array_to_string(bad, ', ');
  end if;
end $$;
select pass('public_runs strips every owner-only race metadata key');

-- ── Owner still sees the full metadata on the base table ───────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ddd01","role":"authenticated"}';
select is(
  (select metadata->>'chip_time' from runs
     where id = 'cccccccc-cccc-cccc-cccc-cccc000ddd01'),
  '1:47:23',
  'owner reads chip_time off the base runs row'
);

-- 4. Deleting the listing nulls the link, never the run (on delete set null).
set local role service_role;
delete from race_listings where id = '22222222-2222-2222-2222-2222000ddd01';
select is(
  (select race_listing_id from runs
     where id = 'cccccccc-cccc-cccc-cccc-cccc000ddd01'),
  null,
  'deleting a listing nulls runs.race_listing_id (run survives)'
);

select * from finish();

rollback;
