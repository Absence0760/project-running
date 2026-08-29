/// Run with `cd apps/backend && deno test --allow-read supabase/functions/_shared/redirect_allowlist.test.ts`.
///
/// The `strava-import` redirect allowlist is the only thing standing
/// between an OAuth `code` captured off some other path under our own
/// domain and a token exchange that hands the captor a live Strava
/// grant — Strava's `/oauth/authorize` pins the callback to the
/// registered Authorization Callback Domain, but that check is
/// path-prefix loose, which is the whole reason this gate exists.
///
/// Before this file, nothing exercised the comparison. The e2e spec
/// (`apps/web/tests-e2e/cross-cutting/strava-import-guards.spec.ts`)
/// pins the fail-closed-when-unset branch and cannot pin either of the
/// other two: the sharded Playwright lane runs against the auto-started
/// edge runtime, which has no `STRAVA_ALLOWED_REDIRECTS` at all, so
/// every `connect` it posts short-circuits at the 503 before the
/// comparison. Setting the var in that job would flip the 503 test
/// rather than add coverage — the wire layer can pin one branch of the
/// three, and it pins the most valuable one.
///
/// It could not pin the ACCEPT branch in any case: accepting means
/// proceeding to `POST https://www.strava.com/oauth/token`, so a
/// wire-level positive test would make CI depend on a third party's
/// availability and post junk OAuth codes at it. The decision is pure,
/// so it is tested pure — here — and the source guards below pin that
/// the handler still routes through it, in the right order.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

import { isExactRedirectAllowed, parseRedirectAllowlist } from './redirect_allowlist.ts';

const WEB_CALLBACK = 'https://app.example.com/settings/integrations';

// ── parse ────────────────────────────────────────────────────────────

Deno.test('parseRedirectAllowlist — a single entry', () => {
  assertEquals(parseRedirectAllowlist(WEB_CALLBACK), [WEB_CALLBACK]);
});

Deno.test('parseRedirectAllowlist — several entries, trimmed', () => {
  assertEquals(
    parseRedirectAllowlist(` ${WEB_CALLBACK} , threkir://strava-callback `),
    [WEB_CALLBACK, 'threkir://strava-callback'],
  );
});

Deno.test('parseRedirectAllowlist — blanks are dropped, never admitted as an entry', () => {
  // The failure that matters: an entry list that kept `''` would make
  // `isExactRedirectAllowed('')` true, so a caller claiming an empty
  // redirect_uri would pass a gate the operator believed was armed.
  const parsed = parseRedirectAllowlist(`,, ${WEB_CALLBACK} ,,`);
  assertEquals(parsed, [WEB_CALLBACK]);
  assertEquals(isExactRedirectAllowed('', parsed), false);
});

Deno.test('parseRedirectAllowlist — unset, empty and whitespace all yield no entries', () => {
  assertEquals(parseRedirectAllowlist(undefined), []);
  assertEquals(parseRedirectAllowlist(null), []);
  assertEquals(parseRedirectAllowlist(''), []);
  assertEquals(parseRedirectAllowlist('   '), []);
  assertEquals(parseRedirectAllowlist(',,,'), []);
});

// ── accept ───────────────────────────────────────────────────────────

Deno.test('isExactRedirectAllowed — the configured callback is accepted', () => {
  // The positive path. A refactor that breaks it locks every real
  // runner out of connecting Strava, and until now nothing said so.
  assert(isExactRedirectAllowed(WEB_CALLBACK, parseRedirectAllowlist(WEB_CALLBACK)));
});

Deno.test('isExactRedirectAllowed — accepted from anywhere in a multi-entry list', () => {
  const allow = parseRedirectAllowlist(
    `https://preview.example.com/settings/integrations, ${WEB_CALLBACK}, threkir://strava-callback`,
  );
  assert(isExactRedirectAllowed(WEB_CALLBACK, allow));
  assert(isExactRedirectAllowed('threkir://strava-callback', allow));
  assert(isExactRedirectAllowed('https://preview.example.com/settings/integrations', allow));
});

Deno.test('isExactRedirectAllowed — a custom-scheme mobile callback is a normal entry', () => {
  // `threkir://strava-callback` has no host under `new URL(...)`, so an
  // origin-based comparison would collapse it against every other
  // opaque-scheme URI. Whole-string matching has no such notion.
  const allow = parseRedirectAllowlist('threkir://strava-callback');
  assert(isExactRedirectAllowed('threkir://strava-callback', allow));
  assertEquals(isExactRedirectAllowed('threkir://evil-callback', allow), false);
});

