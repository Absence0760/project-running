/// Canonical password minimum for every surface that creates or changes
/// a password (/login signup minlength, /settings/account and
/// /auth/reset change-password validation). Mobile mirrors it as
/// `kPasswordMinLength` (apps/mobile_android/lib/auth_validation.dart)
/// and the server enforces it via `minimum_password_length` in
/// apps/backend/supabase/config.toml. Prod is NOT covered by that file
/// — it reads the dashboard's Auth settings, so a prod change is a
/// manual step. Change all four together.
export const PASSWORD_MIN_LENGTH = 8;
