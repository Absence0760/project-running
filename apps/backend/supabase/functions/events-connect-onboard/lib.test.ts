/// Run with `cd apps/backend && deno test supabase/functions/events-connect-onboard/lib.test.ts`.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildAccountCreateParams,
  buildAccountLinkParams,
  validateReturnUrl,
} from './lib.ts';

Deno.test('buildAccountCreateParams — Express type with transfers + card_payments requested', () => {
  const p = buildAccountCreateParams('US', 'usd');
  assertEquals(p.type, 'express');
  assertEquals(p.country, 'US');
  assertEquals(p.default_currency, 'usd');
  assertEquals(p.capabilities.transfers.requested, true);
  assertEquals(p.capabilities.card_payments.requested, true);
});

Deno.test('buildAccountCreateParams — omits country/currency when not supplied', () => {
  const p = buildAccountCreateParams(null, null);
  assertStrictEquals('country' in p, false);
  assertStrictEquals('default_currency' in p, false);
  // Capabilities still requested regardless.
  assertEquals(p.capabilities.transfers.requested, true);
});

Deno.test('buildAccountLinkParams — onboarding type with return/refresh urls wired', () => {
  const p = buildAccountLinkParams(
    'acct_123',
    'https://app.example.com/settings/payouts?onboard=return',
    'https://app.example.com/settings/payouts?onboard=refresh',
  );
  assertEquals(p.account, 'acct_123');
  assertEquals(p.type, 'account_onboarding');
  assertEquals(p.return_url, 'https://app.example.com/settings/payouts?onboard=return');
  assertEquals(p.refresh_url, 'https://app.example.com/settings/payouts?onboard=refresh');
});

Deno.test('validateReturnUrl — allowed origin (any path under it) passes', () => {
  const allow = ['https://app.example.com'];
  assertStrictEquals(validateReturnUrl('https://app.example.com/settings/payouts', allow), true);
  assertStrictEquals(validateReturnUrl('https://app.example.com/anything?x=1', allow), true);
});

Deno.test('validateReturnUrl — foreign host rejected (open-redirect defence)', () => {
  const allow = ['https://app.example.com'];
  assertStrictEquals(validateReturnUrl('https://evil.example.org/settings/payouts', allow), false);
  // Subdomain / port mismatch is a different origin -> rejected.
  assertStrictEquals(validateReturnUrl('https://app.example.com:8443/x', allow), false);
  // Scheme mismatch -> different origin.
  assertStrictEquals(validateReturnUrl('http://app.example.com/x', allow), false);
});

Deno.test('validateReturnUrl — empty allowlist rejects everything (fail closed)', () => {
  assertStrictEquals(validateReturnUrl('https://app.example.com/x', []), false);
});

Deno.test('validateReturnUrl — malformed url rejected', () => {
  assertStrictEquals(validateReturnUrl('not a url', ['https://app.example.com']), false);
  assertStrictEquals(validateReturnUrl('', ['https://app.example.com']), false);
});

Deno.test('validateReturnUrl — multiple allowed origins, any match passes', () => {
  const allow = ['https://app.example.com', 'https://staging.example.com'];
  assertStrictEquals(validateReturnUrl('https://staging.example.com/settings/payouts', allow), true);
});
