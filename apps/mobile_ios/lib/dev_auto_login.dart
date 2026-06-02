// Dev-only seed auto-login gating.
//
// The startup auto-login (driven by `DEV_USER_EMAIL` / `DEV_USER_PASSWORD`)
// is a developer convenience for local work against the seeded backend. It
// must NEVER fire against a production Supabase — a stray credential in a
// developer's environment must not silently sign a real user in. So the
// gate below only allows it when `SUPABASE_URL` resolves to a loopback
// host, matching the dev/prod isolation rule in
// `docs/testing/dev_prod_isolation.md`.

/// The loopback hosts accepted as "local dev" — same set the web
/// `scripts/env_isolation.mjs` guard enforces (127.0.0.1, localhost, the
/// Android-emulator alias 10.0.2.2, and the Docker-desktop alias).
const _loopbackHosts = <String>{
  'localhost',
  '127.0.0.1',
  '::1',
  '10.0.2.2',
  'host.docker.internal',
};

/// Whether [url] points at a local/dev Supabase instance.
bool isLocalSupabaseUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  try {
    return _loopbackHosts.contains(Uri.parse(url).host);
  } catch (_) {
    return false;
  }
}

/// Whether the startup seed auto-login should be attempted: credentials are
/// present AND the backend is a local/dev instance. Pure so the safety rail
/// is unit-tested rather than only exercised at launch.
bool shouldAutoLogin({
  required String? url,
  required String? email,
  required String? password,
}) {
  return isLocalSupabaseUrl(url) &&
      email != null &&
      email.isNotEmpty &&
      password != null &&
      password.isNotEmpty;
}
