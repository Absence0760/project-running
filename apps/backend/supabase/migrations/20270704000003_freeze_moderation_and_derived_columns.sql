-- A shadow-hidden account could unhide itself, and eleven more columns nobody
-- means a client to write were writable by the row's owner.
--
-- Every finding below was measured against the local stack from an ordinary
-- `authenticated` session — `set local role authenticated` with the owner's own
-- `request.jwt.claims` — against the RLS policies as they stand. None of them
-- needs a second account, an admin, or a service key.
--
-- ── 1. The moderation control was self-serve ────────────────────────────────
-- `shadow_hidden` is the moderation bit. `auto_hide_target` (20270218_001)
-- raises it when a target crosses the report threshold, and
-- `admin_unhide_target` — SECURITY DEFINER, gated on `private.is_admin` — is
-- the only intended way down. All three tables it lives on carried a
-- table-level UPDATE grant, so:
--
--     update user_profiles set shadow_hidden = false where id = auth.uid();
--     update clubs set shadow_hidden = false where id = <my club>;
--     update routes set shadow_hidden = false where id = <my route>;
--
-- each returned the target to every surface that filters on it — the profile
-- search floor, the club and route discovery lenses, the three leaderboards
-- 20270524_001 taught to redact a hidden athlete. `user_profiles` was reachable
-- a second way even without the UPDATE: it carries a "users delete own profile"
-- policy, so DELETE + re-INSERT reaches every column an UPDATE grant could
-- withhold — decisions.md 584's class verbatim. Both verbs are guarded here.
--
-- ── 2. `clubs.is_verified` was forgeable at INSERT ──────────────────────────
-- `clubs_protect_is_verified_trg` reverts a non-service-role change and is
-- BEFORE **UPDATE** only, so a club created with `is_verified => true` kept it:
--
--     insert into clubs (owner_id, name, slug, is_public, is_verified)
--       values (auth.uid(), 'Self Verified', 'self-verified', true, true);
--
-- The verified badge is a trust signal shown to every viewer.
-- `race_listings_force_unverified` is the shape that holds — BEFORE INSERT OR
-- UPDATE — and a listing submitted with `is_verified => true` lands false.
--
-- ── 3. Two derived caches ranked shared surfaces off a self-declared number ─
-- `clubs.member_count` is `search_clubs`' sort key. Set to 999999 by the club's
-- owner it stayed there — the maintaining trigger recomputes on a `club_members`
-- change, and a club nobody joins never has one — and `search_clubs` returned
-- that club first, ahead of clubs with real members. `routes.run_count` decides
-- the `popular` lens of `discoverable_routes_in_bbox` (`featured OR run_count >
-- 0`) and excludes a route from `hidden_gems`; the same forge promotes a route
-- into a map every viewer sees. `routes.is_featured` / `featured_at` are the
-- admin-curated `featured` lens outright, and were writable by the author.
--
-- `gym_workouts.set_count` / `volume_kg` and `challenges.participant_count` are
-- the owner's own numbers and are frozen for uniformity rather than for a
-- measured exploit: after this migration no client writes a trigger-maintained
-- cache anywhere in the schema, which is a rule that can be checked, where
-- "these three matter and those two do not" is a judgement that has to be
-- re-made every time a cache is added. It also retires the "known drift
-- (accepted)" note `docs/backend/derived_state.md` carried for
-- `participant_count`.
--
-- ── 4. The privacy-clipped route geometry ──────────────────────────────────
-- `routes.geom_public` is the route's line as a NON-owner may see it, with the
-- owner's privacy zones already clipped off, and `routes_within_box` — granted
-- to `anon` — runs its `ST_Intersects` against it precisely so the raw `geom`
-- never answers a public spatial question (decisions §566). The maintaining
-- trigger is `BEFORE INSERT OR UPDATE **OF waypoints**`, so a write touching
-- the column alone is never recomputed:
--
--     update routes set geom_public = geom where id = <my route>;
--
-- measured to leave `geom_public = geom`, which puts the in-zone tail back
-- inside the box oracle. `geom` and `start_point` are that trigger pair's other
-- outputs and are frozen with it.
--
-- ── Why a trigger, and not a column-level grant lockdown ────────────────────
-- The `20270616_001` shape — revoke the table verb, re-grant column by column —
-- was written first and then abandoned for two reasons, both decisive.
--
-- A grant REFUSES with a 42501, and a refusal on `shadow_hidden` tells the
-- hidden account that it is hidden. That is the one thing a *shadow* hide must
-- not do. Silently accepting the write and discarding it is not a weaker
-- guard here, it is the correct behaviour.
--
-- And a refusal breaks a caller that hands the table a whole row it read back
-- earlier. `backup.dart`'s restore does `client.from('routes').upsert(r)` with
-- `r` straight out of a `select()` archive, so every one of these columns is in
-- the statement's column list; under a grant lockdown every route in the
-- archive would fail to import. The same file already strips
-- `subscription_tier` / `subscription_at` by hand for exactly this reason, with
-- a comment saying so. Discarding the value is what a restore should do with a
-- moderation bit and a derived cache anyway.
--
-- ── How the trigger tells a client apart from the machinery ────────────────
-- Each function below is SECURITY **INVOKER** and branches on `current_user`.
-- That is the only in-band signal that survives the one thing this guard has to
-- get right: the legitimate writers — `admin_unhide_target`, `auto_hide_target`,
-- `refresh_route_run_count`, `refresh_club_member_count`,
-- `refresh_gym_workout_totals`, `sync_challenge_participant_count`,
-- `routes_set_geom`, `routes_set_start_point`,
-- `user_settings_recompute_route_start_points` — are all SECURITY DEFINER owned
-- by `postgres`, and are called BY an ordinary user's session. So the JWT role
-- claim reads `authenticated` inside every one of them, and
-- `current_setting('role')` reads the session's `SET ROLE`, which is also
-- `authenticated`: the two signals `lock_subscription_columns` and
-- `force_unverified_listing` use would each block the moderator.
-- `current_user`, in a SECURITY INVOKER function, follows the effective user —
-- `postgres` inside a definer body, `authenticated` on a direct PostgREST
-- write — which is exactly the distinction wanted. Measured on this Postgres:
-- one trigger, one session, `current_user = authenticated` for the direct
-- UPDATE and `current_user = postgres` for the same UPDATE issued from inside a
-- definer function.
--
-- Making these SECURITY DEFINER would defeat them: the definer switch masks
-- `current_user` to the owner, so every caller would look trusted. The bodies
-- read only OLD and NEW and raise nothing, so invoker rights cost them nothing.
--
-- Only `anon` and `authenticated` are guarded. `service_role` writing directly
-- keeps `current_user = service_role`, and direct SQL from a migration or seed
-- keeps `postgres` — both intended, and both are how the moderator's own tools
-- reach these columns.
--
-- ── Trigger ordering on `routes` ───────────────────────────────────────────
-- BEFORE triggers fire in name order, and `routes_freeze_managed_columns` sorts
-- ahead of `routes_geom_trigger` and `routes_start_point_trigger`. So on INSERT
-- the freeze nulls a client-supplied geometry and the derivation then computes
-- the real one; on an UPDATE that changes `waypoints` the freeze restores OLD
-- and the derivation recomputes from the new line; on an UPDATE that touches
-- only the geometry columns the derivation does not fire at all and OLD stands.
-- All three are the intended outcome.
--
-- Online safety: CREATE FUNCTION and CREATE TRIGGER take a lock on the target
-- relation for the catalogue entry only — no scan, no rewrite — so none of
-- docs/backend/migration_locks.md's machinery applies. No column type,
-- nullability or default moves, so neither row-type generator has anything to
-- regenerate.

