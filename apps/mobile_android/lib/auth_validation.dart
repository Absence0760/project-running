/// Canonical password minimum for every surface that creates or changes
/// a password (sign-up pre-submit validation, the change-password
/// dialog). Web mirrors it as `PASSWORD_MIN_LENGTH`
/// (`apps/web/src/lib/core/auth_rules.ts`) and the server enforces it
/// via `minimum_password_length` in `apps/backend/supabase/config.toml`
/// (prod: the dashboard Auth settings) — change all three together.
const int kPasswordMinLength = 8;

final RegExp _emailShape = RegExp(r'^[^\s@]+@[^\s@]+$');

/// Loose email-shape check for pre-submit validation. Matches the
/// browser's `<input type="email">` semantics (one `@` with non-space
/// text either side) rather than full RFC 5322 — the server remains
/// the authority; this only catches obvious typos before a round-trip.
bool looksLikeEmail(String value) => _emailShape.hasMatch(value.trim());
