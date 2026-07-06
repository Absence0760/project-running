/// Run with `cd apps/backend && deno test supabase/functions/auth-email/lib.test.ts`.
/// (Pure module — no allow-net / allow-env needed.)

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  AUTH_EMAIL_KEYS,
  AUTH_EMAIL_LOCALES,
  authEmailCatalogue,
  authEmailShared,
  buildMime,
  buildVerifyUrl,
  encodeHeaderWord,
  extractAddr,
  isValidRecipient,
  normalizeEmailLocale,
  planSends,
  renderAuthEmail,
  resolveAuthEmailLocale,
  signSendEmailHook,
  verifySendEmailHook,
} from './lib.ts';

const SECRET = 'v1,whsec_' + btoa('0123456789abcdef0123456789abcdef');
const NOW = 1_750_000_000_000;

function tsFor(nowMs: number): string {
  return String(Math.floor(nowMs / 1000));
}

Deno.test('verifySendEmailHook — valid signature passes', async () => {
  const body = '{"user":{}}';
  const ts = tsFor(NOW);
  const sig = await signSendEmailHook(SECRET, 'msg_1', ts, body);
  const outcome = await verifySendEmailHook(
    body,
    { id: 'msg_1', timestamp: ts, signature: sig },
    SECRET,
    NOW,
  );
  assertEquals(outcome, 'ok');
});

Deno.test('verifySendEmailHook — tampered body rejected', async () => {
  const ts = tsFor(NOW);
  const sig = await signSendEmailHook(SECRET, 'msg_1', ts, '{"a":1}');
  const outcome = await verifySendEmailHook(
    '{"a":2}',
    { id: 'msg_1', timestamp: ts, signature: sig },
    SECRET,
    NOW,
  );
  assertEquals(outcome, 'bad_signature');
});

Deno.test('verifySendEmailHook — wrong secret rejected', async () => {
  const body = '{}';
  const ts = tsFor(NOW);
  const sig = await signSendEmailHook(SECRET, 'msg_1', ts, body);
  const other = 'v1,whsec_' + btoa('ffffffffffffffffffffffffffffffff');
  const outcome = await verifySendEmailHook(
    body,
    { id: 'msg_1', timestamp: ts, signature: sig },
    other,
    NOW,
  );
  assertEquals(outcome, 'bad_signature');
});

Deno.test('verifySendEmailHook — stale and future timestamps rejected', async () => {
  const body = '{}';
  const staleTs = tsFor(NOW - 6 * 60 * 1000);
  const staleSig = await signSendEmailHook(SECRET, 'm', staleTs, body);
  assertEquals(
    await verifySendEmailHook(
      body,
      { id: 'm', timestamp: staleTs, signature: staleSig },
      SECRET,
      NOW,
    ),
    'stale',
  );
  const futureTs = tsFor(NOW + 6 * 60 * 1000);
  const futureSig = await signSendEmailHook(SECRET, 'm', futureTs, body);
  assertEquals(
    await verifySendEmailHook(
      body,
      { id: 'm', timestamp: futureTs, signature: futureSig },
      SECRET,
      NOW,
    ),
    'stale',
  );
});

Deno.test('verifySendEmailHook — missing headers rejected', async () => {
  assertEquals(
    await verifySendEmailHook('{}', { id: null, timestamp: '1', signature: 'v1,x' }, SECRET, NOW),
    'missing_headers',
  );
  assertEquals(
    await verifySendEmailHook('{}', { id: 'm', timestamp: null, signature: 'v1,x' }, SECRET, NOW),
    'missing_headers',
  );
  assertEquals(
    await verifySendEmailHook('{}', { id: 'm', timestamp: '1', signature: null }, SECRET, NOW),
    'missing_headers',
  );
});

Deno.test('verifySendEmailHook — one valid entry in a multi-signature header passes', async () => {
  const body = '{}';
  const ts = tsFor(NOW);
  const sig = await signSendEmailHook(SECRET, 'm', ts, body);
  const outcome = await verifySendEmailHook(
    body,
    { id: 'm', timestamp: ts, signature: `v1,${btoa('garbage')} ${sig}` },
    SECRET,
    NOW,
  );
  assertEquals(outcome, 'ok');
});

Deno.test('verifySendEmailHook — rotation: second |-separated secret matches', async () => {
  const body = '{}';
  const ts = tsFor(NOW);
  const sig = await signSendEmailHook(SECRET, 'm', ts, body);
  const rotated = 'v1,whsec_' + btoa('ffffffffffffffffffffffffffffffff') + '|' + SECRET;
  assertEquals(
    await verifySendEmailHook(
      body,
      { id: 'm', timestamp: ts, signature: sig },
      rotated,
      NOW,
    ),
    'ok',
  );
});

