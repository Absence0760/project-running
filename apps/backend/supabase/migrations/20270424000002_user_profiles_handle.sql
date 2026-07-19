-- Public, user-chosen handle (@username) on user_profiles — the stable,
-- shareable identifier the People-search request was really asking for
-- (issue #465; closes the deferred handle item in decisions §31).
--
-- Distinct from runner_handle.ts (`Runner #ABCD`), which is a one-way
-- ANONYMIZER for hiding a broadcaster's identity from strangers. This
-- column is the OPPOSITE: a self-claimed public username you look someone
-- up by. The column name is `handle` (not `username`) to sit next to the
-- existing display_name / avatar_url identity columns.
--
-- Format: lowercase [a-z0-9_], 3–30 chars. Storage is the canonical
-- lowercased form (the claim RPC lowercases), so a plain unique on the
-- column is already case-insensitive; the functional index over
-- lower(handle) is belt-and-braces for the CHECK invariant. No backfill,
-- no reserved-word list — keep it lean per the issue scope.

alter table user_profiles add column handle text;

alter table user_profiles
  add constraint user_profiles_handle_format
  check (handle is null or handle ~ '^[a-z0-9_]{3,30}$');

-- Case-insensitive uniqueness. NULLs are distinct, so the many un-claimed
-- rows don't collide; the partial predicate keeps the index small.
create unique index user_profiles_handle_lower_key
  on user_profiles (lower(handle))
  where handle is not null;

-- The handle is a public identity column (like display_name / avatar_url),
-- so it must be cross-user readable — otherwise the People-search hydrate
-- can't render `@handle`. New user_profiles columns are deny-by-default for
-- authenticated/anon SELECT (column lockdown 20260707_001 / 20260810_001);
-- the re-grant is cumulative, so re-emit the full narrow list plus handle.
revoke select on user_profiles from authenticated, anon;
grant select (
  id,
  display_name,
  avatar_url,
  created_at,
  handle
) on user_profiles to authenticated, anon;

-- set_my_handle — the ONLY write path for a caller's own handle. SECURITY
-- DEFINER so it can enforce format + case-insensitive uniqueness and update
-- the caller's own row without opening a client UPDATE grant on the column.
-- Pass '' / null to clear. Raises a distinct message the client maps to a
-- format vs taken error; the unique index is the race backstop (23505).
create or replace function set_my_handle(p_handle text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_norm text := lower(trim(coalesce(p_handle, '')));
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Empty input clears the handle (un-claim).
  if v_norm = '' then
    update user_profiles set handle = null where id = v_uid;
    return null;
  end if;

  if v_norm !~ '^[a-z0-9_]{3,30}$' then
    raise exception 'handle_invalid' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from user_profiles
    where lower(handle) = v_norm and id <> v_uid
  ) then
    raise exception 'handle_taken' using errcode = 'P0001';
  end if;

  update user_profiles set handle = v_norm where id = v_uid;
  return v_norm;
end;
$$;

revoke all on function set_my_handle(text) from public;
revoke execute on function set_my_handle(text) from anon;
grant execute on function set_my_handle(text) to authenticated;

-- search_user_profiles — People-tab search. Full body re-emitted from the
-- LIVE definition (20270218_001) so the bare-body rewrite keeps every prior
-- fix: shadow_hidden filter, discoverable_in_search opt-out, canonical-DOB +
-- prefs-bag minor floor, the limit cap, and the anon revoke. The ONLY change
-- is the match + ordering: a row now matches on display_name substring OR
-- handle prefix (leading '@' stripped), and an EXACT handle match sorts
-- first so it survives the client's candidate cap + reputation re-sort.
--
-- The opt-out / minor / shadow filters are AND-ed against the whole row, so
-- a handle match is subject to them too — an opted-out user stays unfindable
-- by handle, exactly as by name (issue #465 invariant).
create or replace function search_user_profiles(
  p_query text,
  p_limit int default 60
)
returns table (
  id uuid,
  display_name text,
  avatar_url text
)
language sql
security definer
set search_path = public
stable
as $$
  with capped as (
    select least(greatest(coalesce(p_limit, 60), 1), 200) as v
  )
  select
    u.id,
    u.display_name,
    u.avatar_url
  from user_profiles u
  left join user_settings s on s.user_id = u.id
  where (
      u.display_name ilike '%' || p_query || '%'
      or (
        u.handle is not null
        and ltrim(p_query, '@') <> ''
        and starts_with(u.handle, lower(ltrim(p_query, '@')))
      )
    )
    and u.shadow_hidden = false
    and coalesce(s.prefs->>'discoverable_in_search', 'true') <> 'false'
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
  order by
    (u.handle is not null and u.handle = lower(ltrim(p_query, '@'))) desc,
    u.display_name
  limit (select v from capped);
$$;

revoke all on function search_user_profiles(text, int) from public;
revoke execute on function search_user_profiles(text, int) from anon;
grant execute on function search_user_profiles(text, int) to authenticated;
