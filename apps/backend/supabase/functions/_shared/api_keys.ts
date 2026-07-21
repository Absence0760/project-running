// Server-side API-key resolution across both Supabase key generations.
//
// New-format keys arrive as JSON objects keyed by key name
// (SUPABASE_SECRET_KEYS / SUPABASE_PUBLISHABLE_KEYS); legacy keys as
// plain strings (SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY). The
// legacy vars keep being injected after a project migrates but serve a
// stale value once legacy keys are disabled (supabase/supabase#37648),
// so the new vars win whenever they yield a key; the legacy fallback
// keeps local stacks and un-migrated projects working with no flag day.

function fromJsonByName(raw: string | undefined): string | null {
  if (!raw) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== 'object') return null;
  const map = parsed as Record<string, unknown>;
  if (typeof map.default === 'string' && map.default) return map.default;
  for (const v of Object.values(map)) {
    if (typeof v === 'string' && v) return v;
  }
  return null;
}

export function secretKey(): string {
  const key = fromJsonByName(Deno.env.get('SUPABASE_SECRET_KEYS')) ??
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!key) {
    throw new Error('SUPABASE_SECRET_KEYS / SUPABASE_SERVICE_ROLE_KEY both unset');
  }
  return key;
}

export function publishableKey(): string {
  const key = fromJsonByName(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')) ??
    Deno.env.get('SUPABASE_ANON_KEY');
  if (!key) {
    throw new Error('SUPABASE_PUBLISHABLE_KEYS / SUPABASE_ANON_KEY both unset');
  }
  return key;
}

// Headers for a raw fetch authenticated with the secret key. A legacy
// service_role key is a JWT and travels as both apikey and the
// Authorization bearer; an sb_secret_… key is not a JWT and the docs
// require it on apikey alone — a bearer that differs from the apikey
// is forwarded to Postgres and rejected (PGRST301). The createClient
// sites need no equivalent: sessionless supabase-js sends a bearer
// EQUAL to the apikey, which the gateway's compat carve-out accepts
// (verified against this project, 2026-07-21 — decisions §280).
// Twin of the Go worker's internal/supakey.
export function secretKeyHeaders(): Record<string, string> {
  const key = secretKey();
  return key.startsWith('sb_')
    ? { apikey: key }
    : { apikey: key, Authorization: `Bearer ${key}` };
}
