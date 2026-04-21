-- User settings: universal (one row per user) + per-device overrides.
--
-- Effective value = user_device_settings.prefs ->> key
--               ?? user_settings.prefs ->> key
--               ?? client default.
--
-- Split into two tables rather than a nullable `device_id` column so RLS
-- stays straightforward (owner-only on both) and indexes don't need a
-- functional definition on the nullable case. Known keys, types, and
-- defaults live in `docs/settings.md` — the DB stores an opaque jsonb
-- bag so adding a new pref is a client change, not a migration.

create table user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  prefs jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table user_settings enable row level security;

create policy user_settings_owner_select
  on user_settings for select
  using (auth.uid() = user_id);

create policy user_settings_owner_insert
  on user_settings for insert
  with check (auth.uid() = user_id);

create policy user_settings_owner_update
  on user_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy user_settings_owner_delete
  on user_settings for delete
  using (auth.uid() = user_id);

-- Per-device overrides. `device_id` is a client-minted stable identifier
-- (UUID generated on first launch and cached in device-local storage).
-- `platform` is a free-text tag ('ios', 'android', 'wear_os', 'watch_os',
-- 'web') used for UI — not constrained so a new platform doesn't need a
-- migration.
create table user_device_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  platform text not null,
  label text,
  prefs jsonb not null default '{}'::jsonb,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

create index user_device_settings_by_user on user_device_settings(user_id);

alter table user_device_settings enable row level security;

create policy user_device_settings_owner_select
  on user_device_settings for select
  using (auth.uid() = user_id);

create policy user_device_settings_owner_insert
  on user_device_settings for insert
  with check (auth.uid() = user_id);

create policy user_device_settings_owner_update
  on user_device_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy user_device_settings_owner_delete
  on user_device_settings for delete
  using (auth.uid() = user_id);