// ── reject ───────────────────────────────────────────────────────────

Deno.test('isExactRedirectAllowed — a foreign origin is refused', () => {
  assertEquals(
    isExactRedirectAllowed('https://attacker.example.com/cb', parseRedirectAllowlist(WEB_CALLBACK)),
    false,
  );
});

Deno.test('isExactRedirectAllowed — another path under the SAME origin is refused', () => {
  // This is the window Strava's own domain check leaves open and the
  // one an origin comparison would leave open too. A code that landed
  // on some other route of ours must not be exchangeable.
  const allow = parseRedirectAllowlist(WEB_CALLBACK);
  assertEquals(isExactRedirectAllowed('https://app.example.com/', allow), false);
  assertEquals(isExactRedirectAllowed('https://app.example.com/legacy/oauth', allow), false);
  assertEquals(
    isExactRedirectAllowed('https://app.example.com/settings/integrations/old', allow),
    false,
  );
});

Deno.test('isExactRedirectAllowed — a prefix or extension of an entry is refused', () => {
  // Pins whole-string equality against the two refactors that would
  // quietly widen it: `startsWith` on either side.
  const allow = parseRedirectAllowlist(WEB_CALLBACK);
  assertEquals(isExactRedirectAllowed(`${WEB_CALLBACK}?next=//evil.example.org`, allow), false);
  assertEquals(isExactRedirectAllowed(`${WEB_CALLBACK}#`, allow), false);
  assertEquals(isExactRedirectAllowed(`${WEB_CALLBACK}/`, allow), false);
  assertEquals(isExactRedirectAllowed('https://app.example.com/settings', allow), false);
});

Deno.test('isExactRedirectAllowed — scheme and host case are not folded', () => {
  const allow = parseRedirectAllowlist(WEB_CALLBACK);
  assertEquals(isExactRedirectAllowed('https://APP.EXAMPLE.COM/settings/integrations', allow), false);
  assertEquals(isExactRedirectAllowed('http://app.example.com/settings/integrations', allow), false);
});

Deno.test('isExactRedirectAllowed — an empty allowlist refuses even the real callback', () => {
  assertEquals(isExactRedirectAllowed(WEB_CALLBACK, []), false);
});

Deno.test('isExactRedirectAllowed — a non-string claim refuses without throwing', () => {
  const allow = parseRedirectAllowlist(WEB_CALLBACK);
  for (const claim of [undefined, null, 12345, {}, [WEB_CALLBACK]]) {
    assertEquals(isExactRedirectAllowed(claim, allow), false);
  }
});

// ── source guards: the handler still routes through the gate ─────────

const STRAVA_SRC = await Deno.readTextFile(
  new URL('../strava-import/index.ts', import.meta.url),
);

Deno.test('strava-import routes its allowlist through the shared module', () => {
  assert(
    STRAVA_SRC.includes("from '../_shared/redirect_allowlist.ts'"),
    'strava-import must import the shared parse + comparison, not re-spell them',
  );
  assert(
    STRAVA_SRC.includes("parseRedirectAllowlist(Deno.env.get('STRAVA_ALLOWED_REDIRECTS'))"),
    'strava-import must build its allowlist with parseRedirectAllowlist',
  );
  assert(
    STRAVA_SRC.includes('!isExactRedirectAllowed(redirectUri, allowed)'),
    'strava-import must refuse on the NEGATION of isExactRedirectAllowed — a gate ' +
      'branching the other way rejects every legitimate connect instead',
  );
});

Deno.test('strava-import gates the redirect BEFORE the Strava token exchange', () => {
  const gate = STRAVA_SRC.indexOf('isExactRedirectAllowed(redirectUri, allowed)');
  const exchange = STRAVA_SRC.indexOf("fetch('https://www.strava.com/oauth/token'");
  assert(gate !== -1, 'the redirect gate is gone');
  assert(exchange !== -1, 'the token exchange moved or was renamed');
  assert(
    gate < exchange,
    'the redirect_uri gate must run BEFORE the code is exchanged — after it, the ' +
      'grant already exists and the check protects nothing',
  );
});

