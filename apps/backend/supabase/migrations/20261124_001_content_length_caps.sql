-- Length caps on free-text user content (reviews/audit-xss.md L3).
--
-- club_posts.body and events.description are rendered safely as Svelte text
-- nodes today, but neither had a length CHECK. An unbounded value causes
-- visual overflow now and would be a DoS vector the moment either field is
-- ever routed through a markdown/HTML renderer. Same shape as the
-- coach_messages content cap (20261122_001): NOT VALID so the migration
-- doesn't scan existing rows, but every new INSERT/UPDATE is enforced.

alter table club_posts
  add constraint club_posts_body_len_chk
  check (char_length(body) <= 4096) not valid;

alter table events
  add constraint events_description_len_chk
  check (description is null or char_length(description) <= 2000) not valid;