Deno.test('verifySendEmailHook — undecodable secret fails closed', async () => {
  const body = '{}';
  const ts = tsFor(NOW);
  const sig = await signSendEmailHook(SECRET, 'm', ts, body);
  assertEquals(
    await verifySendEmailHook(
      body,
      { id: 'm', timestamp: ts, signature: sig },
      'v1,whsec_!!!not-base64!!!',
      NOW,
    ),
    'bad_secret',
  );
});

Deno.test('verifySendEmailHook — bare whsec_ secret form accepted', async () => {
  const body = '{}';
  const ts = tsFor(NOW);
  const bare = 'whsec_' + btoa('0123456789abcdef0123456789abcdef');
  const sig = await signSendEmailHook(bare, 'm', ts, body);
  assertEquals(
    await verifySendEmailHook(
      body,
      { id: 'm', timestamp: ts, signature: sig },
      SECRET,
      NOW,
    ),
    'ok',
  );
});

Deno.test('verifySendEmailHook — prefix-less v1,<base64> secret form accepted', async () => {
  // The CI env-file carries the secret WITHOUT the whsec_ marker on
  // purpose (it trips GitHub secret scanning's Stripe-webhook pattern
  // on a throwaway fixture — see the edge-functions job in ci.yml).
  // Tightening parseHookSecrets to require the marker would silently
  // 503 that job's auth-email envelope tests.
  const body = '{}';
  const ts = tsFor(NOW);
  const bare = 'v1,' + btoa('ci-auth-email-hook-secret-32chars');
  const sig = await signSendEmailHook(bare, 'm', ts, body);
  assertEquals(
    await verifySendEmailHook(
      body,
      { id: 'm', timestamp: ts, signature: sig },
      bare,
      NOW,
    ),
    'ok',
  );
});

Deno.test('normalizeEmailLocale — mirrors the worker table', () => {
  assertEquals(normalizeEmailLocale(''), 'en');
  assertEquals(normalizeEmailLocale(null), 'en');
  assertEquals(normalizeEmailLocale(undefined), 'en');
  assertEquals(normalizeEmailLocale('de-DE'), 'de');
  assertEquals(normalizeEmailLocale('de_AT'), 'de');
  assertEquals(normalizeEmailLocale('pt'), 'pt-BR');
  assertEquals(normalizeEmailLocale('pt-PT'), 'pt-BR');
  assertEquals(normalizeEmailLocale('PT-br'), 'pt-BR');
  assertEquals(normalizeEmailLocale('ja'), 'ja');
  assertEquals(normalizeEmailLocale('fr-CA'), 'fr');
  assertEquals(normalizeEmailLocale('xx'), 'en');
});

Deno.test('resolveAuthEmailLocale — settings > metadata > en', () => {
  assertEquals(resolveAuthEmailLocale('de', 'fr'), 'de');
  assertEquals(resolveAuthEmailLocale(null, 'fr-CA'), 'fr');
  assertEquals(resolveAuthEmailLocale(null, 42), 'en');
  assertEquals(resolveAuthEmailLocale(null, undefined), 'en');
  assertEquals(resolveAuthEmailLocale(null, '  '), 'en');
});

Deno.test('catalogue — every locale carries every key, non-empty', () => {
  assertEquals(
    Object.keys(authEmailCatalogue).sort(),
    [...AUTH_EMAIL_LOCALES].sort(),
  );
  const linkKeys = ['signup', 'invite', 'magiclink', 'recovery', 'email_change', 'email_change_current'];
  for (const locale of AUTH_EMAIL_LOCALES) {
    const entries = authEmailCatalogue[locale];
    assertEquals(
      Object.keys(entries).sort(),
      [...AUTH_EMAIL_KEYS].sort(),
      `key set drift in ${locale}`,
    );
    for (const [key, s] of Object.entries(entries)) {
      assert(s.subject.length > 0, `${locale}.${key}.subject empty`);
      assert(s.preheader.length > 0, `${locale}.${key}.preheader empty`);
      assert(s.heading.length > 0, `${locale}.${key}.heading empty`);
      assert(s.body.length > 0, `${locale}.${key}.body empty`);
      if (linkKeys.includes(key)) {
        assert(s.cta.length > 0, `${locale}.${key}.cta empty`);
      }
    }
    assert(authEmailShared[locale].footer.length > 0);
    assert(authEmailShared[locale].altCode.length > 0);
  }
});

