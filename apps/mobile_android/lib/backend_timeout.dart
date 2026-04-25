/// Hard cap on `await`s that hit Supabase / an Edge Function. When the
/// backend is unreachable, supabase-dart's HTTP calls don't resolve on
/// their own for minutes — the timeout converts that into a visible
/// error state the user can retry.
const kBackendLoadTimeout = Duration(seconds: 15);
