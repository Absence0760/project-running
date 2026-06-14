-- Club links — a website + socials row a club can publish on its page.
-- Lets a club point members at its own site / Instagram / Strava club /
-- Facebook group ("Visit our website").
--
-- Security: every URL is constrained to an http/https scheme at the DB so a
-- stored `javascript:` / `data:` URL can never reach a rendered anchor (XSS).
-- The clients additionally validate on input and render with
-- rel="noopener noreferrer". An empty string is treated as unset (the edit
-- form sends '' to clear a link); only a non-empty value must match the scheme.

alter table clubs add column website_url   text
  check (website_url   is null or website_url   ~* '^https?://');
alter table clubs add column instagram_url text
  check (instagram_url is null or instagram_url ~* '^https?://');
alter table clubs add column strava_url    text
  check (strava_url    is null or strava_url    ~* '^https?://');
alter table clubs add column facebook_url  text
  check (facebook_url  is null or facebook_url  ~* '^https?://');

-- `clubs` SELECT is column-level granted (the invite_token lockdown,
-- 20260801_001) — new columns are deny-by-default. These four are meant to be
-- cross-user readable (a public club's links show to anyone who can see the
-- club), so grant SELECT explicitly. INSERT/UPDATE need no column grant — RLS
-- (is_club_admin) gates the write and PostgREST doesn't require column SELECT
-- to write.
grant select (website_url, instagram_url, strava_url, facebook_url)
  on clubs to authenticated, anon;