Deno.test('isValidRecipient — plain addresses pass, injection shapes fail', () => {
  for (
    const good of [
      'runner@test.com',
      'first.last+tag@sub.example.co.uk',
      'admin@localhost',
    ]
  ) {
    assert(isValidRecipient(good), `expected valid: ${good}`);
  }
  for (
    const bad of [
      '',
      'runner@test.com\r\nBcc: victim@example.com',
      'runner@test.com\nX-Injected: 1',
      'a@b.com>\r\nRCPT TO:<c@d.com',
      '<runner@test.com>',
      'two words@example.com',
      'a,b@example.com',
      'a;b@example.com',
      'no-at-sign.example.com',
      'double@@example.com',
      'trailing@',
      '@leading.com',
      'x'.repeat(250) + '@e.com',
    ]
  ) {
    assert(!isValidRecipient(bad), `expected invalid: ${JSON.stringify(bad)}`);
  }
});

Deno.test('planSends — signup goes to the user with a signup verify link', () => {
  const sends = planSends(
    { id: 'u1', email: 'a@example.com' },
    { email_action_type: 'signup', token: '123456', token_hash: 'hash1' },
  );
  assertEquals(sends.length, 1);
  assertEquals(sends[0].to, 'a@example.com');
  assertEquals(sends[0].catalogueKey, 'signup');
  assertEquals(sends[0].verifyType, 'signup');
  assertEquals(sends[0].tokenHash, 'hash1');
});

Deno.test('planSends — email OTP action reuses the magic-link copy', () => {
  const sends = planSends(
    { email: 'a@example.com' },
    { email_action_type: 'email', token: '123456', token_hash: 'h' },
  );
  assertEquals(sends[0].catalogueKey, 'magiclink');
  assertEquals(sends[0].verifyType, 'email');
});

Deno.test('planSends — secure email change fans out to both addresses with reversed hashes', () => {
  const sends = planSends(
    { email: 'old@example.com', new_email: 'new@example.com' },
    {
      email_action_type: 'email_change',
      token: '111111',
      token_hash: 'hash_for_new',
      token_new: '222222',
      token_hash_new: 'hash_for_current',
    },
  );
  assertEquals(sends.length, 2);
  const current = sends.find((s) => s.to === 'old@example.com')!;
  const next = sends.find((s) => s.to === 'new@example.com')!;
  assertEquals(current.catalogueKey, 'email_change_current');
  assertEquals(current.token, '111111');
  assertEquals(current.tokenHash, 'hash_for_current');
  assertEquals(next.catalogueKey, 'email_change');
  assertEquals(next.token, '222222');
  assertEquals(next.tokenHash, 'hash_for_new');
});

Deno.test('planSends — single-confirm email change goes to the new address only', () => {
  const sends = planSends(
    { email: 'old@example.com', new_email: 'new@example.com' },
    { email_action_type: 'email_change', token: '1', token_hash: 'h' },
  );
  assertEquals(sends.length, 1);
  assertEquals(sends[0].to, 'new@example.com');
  assertEquals(sends[0].catalogueKey, 'email_change');
});

Deno.test('planSends — reauthentication is code-only, no verify link', () => {
  const sends = planSends(
    { email: 'a@example.com' },
    { email_action_type: 'reauthentication', token: '424242' },
  );
  assertEquals(sends.length, 1);
  assertEquals(sends[0].verifyType, null);
  assertEquals(sends[0].token, '424242');
});

Deno.test('planSends — unknown action type falls to the informational default, never fails', () => {
  const sends = planSends(
    { email: 'a@example.com' },
    { email_action_type: 'mfa_factor_enrolled_notification' },
  );
  assertEquals(sends.length, 1);
  assertEquals(sends[0].catalogueKey, 'default');
  assertEquals(sends[0].verifyType, null);
});

Deno.test('planSends — password changed notification uses its own copy', () => {
  const sends = planSends(
    { email: 'a@example.com' },
    { email_action_type: 'password_changed_notification' },
  );
  assertEquals(sends[0].catalogueKey, 'password_changed_notification');
});

Deno.test('planSends — no recipient means no sends', () => {
  assertEquals(planSends({}, { email_action_type: 'signup' }), []);
});

Deno.test('buildVerifyUrl — mirrors GoTrue: plain redirect_to stays literal', () => {
  const url = buildVerifyUrl(
    'http://127.0.0.1:54321',
    'abc123',
    'recovery',
    'http://localhost:7777/auth/reset',
  );
  assertEquals(
    url,
    'http://127.0.0.1:54321/auth/v1/verify?token=abc123&type=recovery&redirect_to=http://localhost:7777/auth/reset',
  );
  assertStringIncludes(url, '/auth/reset');
});

Deno.test('buildVerifyUrl — redirect_to with &/=/# gets encoded', () => {
  const url = buildVerifyUrl('http://x', 't', 'signup', 'http://a/b?c=1&d=2');
  assertStringIncludes(url, 'redirect_to=' + encodeURIComponent('http://a/b?c=1&d=2'));
});

