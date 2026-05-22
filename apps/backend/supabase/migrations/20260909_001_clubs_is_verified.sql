-- Verified-club badge.
--
-- Real-world problem the user surfaced: when an official organisation
-- (e.g. the Richmond Marathon) wants to create a club but a fan has
-- already claimed the name, the second creator gets a sibling slug
-- (`richmond-marathon-2`) but both clubs show the SAME visible NAME.
-- `clubs.name` is intentionally NOT unique — only `clubs.slug` is
-- (the original 20260416_001 migration). That stays — squatting on a
-- name shouldn't lock the official entity out of the platform.
--
-- The badge differentiates the authentic / official surface from the
-- fan / squatter:
--   * `is_verified` defaults to false; service-role flips it true
--     after manual moderation (no admin UI in v1 — direct DB toggle
--     or a future moderation Edge Function).
--   * Anon + auth viewers can SELECT the column via the existing
--     `clubs` SELECT policies (no policy change needed — the
--     column rides through with the row).
--   * UPDATE is gated to service-role: an existing `clubs_update`
--     policy lets owners + admins modify their row; we add a
--     trigger that resets `is_verified` to its OLD value unless the
--     caller is the service role, so a regular UPDATE can't grant
--     itself the badge.
--
-- Events inherit verification visually from their parent club —
-- no per-event column. The mobile + web clients render the badge
-- next to a club name OR an event title when the underlying club
-- carries `is_verified = true`.

alter table clubs
  add column is_verified boolean default false not null;

comment on column clubs.is_verified is
  'Manually-verified-as-official flag. Defaults false; flipped true only via service-role moderation. Squatters and fan clubs stay verified=false even when their slug owns the canonical name. Events inherit verification visually from their parent club.';

-- Indexed so the (sparse) verified set scans cheaply when a future
-- "browse verified clubs" surface ships — also keeps the column
-- filterable from the existing search RPCs without a seqscan.
create index clubs_verified_partial on clubs (created_at desc) where is_verified = true;

-- Trigger guard: a non-service-role UPDATE that tries to flip
-- is_verified gets the OLD value back. Owners + admins can still
-- update every OTHER club field — this only protects the badge.
create or replace function clubs_protect_is_verified()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.is_verified is distinct from new.is_verified then
    -- auth.role() returns 'service_role' for the service-role JWT,
    -- 'authenticated' for a signed-in user, 'anon' otherwise. We
    -- only let service_role flip the bit.
    if coalesce(auth.role(), 'anon') <> 'service_role' then
      new.is_verified := old.is_verified;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists clubs_protect_is_verified_trg on clubs;
create trigger clubs_protect_is_verified_trg
  before update on clubs
  for each row execute function clubs_protect_is_verified();
