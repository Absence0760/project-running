-- Reject control characters in user_profiles.display_name (issue #375).
--
-- display_name is plain text with no prior constraint. It flows into the
-- Subject of the safety-contact emails the app relays to third parties
-- (apps/job_worker/internal/mailer.go renderSafetyEmail). A CR/LF in the name
-- splits the header on the SMTP DATA stream — an SMTP/MIME header injection
-- (splice a Bcc:, forge List-Unsubscribe:, inject a body). The Go mailer now
-- strips control chars by construction; this CHECK is the defence-in-depth
-- write-boundary layer, mirroring the safety_contacts_email_format precedent
-- (20261218_001) so an injected value cannot even be stored.

-- Scrub any pre-existing offending value first so VALIDATE cannot fail on a
-- legacy row. Control chars are exactly the attack payload — removing them is
-- the correct normalization, not data loss.
update public.user_profiles
  set display_name = regexp_replace(display_name, '[[:cntrl:]]', '', 'g')
  where display_name ~ '[[:cntrl:]]';

-- Production-safe DDL: ADD ... NOT VALID takes a brief ACCESS EXCLUSIVE lock
-- but does not scan the table; VALIDATE takes only SHARE UPDATE EXCLUSIVE
-- (does not block reads/writes) while it scans. On a populated prod table this
-- avoids a long blocking lock.
alter table public.user_profiles
  add constraint user_profiles_display_name_no_control_chars
  check (display_name is null or display_name !~ '[[:cntrl:]]') not valid;

alter table public.user_profiles
  validate constraint user_profiles_display_name_no_control_chars;
