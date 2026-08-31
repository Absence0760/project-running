/// The Connect onboarding redirect gate, from the attacker's side.
///
/// `return_url` and `refresh_url` arrive in the request BODY, so the candidate
/// is caller-chosen and this gate is the only thing between it and the URL
/// Stripe sends a host to when their hosted onboarding finishes. The sibling
/// suite covers the allowed and foreign-host cases; what is asserted here is
/// the set of things an origin comparison is classically fooled by.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/events-connect-onboard/redirect_invariants.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildAccountCreateParams,
  buildAccountLinkParams,
  validateReturnUrl,
} from './lib.ts';

const ALLOW = ['https://app.threkir.com', 'https://threkir.com'];

Deno.test('validateReturnUrl — the configured origin admits any path, query and fragment under it', () => {
  // The positive control the refusals below need: a gate that refused
  // everything would satisfy every negative case on its own.
  for (const url of [
    'https://app.threkir.com',
    'https://app.threkir.com/',
    'https://app.threkir.com/settings/payouts',
    'https://app.threkir.com/settings/payouts?ok=1#done',
    'https://threkir.com/x',
  ]) {
    assertEquals(validateReturnUrl(url, ALLOW), true, url);
  }
});

Deno.test('validateReturnUrl — an opaque origin is never a match, in either direction', () => {
  // A custom scheme, `data:`, `blob:` and `javascript:` all have NO origin,
  // and the URL spec serialises every one of them to the same literal `null`.
  // An origin comparison over the serialisations therefore makes one such
  // entry in the allowlist admit every one of them — `javascript:` included.
  // The configuration that gets there is not exotic: the sibling
  // STRAVA_ALLOWED_REDIRECTS carries `threkir://strava-callback`, and this
  // gate's own doc comment points an operator at that convention.
  const opaque = [
    'javascript:alert(1)',
    'data:text/html,<script>alert(1)</script>',
    'evil-app://steal',
    'threkir://payouts-return',
    'mailto:someone@evil.com',
  ];
  for (const entry of [...opaque, ...ALLOW]) {
    for (const candidate of opaque) {
      assertEquals(
        validateReturnUrl(candidate, [entry]),
        false,
        `${entry} must not admit ${candidate}`,
      );
    }
  }
  // And an opaque entry does not disable the real ones beside it.
  assertEquals(validateReturnUrl('https://app.threkir.com/x', ['threkir://cb', ...ALLOW]), true);
  // `blob:` is deliberately NOT in that set: its origin is the inner URL's, so
  // it is judged on that rather than on the opaque `null`, which is the right
  // answer and not the collision above.
  assertEquals(validateReturnUrl('blob:https://evil.com/x', ALLOW), false);
  assertEquals(new URL('blob:https://evil.com/x').origin, 'https://evil.com');
});

Deno.test('validateReturnUrl — the classic origin-confusion payloads are all refused', () => {
  const refused = [
    'https://app.threkir.com@evil.com/x',
    'https://evil.com/?next=https://app.threkir.com',
    'https://evil.com#https://app.threkir.com',
    'https://app.threkir.com.evil.com/x',
    'https://evil.app.threkir.com/x',
    'https://app.threkir.com./x',
    'http://app.threkir.com/x',
    'https://app.threkir.com:8443/x',
    'https://app.threkir.com:443@evil.com/x',
    '//app.threkir.com/x',
    '/settings/payouts',
    'app.threkir.com',
    '',
    'https://',
    'https://evil.com\\@app.threkir.com',
  ];
  for (const url of refused) {
    assertEquals(validateReturnUrl(url, ALLOW), false, JSON.stringify(url));
  }
});

Deno.test('validateReturnUrl — an unparseable allowlist entry is skipped, not fatal', () => {
  // A typo in one entry must not take the whole allowlist down, and must not
  // admit anything either.
  assertEquals(validateReturnUrl('https://app.threkir.com/x', ['not a url', ...ALLOW]), true);
  assertEquals(validateReturnUrl('https://evil.com/x', ['not a url', ...ALLOW]), false);
  assertEquals(validateReturnUrl('https://app.threkir.com/x', ['not a url']), false);
});

Deno.test('validateReturnUrl — an empty allowlist refuses even the real callback', () => {
  // A missed `supabase secrets set` must fail closed rather than allow any
  // host: this is the gate's whole reason to exist.
  assertEquals(validateReturnUrl('https://app.threkir.com/x', []), false);
});

Deno.test('validateReturnUrl — the default port is the same origin, a stated one is too', () => {
  assertEquals(validateReturnUrl('https://app.threkir.com:443/x', ALLOW), true);
  assertEquals(validateReturnUrl('https://app.threkir.com:80/x', ALLOW), false);
  assertEquals(validateReturnUrl('http://localhost:7777/x', ['http://localhost:7777']), true);
  assertEquals(validateReturnUrl('http://localhost:8888/x', ['http://localhost:7777']), false);
});

Deno.test('buildAccountCreateParams — both capabilities are requested, and neither is optional', () => {
  // `transfers` is what a destination charge needs; without it every payout to
  // this host fails after the buyer has already been charged.
  const params = buildAccountCreateParams();
  assertEquals(params.type, 'express');
  assertEquals(params.capabilities, {
    transfers: { requested: true },
    card_payments: { requested: true },
  });
  assertEquals(Object.keys(params).sort(), ['capabilities', 'type']);
});

Deno.test('buildAccountCreateParams — an absent optional is omitted, never sent empty', () => {
  // Stripe rejects an explicit empty country, so a blank has to disappear
  // rather than be forwarded.
  for (const blank of [undefined, null, ''] as const) {
    const params = buildAccountCreateParams(blank, blank);
    assert(!('country' in params), String(blank));
    assert(!('default_currency' in params), String(blank));
  }
  const params = buildAccountCreateParams('GB', 'gbp');
  assertEquals(params.country, 'GB');
  assertEquals(params.default_currency, 'gbp');
});

Deno.test('buildAccountLinkParams — the two URLs keep their own places', () => {
  // They are adjacent same-typed arguments, so a transposition typechecks and
  // sends a host who finished onboarding back to the refresh loop for ever.
  const params = buildAccountLinkParams('acct_1', 'https://a.test/return', 'https://a.test/refresh');
  assertEquals(params, {
    account: 'acct_1',
    type: 'account_onboarding',
    return_url: 'https://a.test/return',
    refresh_url: 'https://a.test/refresh',
  });
});
