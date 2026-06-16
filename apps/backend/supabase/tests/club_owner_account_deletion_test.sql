-- Pins 20270205_001 — clubs_member_count_trigger is SECURITY DEFINER, and
-- still maintains member_count correctly.
--
-- Regression: the trigger ran SECURITY INVOKER, so the ON DELETE CASCADE's
-- `update clubs set member_count` fired during a club owner's account
-- deletion executed as the `supabase_auth_admin` role GoTrue uses — which
-- has no UPDATE privilege on public.clubs — raising permission-denied and
-- failing the whole auth delete. Any club owner was undeletable (GDPR
-- Art-17 erasure failure). The full delete-account path is exercised in the
-- web e2e account-data-rights journey; pgtap can't assume the
-- supabase_auth_admin role, so it pins the security attribute (the thing
-- that fixes the cascade) + the count behaviour the DEFINER body must keep.

begin;
select plan(4);

-- 1. The fix itself: SECURITY DEFINER (prosecdef = true). A revert to
--    INVOKER re-breaks club-owner deletion and fails here.
select is(
  (select prosecdef from pg_proc where proname = 'clubs_member_count_trigger'),
  true,
  'clubs_member_count_trigger is SECURITY DEFINER (survives the supabase_auth_admin cascade)'
);

do $$
declare
  v_owner uuid := 'cccccccc-cccc-cccc-cccc-ccccccccaa01';
  v_member uuid := 'cccccccc-cccc-cccc-cccc-ccccccccbb02';
begin
  insert into auth.users (id, email, encrypted_password,
                          email_confirmed_at, instance_id, aud, role)
    values (v_owner, 'clubowner-del@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
           (v_member, 'clubmember-del@example.com', '', now(),
            '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
    on conflict (id) do nothing;
  insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
    values (v_owner, 'Club Owner', 'km', 'free'),
           (v_member, 'Club Member', 'km', 'free')
    on conflict (id) do nothing;
  -- enroll_club_owner seats the owner as an active member → count 1.
  insert into clubs (id, owner_id, name, slug, is_public)
    values ('dddddddd-dddd-dddd-dddd-ddddddddaa01', v_owner,
            'Deletion Test Club', 'deletion-test-club', true);
end $$;

-- 2. Owner seated → member_count = 1.
select is(
  (select member_count from clubs where id = 'dddddddd-dddd-dddd-dddd-ddddddddaa01'::uuid),
  1,
  'creating a club seats the owner and the count trigger sets member_count = 1'
);

-- 3. A second active member → count increments to 2.
insert into club_members (club_id, user_id, role, status)
  values ('dddddddd-dddd-dddd-dddd-ddddddddaa01'::uuid,
          'cccccccc-cccc-cccc-cccc-ccccccccbb02'::uuid, 'member', 'active');
select is(
  (select member_count from clubs where id = 'dddddddd-dddd-dddd-dddd-ddddddddaa01'::uuid),
  2,
  'an active member join increments member_count'
);

-- 4. Removing that member → count decrements back to 1 (the DELETE path the
--    account-deletion cascade exercises).
delete from club_members
  where club_id = 'dddddddd-dddd-dddd-dddd-ddddddddaa01'::uuid
    and user_id = 'cccccccc-cccc-cccc-cccc-ccccccccbb02'::uuid;
select is(
  (select member_count from clubs where id = 'dddddddd-dddd-dddd-dddd-ddddddddaa01'::uuid),
  1,
  'a member leave decrements member_count'
);

rollback;