Deno.test('renderAuthEmail — recovery: CTA verify link is the first URL in the HTML', () => {
  const [send] = planSends(
    { email: 'a@example.com' },
    {
      email_action_type: 'recovery',
      token: '123456',
      token_hash: 'thehash',
      redirect_to: 'http://localhost:7777/auth/reset',
    },
  );
  const r = renderAuthEmail('en', send, {
    supabaseUrl: 'http://127.0.0.1:54321',
    redirectTo: 'http://localhost:7777/auth/reset',
  });
  assertEquals(r.subject, 'Reset your password');
  // The e2e mail fixture (apps/web/tests-e2e/fixtures/mailpit.ts
  // extractLink) grabs the FIRST http(s) URL in the message and decodes
  // the attribute-escaped &amp; — mirror both steps; it must be the
  // verify link.
  const firstUrl = r.html.match(/https?:\/\/[^\s"'<>]+/)![0].replace(/&amp;/g, '&');
  assertStringIncludes(firstUrl, '/auth/v1/verify?token=thehash&type=recovery');
  assertStringIncludes(firstUrl, '/auth/reset');
  assertStringIncludes(r.text, '/auth/v1/verify?token=thehash&type=recovery');
  // The OTP code rides along as the link alternative.
  assertStringIncludes(r.html, '123456');
  assertStringIncludes(r.text, '123456');
});

Deno.test('renderAuthEmail — reauthentication shows the code and no link', () => {
  const [send] = planSends(
    { email: 'a@example.com' },
    { email_action_type: 'reauthentication', token: '987654' },
  );
  const r = renderAuthEmail('en', send, { supabaseUrl: 'http://x' });
  assertStringIncludes(r.html, '987654');
  assertEquals(r.html.match(/https?:\/\/[^\s"'<>]+/), null);
});

Deno.test('renderAuthEmail — localizes and stamps <html lang>', () => {
  const [send] = planSends(
    { email: 'a@example.com' },
    { email_action_type: 'signup', token: '1', token_hash: 'h' },
  );
  const de = renderAuthEmail('de-DE', send, { supabaseUrl: 'http://x' });
  assertEquals(de.subject, 'Bestätige deine Registrierung');
  assertStringIncludes(de.html, '<html lang="de">');
  const ja = renderAuthEmail('ja', send, { supabaseUrl: 'http://x' });
  assertEquals(ja.subject, '登録を確認してください');
});

Deno.test('renderAuthEmail — unknown locale falls back to English', () => {
  const [send] = planSends(
    { email: 'a@example.com' },
    { email_action_type: 'magiclink', token: '1', token_hash: 'h' },
  );
  const r = renderAuthEmail('xx-YY', send, { supabaseUrl: 'http://x' });
  assertEquals(r.subject, 'Your sign-in link');
  assertStringIncludes(r.html, '<html lang="en">');
});

Deno.test('encodeHeaderWord — ASCII untouched, non-ASCII RFC 2047 B-encoded', () => {
  assertEquals(encodeHeaderWord('Reset your password'), 'Reset your password');
  const encoded = encodeHeaderWord('Bestätige deine Registrierung');
  assert(encoded.startsWith('=?UTF-8?B?') && encoded.endsWith('?='));
  const decoded = new TextDecoder().decode(
    Uint8Array.from(atob(encoded.slice(10, -2)), (c) => c.charCodeAt(0)),
  );
  assertEquals(decoded, 'Bestätige deine Registrierung');
});

Deno.test('buildMime — multipart/alternative with CRLF and 8bit parts', () => {
  const mime = buildMime(
    'Threkir <noreply@threkir.com>',
    'a@example.com',
    { subject: 'Bestätige', text: 'hello\nworld', html: '<p>hi</p>' },
    'Thu, 01 Jan 2026 00:00:00 GMT',
  );
  assertStringIncludes(mime, 'From: Threkir <noreply@threkir.com>\r\n');
  assertStringIncludes(mime, 'To: a@example.com\r\n');
  assertStringIncludes(mime, 'Subject: =?UTF-8?B?');
  assertStringIncludes(mime, 'Content-Type: multipart/alternative; boundary="threkir_auth_alt_x7k2"');
  assertStringIncludes(mime, 'Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\nhello\r\nworld');
  assertStringIncludes(mime, 'Content-Type: text/html; charset=UTF-8');
  assertStringIncludes(mime, '--threkir_auth_alt_x7k2--\r\n');
});

Deno.test('extractAddr — bare address out of a display-name From', () => {
  assertEquals(extractAddr('Threkir <noreply@threkir.com>'), 'noreply@threkir.com');
  assertEquals(extractAddr('noreply@threkir.com'), 'noreply@threkir.com');
});
