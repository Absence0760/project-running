// Architecture guard over ../../config.toml's verify_jwt posture.
//
// The platform's verify_jwt gate only accepts JWTs. Functions reached
// by callers WITHOUT a user session (webhooks, cron, logged-out
// spectators whose supabase-js sends the publishable API key as the
// bearer) must therefore carry an explicit `verify_jwt = false` and
// authorize in-handler. This test fails when one of those functions
// loses its override — a regression that would 401 every anonymous
// caller — and when a NEW function turns the gate off without being
// added to the allowlist here (turning it off silently widens the
// anonymous surface).

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const ANON_REACHABLE = [
  'auth-email',
  'clip-public-track',
  'donations-checkout',
  'refresh-tokens',
  'revenuecat-webhook',
  'strava-webhook',
  'stripe-events-webhook',
].sort()

function verifyJwtFalseSections(toml: string): string[] {
  const out: string[] = []
  const sections = toml.split(/^\[/m)
  for (const s of sections) {
    const m = s.match(/^functions\.([A-Za-z0-9_-]+)\]/)
    if (!m) continue
    if (/^\s*verify_jwt\s*=\s*false\s*$/m.test(s)) out.push(m[1])
  }
  return out.sort()
}

Deno.test('every anon-reachable function has an explicit verify_jwt = false', async () => {
  const toml = await Deno.readTextFile(new URL('../../config.toml', import.meta.url))
  const off = verifyJwtFalseSections(toml)
  for (const fn of ANON_REACHABLE) {
    assert(
      off.includes(fn),
      `${fn} is reachable without a user JWT but config.toml no longer sets verify_jwt = false for it`,
    )
  }
})

Deno.test('no function disables verify_jwt without being on the anon-reachable allowlist', async () => {
  const toml = await Deno.readTextFile(new URL('../../config.toml', import.meta.url))
  assertEquals(
    verifyJwtFalseSections(toml),
    ANON_REACHABLE,
    'a function turned verify_jwt off — if intentional, add it here with a caller audit',
  )
})
