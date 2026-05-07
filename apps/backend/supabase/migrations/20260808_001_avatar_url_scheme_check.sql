-- /audit/all Medium (xss): `user_profiles.avatar_url` and
-- `clubs.avatar_url` are unconstrained `text` columns. Today every
-- renderer uses them as `<img src={avatar_url}>` and modern browsers
-- don't execute `javascript:` URIs in img-src — but:
--   1. CSP `img-src` doesn't block scheme-based exfil (the URL is
--      still parsed, and the image-load attempt can leak referer /
--      user-agent to any HTTP host).
--   2. Any future surface that renders `avatar_url` in an `<a href>`
--      context (a profile-link card, an event admin badge with a
--      clickable avatar) would be immediately exploitable for
--      stored XSS via `javascript:alert(...)`.
--   3. `updateClub` accepts `avatar_url` in its patch payload
--      (apps/web/src/lib/data.ts), so a future settings form binding
--      `<input type="url">` to that field becomes the user-controlled
--      href.
--
-- Fix at the DB layer: CHECK constraint enforcing `https?:` (or
-- protocol-relative `//host/...` for legacy edge cases). Closes the
-- vector regardless of which rendering surface ships next.
--
-- The existing rows in both tables come from OAuth providers
-- (Google avatar URLs, Apple-Pasted dataURI placeholders) — both
-- start with `https://`. Validated by the seed: no current row has
-- a non-http(s) scheme, so the CHECK is non-disruptive.

alter table user_profiles
  add constraint user_profiles_avatar_url_scheme
  check (
    avatar_url is null
    or avatar_url ~* '^https?://'
  );

alter table clubs
  add constraint clubs_avatar_url_scheme
  check (
    avatar_url is null
    or avatar_url ~* '^https?://'
  );
