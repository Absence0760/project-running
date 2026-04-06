-- Initial schema for Run app

-- Runs table
create table runs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users not null,
  started_at    timestamptz not null,
  duration_s    integer not null,
  distance_m    numeric(10, 2) not null,
  track         jsonb,
  route_id      uuid references routes,
  source        text not null,
  external_id   text unique,
  metadata      jsonb,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create index runs_user_started_at on runs (user_id, started_at desc);
create unique index runs_external_id on runs (external_id) where external_id is not null;

-- Routes table
create table routes (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users not null,
  name            text not null,
  waypoints       jsonb not null,
  distance_m      numeric(10, 2) not null,
  elevation_m     numeric(8, 2),
  surface         text default 'road',
  is_public       boolean default false,
  slug            text unique,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

create index routes_user_id on routes (user_id, created_at desc);
create index routes_public on routes (is_public, created_at desc) where is_public = true;

-- Integrations table
create table integrations (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users not null,
  provider        text not null,
  access_token    text,
  refresh_token   text,
  token_expiry    timestamptz,
  external_id     text,
  scope           text,
  last_sync_at    timestamptz,
  sync_cursor     text,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  unique (user_id, provider)
);

-- User profiles table
create table user_profiles (
  id                uuid primary key references auth.users,
  display_name      text,
  avatar_url        text,
  parkrun_number    text,
  preferred_unit    text default 'km',
  subscription_tier text default 'free',
  subscription_at   timestamptz,
  created_at        timestamptz default now()
);

-- Row-level security
alter table runs enable row level security;
create policy "users own their runs"
  on runs for all using (auth.uid() = user_id);

alter table routes enable row level security;
create policy "users own their routes"
  on routes for all using (auth.uid() = user_id);
create policy "public routes are readable by anyone"
  on routes for select using (is_public = true);

alter table integrations enable row level security;
create policy "users own their integrations"
  on integrations for all using (auth.uid() = user_id);

alter table user_profiles enable row level security;
create policy "users own their profile"
  on user_profiles for all using (auth.uid() = id);