-- ── user_profiles ───────────────────────────────────────────────────────────
create or replace function freeze_user_profile_managed_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.shadow_hidden := false;
  else
    new.shadow_hidden := old.shadow_hidden;
  end if;
  return new;
end;
$$;

create trigger user_profiles_freeze_managed_columns
  before insert or update on user_profiles
  for each row execute function freeze_user_profile_managed_columns();

-- ── clubs ───────────────────────────────────────────────────────────────────
create or replace function freeze_club_managed_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.shadow_hidden := false;
    new.is_verified   := false;
    new.member_count  := 0;
  else
    new.shadow_hidden := old.shadow_hidden;
    new.is_verified   := old.is_verified;
    new.member_count  := old.member_count;
  end if;
  return new;
end;
$$;

create trigger clubs_freeze_managed_columns
  before insert or update on clubs
  for each row execute function freeze_club_managed_columns();

-- ── routes ──────────────────────────────────────────────────────────────────
create or replace function freeze_route_managed_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.shadow_hidden := false;
    new.is_featured   := false;
    new.featured_at   := null;
    new.run_count     := 0;
    new.geom          := null;
    new.geom_public   := null;
    new.start_point   := null;
  else
    new.shadow_hidden := old.shadow_hidden;
    new.is_featured   := old.is_featured;
    new.featured_at   := old.featured_at;
    new.run_count     := old.run_count;
    new.geom          := old.geom;
    new.geom_public   := old.geom_public;
    new.start_point   := old.start_point;
  end if;
  return new;
end;
$$;

create trigger routes_freeze_managed_columns
  before insert or update on routes
  for each row execute function freeze_route_managed_columns();

-- ── gym_workouts ────────────────────────────────────────────────────────────
create or replace function freeze_gym_workout_managed_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.set_count := 0;
    new.volume_kg := 0;
  else
    new.set_count := old.set_count;
    new.volume_kg := old.volume_kg;
  end if;
  return new;
end;
$$;

create trigger gym_workouts_freeze_managed_columns
  before insert or update on gym_workouts
  for each row execute function freeze_gym_workout_managed_columns();

-- ── challenges ──────────────────────────────────────────────────────────────
create or replace function freeze_challenge_managed_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.participant_count := 0;
  else
    new.participant_count := old.participant_count;
  end if;
  return new;
end;
$$;

create trigger challenges_freeze_managed_columns
  before insert or update on challenges
  for each row execute function freeze_challenge_managed_columns();

comment on function freeze_route_managed_columns() is
  'Discards a client write to the moderation bit, the curation flags, the '
  'run_count cache and the three trigger-derived geometries. SECURITY INVOKER '
  'so current_user still distinguishes a direct PostgREST write from a '
  'SECURITY DEFINER body executing as the table owner (20270704000003).';
