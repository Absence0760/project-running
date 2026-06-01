-- XSS audit H1 + M3 (reviews/audit-xss.md): lock down who can write
-- `coach_messages` rows and how large they can be.
--
-- H1 — assistant-role injection. The web /coach handler runs as the
-- authenticated *user* (anon key + the caller's JWT — see
-- apps/web/src/lib/coach/handler.ts), not service_role. The old
-- `coach_messages_owner_insert` policy only checked `auth.uid() =
-- user_id`, so a hand-rolled REST insert (or the handler itself)
-- could write a `role = 'assistant'` row with arbitrary `content`.
-- That content is rendered via `{@html renderMarkdown(...)}` in
-- CoachChat.svelte. DOMPurify sanitises it today (self-XSS only,
-- since SELECT is owner-only), but it is a least-privilege violation
-- and would become cross-user stored XSS the moment a coach-athlete
-- shared-thread read path exists.
--
-- Fix: clients may only ever insert their own `role = 'user'` turns.
-- Assistant rows are written exclusively by the coach handler through
-- a service_role client, which bypasses RLS — so this WITH CHECK does
-- not constrain the trusted writer, only untrusted callers.
drop policy if exists coach_messages_owner_insert on coach_messages;
create policy coach_messages_owner_insert on coach_messages
  for insert
  with check (auth.uid() = user_id and role = 'user');

-- M3 — unbounded content. `content` was `text` with no cap, so an
-- oversized assistant row (or a hand-rolled insert) could push a
-- multi-MB string through marked.parse() + DOMPurify and the inline
-- render. Cap at 64 KiB to match MAX_COACH_ASSISTANT_CONTENT_BYTES in
-- apps/web/src/lib/coach/limits.ts; the handler truncates to the same
-- bound before insert, this CHECK is the load-bearing guard.
--
-- NOT VALID: enforce the bound on every new insert/update without
-- scanning (and potentially failing on) any legacy row that predates
-- the cap. New writes — the only thing that matters for the guard —
-- are checked immediately.
alter table coach_messages
  add constraint coach_messages_content_len_chk
  check (char_length(content) <= 65536) not valid;
