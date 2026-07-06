-- Complete the shadow_hidden backstop (decisions §172/§206) for the two
-- surfaces 20270328_001 (clubs + events) missed — found by the 2026-07-06
-- audit/rls + audit/storage passes.
--
-- 1. user_profiles. The base-table SELECT policy (20260521_001) admits ANY
--    authenticated caller with no shadow_hidden clause, and the
--    public_profiles view (20260824_001) has no WHERE at all — so a
--    moderation-hidden user's display_name + avatar stayed resolvable to
--    every authenticated caller and kept rendering through the ~25
--    unfiltered `.from('user_profiles')` call sites in the web data layer.
--    search_user_profiles + public_profile_by_id were already filtered
--    (20270218_001 / 20270307_001); these two paths were the bypass.
--    Owner carve-out mirrors the clubs backstop: a hidden user still reads
--    their own row (soft-hide pending review, not a deletion).
--
-- 2. routes. private.is_route_visible_to (20260819_001) and
--    clip_route_for_viewer (20260625_001) gate on is_public with no
--    shadow_hidden clause. Both are SECURITY DEFINER, so unlike the
--    club-photos storage policy (a plain join that inherits clubs' RLS)
--    they do NOT inherit the routes filtering the listing surfaces got in
--    20270218_001 — a hidden route's waypoints, route-photos bytes,
--    reviews, segments, markers, and condition reports stayed readable by
--    anyone holding the route id (verified live by audit/storage). Only
--    the is_public branch gains the clause: the owner keeps visibility,
--    and an active club member keeps club-route visibility, mirroring
--    "members and owners read their own club" (20270328_001).

-- ── user_profiles base SELECT policy ──
drop policy "profiles are readable by anyone authenticated" on user_profiles;
create policy "authenticated read profiles except shadow-hidden"
  on user_profiles for select
  to authenticated
  using (auth.uid() = id or shadow_hidden = false);

-- ── public_profiles view ──
-- Live body is 20260824_001 (three columns, no WHERE); grants are
-- select→authenticated only (anon revoked 20261011_001, write privileges
-- revoked 20270324_001). create or replace view preserves grants, but the
-- lockdown is re-emitted per the every-view rule.
create or replace view public_profiles as
select
  id,
  display_name,
  avatar_url
from user_profiles
where shadow_hidden = false;

revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

-- ── private.is_route_visible_to ──
-- Live body is 20260819_001; re-emitted complete (bare-body rule) with the
-- shadow_hidden clause on the is_public branch only.
create or replace function private.is_route_visible_to(p_route_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from routes r
    where r.id = p_route_id
      and (
        r.user_id = p_user_id
        or (r.is_public = true and r.shadow_hidden = false)
        or (
          r.club_id is not null
          and exists (
            select 1 from club_members
            where club_id = r.club_id
              and user_id = p_user_id
              and status = 'active'
          )
        )
      )
  );
$$;

revoke execute on function private.is_route_visible_to(uuid, uuid) from public;
grant execute on function private.is_route_visible_to(uuid, uuid)
  to anon, authenticated, service_role;

-- ── clip_route_for_viewer ──
-- Live body is 20260625_001 with search_path widened to
-- `public, extensions, private` by 20261120_001 (the is_club_member call
-- resolves through `private`) — the re-emit must keep that search_path or
-- the membership check breaks. The only functional change is the
-- shadow_hidden gate on the public branch; the club-member call is now
-- schema-qualified to match current house style.
create or replace function clip_route_for_viewer(p_route_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, private
as $$
declare
  v_caller uuid := auth.uid();
  v_owner uuid;
  v_is_public boolean;
  v_shadow_hidden boolean;
  v_club_id uuid;
  v_waypoints jsonb;
  v_visible boolean;
begin
  select user_id, is_public, shadow_hidden, club_id, waypoints
    into v_owner, v_is_public, v_shadow_hidden, v_club_id, v_waypoints
    from routes where id = p_route_id;

  if v_owner is null then
    raise exception 'route not found' using errcode = 'P0002';
  end if;

  -- Visibility gate, mirroring private.is_route_visible_to:
  --   - users own their routes (auth.uid() = user_id), hidden or not
  --   - public routes are readable by anyone UNLESS shadow-hidden
  --   - active club members read club routes, hidden or not
  v_visible := (v_caller is not null and v_caller = v_owner)
            or (v_is_public = true and v_shadow_hidden = false);
  if not v_visible and v_club_id is not null and v_caller is not null then
    if private.is_club_member(v_club_id) then
      v_visible := true;
    end if;
  end if;

  if not v_visible then
    raise exception 'route not visible' using errcode = '42501';
  end if;

  -- Owner gets unclipped waypoints.
  if v_caller is not null and v_caller = v_owner then
    return coalesce(v_waypoints, '[]'::jsonb);
  end if;

  -- Non-owner: delegate the zone walk to clip_track_for_user so the
  -- runs and routes paths share one implementation. clip_track_for_user
  -- handles the empty / non-array / oversize cases internally.
  return clip_track_for_user(v_owner, coalesce(v_waypoints, '[]'::jsonb));
end;
$$;

grant execute on function clip_route_for_viewer(uuid) to anon, authenticated;
