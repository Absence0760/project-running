-- Push-notification device tokens.
--
-- One row per (user, device) — the same user may have multiple tokens
-- live simultaneously (phone + tablet + watch). Tokens are registered
-- by the mobile clients on sign-in and refreshed when the platform
-- rotates them (APNs after install, FCM on app-data clear).
--
-- The `device_tokens` table unblocks Phase 4b of the Clubs initiative
-- (event-day reminders, admin-update fan-out) — see
-- `apps/backend/supabase/migrations/20260417_001_phase2_social.sql`
-- for the Phase 2 baseline. No FCM / APNs credentials are wired yet;
-- this migration only prepares the storage.

create table device_tokens (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  platform          text not null check (platform in ('ios', 'android', 'web')),
  token             text not null,
  app_version       text,
  locale            text,
  -- Whether the client has opted in / out of push notifications on
  -- this device. The token stays in the table either way so the next
  -- opt-in doesn't require re-registering with the platform.
  notifications_enabled  boolean not null default true,
  last_seen_at      timestamptz not null default now(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  -- The same token being stored under different users is a platform
  -- signal that the device changed hands — keep the newer row and let
  -- the old user's push send 404 on next fan-out.
  unique (user_id, token)
);

-- Fan-out sender queries by (user_id, notifications_enabled=true). Keep
-- the index narrow so it fits in memory on the push worker.
create index device_tokens_active
  on device_tokens (user_id)
  where notifications_enabled;

-- Debug / ops: find all tokens for a given platform (e.g. audit which
-- APNs tokens are registered before rotating the APNs key).
create index device_tokens_platform on device_tokens (platform, last_seen_at desc);

alter table device_tokens enable row level security;

-- Users only see their own tokens. The push worker uses the service
-- role key (no RLS) to read every active token when fanning out.
create policy device_tokens_self_select on device_tokens
  for select using (user_id = auth.uid());

create policy device_tokens_self_insert on device_tokens
  for insert with check (user_id = auth.uid());

create policy device_tokens_self_update on device_tokens
  for update using (user_id = auth.uid());

create policy device_tokens_self_delete on device_tokens
  for delete using (user_id = auth.uid());

-- Touch `updated_at` on any mutation so the fan-out worker can skip
-- tokens that haven't checked in for >N days (platform tokens rotate
-- silently and a stale entry just generates a 404 per push).
create or replace function touch_device_tokens_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger device_tokens_touch_updated_at
  before update on device_tokens
  for each row
  execute function touch_device_tokens_updated_at();