Deno.test('strava-import still fails closed on an unset allowlist', () => {
  const empty = STRAVA_SRC.indexOf('allowed.length === 0');
  const gate = STRAVA_SRC.indexOf('isExactRedirectAllowed(redirectUri, allowed)');
  assert(empty !== -1, 'the empty-allowlist 503 branch is gone — a missed `supabase secrets set` would allow any redirect');
  assert(STRAVA_SRC.includes("error: 'strava_not_configured'"), '503 strava_not_configured must be the empty-allowlist answer');
  assert(empty < gate, 'the empty-allowlist check must precede the comparison');
});

// ── source guard: nobody re-spells the parse ─────────────────────────

async function* sourceFiles(dir: URL): AsyncGenerator<URL> {
  for await (const entry of Deno.readDir(dir)) {
    const child = new URL(`${entry.name}${entry.isDirectory ? '/' : ''}`, dir);
    if (entry.isDirectory) {
      yield* sourceFiles(child);
    } else if (entry.name.endsWith('.ts') && !entry.name.endsWith('.test.ts')) {
      yield child;
    }
  }
}

Deno.test('no Edge Function re-spells the allowlist parse inline', async () => {
  const offenders: string[] = [];
  let reads = 0;
  for await (const file of sourceFiles(new URL('../', import.meta.url))) {
    if (file.pathname.endsWith('_shared/redirect_allowlist.ts')) continue;
    const src = await Deno.readTextFile(file);
    for (const m of src.matchAll(/Deno\.env\.get\('[A-Z_]*ALLOWED_REDIRECTS'\)/g)) {
      reads++;
      const statement = src.slice(m.index ?? 0, (m.index ?? 0) + 200);
      if (statement.includes('.split(')) {
        offenders.push(file.pathname.split('/functions/')[1]);
      }
    }
  }
  // Nobody re-spelling the parse is also what a tree with no callers looks
  // like — and the four callers are exactly what this guard exists for, so
  // their disappearance must not read as compliance.
  assert(reads > 0, 'no function reads an *_ALLOWED_REDIRECTS var at all');
  assertEquals(
    offenders,
    [],
    `these functions parse an *_ALLOWED_REDIRECTS var inline instead of calling ` +
      `parseRedirectAllowlist: ${offenders.join(', ')}. A copy that stops filtering ` +
      `blanks admits the empty string as an allowed redirect.`,
  );
});

// ── the committed dev allowlist follows the lane's port ──────────────

/// Pull the sharded Playwright lane's port off the module that owns it
/// (decisions § 743) rather than restating `7777` here — a fourth copy
/// of the port is the thing this guard exists to prevent.
async function laneCallbackUrl(): Promise<string> {
  const baseUrlSrc = await Deno.readTextFile(
    new URL('../../../../web/tests-e2e/fixtures/base-url.ts', import.meta.url),
  );
  const port = baseUrlSrc.match(/DEFAULT_E2E_PORT\s*=\s*(\d+)/)?.[1];
  assert(
    port,
    'apps/web/tests-e2e/fixtures/base-url.ts no longer declares DEFAULT_E2E_PORT — ' +
      'the dev callback URL has lost its source of truth',
  );
  const stravaSrc = await Deno.readTextFile(
    new URL('../../../../web/src/lib/integrations/strava.ts', import.meta.url),
  );
  const path = stravaSrc.match(/redirect_uri:\s*`\$\{origin\}([^`]*)`/)?.[1];
  assert(
    path,
    'apps/web/src/lib/integrations/strava.ts no longer builds redirect_uri as ' +
      '`${origin}<path>` — the callback path has lost its source of truth',
  );
  return `http://localhost:${port}${path}`;
}

for (const envFile of ['.env.development', '.env.example']) {
  Deno.test(`${envFile} allow-lists the web lane's own Strava callback`, async () => {
    const expected = await laneCallbackUrl();
    const src = await Deno.readTextFile(
      new URL(`../../../${envFile}`, import.meta.url),
    );
    const line = src.match(/^STRAVA_ALLOWED_REDIRECTS=(.*)$/m)?.[1];
    assert(line !== undefined, `${envFile} must declare STRAVA_ALLOWED_REDIRECTS`);
    assert(
      parseRedirectAllowlist(line).includes(expected),
      `${envFile}'s STRAVA_ALLOWED_REDIRECTS must contain ${expected} — the port comes ` +
        `from tests-e2e/fixtures/base-url.ts and the path from the web client that ` +
        `sends it, so move the lane and this follows. Found: ${line}`,
    );
  });
}
