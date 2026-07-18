-- Opt-in coarse-location "runners nearby" discovery (issue #466).
--
-- This is the FIRST surface in the product to expose person-location.
-- Every other person-facing surface (privacy zones, track clipping,
-- coarse-only share pages, Runner #ABCD handles) is deliberately built
-- to NOT reveal where a person is. So the whole path is fail-closed by
-- construction and the discovery surface itself renders only behind a
-- default-OFF feature flag (PUBLIC_ENABLE_NEARBY_RUNNERS) pending an
-- owner + CISO/counsel sign-off (Art 9-adjacent location data). See
-- docs/architecture/decisions.md and docs/features/clubs.md.
--
-- The privacy design, enforced entirely inside the SECURITY DEFINER
-- reader below so eligibility can't be side-channel-probed:
--
--   1. Explicit opt-in, off by default. A NEW `discoverable_nearby`
--      pref in `user_settings.prefs`, separate from
--      `discoverable_in_search`, default false. No one appears unless
--      they flipped it to the string 'true'.
--   2. Coarse location only. A user-chosen AREA centroid (city /
--      neighbourhood), NOT live GPS, stored rounded to 2 decimal
--      degrees (~1.1 km) so even a breach can't recover a home point.
--      The stored point is NEVER returned to another user — the reader
--      returns only a bucketed distance.
--   3. Every existing person-discovery filter applies: minor exclusion
--      (canonical `user_profiles.date_of_birth` + the legacy prefs
--      mirror, mirroring `search_user_profiles`), `shadow_hidden`,
--      `discoverable_in_search`, the block predicate, AND the new
--      `discoverable_nearby`.
--   4. Distance BUCKETS, not exact distance or bearing. The reader
--      computes the bucket server-side; exact metres never cross the
--      wire, so nobody can triangulate.
--   5. Reciprocal: the center is the CALLER's own stored area, never a
--      client-supplied coordinate, and the caller must themselves be
--      opted in with an area set. A lurker can neither probe arbitrary
--      coordinates nor scrape the opted-in set without being in it.

-- Hosted `supabase db push` sessions may lack `extensions` on the
-- search_path (and the CLI RESETs it before every file), so unqualified
-- postgis references only resolve if each file sets it itself.
set search_path = public, extensions;

-- ─── 1. Coarse-area storage on user_settings ──────────────────────────
-- Owner-only RLS already covers the table; these columns are read/written
-- ONLY through the definer RPCs below (the client settings loader selects
-- just `prefs`, so a geography column can't break existing reads).
alter table user_settings add column discoverable_area geography(Point, 4326);
alter table user_settings add column discoverable_area_label text;

create index user_settings_discoverable_area_gist
  on user_settings using gist (discoverable_area)
  where discoverable_area is not null;

-- ─── 2. set_discoverable_area(): store the caller's coarse area ────────
-- Definer so it can upsert the caller's own settings row without the
-- client needing a column grant. Writes ONLY `auth.uid()`'s row. Rounds
-- the coordinate to 2 decimal degrees so no precise point is ever
-- persisted, even if a client sends one. Returns the stored label so the
-- preferences UI can echo it back.
create or replace function set_discoverable_area(
  p_lng double precision,
  p_lat double precision,
  p_label text default null
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lng double precision := round(p_lng::numeric, 2);
  v_lat double precision := round(p_lat::numeric, 2);
  v_label text := nullif(btrim(coalesce(p_label, '')), '');
begin
  if v_uid is null then
    raise exception 'set_discoverable_area: not authenticated'
      using errcode = '42501';
  end if;
  if p_lng is null or p_lat is null
     or p_lng < -180 or p_lng > 180 or p_lat < -90 or p_lat > 90 then
    raise exception 'set_discoverable_area: invalid coordinate'
      using errcode = '22023';
  end if;

  insert into user_settings (user_id, discoverable_area, discoverable_area_label)
  values (
    v_uid,
    ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326)::geography,
    v_label
  )
  on conflict (user_id) do update set
    discoverable_area = excluded.discoverable_area,
    discoverable_area_label = excluded.discoverable_area_label,
    updated_at = now();

  return v_label;
end;
$$;

revoke all on function set_discoverable_area(double precision, double precision, text) from public;
revoke execute on function set_discoverable_area(double precision, double precision, text) from anon;
grant execute on function set_discoverable_area(double precision, double precision, text) to authenticated;

-- ─── 3. clear_discoverable_area(): forget the caller's area ────────────
create or replace function clear_discoverable_area()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'clear_discoverable_area: not authenticated'
      using errcode = '42501';
  end if;
  update user_settings
    set discoverable_area = null,
        discoverable_area_label = null,
        updated_at = now()
    where user_id = v_uid;
end;
$$;

revoke all on function clear_discoverable_area() from public;
revoke execute on function clear_discoverable_area() from anon;
grant execute on function clear_discoverable_area() to authenticated;

-- ─── 4. my_discoverable_area(): the caller's own stored label ──────────
-- The preferences UI reads this to show "Your area: Richmond, VA". Never
-- returns the coordinate — only the human-readable label the user typed.
create or replace function my_discoverable_area()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select discoverable_area_label
  from user_settings
  where user_id = auth.uid()
    and discoverable_area is not null;
$$;

revoke all on function my_discoverable_area() from public;
revoke execute on function my_discoverable_area() from anon;
grant execute on function my_discoverable_area() to authenticated;

-- ─── 5. discoverable_runners_near(): the opt-in coarse discovery ───────
-- Center is the CALLER's own stored area (never a client coordinate). The
-- caller must be opted in (`discoverable_nearby` = 'true') AND have an
-- area set, or the reader returns zero rows — reciprocity, so a lurker
-- can't scrape the opted-in set. Returns each nearby runner's coarse
-- identity (display_name + avatar — they opted into being discoverable)
-- plus a distance BUCKET, never a coordinate or exact distance.
--
-- Bucket boundaries (metres): 0:<2k 1:<5k 2:<10k 3:<25k 4:<50k. These
-- MUST stay in lockstep with the `nearbyDistanceBucket` helper on web
-- (apps/web/src/lib/social/nearby.ts) and mobile (nearby.dart).
create or replace function discoverable_runners_near(
  p_radius_m double precision default 25000,
  p_limit int default 60
)
returns table (
  id uuid,
  display_name text,
  avatar_url text,
  bucket int
)
language sql
security definer
set search_path = public, extensions
stable
as $$
  with me as (
    select
      s.discoverable_area as pt,
      coalesce(s.prefs->>'discoverable_nearby', 'false') = 'true' as opted_in
    from user_settings s
    where s.user_id = auth.uid()
  ),
  radius as (
    select least(greatest(coalesce(p_radius_m, 25000), 1000), 50000) as r
  ),
  cap as (
    select least(greatest(coalesce(p_limit, 60), 1), 200) as v
  )
  select
    u.id,
    u.display_name,
    u.avatar_url,
    case
      when ST_Distance(s.discoverable_area, me.pt) < 2000  then 0
      when ST_Distance(s.discoverable_area, me.pt) < 5000  then 1
      when ST_Distance(s.discoverable_area, me.pt) < 10000 then 2
      when ST_Distance(s.discoverable_area, me.pt) < 25000 then 3
      else 4
    end as bucket
  from me
  cross join radius
  cross join cap
  join user_settings s on s.discoverable_area is not null
  join user_profiles u on u.id = s.user_id
  where me.opted_in
    and me.pt is not null
    and u.id <> auth.uid()
    and u.shadow_hidden = false
    -- Both opt-outs apply: a search opt-out is the stronger privacy
    -- signal and also removes the runner from nearby discovery.
    and coalesce(s.prefs->>'discoverable_in_search', 'true') <> 'false'
    and coalesce(s.prefs->>'discoverable_nearby', 'false') = 'true'
    -- Hard minor floor, identical to search_user_profiles: under-18 by
    -- EITHER the canonical column OR the legacy prefs mirror is excluded;
    -- both terms are NULL-safe so adults / unknown-age accounts stay in.
    and not (
      (u.date_of_birth is not null
        and u.date_of_birth > (current_date - interval '18 years'))
      or coalesce(
        s.prefs ? 'date_of_birth'
        and (s.prefs->>'date_of_birth') ~ '^\d{4}-\d{2}-\d{2}$'
        and (s.prefs->>'date_of_birth')::date > (current_date - interval '18 years'),
        false
      )
    )
    and not is_blocked_either_way(auth.uid(), u.id)
    and ST_DWithin(s.discoverable_area, me.pt, (select r from radius))
  order by ST_Distance(s.discoverable_area, me.pt) asc, u.display_name asc
  limit (select v from cap);
$$;

revoke all on function discoverable_runners_near(double precision, int) from public;
revoke execute on function discoverable_runners_near(double precision, int) from anon;
grant execute on function discoverable_runners_near(double precision, int) to authenticated;
